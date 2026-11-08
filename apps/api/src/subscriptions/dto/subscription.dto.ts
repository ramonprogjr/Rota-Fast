import { ApiProperty } from '@nestjs/swagger';

export class PlanResponse {
  code: string;
  name: string;
  priceCents: number;
  currency: string;
  interval: string;
  @ApiProperty({ type: 'object', additionalProperties: true, example: { devices: 2, syncEnabled: true } })
  limits: Record<string, unknown>;
}

export class SubscriptionResponse {
  plan: PlanResponse;
  @ApiProperty({ enum: ['trialing', 'active', 'past_due', 'canceled'] })
  status: string;
  /** default = sem assinatura (plano free). */
  @ApiProperty({ enum: ['default', 'subscription'] })
  source: 'default' | 'subscription';
  currentPeriodEnd: Date | null;
  /** Sempre false na v1: nenhuma cobrança ligada. */
  billingEnabled: boolean;
}
