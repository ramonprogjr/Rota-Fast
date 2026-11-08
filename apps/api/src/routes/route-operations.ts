import { randomUUID } from 'node:crypto';
import { isOpenStatus } from '../common/domain/delivery-status';
import { deleteDelivery, toDeliveryResponse } from '../deliveries/delivery-operations';
import type { DataStore } from '../persistence/data-store';
import type { DeliveryRow, RouteRow, RouteStopRow } from '../persistence/entities';
import { EntityWriter, findOwned } from '../persistence/entity-writer';
import type { RouteDetailResponse, RouteResponse, RouteStatus, RouteStopResponse } from './dto/route.dto';

/**
 * Regras de rota que valem para o REST e para o sync. Recebem o store da
 * transação; quem chama abre a transação e trava o usuário.
 */

export class RouteRuleError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly details?: unknown,
    readonly kind: 'conflict' | 'invalid' | 'not_found' = 'invalid',
  ) {
    super(message);
  }
}

/** Campo lógico em field_versions que muda a cada reordenação. */
export const STOP_ORDER_FIELD = 'stopOrder';

const ROUTE_TRANSITIONS:Record<RouteStatus, RouteStatus[]> = {
  draft: ['active', 'completed'],
  active: ['completed', 'draft'],
  completed: ['active'],
};

export function canRouteGoTo(from: RouteStatus, to: RouteStatus): boolean {
  return from === to || ROUTE_TRANSITIONS[from].includes(to);
}

/** Só uma rota ativa por usuário (também garantido por índice parcial no banco). */
export async function assertNoOtherActive(store: DataStore, userId: string, routeId: string): Promise<void> {
  const active = await store.findFirst('route', { userId, status: 'active', deletedAt: null });
  if (active && active.id !== routeId) {
    throw new RouteRuleError(
      'ACTIVE_ROUTE_EXISTS',
      'Já existe uma rota ativa. Conclua-a antes de ativar outra.',
      { activeRouteId: active.id },
      'conflict',
    );
  }
}

/** Campos derivados de uma troca de status da rota. */
export function routeStatusSideEffects(route: RouteRow, to: RouteStatus, at: Date): Partial<RouteRow> {
  if (to === route.status) {
    return {};
  }
  if (to === 'completed') {
    return { status: to, completedAt: at };
  }
  if (to === 'active' && route.status === 'completed') {
    return { status: to, completedAt: null };
  }
  return { status: to };
}

export interface StopWithDelivery {
  stop: RouteStopRow;
  delivery: DeliveryRow;
  isOpen: boolean;
}

/** Paradas vivas da rota, pela posição, com a entrega. */
export async function loadStops(store: DataStore, routeId: string): Promise<StopWithDelivery[]> {
  const stops = await store.findMany(
    'routeStop',
    { routeId, deletedAt: null },
    { orderBy: [{ position: 'asc' }, { createdAt: 'asc' }] },
  );
  if (stops.length === 0) {
    return [];
  }
  const deliveries = await store.findMany('delivery', { id: { in: stops.map((s) => s.deliveryId) } });
  const byId = new Map(deliveries.map((d) => [d.id, d]));
  const out: StopWithDelivery[] = [];
  for (const stop of stops) {
    const delivery = byId.get(stop.deliveryId);
    if (!delivery || delivery.deletedAt) {
      continue;
    }
    out.push({ stop, delivery, isOpen: isOpenStatus(delivery.status) });
  }
  return out;
}

/**
 * Mesma regra do app (validateReorder): a lista precisa ter exatamente todas
 * as paradas abertas, sem repetir.
 */
export function validateReorder(ids: string[], openIds: Set<string>): void {
  if (new Set(ids).size !== ids.length) {
    const seen = new Set<string>();
    const duplicates = ids.filter((id) => (seen.has(id) ? true : (seen.add(id), false)));
    throw new RouteRuleError('DUPLICATE_STOPS', 'A nova ordem tem paradas repetidas.', { duplicates });
  }
  const missing = [...openIds].filter((id) => !ids.includes(id));
  const unknown = ids.filter((id) => !openIds.has(id));
  if (missing.length || unknown.length) {
    throw new RouteRuleError(
      'STOPS_MISMATCH',
      'A lista de paradas mudou enquanto você editava. Abra a edição de novo.',
      { missing, unknown },
    );
  }
}

/**
 * Grava a ordem das abertas. As concluídas mantêm a posição; as abertas vêm
 * depois da maior posição concluída, na ordem dada. Trava e posição fixa
 * ficam como estão (são regras para recalcular, não para a ordem manual).
 */
export async function reorderRoute(
  store: DataStore,
  writer: EntityWriter,
  route: RouteRow,
  stopIds: string[],
): Promise<RouteRow> {
  if (route.status === 'completed') {
    throw new RouteRuleError('ROUTE_COMPLETED', 'Rota concluída não pode ser reordenada.', undefined, 'conflict');
  }
  const stops = await loadStops(store, route.id);
  const open = stops.filter((s) => s.isOpen);
  validateReorder(stopIds, new Set(open.map((s) => s.stop.id)));
  const base = Math.max(0, ...stops.filter((s) => !s.isOpen).map((s) => s.stop.position));
  const byId = new Map(open.map((s) => [s.stop.id, s.stop]));
  for (const [index, id] of stopIds.entries()) {
    await writer.patch('routeStop', byId.get(id)!, { position: base + index + 1 });
  }
  // `stopOrder` é o "campo" ordem da rota, para detectar conflito de reordenação.
  const { row } = await writer.patch('route', route, { manuallyEdited: true }, [STOP_ORDER_FIELD]);
  return row;
}

