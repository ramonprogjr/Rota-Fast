import { Inject, Injectable } from '@nestjs/common';
import type { AuthPrincipal } from '../auth/jwt-verifier';
import { NotFoundAppException } from '../common/exceptions/app.exception';
import { DATABASE, type Database } from '../persistence/data-store';
import type { UserRow } from '../persistence/entities';
import type { UpdateMeDto } from './dto/user.dto';

const CACHE_LIMIT = 10_000;

@Injectable()
export class UsersService {
  /** Usuários que já sabemos existir em `users` (evita 1 query por requisição). */
  private readonly known = new Set<string>();

  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** Cria a linha em `users` no primeiro acesso (id = sub do JWT). */
  async ensureExists(principal: AuthPrincipal): Promise<void> {
    if (this.known.has(principal.userId)) {
      return;
    }
    await this.db.transaction(async (store) => {
      const existing = await store.findById('user', principal.userId);
      if (!existing) {
        await store.create('user', {
          id: principal.userId,
          email: principal.email ?? null,
          name: null,
          country: 'BR',
          locale: 'pt-BR',
          timezone: 'America/Sao_Paulo',
          deletedAt: null,
        });
      } else if (principal.email && existing.email !== principal.email) {
        // O e-mail vem do Supabase Auth; acompanha a troca feita lá.
        await store.update('user', principal.userId, { email: principal.email, updatedAt: new Date() });
      }
    });
    if (this.known.size >= CACHE_LIMIT) {
      this.known.clear();
    }
    this.known.add(principal.userId);
  }

  async getMe(userId: string): Promise<UserRow> {
    const user = await this.db.store.findById('user', userId);
    if (!user || user.deletedAt) {
      throw new NotFoundAppException('user');
    }
    return user;
  }

  async updateMe(userId: string, dto: UpdateMeDto): Promise<UserRow> {
    await this.getMe(userId);
    return this.db.store.update('user', userId, {
      ...(dto.name !== undefined ? { name: dto.name } : {}),
      ...(dto.country !== undefined ? { country: dto.country.toUpperCase() } : {}),
      ...(dto.locale !== undefined ? { locale: dto.locale } : {}),
      ...(dto.timezone !== undefined ? { timezone: dto.timezone } : {}),
      updatedAt: new Date(),
    });
  }
}
