import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { Prisma, PrismaClient } from '@prisma/client';
import { type EntityMap, type EntityName, NULLABLE_JSON_FIELDS } from '../entities';
import type { Database, DataStore, FindOptions, Where } from '../data-store';

type Client = PrismaClient | Prisma.TransactionClient;

/** Delegate genérico (findUnique/findFirst/...). Os tipos ficam no DataStore. */
interface Delegate {
  findUnique(args: unknown): Promise<unknown>;
  findFirst(args: unknown): Promise<unknown>;
  findMany(args: unknown): Promise<unknown[]>;
  count(args: unknown): Promise<number>;
  create(args: unknown): Promise<unknown>;
  update(args: unknown): Promise<unknown>;
}

const PRIMARY_KEY: Partial<Record<EntityName, string>> = { syncChange: 'seq' };

/** bigint (version, seq, base_version) -> number. Seguro até 2^53. */
function normalize<T>(row: unknown): T {
  if (row === null || row === undefined) {
    return row as T;
  }
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(row as Record<string, unknown>)) {
    out[key] = typeof value === 'bigint' ? Number(value) : value;
  }
  return out as T;
}

/** null em JSON anulável precisa ser Prisma.DbNull. */
function toPrismaData(data: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(data)) {
    if (value === undefined) continue;
    out[key] = value === null && NULLABLE_JSON_FIELDS.has(key) ? Prisma.DbNull : value;
  }
  return out;
}

class PrismaStore implements DataStore {
  constructor(private readonly client: Client) {}

  private delegate(name: EntityName): Delegate {
    return (this.client as unknown as Record<string, Delegate>)[name];
  }

  async findById<N extends EntityName>(name: N, id: string): Promise<EntityMap[N] | null> {
    const pk = PRIMARY_KEY[name] ?? 'id';
    return normalize(await this.delegate(name).findUnique({ where: { [pk]: id } }));
  }

  async findFirst<N extends EntityName>(
    name: N,
    where: Where<EntityMap[N]>,
    options: FindOptions<EntityMap[N]> = {},
  ): Promise<EntityMap[N] | null> {
    return normalize(await this.delegate(name).findFirst({ where, orderBy: options.orderBy, skip: options.skip }));
  }

  async findMany<N extends EntityName>(
    name: N,
    where: Where<EntityMap[N]>,
    options: FindOptions<EntityMap[N]> = {},
  ): Promise<EntityMap[N][]> {
    const rows = await this.delegate(name).findMany({
      where,
      orderBy: options.orderBy,
      skip: options.skip,
      take: options.take,
    });
    return rows.map((row) => normalize<EntityMap[N]>(row));
  }

  count<N extends EntityName>(name: N, where: Where<EntityMap[N]>): Promise<number> {
    return this.delegate(name).count({ where });
  }

  async create<N extends EntityName>(name: N, data: Partial<EntityMap[N]>): Promise<EntityMap[N]> {
    return normalize(await this.delegate(name).create({ data: toPrismaData(data as Record<string, unknown>) }));
  }

  async update<N extends EntityName>(name: N, id: string, data: Partial<EntityMap[N]>): Promise<EntityMap[N]> {
    return normalize(
      await this.delegate(name).update({ where: { id }, data: toPrismaData(data as Record<string, unknown>) }),
    );
  }

  async lockUser(userId: string): Promise<void> {
    await (this.client as Prisma.TransactionClient).$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${userId}, 0))`;
  }
}

/**
 * Implementação de produção. Conecta com DATABASE_URL (pooler do Supabase).
 * O papel usado é dono das tabelas e por isso ignora RLS — só a API usa essa
 * credencial; ela nunca vai para o app.
 */
@Injectable()
export class PrismaDatabase implements Database, OnModuleDestroy {
  private readonly logger = new Logger('PrismaDatabase');
  private readonly client = new PrismaClient({ log: ['warn', 'error'] });
  readonly store: DataStore = new PrismaStore(this.client);

  transaction<T>(fn: (store: DataStore) => Promise<T>): Promise<T> {
    return this.client.$transaction((tx) => fn(new PrismaStore(tx)), {
      maxWait: 10_000,
      timeout: 30_000,
      isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted,
    });
  }

  async ping(): Promise<boolean> {
    try {
      await this.client.$queryRaw`SELECT 1`;
      return true;
    } catch (error) {
      this.logger.warn(`Banco indisponível: ${(error as Error).message}`);
      return false;
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.client.$disconnect();
  }
}
