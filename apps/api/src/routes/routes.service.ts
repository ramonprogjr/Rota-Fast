import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { Page } from '../common/dto/pagination.dto';
import {
  AppException,
  ConflictAppException,
  NotFoundAppException,
  UnprocessableAppException,
} from '../common/exceptions/app.exception';
import { newDeliveryData } from '../deliveries/delivery-operations';
import { DATABASE, type Database, type DataStore } from '../persistence/data-store';
import type { DeliveryRow, RouteRow } from '../persistence/entities';
import { EntityWriter, findOwned, staleFields } from '../persistence/entity-writer';
import type {
  AddStopsDto,
  CreateRouteDto,
  ListRoutesQueryDto,
  ReorderStopsDto,
  RouteDetailResponse,
  RouteResponse,
  RouteStatus,
  UpdateRouteDto,
} from './dto/route.dto';
import {
  appendStops,
  assertNoOtherActive,
  canRouteGoTo,
  deleteRoute,
  reorderRoute,
  routeStatusSideEffects,
  RouteRuleError,
  STOP_ORDER_FIELD,
  toRouteDetail,
  toRouteResponse,
} from './route-operations';

/** RouteRuleError -> erro HTTP padronizado. */
export function toHttpError(error: unknown): unknown {
  if (!(error instanceof RouteRuleError)) {
    return error;
  }
  if (error.kind === 'not_found') {
    return new AppException(404, error.code, error.message, error.details);
  }
  if (error.kind === 'conflict') {
    return new ConflictAppException(error.code, error.message, error.details);
  }
  return new UnprocessableAppException(error.code, error.message, error.details);
}

@Injectable()
export class RoutesService {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  async list(userId: string, query: ListRoutesQueryDto): Promise<Page<RouteResponse>> {
    const where = { userId, deletedAt: null, ...(query.status ? { status: query.status } : {}) };
    const [items, total] = await Promise.all([
      this.db.store.findMany('route', where, {
        orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
        skip: (query.page - 1) * query.pageSize,
        take: query.pageSize,
      }),
      this.db.store.count('route', where),
    ]);
    return { items: items.map(toRouteResponse), page: query.page, pageSize: query.pageSize, total };
  }

  async get(userId: string, id: string): Promise<RouteDetailResponse> {
    const route = await findOwned(this.db.store, 'route', userId, id);
    if (!route) {
      throw new NotFoundAppException('route');
    }
    return toRouteDetail(this.db.store, route);
  }

  create(userId: string, dto: CreateRouteDto): Promise<RouteResponse> {
    return this.inTx(userId, async (store, writer) => {
      const id = dto.id ?? randomUUID();
      if (await store.findById('route', id)) {
        throw new ConflictAppException('ROUTE_EXISTS', 'Já existe uma rota com este id.');
      }
      const status = dto.status ?? 'draft';
      if (status === 'active') {
        await assertNoOtherActive(store, userId, id);
      }
      const route = await writer.insert('route', {
        id,
        name: dto.name ?? null,
        status,
        originLat: dto.originLat ?? null,
        originLng: dto.originLng ?? null,
        endLat: dto.endLat ?? null,
        endLng: dto.endLng ?? null,
        estimatedKm: null,
        estimatedMinutes: null,
        navApp: dto.navApp ?? null,
        manuallyEdited: false,
        startedAt: null,
        completedAt: null,
      });
      return toRouteResponse(route);
    });
  }

  update(userId: string, id: string, dto: UpdateRouteDto): Promise<RouteResponse> {
    return this.inTx(userId, async (store, writer) => {
      const route = await this.owned(store, userId, id);
      const { baseVersion, status, ...rest } = dto;
      const changes: Partial<RouteRow> = { ...rest };
      if (status !== undefined) {
        if (!canRouteGoTo(route.status as RouteStatus, status)) {
          throw new UnprocessableAppException(
            'INVALID_ROUTE_TRANSITION',
            `Não dá para passar a rota de ${route.status} para ${status}.`,
          );
        }
        if (status === 'active') {
          await assertNoOtherActive(store, userId, id);
        }
        Object.assign(changes, routeStatusSideEffects(route, status, new Date()));
      }
      if (baseVersion !== undefined) {
        const stale = staleFields(route, baseVersion, Object.keys(changes));
        if (stale.length) {
          throw new ConflictAppException('VERSION_CONFLICT', 'A rota mudou em outro aparelho.', {
            fields: stale,
            server: toRouteResponse(route),
          });
        }
      }
      const { row } = await writer.patch('route', route, changes);
      return toRouteResponse(row);
    });
  }

  remove(userId: string, id: string, withExclusiveDeliveries: boolean): Promise<{ deletedDeliveryIds: string[] }> {
    return this.inTx(userId, async (store, writer) => {
      const route = await this.owned(store, userId, id);
      const result = await deleteRoute(store, writer, route, withExclusiveDeliveries);
      await store.create('auditLog', {
        userId,
        action: 'route.delete',
        entityType: 'route',
        entityId: id,
        metadata: { withExclusiveDeliveries, deletedDeliveries: result.deletedDeliveryIds.length },
        createdAt: new Date(),
      });
      return result;
    });
  }

  addStops(userId: string, id: string, dto: AddStopsDto): Promise<RouteDetailResponse> {
    return this.inTx(userId, async (store, writer) => {
      const route = await this.owned(store, userId, id);
      const ids = [...(dto.deliveryIds ?? [])];
      for (const input of dto.deliveries ?? []) {
        const deliveryId = input.id ?? randomUUID();
        if (await store.findById('delivery', deliveryId)) {
          throw new ConflictAppException('DELIVERY_EXISTS', 'Já existe uma entrega com este id.', { deliveryId });
        }
        await writer.insert('delivery', newDeliveryData({ ...input, id: deliveryId } as Partial<DeliveryRow> & { id: string }));
        ids.push(deliveryId);
      }
      if (ids.length === 0) {
        throw new UnprocessableAppException('NO_STOPS', 'Envie deliveryIds ou deliveries.');
      }
      await appendStops(store, writer, userId, route, ids);
      const fresh = await store.findById('route', id);
      return toRouteDetail(store, fresh!);
    });
  }

  reorder(userId: string, id: string, dto: ReorderStopsDto): Promise<RouteDetailResponse> {
    return this.inTx(userId, async (store, writer) => {
      const route = await this.owned(store, userId, id);
      if (dto.baseVersion !== undefined && staleFields(route, dto.baseVersion, [STOP_ORDER_FIELD]).length) {
        // Outra reordenação aconteceu depois da versão que o cliente viu.
        throw new ConflictAppException('VERSION_CONFLICT', 'A ordem da rota mudou em outro aparelho.', {
          fields: [STOP_ORDER_FIELD],
          server: toRouteResponse(route),
        });
      }
      const updated = await reorderRoute(store, writer, route, dto.stopIds);
      return toRouteDetail(store, updated);
    });
  }

  private async owned(store: DataStore, userId: string, id: string): Promise<RouteRow> {
    const route = await findOwned(store, 'route', userId, id);
    if (!route) {
      throw new NotFoundAppException('route');
    }
    return route;
  }

  private inTx<T>(userId: string, fn: (store: DataStore, writer: EntityWriter) => Promise<T>): Promise<T> {
    return this.db
      .transaction(async (store) => {
        await store.lockUser(userId);
        return fn(store, new EntityWriter(store, userId));
      })
      .catch((error: unknown) => {
        throw toHttpError(error);
      });
  }
}