/**
 * Coloca entregas do usuário no fim da rota. Entrega de outro usuário = não
 * encontrada; entrega já presente na rota = conflito.
 */
export async function appendStops(
  store: DataStore,
  writer: EntityWriter,
  userId: string,
  route: RouteRow,
  deliveryIds: string[],
): Promise<RouteStopRow[]> {
  if (route.status === 'completed') {
    throw new RouteRuleError('ROUTE_COMPLETED', 'Rota concluída não recebe paradas novas.', undefined, 'conflict');
  }
  if (new Set(deliveryIds).size !== deliveryIds.length) {
    throw new RouteRuleError('DUPLICATE_STOPS', 'A mesma entrega veio mais de uma vez.');
  }
  const live = await store.findMany('routeStop', { routeId: route.id, deletedAt: null });
  const present = new Set(live.map((s) => s.deliveryId));
  let position = Math.max(0, ...live.map((s) => s.position));
  const created: RouteStopRow[] = [];
  for (const deliveryId of deliveryIds) {
    const delivery = await findOwned(store, 'delivery', userId, deliveryId);
    if (!delivery) {
      throw new RouteRuleError('DELIVERY_NOT_FOUND', 'Entrega não encontrada.', { deliveryId }, 'not_found');
    }
    if (present.has(deliveryId)) {
      throw new RouteRuleError('STOP_EXISTS', 'Esta entrega já está na rota.', { deliveryId }, 'conflict');
    }
    created.push(
      await writer.insert('routeStop', {
        id: randomUUID(),
        routeId: route.id,
        deliveryId,
        position: ++position,
        locked: false,
        fixedPosition: null,
      }),
    );
    present.add(deliveryId);
  }
  return created;
}

/**
 * Exclusão lógica da rota, das paradas e dos planos. Entregas só são
 * excluídas com [withExclusiveDeliveries] e só as que não estão em nenhuma
 * outra rota viva — nunca as de outra rota.
 */
export async function deleteRoute(
  store: DataStore,
  writer: EntityWriter,
  route: RouteRow,
  withExclusiveDeliveries: boolean,
): Promise<{ deletedDeliveryIds: string[] }> {
  const stops = await store.findMany('routeStop', { routeId: route.id, deletedAt: null });
  const deletedDeliveryIds: string[] = [];
  for (const stop of stops) {
    await writer.softDelete('routeStop', stop);
  }
  if (withExclusiveDeliveries) {
    for (const stop of stops) {
      const others = await store.findMany('routeStop', { deliveryId: stop.deliveryId, deletedAt: null });
      let inOtherLiveRoute = false;
      for (const other of others) {
        const otherRoute = await store.findById('route', other.routeId);
        if (otherRoute && !otherRoute.deletedAt && otherRoute.id !== route.id) {
          inOtherLiveRoute = true;
          break;
        }
      }
      if (inOtherLiveRoute) continue;
      const delivery = await store.findById('delivery', stop.deliveryId);
      if (delivery && !delivery.deletedAt) {
        await deleteDelivery(store, writer, delivery);
        deletedDeliveryIds.push(delivery.id);
      }
    }
  }
  const plans = await store.findMany('routePlan', { routeId: route.id, deletedAt: null });
  for (const plan of plans) {
    await writer.softDelete('routePlan', plan);
  }
  await writer.softDelete('route', route);
  return { deletedDeliveryIds };
}

export function toRouteResponse(row: RouteRow): RouteResponse {
  return {
    id: row.id,
    name: row.name ?? null,
    status: row.status,
    originLat: row.originLat ?? null,
    originLng: row.originLng ?? null,
    endLat: row.endLat ?? null,
    endLng: row.endLng ?? null,
    estimatedKm: row.estimatedKm ?? null,
    estimatedMinutes: row.estimatedMinutes ?? null,
    navApp: row.navApp ?? null,
    manuallyEdited: row.manuallyEdited,
    startedAt: row.startedAt ?? null,
    completedAt: row.completedAt ?? null,
    version: row.version,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  };
}

export function toStopResponse(item: StopWithDelivery): RouteStopResponse {
  return {
    id: item.stop.id,
    deliveryId: item.stop.deliveryId,
    position: item.stop.position,
    locked: item.stop.locked,
    fixedPosition: item.stop.fixedPosition ?? null,
    isOpen: item.isOpen,
    version: item.stop.version,
    delivery: toDeliveryResponse(item.delivery),
  };
}

export async function toRouteDetail(store: DataStore, route: RouteRow): Promise<RouteDetailResponse> {
  const stops = await loadStops(store, route.id);
  return { ...toRouteResponse(route), stops: stops.map(toStopResponse) };
}
