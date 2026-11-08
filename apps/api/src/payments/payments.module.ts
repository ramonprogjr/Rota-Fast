import { Module } from '@nestjs/common';

/**
 * Pagamentos — PREPARADO E VAZIO na v1. A tabela `payments` existe; não há
 * provedor, webhook nem cobrança. Ao ligar (ex.: Mercado Pago/Stripe):
 * - webhook público com verificação de assinatura do provedor;
 * - grava `payments` e atualiza `subscriptions` numa transação;
 * - segredo do provedor só em variável de ambiente do servidor.
 */
@Module({})
export class PaymentsModule {}
