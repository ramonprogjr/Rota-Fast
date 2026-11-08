import { Inject, Injectable, Logger } from '@nestjs/common';
import { FailureReasonRequiredError, InvalidTransitionError } from '../common/domain/delivery-status';
import { ServiceUnavailableAppException } from '../common/exceptions/app.exception';
import { deleteDelivery, StatusMismatchError, transitionDelivery } from '../deliveries/delivery-operations';
import { DevicesService } from '../devices/devices.service';
import { DATABASE, type Database, type DataStore } from '../persistence/data-store';
import type { DeliveryRow, RouteRow, SyncedEntityName, SyncedRow, SyncOperationRow } from '../persistence/entities';
import {
  ENTITY_BY_WIRE,
  EntityWriter,
  findOwned,
  publicView,
  staleFields,
  type WireEntityType,
} from '../persistence/entity-writer';
import type { RouteStatus } from '../routes/dto/route.dto';
import {
  assertNoOtherActive,
  canRouteGoTo,
  deleteRoute,
  reorderRoute,
  routeStatusSideEffects,
  RouteRuleError,
  STOP_ORDER_FIELD,
} from '../routes/route-operations';
import type {
  SyncChangeDto,
  SyncOperationDto,
  SyncOperationResult,
  SyncPullResponse,
  SyncPushDto,
  SyncPushResponse,
  SyncResultStatus,
} from './dto/sync.dto';
import {
  DELIVERY_TRANSITION_FIELDS,
  reorderPayload,
  SYNC_ENTITIES,
  type SyncEntityDef,
  transitionPayload,
  zodIssues,
} from './sync-schemas';

type StoredStatus = 'applied' | 'conflict' | 'rejected';

/** Resultado de uma operação antes de virar resposta. */
interface Outcome {
  status: StoredStatus;
  reason?: string;
  message?: string;
  version?: number;
  server?: Record<string, unknown> | null;
  details?: unknown;
  /** false = não grava em sync_operations (ex.: operation_id de outro usuário). */
  store?: boolean;
}

const applied = (row: { version: number }, message?: string): Outcome => ({
  status: 'applied',
  version: row.version,
  ...(message ? { message } : {}),
});
const rejected = (reason: string, message: string, details?: unknown): Outcome => ({
  status: 'rejected',
  reason,
  message,
  ...(details !== undefined ? { details } : {}),
});
const conflict = (reason: string, message: string, row: SyncedRow | null, details?: unknown): Outcome => ({
  status: 'conflict',
  reason,
  message,
  version: row?.version,
  server: row ? snapshot(row) : null,
  ...(details !== undefined ? { details } : {}),
});

function snapshot(row: SyncedRow): Record<string, unknown> {
  return publicView(row) as Record<string, unknown>;
}

/** Erro inesperado numa operação: a transação do lote é refeita sem ela. */
class PoisonedOperation extends Error {
  constructor(
    readonly index: number,
    override readonly cause: unknown,
  ) {
    super(`Operação ${index} falhou: ${(cause as Error)?.message ?? cause}`);
  }
}

/** Falha de infraestrutura (banco fora): não culpar a operação. */
function isInfrastructureError(error: unknown): boolean {
  const e = error as { name?: string; code?: string } | null;
  return (
    !!e &&
    (e.name === 'PrismaClientInitializationError' ||
      e.name === 'PrismaClientRustPanicError' ||
      (typeof e.code === 'string' && e.code.startsWith('P1')))
  );
}

const MAX_POISON_RETRIES = 3;

