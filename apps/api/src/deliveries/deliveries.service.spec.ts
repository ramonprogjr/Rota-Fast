import { randomUUID } from 'node:crypto';
import { AppException } from '../common/exceptions/app.exception';
import { createRouteWithStops, createServices, createUser, type Services } from '../testing/fixtures';

async function httpError(promise: Promise<unknown>): Promise<AppException> {
  const error = await promise.then(
    () => {
      throw new Error('esperava erro');
    },
    (e: unknown) => e,
  );
  expect(error).toBeInstanceOf(AppException);
  return error as AppException;
}

describe('DeliveriesService', () => {
  let s: Services;
  let alice: string;
  let deliveryId: string;

  beforeEach(async () => {
    s = createServices();
    alice = await createUser(s);
    ({
      deliveryIds: [deliveryId],
    } = await createRouteWithStops(s, alice, 1));
  });

  it('troca de status grava o evento na mesma transação', async () => {
    const { delivery, event } = await s.deliveries.addEvent(alice, deliveryId, {
      toStatus: 'FAILED',
      reason: 'ABSENT',
      note: 'ninguém atendeu',
    });
    expect(delivery).toMatchObject({ status: 'FAILED', failureReason: 'ABSENT', attempts: 1, version: 2 });
    expect(event).toMatchObject({ kind: 'status', fromStatus: 'PENDING', toStatus: 'FAILED', reason: 'ABSENT' });
    const events = await s.db.store.findMany('deliveryEvent', { deliveryId });
    expect(events).toHaveLength(1);
  });

  it('transição inválida = 422 e nada muda', async () => {
    await s.deliveries.addEvent(alice, deliveryId, { toStatus: 'DELIVERED' });
    const error = await httpError(s.deliveries.addEvent(alice, deliveryId, { toStatus: 'SKIPPED' }));
    expect(error.getStatus()).toBe(422);
    expect(error.code).toBe('INVALID_TRANSITION');
    expect((await s.deliveries.get(alice, deliveryId)).status).toBe('DELIVERED');
  });

  it('FAILED sem motivo = 422 FAILURE_REASON_REQUIRED', async () => {
    const error = await httpError(s.deliveries.addEvent(alice, deliveryId, { toStatus: 'FAILED' }));
    expect(error.code).toBe('FAILURE_REASON_REQUIRED');
  });

  it('fromStatus diferente do servidor = 409 STATUS_CONFLICT', async () => {
    await s.deliveries.addEvent(alice, deliveryId, { toStatus: 'IN_PROGRESS' });
    const error = await httpError(
      s.deliveries.addEvent(alice, deliveryId, { fromStatus: 'PENDING', toStatus: 'SKIPPED' }),
    );
    expect(error.getStatus()).toBe(409);
    expect(error.code).toBe('STATUS_CONFLICT');
  });

  it('mesmo id de evento duas vezes devolve o mesmo evento (idempotente)', async () => {
    const id = randomUUID();
    const first = await s.deliveries.addEvent(alice, deliveryId, { id, toStatus: 'DELIVERED' });
    const again = await s.deliveries.addEvent(alice, deliveryId, { id, toStatus: 'DELIVERED' });
    expect(again.event.id).toBe(first.event.id);
    expect(await s.db.store.count('deliveryEvent', { deliveryId })).toBe(1);
  });

  it('PATCH grava evento edit com os campos alterados e detecta conflito por campo', async () => {
    const updated = await s.deliveries.update(alice, deliveryId, { number: '999', baseVersion: 1 });
    expect(updated.number).toBe('999');
    const [edit] = await s.db.store.findMany('deliveryEvent', { deliveryId, kind: 'edit' });
    expect(edit.changedFields).toEqual(['number']);
    // Outro campo, mesma versão base antiga: mescla sem conflito.
    await expect(s.deliveries.update(alice, deliveryId, { notes: 'portão azul', baseVersion: 1 })).resolves.toMatchObject({
      notes: 'portão azul',
      number: '999',
    });
    // Mesmo campo com versão base antiga: conflito.
    const error = await httpError(s.deliveries.update(alice, deliveryId, { number: '1', baseVersion: 1 }));
    expect(error.code).toBe('VERSION_CONFLICT');
  });

  it('outro usuário recebe 404', async () => {
    const bob = await createUser(s);
    expect((await httpError(s.deliveries.get(bob, deliveryId))).getStatus()).toBe(404);
    expect((await httpError(s.deliveries.addEvent(bob, deliveryId, { toStatus: 'DELIVERED' }))).getStatus()).toBe(404);
  });
});
