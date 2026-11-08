import {
  applyTransition,
  canGoTo,
  DELIVERY_STATUSES,
  type DeliveryStatus,
  FailureReasonRequiredError,
  InvalidTransitionError,
  isOpenStatus,
} from './delivery-status';

/** Tabela esperada, igual a DeliveryStatus.canGoTo do app. */
const ALLOWED: Record<DeliveryStatus, DeliveryStatus[]> = {
  PENDING: ['IN_PROGRESS', 'DELIVERED', 'FAILED', 'SKIPPED'],
  IN_PROGRESS: ['PENDING', 'DELIVERED', 'FAILED', 'SKIPPED'],
  SKIPPED: ['PENDING', 'IN_PROGRESS', 'DELIVERED', 'FAILED'],
  FAILED: ['PENDING'],
  DELIVERED: ['PENDING'],
};

describe('máquina de estados da entrega', () => {
  const at = new Date('2026-11-08T12:00:00Z');
  const base = { failureReason: null, attempts: 0, deliveredAt: null };

  for (const from of DELIVERY_STATUSES) {
    for (const to of DELIVERY_STATUSES) {
      const allowed = ALLOWED[from].includes(to);
      it(`${from} -> ${to}: ${allowed ? 'permitido' : 'recusado'}`, () => {
        expect(canGoTo(from, to)).toBe(allowed);
      });
    }
  }

  it('DELIVERED grava deliveredAt e limpa motivo', () => {
    const next = applyTransition({ ...base, status: 'IN_PROGRESS' }, 'DELIVERED', null, at);
    expect(next).toEqual({ status: 'DELIVERED', deliveredAt: at, failureReason: null, attempts: 0 });
  });

  it('FAILED exige motivo e soma uma tentativa', () => {
    expect(() => applyTransition({ ...base, status: 'PENDING' }, 'FAILED', null, at)).toThrow(
      FailureReasonRequiredError,
    );
    const next = applyTransition({ ...base, status: 'PENDING', attempts: 1 }, 'FAILED', 'ABSENT', at);
    expect(next).toEqual({ status: 'FAILED', deliveredAt: null, failureReason: 'ABSENT', attempts: 2 });
  });

  it('"Tentar de novo" (FAILED -> PENDING) limpa o motivo e mantém tentativas', () => {
    const next = applyTransition(
      { status: 'FAILED', failureReason: 'CLOSED', attempts: 2, deliveredAt: null },
      'PENDING',
      null,
      at,
    );
    expect(next).toEqual({ status: 'PENDING', failureReason: null, attempts: 2, deliveredAt: null });
  });

  it('"Reabrir" (DELIVERED -> PENDING) limpa deliveredAt', () => {
    const next = applyTransition({ ...base, status: 'DELIVERED', deliveredAt: at }, 'PENDING', null, at);
    expect(next.deliveredAt).toBeNull();
  });

  it('transição fora da máquina lança InvalidTransitionError', () => {
    expect(() => applyTransition({ ...base, status: 'DELIVERED' }, 'FAILED', 'ABSENT', at)).toThrow(
      InvalidTransitionError,
    );
    expect(() => applyTransition({ ...base, status: 'PENDING' }, 'PENDING', null, at)).toThrow(InvalidTransitionError);
  });

  it('abertas = PENDING, IN_PROGRESS, SKIPPED', () => {
    expect(DELIVERY_STATUSES.filter(isOpenStatus)).toEqual(['PENDING', 'IN_PROGRESS', 'SKIPPED']);
  });
});
