import { randomUUID } from 'node:crypto';
import { createServices, createUser, type Services } from '../testing/fixtures';
import type { SyncOperationDto } from './dto/sync.dto';

const deliveryPayload = (extra: Record<string, unknown> = {}) => ({
  customerName: 'Maria',
  address: 'Rua das Flores',
  number: '10',
  city: 'São Bernardo do Campo',
  latitude: -23.69,
  longitude: -46.56,
  ...extra,
});

function op(
  entityType: string,
  entityId: string,
  operationType: SyncOperationDto['operationType'],
  payload: Record<string, unknown>,
  extra: Partial<SyncOperationDto> = {},
): SyncOperationDto {
  return { operationId: randomUUID(), entityType, entityId, operationType, payload, ...extra };
}

describe('SyncService', () => {
  let s: Services;
  let alice: string;
  const phoneA = randomUUID();
  const phoneB = randomUUID();

  beforeEach(async () => {
    s = createServices();
    alice = await createUser(s);
  });

  const push = (userId: string, deviceId: string, operations: SyncOperationDto[]) =>
    s.sync.push(userId, { deviceId, operations });

  describe('push idempotente', () => {
    it('mesmo operationId 3 vezes: aplica uma vez, depois duplicate com o resultado original', async () => {
      const id = randomUUID();
      const create = op('delivery', id, 'create', deliveryPayload());
      const first = await push(alice, phoneA, [create]);
      const second = await push(alice, phoneA, [create]);
      const third = await push(alice, phoneA, [create]);

      expect(first.results[0]).toMatchObject({ status: 'applied', version: 1 });
      for (const replay of [second, third]) {
        expect(replay.results[0]).toMatchObject({
          operationId: create.operationId,
          status: 'duplicate',
          originalStatus: 'applied',
          version: 1,
        });
      }
      expect(await s.db.store.count('delivery', { id })).toBe(1);
      expect(await s.db.store.count('syncOperation', { id: create.operationId })).toBe(1);
      expect(await s.db.store.count('syncChange', { entityId: id })).toBe(1);
    });

    it('operationId repetido dentro do mesmo lote também é duplicate', async () => {
      const create = op('delivery', randomUUID(), 'create', deliveryPayload());
      const result = await push(alice, phoneA, [create, create]);
      expect(result.results.map((r) => r.status)).toEqual(['applied', 'duplicate']);
      expect(result.summary).toMatchObject({ applied: 1, duplicate: 1 });
    });

    it('operationId de outro usuário é recusado e não vaza o resultado', async () => {
      const bob = await createUser(s);
      const create = op('delivery', randomUUID(), 'create', deliveryPayload());
      await push(alice, phoneA, [create]);
      const stolen = await push(bob, phoneB, [create]);
      expect(stolen.results[0]).toEqual(
        expect.objectContaining({ status: 'rejected', reason: 'operation_id_reused' }),
      );
      expect(stolen.results[0].version).toBeUndefined();
    });

    it('registra o aparelho automaticamente e recusa aparelho de outro usuário', async () => {
      await push(alice, phoneA, [op('delivery', randomUUID(), 'create', deliveryPayload())]);
      expect(await s.db.store.findById('device', phoneA)).toMatchObject({ userId: alice });
      const bob = await createUser(s);
      await expect(push(bob, phoneA, [op('delivery', randomUUID(), 'create', deliveryPayload())])).rejects.toMatchObject({
        code: 'DEVICE_ID_TAKEN',
      });
    });
  });

  describe('conflitos', () => {
    let id: string;

    beforeEach(async () => {
      id = randomUUID();
      await push(alice, phoneA, [op('delivery', id, 'create', deliveryPayload())]);
    });

    it('campos diferentes com a mesma baseVersion são mesclados', async () => {
      const a = await push(alice, phoneA, [op('delivery', id, 'update', { number: '20' }, { baseVersion: 1 })]);
      const b = await push(alice, phoneB, [op('delivery', id, 'update', { notes: 'fundos' }, { baseVersion: 1 })]);
      expect(a.results[0]).toMatchObject({ status: 'applied', version: 2 });
      expect(b.results[0]).toMatchObject({ status: 'applied', version: 3 });
      expect(await s.db.store.findById('delivery', id)).toMatchObject({ number: '20', notes: 'fundos', version: 3 });
    });

    it('mesmo campo com baseVersion antiga = conflict, guardado e com o retrato do servidor', async () => {
      await push(alice, phoneA, [op('delivery', id, 'update', { number: '20' }, { baseVersion: 1 })]);
      const late = op('delivery', id, 'update', { number: '30' }, { baseVersion: 1 });
      const result = await push(alice, phoneB, [late]);
      expect(result.results[0]).toMatchObject({
        status: 'conflict',
        reason: 'version_conflict',
        version: 2,
        details: { fields: ['number'] },
      });
      expect(result.results[0].server).toMatchObject({ number: '20', version: 2 });
      expect(await s.db.store.findById('delivery', id)).toMatchObject({ number: '20' });
      // Nunca descarta em silêncio: a operação fica guardada.
      expect(await s.db.store.findById('syncOperation', late.operationId)).toMatchObject({
        status: 'conflict',
        payload: { number: '30' },
      });
      // Reenviar com a versão nova resolve.
      const retry = await push(alice, phoneB, [op('delivery', id, 'update', { number: '30' }, { baseVersion: 2 })]);
      expect(retry.results[0]).toMatchObject({ status: 'applied', version: 3 });
    });

    it('update sem baseVersion, com status ou campo desconhecido é recusado', async () => {
      const result = await push(alice, phoneA, [
        op('delivery', id, 'update', { number: '1' }),
        op('delivery', id, 'update', { status: 'DELIVERED' }, { baseVersion: 1 }),
        op('delivery', id, 'update', { hacker: true }, { baseVersion: 1 }),
      ]);
      expect(result.results.map((r) => r.reason)).toEqual(['base_version_required', 'use_transition', 'invalid_payload']);
    });

    it('update em entidade excluída = conflict deleted', async () => {
      await push(alice, phoneA, [op('delivery', id, 'delete', {}, { baseVersion: 1 })]);
      const result = await push(alice, phoneB, [op('delivery', id, 'update', { number: '5' }, { baseVersion: 1 })]);
      expect(result.results[0]).toMatchObject({ status: 'conflict', reason: 'deleted' });
    });

    it('transição segue a máquina do app e detecta status divergente', async () => {
      const t1 = await push(alice, phoneA, [
        op('delivery', id, 'transition', { eventId: randomUUID(), fromStatus: 'PENDING', toStatus: 'DELIVERED' }),
      ]);
      expect(t1.results[0]).toMatchObject({ status: 'applied', version: 2 });

      // Outro aparelho, ainda vendo PENDING, tenta marcar FAILED.
      const t2 = await push(alice, phoneB, [
        op('delivery', id, 'transition', {
          eventId: randomUUID(),
          fromStatus: 'PENDING',
          toStatus: 'FAILED',
          reason: 'ABSENT',
        }),
      ]);
      expect(t2.results[0]).toMatchObject({ status: 'conflict', reason: 'status_conflict' });

      // Mesmo destino que o servidor já tem: converge sem erro e sem evento novo.
      const t3 = await push(alice, phoneB, [
        op('delivery', id, 'transition', { eventId: randomUUID(), fromStatus: 'PENDING', toStatus: 'DELIVERED' }),
      ]);
      expect(t3.results[0]).toMatchObject({ status: 'applied', message: 'already_in_status', version: 2 });

      // Fora da máquina: DELIVERED -> SKIPPED.
      const t4 = await push(alice, phoneA, [
        op('delivery', id, 'transition', { eventId: randomUUID(), toStatus: 'SKIPPED' }),
      ]);
      expect(t4.results[0]).toMatchObject({ status: 'rejected', reason: 'invalid_transition' });
      expect(await s.db.store.count('deliveryEvent', { deliveryId: id })).toBe(1);
    });

    it('entidade de outro usuário: not_found, sem revelar nada', async () => {
      const bob = await createUser(s);
      const result = await push(bob, phoneB, [
        op('delivery', id, 'update', { number: '1' }, { baseVersion: 1 }),
        op('delivery', id, 'create', deliveryPayload()),
        op('delivery', id, 'delete', {}),
      ]);
      expect(result.results.map((r) => [r.status, r.reason])).toEqual([
        ['rejected', 'not_found'],
        ['rejected', 'not_found'],
        ['rejected', 'not_found'],
      ]);
      expect(result.results.every((r) => r.server === undefined)).toBe(true);
    });
  });

  describe('rotas no sync', () => {
    it('cria rota, paradas e reordena; referência inexistente é recusada', async () => {
      const routeId = randomUUID();
      const d1 = randomUUID();
      const d2 = randomUUID();
      const s1 = randomUUID();
      const s2 = randomUUID();
      const result = await push(alice, phoneA, [
        op('route', routeId, 'create', { name: 'Manhã', status: 'active' }),
        op('delivery', d1, 'create', deliveryPayload()),
        op('delivery', d2, 'create', deliveryPayload({ customerName: 'João' })),
        op('route_stop', s1, 'create', { routeId, deliveryId: d1, position: 1 }),
        op('route_stop', s2, 'create', { routeId, deliveryId: d2, position: 2 }),
        op('route', routeId, 'reorder', { stopIds: [s2, s1] }, { baseVersion: 1 }),
        op('route_stop', randomUUID(), 'create', { routeId, deliveryId: randomUUID(), position: 3 }),
      ]);
      expect(result.results.map((r) => r.status)).toEqual([
        'applied',
        'applied',
        'applied',
        'applied',
        'applied',
        'applied',
        'rejected',
      ]);
      expect(result.results[6].reason).toBe('reference_not_found');
      const detail = await s.routes.get(alice, routeId);
      expect(detail.stops.map((x) => x.id)).toEqual([s2, s1]);
      expect(detail.manuallyEdited).toBe(true);

      // Lista de abertas diferente da do servidor = conflito (não erro silencioso).
      const stale = await push(alice, phoneB, [op('route', routeId, 'reorder', { stopIds: [s1] })]);
      expect(stale.results[0]).toMatchObject({ status: 'conflict', reason: 'stops_mismatch' });
    });

    it('segunda rota ativa = conflict active_route_exists', async () => {
      const result = await push(alice, phoneA, [
        op('route', randomUUID(), 'create', { status: 'active' }),
        op('route', randomUUID(), 'create', { status: 'active' }),
      ]);
      expect(result.results.map((r) => r.reason ?? r.status)).toEqual(['applied', 'active_route_exists']);
    });

    it('excluir rota pelo sync apaga paradas (tombstone) e mantém entregas', async () => {
      const routeId = randomUUID();
      const d1 = randomUUID();
      const s1 = randomUUID();
      await push(alice, phoneA, [
        op('route', routeId, 'create', {}),
        op('delivery', d1, 'create', deliveryPayload()),
        op('route_stop', s1, 'create', { routeId, deliveryId: d1, position: 1 }),
      ]);
      const del = await push(alice, phoneA, [op('route', routeId, 'delete', {})]);
      expect(del.results[0].status).toBe('applied');
      expect((await s.db.store.findById('routeStop', s1))?.deletedAt).toBeInstanceOf(Date);
      expect((await s.db.store.findById('delivery', d1))?.deletedAt).toBeNull();
    });
  });

  describe('lote', () => {
    it('erro inesperado numa operação: ela vira rejected internal_error e o resto é aplicado', async () => {
      const good = op('delivery', randomUUID(), 'create', deliveryPayload());
      const bad = op('vehicle', randomUUID(), 'create', {
        name: 'Moto',
        type: 'motorcycle',
        kmPerLiter: 35,
        fuelPrice: 6,
        avgSpeedKmh: 28,
        oilIntervalKm: 1000,
      });
      const original = s.db.store.create.bind(s.db.store);
      const spy = jest.spyOn(s.db.store, 'create').mockImplementation((name, data) => {
        if (name === 'vehicle') throw new Error('falha simulada');
        return original(name, data);
      });
      const result = await push(alice, phoneA, [good, bad]);
      spy.mockRestore();
      expect(result.results.map((r) => [r.status, r.reason])).toEqual([
        ['applied', undefined],
        ['rejected', 'internal_error'],
      ]);
      expect(await s.db.store.count('delivery', { id: good.entityId })).toBe(1);
    });
  });

  describe('pull', () => {
    it('pagina pelo cursor, em ordem, com tombstones e só do usuário', async () => {
      const bob = await createUser(s);
      const ids = Array.from({ length: 5 }, () => randomUUID());
      await push(
        alice,
        phoneA,
        ids.map((id) => op('delivery', id, 'create', deliveryPayload())),
      );
      await push(bob, phoneB, [op('delivery', randomUUID(), 'create', deliveryPayload())]);
      await push(alice, phoneA, [op('delivery', ids[0], 'delete', {})]);

      const page1 = await s.sync.pull(alice, '0', 2);
      expect(page1.hasMore).toBe(true);
      expect(page1.changes.map((c) => c.entityId)).toEqual([ids[0], ids[1]]);
      const page2 = await s.sync.pull(alice, page1.nextCursor, 2);
      const page3 = await s.sync.pull(alice, page2.nextCursor, 2);
      expect(page3.hasMore).toBe(false);
      const all = [...page1.changes, ...page2.changes, ...page3.changes];
      const seqs = all.map((c) => Number(c.seq));
      expect([...seqs].sort((a, b) => a - b)).toEqual(seqs);
      expect(new Set(all.map((c) => c.entityId))).toEqual(new Set(ids));
      // ids[0] aparece de novo no fim como tombstone (o retrato é sempre o atual).
      const tomb = all.filter((c) => c.entityId === ids[0]).at(-1)!;
      expect(tomb).toMatchObject({ operation: 'delete', data: null, version: 2 });
      expect(tomb.deletedAt).toBeInstanceOf(Date);
      const upsert = all.find((c) => c.entityId === ids[2])!;
      expect(upsert.data).toMatchObject({ customerName: 'Maria', status: 'PENDING' });
      expect(upsert.data).not.toHaveProperty('userId');
      expect(upsert.data).not.toHaveProperty('fieldVersions');

      // Nada novo: cursor parado, lista vazia.
      const empty = await s.sync.pull(alice, page3.nextCursor, 2);
      expect(empty).toMatchObject({ changes: [], hasMore: false, nextCursor: page3.nextCursor });
    });

    it('cada entidade aparece uma vez por página, com o retrato mais novo', async () => {
      const id = randomUUID();
      await push(alice, phoneA, [op('delivery', id, 'create', deliveryPayload())]);
      await push(alice, phoneA, [op('delivery', id, 'update', { number: '77' }, { baseVersion: 1 })]);
      const page = await s.sync.pull(alice, '0', 100);
      expect(page.changes).toHaveLength(1);
      expect(page.changes[0]).toMatchObject({ version: 2, data: { number: '77' } });
    });
  });
});
