import type { EntityMap, EntityName } from './entities';

/** Filtro por igualdade (null = IS NULL), lista (`in`) ou maior que (`gt`). */
export type FieldFilter<V> = V | null | { in: V[] } | { gt: V };
export type Where<T> = { [K in keyof T]?: FieldFilter<T[K]> };
export type OrderBy<T> = { [K in keyof T]?: 'asc' | 'desc' };

export interface FindOptions<T> {
  orderBy?: OrderBy<T>[];
  skip?: number;
  take?: number;
}

/**
 * Porta única de dados (repositório genérico). Duas implementações:
 * - PrismaDatabase (produção, Supabase Postgres);
 * - MemoryDatabase (testes unitários e e2e, sem banco).
 * Serviços nunca importam Prisma direto: só esta interface.
 */
export interface DataStore {
  findById<N extends EntityName>(name: N, id: string): Promise<EntityMap[N] | null>;
  findFirst<N extends EntityName>(
    name: N,
    where: Where<EntityMap[N]>,
    options?: FindOptions<EntityMap[N]>,
  ): Promise<EntityMap[N] | null>;
  findMany<N extends EntityName>(
    name: N,
    where: Where<EntityMap[N]>,
    options?: FindOptions<EntityMap[N]>,
  ): Promise<EntityMap[N][]>;
  count<N extends EntityName>(name: N, where: Where<EntityMap[N]>): Promise<number>;
  /** Insere e devolve a linha com os padrões do banco preenchidos. */
  create<N extends EntityName>(name: N, data: Partial<EntityMap[N]>): Promise<EntityMap[N]>;
  /** Atualiza por id e devolve a linha nova. */
  update<N extends EntityName>(name: N, id: string, data: Partial<EntityMap[N]>): Promise<EntityMap[N]>;
  /**
   * Serializa as escritas de um usuário dentro da transação
   * (pg_advisory_xact_lock). Garante que o `seq` de sync_changes de um mesmo
   * usuário é confirmado em ordem — o pull nunca pula uma mudança.
   */
  lockUser(userId: string): Promise<void>;
}

export interface Database {
  /** Acesso fora de transação (leituras simples). */
  readonly store: DataStore;
  /** Roda [fn] numa transação. Exceção = rollback de tudo. */
  transaction<T>(fn: (store: DataStore) => Promise<T>): Promise<T>;
  ping(): Promise<boolean>;
}

export const DATABASE = Symbol('DATABASE');
