import type { EntityMap, SyncedEntityName, SyncedRow } from './entities';
import type { DataStore } from './data-store';

/** Nome da entidade no protocolo de sync (snake_case) <-> nome interno. */
export const WIRE_TYPES = {
  delivery: 'delivery',
  route: 'route',
  routeStop: 'route_stop',
  deliveryEvent: 'delivery_event',
  routePlan: 'route_plan',
  vehicle: 'vehicle',
  oilChange: 'oil_change',
  shift: 'shift',
  baseLocation: 'base_location',
} as const satisfies Record<SyncedEntityName, string>;

export type WireEntityType = (typeof WIRE_TYPES)[SyncedEntityName];

export const ENTITY_BY_WIRE: Record<WireEntityType, SyncedEntityName> = Object.fromEntries(
  Object.entries(WIRE_TYPES).map(([name, wire]) => [wire, name]),
) as Record<WireEntityType, SyncedEntityName>;

const SYSTEM_FIELDS = new Set(['id', 'userId', 'version', 'fieldVersions', 'createdAt', 'updatedAt', 'deletedAt']);

function sameValue(a: unknown, b: unknown): boolean {
  if (a instanceof Date || b instanceof Date) {
    return a instanceof Date && b instanceof Date && a.getTime() === b.getTime();
  }
  if (typeof a === 'object' && a !== null && typeof b === 'object' && b !== null) {
    return JSON.stringify(a) === JSON.stringify(b);
  }
  return (a ?? null) === (b ?? null);
}

/**
 * Toda escrita em entidade sincronizada passa por aqui (REST e sync):
 * - version +1 a cada mudança e field_versions[campo] = versão nova;
 * - uma linha em sync_changes por mudança (cursor do pull);
 * - exclusão é lógica (deleted_at) e vira tombstone no pull.
 * Precisa rodar dentro de uma transação com lockUser(userId) já chamado.
 */
export class EntityWriter {
  constructor(
    private readonly store: DataStore,
    private readonly userId: string,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async insert<N extends SyncedEntityName>(name: N, data: Partial<EntityMap[N]> & { id: string }): Promise<EntityMap[N]> {
    const at = this.now();
    const row = await this.store.create(name, {
      createdAt: at,
      ...data,
      userId: this.userId,
      version: 1,
      fieldVersions: {},
      updatedAt: at,
      deletedAt: null,
    } as Partial<EntityMap[N]>);
    await this.log(name, row as SyncedRow, 'upsert');
    return row;
  }

  /**
   * Aplica só os campos que mudaram de verdade. Sem mudança, devolve a linha
   * como está (mesma versão, nada no log).
   */
  async patch<N extends SyncedEntityName>(
    name: N,
    current: EntityMap[N],
    changes: Partial<EntityMap[N]>,
    /** Campos lógicos sem coluna (ex.: `stopOrder` da rota) que contam como mudança. */
    touched: string[] = [],
  ): Promise<{ row: EntityMap[N]; changed: string[] }> {
    const base = current as unknown as SyncedRow & Record<string, unknown>;
    const changed = Object.entries(changes as Record<string, unknown>)
      .filter(([key, value]) => value !== undefined && !SYSTEM_FIELDS.has(key) && !sameValue(base[key], value))
      .map(([key]) => key);
    if (changed.length === 0 && touched.length === 0) {
      return { row: current, changed };
    }
    const version = base.version + 1;
    const fieldVersions = { ...base.fieldVersions };
    const data: Record<string, unknown> = {};
    for (const key of changed) {
      data[key] = (changes as Record<string, unknown>)[key];
      fieldVersions[key] = version;
    }
    for (const key of touched) {
      fieldVersions[key] = version;
    }
    const row = await this.store.update(name, base.id, {
      ...data,
      version,
      fieldVersions,
      updatedAt: this.now(),
    } as Partial<EntityMap[N]>);
    await this.log(name, row as SyncedRow, 'upsert');
    return { row, changed };
  }

  /** Exclusão lógica. Já excluída = nada muda. */
  async softDelete<N extends SyncedEntityName>(name: N, current: EntityMap[N]): Promise<EntityMap[N]> {
    const base = current as unknown as SyncedRow;
    if (base.deletedAt) {
      return current;
    }
    const at = this.now();
    const version = base.version + 1;
    const row = await this.store.update(name, base.id, {
      deletedAt: at,
      updatedAt: at,
      version,
      fieldVersions: { ...base.fieldVersions, deletedAt: version },
    } as unknown as Partial<EntityMap[N]>);
    await this.log(name, row as SyncedRow, 'delete');
    return row;
  }

  private async log(name: SyncedEntityName, row: SyncedRow, operation: 'upsert' | 'delete'): Promise<void> {
    await this.store.create('syncChange', {
      userId: this.userId,
      entityType: WIRE_TYPES[name],
      entityId: row.id,
      version: row.version,
      operation,
      changedAt: this.now(),
    });
  }
}

/**
 * Campos de [fields] que mudaram no servidor depois de [baseVersion]
 * (a versão que o cliente tinha quando editou). Vazio = sem conflito.
 * Mudanças em campos diferentes não conflitam: são mescladas.
 */
export function staleFields(row: SyncedRow, baseVersion: number, fields: string[]): string[] {
  return fields.filter((field) => (row.fieldVersions?.[field] ?? 1) > baseVersion);
}

/**
 * Linha do usuário, viva (não excluída). Outro dono ou inexistente = null:
 * quem chama responde 404, sem revelar que o recurso existe.
 */
export async function findOwned<N extends SyncedEntityName>(
  store: DataStore,
  name: N,
  userId: string,
  id: string,
  options: { includeDeleted?: boolean } = {},
): Promise<EntityMap[N] | null> {
  const row = (await store.findById(name, id)) as (EntityMap[N] & SyncedRow) | null;
  if (!row || row.userId !== userId || (row.deletedAt && !options.includeDeleted)) {
    return null;
  }
  return row;
}

/** Remove campos internos antes de devolver ao cliente. */
export function publicView<T extends object>(row: T): Omit<T, 'userId' | 'fieldVersions'> {
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  const { userId, fieldVersions, ...rest } = row as T & { userId?: unknown; fieldVersions?: unknown };
  return rest as Omit<T, 'userId' | 'fieldVersions'>;
}
