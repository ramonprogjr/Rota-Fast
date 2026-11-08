import { randomUUID } from 'node:crypto';
import type { EntityMap, EntityName } from '../entities';
import type { Database, DataStore, FindOptions, Where } from '../data-store';

type Row = Record<string, unknown>;
type Tables = Map<EntityName, Map<string, Row>>;

const PRIMARY_KEY: Partial<Record<EntityName, string>> = { syncChange: 'seq' };

/** Defaults que o Postgres/Prisma preencheria. */
const DEFAULTS: Partial<Record<EntityName, () => Row>> = {
  user: () => ({ email: null, name: null, country: 'BR', locale: 'pt-BR', timezone: 'America/Sao_Paulo', deletedAt: null }),
  device: () => ({ model: null, osVersion: null, appVersion: null, lastSeenAt: new Date(), revokedAt: null }),
  subscription: () => ({
    userId: null,
    organizationId: null,
    status: 'active',
    currentPeriodStart: null,
    currentPeriodEnd: null,
    provider: null,
    providerRef: null,
  }),
  syncOperation: () => ({ reason: null, baseVersion: null, clientCreatedAt: null, receivedAt: new Date() }),
  syncChange: () => ({ changedAt: new Date() }),
  auditLog: () => ({ userId: null, entityType: null, entityId: null, metadata: {} }),
};

/** Cópia profunda (Date, Map, arrays, objetos). Sem structuredClone: no Jest
 * ele cria Date de outro "realm" e quebra `instanceof Date`. */
function clone<T>(value: T): T {
  if (value === null || typeof value !== 'object') {
    return value;
  }
  if (value instanceof Date) {
    return new Date(value.getTime()) as T;
  }
  if (value instanceof Map) {
    return new Map([...value.entries()].map(([k, v]) => [k, clone(v)])) as T;
  }
  if (Array.isArray(value)) {
    return value.map((item) => clone(item)) as T;
  }
  const out: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
    out[key] = clone(item);
  }
  return out as T;
}

function matches(row: Row, where: Row): boolean {
  for (const [key, cond] of Object.entries(where)) {
    if (cond === undefined) {
      continue;
    }
    const value = row[key] ?? null;
    if (cond === null) {
      if (value !== null) return false;
    } else if (cond instanceof Date) {
      if (!(value instanceof Date) || value.getTime() !== cond.getTime()) return false;
    } else if (typeof cond === 'object' && 'in' in cond) {
      if (!(cond as { in: unknown[] }).in.includes(value)) return false;
    } else if (typeof cond === 'object' && 'gt' in cond) {
      const gt = (cond as { gt: number | Date }).gt;
      if (value === null || (value as number | Date) <= gt) return false;
    } else if (value !== cond) {
      return false;
    }
  }
  return true;
}

function compare(a: unknown, b: unknown): number {
  if (a === b) return 0;
  if (a === null || a === undefined) return -1;
  if (b === null || b === undefined) return 1;
  const va = a instanceof Date ? a.getTime() : (a as number | string);
  const vb = b instanceof Date ? b.getTime() : (b as number | string);
  return va < vb ? -1 : va > vb ? 1 : 0;
}

class MemoryStore implements DataStore {
  constructor(private readonly db: MemoryDatabase) {}

  private table(name: EntityName): Map<string, Row> {
    let table = this.db.tables.get(name);
    if (!table) {
      table = new Map();
      this.db.tables.set(name, table);
    }
    return table;
  }

  async findById<N extends EntityName>(name: N, id: string): Promise<EntityMap[N] | null> {
    const row = this.table(name).get(id);
    return row ? (clone(row) as unknown as EntityMap[N]) : null;
  }

  async findFirst<N extends EntityName>(
    name: N,
    where: Where<EntityMap[N]>,
    options?: FindOptions<EntityMap[N]>,
  ): Promise<EntityMap[N] | null> {
    const rows = await this.findMany(name, where, { ...options, take: 1 });
    return rows[0] ?? null;
  }

