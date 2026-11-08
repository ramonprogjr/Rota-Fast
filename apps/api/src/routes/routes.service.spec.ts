import { randomUUID } from 'node:crypto';
import { AppException } from '../common/exceptions/app.exception';
import { createRouteWithStops, createServices, createUser, deliveryInput, type Services } from '../testing/fixtures';

async function expectHttp(promise: Promise<unknown>, status: number, code?: string) {
  const error = await promise.then(
    () => {
      throw new Error('esperava erro');
    },
    (e: unknown) => e,
  );
  expect(error).toBeInstanceOf(AppException);
  expect((error as AppException).getStatus()).toBe(status);
  if (code) expect((error as AppException).code).toBe(code);
  return error as AppException;
}

describe('RoutesService', () => {
  let s: Services;
  let alice: string;
  let bob: string;

  beforeEach(async () => {
    s = createServices();
    alice = await createUser(s);
    bob = await createUser(s);
  });

  describe('dono da rota', () => {
    it('B não lê, não altera, não reordena, não adiciona paradas e não exclui a rota de A (404)', async () => {
      const { route, stopIds } = await createRouteWithStops(s, alice, 2);
      await expectHttp(s.routes.get(bob, route.id), 404, 'ROUTE_NOT_FOUND');
      await expectHttp(s.routes.update(bob, route.id, { name: 'invadida' }), 404, 'ROUTE_NOT_FOUND');
      await expectHttp(s.routes.reorder(bob, route.id, { stopIds: [...stopIds].reverse() }), 404);
      await expectHttp(s.routes.addStops(bob, route.id, { deliveries: [deliveryInput()] }), 404);
      await expectHttp(s.routes.remove(bob, route.id, false), 404);
      const intact = await s.routes.get(alice, route.id);
      expect(intact.name).toBe('Rota de teste');
      expect(intact.stops.map((x) => x.id)).toEqual(stopIds);
    });

    it('lista só as rotas do próprio usuário, paginadas', async () => {
      for (let i = 0; i < 3; i++) await s.routes.create(alice, { name: `A${i}` });
      await s.routes.create(bob, { name: 'B' });
      const page1 = await s.routes.list(alice, { page: 1, pageSize: 2 });
      const page2 = await s.routes.list(alice, { page: 2, pageSize: 2 });
      expect(page1.total).toBe(3);
      expect(page1.items).toHaveLength(2);
      expect(page2.items).toHaveLength(1);
      expect([...page1.items, ...page2.items].map((r) => r.name).sort()).toEqual(['A0', 'A1', 'A2']);
    });

    it('B não coloca a entrega de A na própria rota', async () => {
      const { deliveryIds } = await createRouteWithStops(s, alice, 1);
      const bobRoute = await s.routes.create(bob, {});
      await expectHttp(s.routes.addStops(bob, bobRoute.id, { deliveryIds }), 404, 'DELIVERY_NOT_FOUND');
    });
  });

  describe('reorder', () => {
    it('grava a nova ordem, marca manuallyEdited e sobe a versão', async () => {
      const { route, stopIds } = await createRouteWithStops(s, alice, 3);
      const reversed = [...stopIds].reverse();
      const result = await s.routes.reorder(alice, route.id, { stopIds: reversed });
      expect(result.stops.map((x) => x.id)).toEqual(reversed);
      expect(result.manuallyEdited).toBe(true);
      expect(result.version).toBeGreaterThan(route.version);
    });

    it('recusa parada repetida (422 DUPLICATE_STOPS)', async () => {
      const { route, stopIds } = await createRouteWithStops(s, alice, 3);
      await expectHttp(
        s.routes.reorder(alice, route.id, { stopIds: [stopIds[0], stopIds[0], stopIds[1]] }),
        422,
        'DUPLICATE_STOPS',
      );
    });

    it('recusa lista incompleta ou com parada estranha (422 STOPS_MISMATCH)', async () => {
      const { route, stopIds } = await createRouteWithStops(s, alice, 3);
      const missing = await expectHttp(
        s.routes.reorder(alice, route.id, { stopIds: stopIds.slice(0, 2) }),
        422,
        'STOPS_MISMATCH',
      );
      expect(missing.details).toEqual({ missing: [stopIds[2]], unknown: [] });
      const stranger = randomUUID();
      await expectHttp(
        s.routes.reorder(alice, route.id, { stopIds: [...stopIds, stranger] }),
        422,
        'STOPS_MISMATCH',
      );
    });

    it('só aceita as abertas: concluídas ficam fora da lista e mantêm a posição', async () => {
      const { route, stopIds, deliveryIds } = await createRouteWithStops(s, alice, 3);
      await s.deliveries.addEvent(alice, deliveryIds[0], { toStatus: 'DELIVERED' });
      // Mandar a concluída junto é erro.
      await expectHttp(s.routes.reorder(alice, route.id, { stopIds: [...stopIds].reverse() }), 422, 'STOPS_MISMATCH');
      const result = await s.routes.reorder(alice, route.id, { stopIds: [stopIds[2], stopIds[1]] });
      expect(result.stops.map((x) => [x.id, x.position, x.isOpen])).toEqual([
        [stopIds[0], 1, false],
        [stopIds[2], 2, true],
        [stopIds[1], 3, true],
      ]);
    });

    it('baseVersion antiga depois de outra reordenação = 409', async () => {
      const { route, stopIds } = await createRouteWithStops(s, alice, 3);
      const current = await s.routes.get(alice, route.id);
      await s.routes.reorder(alice, route.id, { stopIds: [...stopIds].reverse(), baseVersion: current.version });
      await expectHttp(
        s.routes.reorder(alice, route.id, { stopIds, baseVersion: current.version }),
        409,
        'VERSION_CONFLICT',
      );
    });

    it('rota concluída não é reordenada', async () => {
      const { route, stopIds } = await createRouteWithStops(s, alice, 2);
      await s.routes.update(alice, route.id, { status: 'completed' });
      await expectHttp(s.routes.reorder(alice, route.id, { stopIds }), 409, 'ROUTE_COMPLETED');
    });
  });

  describe('status e exclusão', () => {
    it('só uma rota ativa por usuário', async () => {
      const a = await s.routes.create(alice, { status: 'active' });
      await expectHttp(s.routes.create(alice, { status: 'active' }), 409, 'ACTIVE_ROUTE_EXISTS');
      const b = await s.routes.create(alice, {});
      await expectHttp(s.routes.update(alice, b.id, { status: 'active' }), 409, 'ACTIVE_ROUTE_EXISTS');
      await s.routes.update(alice, a.id, { status: 'completed' });
      const activated = await s.routes.update(alice, b.id, { status: 'active' });
      expect(activated.status).toBe('active');
      // Outro usuário tem a própria rota ativa.
      await expect(s.routes.create(bob, { status: 'active' })).resolves.toBeDefined();
    });

    it('concluir grava completedAt; reabrir limpa', async () => {
      const route = await s.routes.create(alice, { status: 'active' });
      const done = await s.routes.update(alice, route.id, { status: 'completed' });
      expect(done.completedAt).toBeInstanceOf(Date);
      const reopened = await s.routes.update(alice, route.id, { status: 'active' });
      expect(reopened.completedAt).toBeNull();
      // Status mudou depois da versão 1: quem ainda via a v1 entra em conflito...
      await expectHttp(s.routes.update(alice, route.id, { status: 'completed', baseVersion: 1 }), 409, 'VERSION_CONFLICT');
      // ...mas um campo que ninguém mexeu é mesclado.
      await expect(s.routes.update(alice, route.id, { name: 'Tarde', baseVersion: 1 })).resolves.toMatchObject({
        name: 'Tarde',
      });
    });

    it('excluir é lógico e nunca apaga entregas que estão em outra rota', async () => {
      const first = await createRouteWithStops(s, alice, 2);
      const second = await s.routes.create(alice, {});
      // A entrega 0 também está na segunda rota.
      await s.routes.addStops(alice, second.id, { deliveryIds: [first.deliveryIds[0]] });

      const result = await s.routes.remove(alice, first.route.id, true);
      expect(result.deletedDeliveryIds).toEqual([first.deliveryIds[1]]);
      await expectHttp(s.routes.get(alice, first.route.id), 404);
      await expect(s.deliveries.get(alice, first.deliveryIds[0])).resolves.toBeDefined();
      await expectHttp(s.deliveries.get(alice, first.deliveryIds[1]), 404);
      const other = await s.routes.get(alice, second.id);
      expect(other.stops.map((x) => x.deliveryId)).toEqual([first.deliveryIds[0]]);
      const audit = await s.db.store.findMany('auditLog', { userId: alice, action: 'route.delete' });
      expect(audit).toHaveLength(1);
    });

    it('excluir sem withExclusiveDeliveries mantém todas as entregas', async () => {
      const { route, deliveryIds } = await createRouteWithStops(s, alice, 2);
      await s.routes.remove(alice, route.id, false);
      for (const id of deliveryIds) {
        await expect(s.deliveries.get(alice, id)).resolves.toBeDefined();
      }
    });

    it('entrega já presente na rota = 409 STOP_EXISTS', async () => {
      const { route, deliveryIds } = await createRouteWithStops(s, alice, 1);
      await expectHttp(s.routes.addStops(alice, route.id, { deliveryIds }), 409, 'STOP_EXISTS');
    });
  });
});
