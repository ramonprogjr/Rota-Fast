import { Inject, Injectable } from '@nestjs/common';
import { DATABASE, type Database } from '../persistence/data-store';
import type { PlanRow } from '../persistence/entities';
import type { SubscriptionResponse } from './dto/subscription.dto';

/** Plano usado se a tabela de planos ainda não tiver a semente. */
const FALLBACK_FREE: Pick<PlanRow, 'code' | 'name' | 'priceCents' | 'currency' | 'interval' | 'limits'> = {
  code: 'free',
  name: 'Grátis',
  priceCents: 0,
  currency: 'BRL',
  interval: 'month',
  limits: { devices: 2, syncEnabled: true, historyDays: 365 },
};

/**
 * Monetização preparada e DESLIGADA: não há cobrança nem integração de
 * pagamento. Sem assinatura = plano free.
 */
@Injectable()
export class SubscriptionsService {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  async getForUser(userId: string): Promise<SubscriptionResponse> {
    const subscription = await this.db.store.findFirst(
      'subscription',
      { userId, status: { in: ['active', 'trialing'] } },
      { orderBy: [{ createdAt: 'desc' }] },
    );
    if (subscription) {
      const plan = await this.db.store.findById('plan', subscription.planId);
      if (plan) {
        return {
          plan: pickPlan(plan),
          status: subscription.status,
          source: 'subscription',
          currentPeriodEnd: subscription.currentPeriodEnd,
          billingEnabled: false,
        };
      }
    }
    const free = (await this.db.store.findFirst('plan', { code: 'free' })) ?? FALLBACK_FREE;
    return { plan: pickPlan(free), status: 'active', source: 'default', currentPeriodEnd: null, billingEnabled: false };
  }
}

function pickPlan(plan: Pick<PlanRow, 'code' | 'name' | 'priceCents' | 'currency' | 'interval' | 'limits'>) {
  return {
    code: plan.code,
    name: plan.name,
    priceCents: plan.priceCents,
    currency: plan.currency,
    interval: plan.interval,
    limits: plan.limits,
  };
}