@Injectable()
export class SyncService {
  private readonly logger = new Logger('SyncService');

  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly devices: DevicesService,
  ) {}

  /**
   * Aplica um lote numa transação (com lock do usuário). Idempotente por
   * operationId. Conflitos e recusas são devolvidos E guardados.
   */
  async push(userId: string, dto: SyncPushDto): Promise<SyncPushResponse> {
    const poisoned = new Set<number>();
    for (let attempt = 0; ; attempt++) {
      try {
        const results = await this.db.transaction((store) => this.runBatch(store, userId, dto, poisoned));
        const summary = { applied: 0, duplicate: 0, conflict: 0, rejected: 0 } as Record<SyncResultStatus, number>;
        for (const r of results) summary[r.status]++;
        return { results, summary, serverTime: new Date().toISOString() };
      } catch (error) {
        if (error instanceof PoisonedOperation && attempt < MAX_POISON_RETRIES && !isInfrastructureError(error.cause)) {
          this.logger.error(error.message, (error.cause as Error)?.stack);
          poisoned.add(error.index);
          continue;
        }
        if (error instanceof PoisonedOperation) {
          this.logger.error(error.message, (error.cause as Error)?.stack);
          throw new ServiceUnavailableAppException('SYNC_UNAVAILABLE', 'Não foi possível sincronizar agora. Tente de novo.');
        }
        throw error;
      }
    }
  }

  private async runBatch(
    store: DataStore,
    userId: string,
    dto: SyncPushDto,
    poisoned: Set<number>,
  ): Promise<SyncOperationResult[]> {
    await store.lockUser(userId);
    await this.devices.upsert(store, userId, { id: dto.deviceId });
    const writer = new EntityWriter(store, userId);

    const ids = [...new Set(dto.operations.map((op) => op.operationId))];
    const previous = new Map<string, SyncOperationRow>();
    for (const row of await store.findMany('syncOperation', { id: { in: ids } })) {
      previous.set(row.id, row);
    }

    const results: SyncOperationResult[] = [];
    const seenInBatch = new Map<string, SyncOperationResult>();
    for (const [index, op] of dto.operations.entries()) {
      const base = { operationId: op.operationId, entityType: op.entityType, entityId: op.entityId };

      const earlier = previous.get(op.operationId);
      if (earlier) {
        if (earlier.userId !== userId) {
          results.push({ ...base, status: 'rejected', reason: 'operation_id_reused', message: 'operationId já usado. Gere outro.' });
        } else {
          results.push(duplicateOf(earlier));
        }
        continue;
      }
      const sameBatch = seenInBatch.get(op.operationId);
      if (sameBatch) {
        results.push({ ...sameBatch, status: 'duplicate', originalStatus: sameBatch.status as StoredStatus });
        continue;
      }

      let outcome: Outcome;
      if (poisoned.has(index)) {
        outcome = rejected('internal_error', 'Erro inesperado ao aplicar. A operação foi guardada para análise.');
      } else if (op.deviceId && op.deviceId !== dto.deviceId) {
        outcome = rejected('device_mismatch', 'deviceId da operação difere do lote.');
      } else {
        try {
          outcome = await this.apply(store, writer, userId, dto.deviceId, op);
        } catch (error) {
          throw new PoisonedOperation(index, error);
        }
      }

      const result: SyncOperationResult = {
        ...base,
        status: outcome.status,
        ...(outcome.reason ? { reason: outcome.reason } : {}),
        ...(outcome.message ? { message: outcome.message } : {}),
        ...(outcome.version !== undefined ? { version: outcome.version } : {}),
        ...(outcome.server !== undefined ? { server: outcome.server } : {}),
        ...(outcome.details !== undefined ? { details: outcome.details } : {}),
      };
      if (outcome.store !== false) {
        await store.create('syncOperation', {
          id: op.operationId,
          userId,
          deviceId: dto.deviceId,
          entityType: op.entityType,
          entityId: op.entityId,
          operationType: op.operationType,
          baseVersion: op.baseVersion ?? null,
          payload: op.payload,
          status: outcome.status,
          reason: outcome.reason ?? null,
          result: JSON.parse(JSON.stringify(result)) as Record<string, unknown>,
          clientCreatedAt: op.clientCreatedAt ?? null,
          receivedAt: new Date(),
        });
      }
      seenInBatch.set(op.operationId, result);
      results.push(result);
    }
    return results;
  }

  private async apply(
    store: DataStore,
    writer: EntityWriter,
    userId: string,
    deviceId: string,
    op: SyncOperationDto,
  ): Promise<Outcome> {
    const def = SYNC_ENTITIES[op.entityType as WireEntityType];
    switch (op.operationType) {
      case 'create':
        return this.create(store, writer, userId, def, op);
      case 'update':
        return this.update(store, writer, userId, def, op);
      case 'delete':
        return this.remove(store, writer, userId, def, op);
      case 'transition':
        if (def.name !== 'delivery') {
          return rejected('unsupported_operation', 'transition só vale para delivery.');
        }
        return this.transition(store, writer, userId, deviceId, op);
      case 'reorder':
        if (def.name !== 'route') {
          return rejected('unsupported_operation', 'reorder só vale para route.');
        }
        return this.reorder(store, writer, userId, op);
    }
  }

  private async checkRefs(
    store: DataStore,
    userId: string,
    def: SyncEntityDef,
    data: Record<string, unknown>,
  ): Promise<Outcome | null> {
    for (const ref of def.refs) {
      const value = data[ref.field];
      if (value === undefined || value === null) continue;
      const target = await findOwned(store, ref.entity, userId, value as string, { includeDeleted: true });
      if (!target) {
        return rejected('reference_not_found', `${ref.field} não encontrado. Envie a criação dele antes.`, {
          field: ref.field,
          id: value,
        });
      }
    }
    return null;
  }

  /** Regras de unicidade/estado que dependem de outras linhas. */
  private async checkInvariants(
    store: DataStore,
    userId: string,
    name: SyncedEntityName,
    id: string,
    data: Record<string, unknown>,
    current: SyncedRow | null,
  ): Promise<Outcome | null> {
    if (name === 'route' && data.status === 'active') {
      try {
        await assertNoOtherActive(store, userId, id);
      } catch (error) {
        if (error instanceof RouteRuleError) {
          return conflict('active_route_exists', error.message, current, error.details);
        }
        throw error;
      }
    }
    if (name === 'vehicle' && data.isActive === true) {
      const other = await store.findFirst('vehicle', { userId, isActive: true, deletedAt: null });
      if (other && other.id !== id) {
        return conflict('active_vehicle_exists', 'Já existe um veículo ativo. Desative-o antes.', current, {
          activeVehicleId: other.id,
        });
      }
    }
    if (name === 'routeStop' && !current) {
      const dup = await store.findFirst('routeStop', {
        routeId: data.routeId as string,
        deliveryId: data.deliveryId as string,
        deletedAt: null,
      });
      if (dup) {
        return conflict('stop_exists', 'Esta entrega já está nesta rota.', null, { existingStopId: dup.id });
      }
    }
    return null;
  }

  private async create(
    store: DataStore,
    writer: EntityWriter,
    userId: string,
    def: SyncEntityDef,
    op: SyncOperationDto,
  ): Promise<Outcome> {
    const parsed = def.create.safeParse(op.payload);
    if (!parsed.success) {
      return rejected('invalid_payload', 'Payload inválido.', zodIssues(parsed.error));
    }
    const data = parsed.data;
    const existing = (await store.findById(def.name, op.entityId)) as SyncedRow | null;
    if (existing) {
      if (existing.userId !== userId) {
        return rejected('not_found', 'Entidade não encontrada.');
      }
      return conflict('already_exists', 'Já existe uma entidade com este id.', existing);
    }
    const refError = await this.checkRefs(store, userId, def, data);
    if (refError) return refError;
    const invariant = await this.checkInvariants(store, userId, def.name, op.entityId, data, null);
    if (invariant) return invariant;
    const row = await writer.insert(def.name, {
      ...def.defaults,
      ...data,
      id: op.entityId,
      createdAt: (data.createdAt as Date | undefined) ?? op.clientCreatedAt ?? new Date(),
    } as never);
    return applied(row as SyncedRow);
  }

  private async update(
    store: DataStore,
    writer: EntityWriter,
    userId: string,
    def: SyncEntityDef,
    op: SyncOperationDto,
  ): Promise<Outcome> {
    if (!def.update) {
      return rejected('immutable_entity', `${op.entityType} não aceita update.`);
    }
    if (def.name === 'delivery') {
      const forbidden = Object.keys(op.payload).filter((k) => DELIVERY_TRANSITION_FIELDS.includes(k));
      if (forbidden.length) {
        return rejected('use_transition', 'Status só muda por operação transition.', { fields: forbidden });
      }
    }
    const parsed = def.update.safeParse(op.payload);
    if (!parsed.success) {
      return rejected('invalid_payload', 'Payload inválido.', zodIssues(parsed.error));
    }
    if (op.baseVersion === undefined) {
      return rejected('base_version_required', 'update precisa de baseVersion.');
    }
    const row = (await findOwned(store, def.name, userId, op.entityId, { includeDeleted: true })) as SyncedRow | null;
    if (!row) {
      return rejected('not_found', 'Entidade não encontrada.');
    }
    if (row.deletedAt) {
      return conflict('deleted', 'A entidade foi excluída em outro aparelho.', row);
    }
    if (op.baseVersion > row.version) {
      return rejected('invalid_base_version', 'baseVersion maior que a versão do servidor.', { serverVersion: row.version });
    }
    const changes: Record<string, unknown> = { ...parsed.data };
    const stale = staleFields(row, op.baseVersion, Object.keys(changes));
    if (stale.length) {
      return conflict('version_conflict', 'Os mesmos campos mudaram em outro aparelho.', row, { fields: stale });
    }
    const refError = await this.checkRefs(store, userId, def, changes);
    if (refError) return refError;
    if (def.name === 'route' && changes.status !== undefined) {
      const route = row as RouteRow;
      const to = changes.status as RouteStatus;
      if (!canRouteGoTo(route.status as RouteStatus, to)) {
        return rejected('invalid_route_transition', `Rota não passa de ${route.status} para ${to}.`);
      }
      const effects = routeStatusSideEffects(route, to, op.clientCreatedAt ?? new Date());
      for (const [key, value] of Object.entries(effects)) {
        if (!(key in changes)) changes[key] = value;
      }
    }
    const invariant = await this.checkInvariants(store, userId, def.name, op.entityId, changes, row);
    if (invariant) return invariant;
    const { row: updated } = await writer.patch(def.name, row as never, changes as never);
    return applied(updated as SyncedRow);
  }

  private async remove(
    store: DataStore,
    writer: EntityWriter,
    userId: string,
    def: SyncEntityDef,
    op: SyncOperationDto,
  ): Promise<Outcome> {
    if (def.undeletable) {
      return rejected('immutable_entity', `${op.entityType} é histórico e não pode ser excluído.`);
    }
    const row = (await findOwned(store, def.name, userId, op.entityId, { includeDeleted: true })) as SyncedRow | null;
    if (!row) {
      return rejected('not_found', 'Entidade não encontrada.');
    }
    if (row.deletedAt) {
      return applied(row, 'already_deleted');
    }
    if (op.baseVersion !== undefined && op.baseVersion < row.version) {
      return conflict('version_conflict', 'A entidade mudou depois da versão que o aparelho viu.', row, {
        fields: Object.keys(row.fieldVersions ?? {}).filter((f) => row.fieldVersions[f] > op.baseVersion!),
      });
    }
    let deleted: SyncedRow;
    switch (def.name) {
      case 'route':
        await deleteRoute(store, writer, row as RouteRow, false);
        deleted = (await store.findById('route', row.id))!;
        break;
      case 'delivery':
        deleted = await deleteDelivery(store, writer, row as DeliveryRow);
        break;
      case 'vehicle': {
        for (const oil of await store.findMany('oilChange', { vehicleId: row.id, deletedAt: null })) {
          await writer.softDelete('oilChange', oil);
        }
        deleted = await writer.softDelete('vehicle', row as never);
        break;
      }
      default:
        deleted = await writer.softDelete(def.name, row as never);
    }
    return applied(deleted);
  }

  private async transition(
    store: DataStore,
    writer: EntityWriter,
    userId: string,
    deviceId: string,
    op: SyncOperationDto,
  ): Promise<Outcome> {
    const parsed = transitionPayload.safeParse(op.payload);
    if (!parsed.success) {
      return rejected('invalid_payload', 'Payload inválido.', zodIssues(parsed.error));
    }
    const input = parsed.data;
    const delivery = await findOwned(store, 'delivery', userId, op.entityId, { includeDeleted: true });
    if (!delivery) {
      return rejected('not_found', 'Entrega não encontrada.');
    }
    if (delivery.deletedAt) {
      return conflict('deleted', 'A entrega foi excluída em outro aparelho.', delivery);
    }
    if (await store.findById('deliveryEvent', input.eventId)) {
      return conflict('already_exists', 'eventId já usado.', delivery);
    }
    try {
      const result = await transitionDelivery(store, writer, delivery, {
        to: input.toStatus,
        from: input.fromStatus,
        reason: input.reason,
        note: input.note,
        latitude: input.latitude,
        longitude: input.longitude,
        occurredAt: input.occurredAt ?? op.clientCreatedAt,
        deviceId,
        eventId: input.eventId,
      });
      return applied(result.delivery, result.converged ? 'already_in_status' : undefined);
    } catch (error) {
      if (error instanceof InvalidTransitionError) {
        return rejected('invalid_transition', error.message, { from: error.from, to: error.to });
      }
      if (error instanceof FailureReasonRequiredError) {
        return rejected('failure_reason_required', error.message);
      }
      if (error instanceof StatusMismatchError) {
        return conflict('status_conflict', error.message, delivery, { expected: error.expected, current: error.current });
      }
      throw error;
    }
  }

  private async reorder(store: DataStore, writer: EntityWriter, userId: string, op: SyncOperationDto): Promise<Outcome> {
    const parsed = reorderPayload.safeParse(op.payload);
    if (!parsed.success) {
      return rejected('invalid_payload', 'Payload inválido.', zodIssues(parsed.error));
    }
    const route = await findOwned(store, 'route', userId, op.entityId, { includeDeleted: true });
    if (!route) {
      return rejected('not_found', 'Rota não encontrada.');
    }
    if (route.deletedAt) {
      return conflict('deleted', 'A rota foi excluída em outro aparelho.', route);
    }
    if (op.baseVersion !== undefined && staleFields(route, op.baseVersion, [STOP_ORDER_FIELD]).length) {
      return conflict('version_conflict', 'A ordem da rota mudou em outro aparelho.', route, {
        fields: [STOP_ORDER_FIELD],
      });
    }
    try {
      const updated = await reorderRoute(store, writer, route, parsed.data.stopIds);
      return applied(updated);
    } catch (error) {
      if (error instanceof RouteRuleError) {
        // A lista de abertas do aparelho não bate com a do servidor: conflito.
        return error.code === 'STOPS_MISMATCH' || error.kind === 'conflict'
          ? conflict(error.code.toLowerCase(), error.message, route, error.details)
          : rejected(error.code.toLowerCase(), error.message, error.details);
      }
      throw error;
    }
  }

  /**
   * Mudanças depois de [since], em ordem, só do usuário. Cada entidade aparece
   * uma vez por página (a mudança mais recente), com o retrato atual ou
   * tombstone.
   */
  async pull(userId: string, since: string | undefined, limit: number | undefined): Promise<SyncPullResponse> {
    const cursor = Number(since ?? '0');
    const take = limit ?? 200;
    const rows = await this.db.store.findMany(
      'syncChange',
      { userId, seq: { gt: cursor } },
      { orderBy: [{ seq: 'asc' }], take: take + 1 },
    );
    const hasMore = rows.length > take;
    const page = rows.slice(0, take);
    const nextCursor = page.length ? String(page[page.length - 1].seq) : String(cursor);

    const latest = new Map<string, (typeof page)[number]>();
    for (const change of page) {
      const key = `${change.entityType}:${change.entityId}`;
      latest.delete(key);
      latest.set(key, change);
    }
    const byType = new Map<WireEntityType, string[]>();
    for (const change of latest.values()) {
      const type = change.entityType as WireEntityType;
      byType.set(type, [...(byType.get(type) ?? []), change.entityId]);
    }
    const loaded = new Map<string, SyncedRow>();
    for (const [type, ids] of byType) {
      const name = ENTITY_BY_WIRE[type];
      const entities = (await this.db.store.findMany(name, { id: { in: ids }, userId } as never)) as SyncedRow[];
      for (const entity of entities) loaded.set(`${type}:${entity.id}`, entity);
    }
    const changes: SyncChangeDto[] = [];
    for (const [key, change] of [...latest.entries()].sort((a, b) => a[1].seq - b[1].seq)) {
      const entity = loaded.get(key);
      if (!entity) continue;
      changes.push({
        seq: String(change.seq),
        entityType: change.entityType,
        entityId: change.entityId,
        operation: entity.deletedAt ? 'delete' : 'upsert',
        version: entity.version,
        data: entity.deletedAt ? null : snapshot(entity),
        deletedAt: entity.deletedAt ?? null,
      });
    }
    return { changes, nextCursor, hasMore, serverTime: new Date().toISOString() };
  }
}

function duplicateOf(earlier: SyncOperationRow): SyncOperationResult {
  const original = earlier.result as unknown as SyncOperationResult;
  return {
    ...original,
    operationId: earlier.id,
    entityType: earlier.entityType,
    entityId: earlier.entityId,
    status: 'duplicate',
    originalStatus: earlier.status,
  };
}
