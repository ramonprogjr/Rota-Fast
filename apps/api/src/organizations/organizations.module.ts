import { Inject, Injectable, Module } from '@nestjs/common';
import { DATABASE, type Database } from '../persistence/data-store';
import type { MembershipRow } from '../persistence/entities';

/**
 * Organizações (empresas/equipes) — PREPARADO, sem endpoints na v1.
 * Tabelas `organizations` e `memberships` (owner/admin/driver) já existem,
 * com RLS por `is_org_member`. Quando houver equipes, as entidades ganham
 * `organization_id` opcional e a checagem de dono passa a aceitar membros.
 */
@Injectable()
export class OrganizationsService {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  membershipsOf(userId: string): Promise<MembershipRow[]> {
    return this.db.store.findMany('membership', { userId });
  }

  async isMember(userId: string, organizationId: string): Promise<boolean> {
    return (await this.db.store.count('membership', { userId, organizationId })) > 0;
  }
}

@Module({
  providers: [OrganizationsService],
  exports: [OrganizationsService],
})
export class OrganizationsModule {}
