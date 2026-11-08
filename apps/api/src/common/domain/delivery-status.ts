/**
 * Máquina de estados da entrega. Cópia fiel de `DeliveryStatus.canGoTo` e
 * `applyTransition` do app (lib/models/delivery.dart e
 * lib/data/repositories/delivery_repository.dart). Se a regra mudar lá, muda aqui.
 *
 * PENDING ──> IN_PROGRESS ──> DELIVERED
 *    │             │  └─────> FAILED ──┐
 *    │             └────────> SKIPPED ─┤
 *    ├──> DELIVERED / FAILED / SKIPPED │  (marcar direto da lista)
 *    └<────────────────────────────────┘  "Tentar de novo"
 * DELIVERED ──> PENDING  só pela ação explícita "Reabrir"
 */
export const DELIVERY_STATUSES = ['PENDING', 'IN_PROGRESS', 'DELIVERED', 'FAILED', 'SKIPPED'] as const;
export type DeliveryStatus = (typeof DELIVERY_STATUSES)[number];

export const FAILURE_REASONS = ['ABSENT', 'ADDRESS_NOT_FOUND', 'REFUSED', 'CLOSED', 'ACCESS', 'OTHER'] as const;
export type FailureReason = (typeof FAILURE_REASONS)[number];

export const DELIVERY_PRIORITIES = ['normal', 'high', 'urgent'] as const;
export type DeliveryPriority = (typeof DELIVERY_PRIORITIES)[number];

/** Ainda faz parte da rota (entra na otimização e na lista "Na rota"). */
export function isOpenStatus(status: string): boolean {
  return status === 'PENDING' || status === 'IN_PROGRESS' || status === 'SKIPPED';
}

export function canGoTo(from: DeliveryStatus, to: DeliveryStatus): boolean {
  if (from === to) {
    return false;
  }
  switch (from) {
    case 'PENDING':
    case 'IN_PROGRESS':
    case 'SKIPPED':
      return true;
    case 'FAILED':
      return to === 'PENDING';
    case 'DELIVERED':
      // Só pela ação explícita "Reabrir".
      return to === 'PENDING';
  }
}

export class InvalidTransitionError extends Error {
  constructor(
    readonly from: DeliveryStatus,
    readonly to: DeliveryStatus,
  ) {
    super(`Transição inválida: ${from} -> ${to}.`);
  }
}

export class FailureReasonRequiredError extends Error {
  constructor() {
    super('Informe o motivo de não ter entregado (failureReason).');
  }
}

export interface TransitionState {
  status: DeliveryStatus;
  failureReason: FailureReason | null;
  attempts: number;
  deliveredAt: Date | null;
}

/**
 * Regra única de troca de status. Devolve os campos novos; lança
 * [InvalidTransitionError] fora da máquina e [FailureReasonRequiredError]
 * se FAILED vier sem motivo.
 */
export function applyTransition(
  current: TransitionState,
  to: DeliveryStatus,
  reason: FailureReason | null | undefined,
  at: Date,
): TransitionState {
  if (!canGoTo(current.status, to)) {
    throw new InvalidTransitionError(current.status, to);
  }
  if (to === 'FAILED' && !reason) {
    throw new FailureReasonRequiredError();
  }
  return {
    status: to,
    deliveredAt: to === 'DELIVERED' ? at : null,
    failureReason: to === 'FAILED' ? (reason as FailureReason) : null,
    attempts: to === 'FAILED' ? current.attempts + 1 : current.attempts,
  };
}