  async findMany<N extends EntityName>(
    name: N,
    where: Where<EntityMap[N]>,
    options: FindOptions<EntityMap[N]> = {},
  ): Promise<EntityMap[N][]> {
    let rows = [...this.table(name).values()].filter((row) => matches(row, where as Row));
    const orderBy = options.orderBy ?? [];
    if (orderBy.length) {
      rows.sort((a, b) => {
        for (const spec of orderBy) {
          for (const [key, dir] of Object.entries(spec)) {
            const c = compare(a[key], b[key]);
            if (c !== 0) return dir === 'desc' ? -c : c;
          }
        }
        return 0;
      });
    }
    const skip = options.skip ?? 0;
    rows = rows.slice(skip, options.take !== undefined ? skip + options.take : undefined);
    return rows.map((row) => clone(row) as unknown as EntityMap[N]);
  }

  async count<N extends EntityName>(name: N, where: Where<EntityMap[N]>): Promise<number> {
    return [...this.table(name).values()].filter((row) => matches(row, where as Row)).length;
  }

  async create<N extends EntityName>(name: N, data: Partial<EntityMap[N]>): Promise<EntityMap[N]> {
    const pk = PRIMARY_KEY[name] ?? 'id';
    const now = new Date();
    const row: Row = { ...(DEFAULTS[name]?.() ?? {}), ...clone(data as Row) };
    if (pk === 'seq') {
      row.seq = ++this.db.sequence;
    } else {
      row.id ??= randomUUID();
      row.createdAt ??= now;
      row.updatedAt ??= now;
    }
    const key = String(row[pk]);
    const table = this.table(name);
    if (table.has(key)) {
      throw new Error(`Unique constraint failed on ${name}.${pk}`);
    }
    table.set(key, row);
    return clone(row) as unknown as EntityMap[N];
  }

  async update<N extends EntityName>(name: N, id: string, data: Partial<EntityMap[N]>): Promise<EntityMap[N]> {
    const table = this.table(name);
    const current = table.get(id);
    if (!current) {
      throw new Error(`Record to update not found: ${name}.${id}`);
    }
    const next = { ...current, ...clone(data as Row) };
    table.set(id, next);
    return clone(next) as unknown as EntityMap[N];
  }

  async lockUser(): Promise<void> {
    // As transações em memória já são serializadas (mutex global).
  }
}

/**
 * Banco em memória com a mesma interface do Prisma. Transação = cópia do
 * estado; erro restaura a cópia. Transações rodam uma por vez.
 */
export class MemoryDatabase implements Database {
  tables: Tables = new Map();
  sequence = 0;
  readonly store: DataStore = new MemoryStore(this);
  private queue: Promise<unknown> = Promise.resolve();

  constructor(options: { seedPlans?: boolean } = {}) {
    if (options.seedPlans ?? true) {
      const now = new Date();
      const plans = new Map<string, Row>();
      for (const plan of [
        { code: 'free', name: 'Grátis', isActive: true, limits: { devices: 2, syncEnabled: true, historyDays: 365 } },
        { code: 'pro', name: 'Pro', isActive: false, limits: { devices: 5, syncEnabled: true, historyDays: 1825 } },
      ]) {
        const id = randomUUID();
        plans.set(id, { id, priceCents: 0, currency: 'BRL', interval: 'month', createdAt: now, updatedAt: now, ...plan });
      }
      this.tables.set('plan', plans);
    }
  }

  transaction<T>(fn: (store: DataStore) => Promise<T>): Promise<T> {
    const run = async () => {
      const snapshot = clone({ tables: this.tables, sequence: this.sequence });
      try {
        return await fn(this.store);
      } catch (error) {
        this.tables = snapshot.tables;
        this.sequence = snapshot.sequence;
        throw error;
      }
    };
    const result = this.queue.then(run, run);
    this.queue = result.catch(() => undefined);
    return result;
  }

  async ping(): Promise<boolean> {
    return true;
  }

  /** Cópia profunda do estado, para testes compararem antes/depois. */
  snapshot(): unknown {
    return clone({ tables: [...this.tables.entries()].map(([k, v]) => [k, [...v.entries()]]), sequence: this.sequence });
  }
}
