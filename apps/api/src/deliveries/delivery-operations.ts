import { randomUUID } from 'node:crypto';
import {
  applyTransition,
  type DeliveryStatus,
  type FailureReason,
} from '../common/domain/delivery-status';
import type { DataStore } from '../persistence/data-store';
import type { DeliveryEventRow, DeliveryRow } from '../persistence/entities';
import { EntityWriter } from '../persistence/entity-writer';
import type { DeliveryEventResponse, DeliveryResponse } from './dto/delivery.dto';

/**
 * Regras de entrega que valem para o REST e para o sync. Recebem o store da
 * transação; quem chama abre a transação e trava o usuário.
 */

/** O status no servidor não é o que o cliente esperava (e não convergiu). */
export class StatusMismatchError extends Error {
  constructor(
    readonly expected: string,
    readonly current: string,
  ) {
    super(`Status esperado ${expected}, mas está ${current}.`);
  }
}

/** Campos que só mudam por transição, nunca por update. */
export const TRANSITION_FIELDS = ['status', 'failureReason', 'attempts', 'deliveredAt'] as const;

/** Campos editáveis de uma entrega (nomes do código). */
export const EDITABLE_DELIVERY_FIELDS = [
  'orderNumber',
  'packageId',
  'customerName',
  'phone',
  'address',
  'number',
  'complement',
  'neighborhood',
  'postalCode',
  'city',
  'state',
  'latitude',
  'longitude',
  'locationConfirmed',
  'value',
  'notes',
  'priority',
] as const;

export interface TransitionInput {
  to: DeliveryStatus;
  from?: DeliveryStatus;
  reason?: FailureReason | null;
  note?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  occurredAt?: Date;
  deviceId?: string | null;
  eventId?: string;
}

export interface TransitionResult {
  delivery: DeliveryRow;
  event: DeliveryEventRow | null;
  /** O servidor já estava no status pedido: nada mudou. */
  converged: boolean;
}

/**
 * Troca o status e grava o evento (mesma transação). Não faz efeitos
 * colaterais em outras entregas (ex.: a antiga IN_PROGRESS voltar a PENDING):
 * o app manda essas transições explicitamente.
 */
export async function transitionDelivery(
  store: DataStore,
  writer: EntityWriter,
  delivery: DeliveryRow,
  input: TransitionInput,
): Promise<TransitionResult> {
  const current = delivery.status as DeliveryStatus;
  if (input.from && input.from !== current) {
    if (input.to === current) {
      return { delivery, event: null, converged: true };
    }
    throw new StatusMismatchError(input.from, current);
  }
  const at = input.occurredAt ?? new Date();
  const next = applyTransition(
    {
      status: current,
      failureReason: delivery.failureReason as FailureReason | null,
      attempts: delivery.attempts,
      deliveredAt: delivery.deliveredAt,
    },
    input.to,
    input.reason,
    at,
  );
  const { row } = await writer.patch('delivery', delivery, next);
  const event = await writer.insert('deliveryEvent', {
    id: input.eventId ?? randomUUID(),
    deliveryId: delivery.id,
    kind: 'status',
    fromStatus: current,
    toStatus: input.to,
    reason: input.reason ?? null,
    note: input.note ?? null,
    changedFields: null,
    latitude: input.latitude ?? null,
    longitude: input.longitude ?? null,
    occurredAt: at,
    deviceId: input.deviceId ?? null,
  });
  return { delivery: row, event, converged: false };
}

/** Exclusão lógica da entrega e das paradas vivas dela. O histórico fica. */
export async function deleteDelivery(store: DataStore, writer: EntityWriter, delivery: DeliveryRow): Promise<DeliveryRow> {
  const stops = await store.findMany('routeStop', { deliveryId: delivery.id, deletedAt: null });
  for (const stop of stops) {
    await writer.softDelete('routeStop', stop);
  }
  return writer.softDelete('delivery', delivery);
}

export function toDeliveryResponse(row: DeliveryRow): DeliveryResponse {
  return {
    id: row.id,
    orderNumber: row.orderNumber ?? null,
    packageId: row.packageId ?? null,
    customerName: row.customerName,
    phone: row.phone ?? null,
    address: row.address,
    number: row.number ?? null,
    complement: row.complement ?? null,
    neighborhood: row.neighborhood ?? null,
    postalCode: row.postalCode ?? null,
    city: row.city,
    state: row.state ?? null,
    latitude: row.latitude ?? null,
    longitude: row.longitude ?? null,
    locationConfirmed: row.locationConfirmed,
    value: row.value ?? null,
    notes: row.notes ?? null,
    priority: row.priority,
    status: row.status,
    failureReason: row.failureReason ?? null,
    attempts: row.attempts,
    deliveredAt: row.deliveredAt ?? null,
    version: row.version,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt ?? null,
  };
}

export function toEventResponse(row: DeliveryEventRow): DeliveryEventResponse {
  return {
    id: row.id,
    deliveryId: row.deliveryId,
    kind: row.kind,
    fromStatus: row.fromStatus ?? null,
    toStatus: row.toStatus,
    reason: row.reason ?? null,
    note: row.note ?? null,
    changedFields: row.changedFields ?? null,
    latitude: row.latitude ?? null,
    longitude: row.longitude ?? null,
    occurredAt: row.occurredAt,
    deviceId: row.deviceId ?? null,
    createdAt: row.createdAt,
  };
}

/** Valores padrão de uma entrega nova (iguais aos do SQLite do app). */
export function newDeliveryData(input: Partial<DeliveryRow> & { id: string }): Partial<DeliveryRow> & { id: string } {
  return {
    orderNumber: null,
    packageId: null,
    phone: null,
    number: null,
    complement: null,
    neighborhood: null,
    postalCode: null,
    state: null,
    latitude: null,
    longitude: null,
    locationConfirmed: false,
    value: null,
    notes: null,
    priority: 'normal',
    status: 'PENDING',
    failureReason: null,
    attempts: 0,
    deliveredAt: null,
    ...input,
  };
}
