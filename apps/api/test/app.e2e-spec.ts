import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import type { App } from 'supertest/types';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { MemoryDatabase } from '../src/persistence/memory/memory-database';
import { createTestAuth } from '../src/testing/jwt-test-keys';

/**
 * Sobe a API inteira (guards, pipes, filtro de erro, rate limit) com o banco
 * em memória e um JWKS local. Mesmo caminho HTTP da produção, sem Supabase.
 */
describe('Rota Max API (e2e)', () => {
  let app: INestApplication<App>;
  let alice: string;
  let bob: string;
  const aliceId = randomUUID();
  const bobId = randomUUID();
  const deviceId = randomUUID();

  beforeAll(async () => {
    const auth = await createTestAuth();
    const moduleRef = await Test.createTestingModule({
      imports: [AppModule.forRoot({ database: new MemoryDatabase(), verifier: auth.verifier })],
    }).compile();
    app = moduleRef.createNestApplication();
    configureApp(app);
    await app.init();
    alice = `Bearer ${await auth.sign(aliceId)}`;
    bob = `Bearer ${await auth.sign(bobId)}`;
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET /v1/health é público', async () => {
    const res = await request(app.getHttpServer()).get('/v1/health').expect(200);
    expect(res.body).toMatchObject({ status: 'ok', database: 'up' });
    expect(res.headers['x-request-id']).toBeDefined();
  });

  it('sem token = 401 no formato padrão', async () => {
    const res = await request(app.getHttpServer()).get('/v1/me').expect(401);
    expect(res.body).toMatchObject({
      statusCode: 401,
      error: 'TOKEN_MISSING',
      path: '/v1/me',
      requestId: expect.any(String),
    });
    expect(res.body.timestamp).toBeDefined();
  });

  it('token inválido = 401 TOKEN_INVALID', async () => {
    const res = await request(app.getHttpServer()).get('/v1/routes').set('Authorization', 'Bearer x.y.z').expect(401);
    expect(res.body.error).toBe('TOKEN_INVALID');
  });

  it('GET /v1/me cria o perfil no primeiro acesso; PATCH atualiza', async () => {
    const me = await request(app.getHttpServer()).get('/v1/me').set('Authorization', alice).expect(200);
    expect(me.body).toMatchObject({ id: aliceId, country: 'BR', locale: 'pt-BR' });
    const patched = await request(app.getHttpServer())
      .patch('/v1/me')
      .set('Authorization', alice)
      .send({ name: 'Alice', timezone: 'America/Sao_Paulo' })
      .expect(200);
    expect(patched.body.name).toBe('Alice');
  });

  it('campo fora do DTO = 400 VALIDATION_FAILED (nunca aceita user_id do corpo)', async () => {
    const res = await request(app.getHttpServer())
      .post('/v1/routes')
      .set('Authorization', alice)
      .send({ name: 'x', userId: bobId })
      .expect(400);
    expect(res.body.error).toBe('VALIDATION_FAILED');
    expect(res.body.details).toEqual(expect.arrayContaining([expect.stringContaining('userId')]));
  });

  describe('rota: criar, adicionar paradas, reordenar', () => {
    let routeId: string;
    let stopIds: string[];

    it('cria a rota e adiciona entregas', async () => {
      const created = await request(app.getHttpServer())
        .post('/v1/routes')
        .set('Authorization', alice)
        .send({ name: 'Manhã', status: 'active', originLat: -23.7, originLng: -46.6 })
        .expect(201);
      routeId = created.body.id;
      expect(created.body).toMatchObject({ name: 'Manhã', status: 'active', version: 1 });

      const withStops = await request(app.getHttpServer())
        .post(`/v1/routes/${routeId}/stops`)
        .set('Authorization', alice)
        .send({
          deliveries: [
            { customerName: 'C', address: 'Rua C', city: 'SBC', latitude: -23.7, longitude: -46.57 },
            { customerName: 'A', address: 'Rua A', city: 'SBC', latitude: -23.7, longitude: -46.59 },
            { customerName: 'B', address: 'Rua B', city: 'SBC', latitude: -23.7, longitude: -46.58 },
          ],
        })
        .expect(201);
      stopIds = withStops.body.stops.map((s: { id: string }) => s.id);
      expect(withStops.body.stops.map((s: { delivery: { customerName: string } }) => s.delivery.customerName)).toEqual([
        'C',
        'A',
        'B',
      ]);
    });

    it('preview de otimização propõe A, B, C sem mudar a rota', async () => {
      const preview = await request(app.getHttpServer())
        .post('/v1/optimization/preview')
        .set('Authorization', alice)
        .send({ routeId })
        .expect(200);
      expect(preview.body.order).toEqual([stopIds[1], stopIds[2], stopIds[0]]);
      const route = await request(app.getHttpServer()).get(`/v1/routes/${routeId}`).set('Authorization', alice).expect(200);
      expect(route.body.stops.map((s: { id: string }) => s.id)).toEqual(stopIds);
    });

    it('reordena com a lista completa; lista errada = 422', async () => {
      const order = [stopIds[1], stopIds[2], stopIds[0]];
      const res = await request(app.getHttpServer())
        .patch(`/v1/routes/${routeId}/stops/reorder`)
        .set('Authorization', alice)
        .send({ stopIds: order })
        .expect(200);
      expect(res.body.stops.map((s: { id: string }) => s.id)).toEqual(order);
      expect(res.body.manuallyEdited).toBe(true);

      const bad = await request(app.getHttpServer())
        .patch(`/v1/routes/${routeId}/stops/reorder`)
        .set('Authorization', alice)
        .send({ stopIds: order.slice(0, 2) })
        .expect(422);
      expect(bad.body).toMatchObject({ error: 'STOPS_MISMATCH', details: { missing: [stopIds[0]], unknown: [] } });
    });

    it('evento de status pela API segue a máquina de estados', async () => {
      const route = await request(app.getHttpServer()).get(`/v1/routes/${routeId}`).set('Authorization', alice);
      const deliveryId = route.body.stops[0].deliveryId;
      await request(app.getHttpServer())
        .post(`/v1/deliveries/${deliveryId}/events`)
        .set('Authorization', alice)
        .send({ toStatus: 'FAILED' })
        .expect(422);
      const ok = await request(app.getHttpServer())
        .post(`/v1/deliveries/${deliveryId}/events`)
        .set('Authorization', alice)
        .send({ toStatus: 'FAILED', reason: 'ABSENT' })
        .expect(201);
      expect(ok.body.delivery).toMatchObject({ status: 'FAILED', attempts: 1 });
    });

    it('outro usuário recebe 404 em tudo da rota', async () => {
      await request(app.getHttpServer()).get(`/v1/routes/${routeId}`).set('Authorization', bob).expect(404);
      await request(app.getHttpServer())
        .patch(`/v1/routes/${routeId}/stops/reorder`)
        .set('Authorization', bob)
        .send({ stopIds })
        .expect(404);
      await request(app.getHttpServer()).delete(`/v1/routes/${routeId}`).set('Authorization', bob).expect(404);
      const list = await request(app.getHttpServer()).get('/v1/routes').set('Authorization', bob).expect(200);
      expect(list.body).toMatchObject({ items: [], total: 0, page: 1 });
    });
  });

  describe('sync', () => {
    const deliveryId = randomUUID();
    const batch = () => ({
      deviceId,
      operations: [
        {
          operationId: '11111111-1111-4111-8111-111111111111',
          entityType: 'delivery',
          entityId: deliveryId,
          operationType: 'create',
          payload: { customerName: 'Zé', address: 'Rua Z', city: 'SBC', createdAt: '2026-11-08T10:00:00-03:00' },
        },
        {
          operationId: '22222222-2222-4222-8222-222222222222',
          entityType: 'delivery',
          entityId: deliveryId,
          operationType: 'transition',
          payload: {
            eventId: randomUUID(),
            fromStatus: 'PENDING',
            toStatus: 'DELIVERED',
            occurredAt: '2026-11-08T10:30:00-03:00',
          },
        },
      ],
    });

    it('push duas vezes: aplica uma vez, depois devolve duplicate', async () => {
      const first = await request(app.getHttpServer())
        .post('/v1/sync/push')
        .set('Authorization', alice)
        .send(batch())
        .expect(200);
      expect(first.body.results.map((r: { status: string }) => r.status)).toEqual(['applied', 'applied']);
      expect(first.body.results[1].version).toBe(2);

      const second = await request(app.getHttpServer())
        .post('/v1/sync/push')
        .set('Authorization', alice)
        .send(batch())
        .expect(200);
      expect(second.body.results.map((r: { status: string }) => r.status)).toEqual(['duplicate', 'duplicate']);
      expect(second.body.results[1]).toMatchObject({ originalStatus: 'applied', version: 2 });
      expect(second.body.summary).toMatchObject({ duplicate: 2, applied: 0 });
    });

    it('lote acima de 500 = 400', async () => {
      const operations = Array.from({ length: 501 }, () => ({
        operationId: randomUUID(),
        entityType: 'delivery',
        entityId: randomUUID(),
        operationType: 'create',
        payload: {},
      }));
      await request(app.getHttpServer())
        .post('/v1/sync/push')
        .set('Authorization', alice)
        .send({ deviceId, operations })
        .expect(400);
    });

    it('pull pagina pelo cursor e traz só o que é do usuário', async () => {
      const page1 = await request(app.getHttpServer())
        .get('/v1/sync/pull?since=0&limit=3')
        .set('Authorization', alice)
        .expect(200);
      expect(page1.body.hasMore).toBe(true);
      expect(page1.body.changes.length).toBeLessThanOrEqual(3);

      const seen = [...page1.body.changes];
      let cursor = page1.body.nextCursor;
      for (let i = 0; i < 20; i++) {
        const page = await request(app.getHttpServer())
          .get(`/v1/sync/pull?since=${cursor}&limit=3`)
          .set('Authorization', alice)
          .expect(200);
        seen.push(...page.body.changes);
        cursor = page.body.nextCursor;
        if (!page.body.hasMore) break;
      }
      const types = new Set(seen.map((c: { entityType: string }) => c.entityType));
      expect(types).toEqual(new Set(['route', 'delivery', 'route_stop', 'delivery_event']));
      const synced = seen.filter((c: { entityId: string }) => c.entityId === deliveryId).at(-1);
      expect(synced).toMatchObject({ operation: 'upsert', version: 2, data: { status: 'DELIVERED' } });

      const bobPull = await request(app.getHttpServer()).get('/v1/sync/pull').set('Authorization', bob).expect(200);
      expect(bobPull.body).toMatchObject({ changes: [], hasMore: false, nextCursor: '0' });
    });

    it('cursor inválido = 400', async () => {
      await request(app.getHttpServer()).get('/v1/sync/pull?since=-1').set('Authorization', alice).expect(400);
    });
  });

  it('GET /v1/subscriptions/me devolve o plano free', async () => {
    const res = await request(app.getHttpServer()).get('/v1/subscriptions/me').set('Authorization', alice).expect(200);
    expect(res.body).toMatchObject({ plan: { code: 'free' }, status: 'active', source: 'default', billingEnabled: false });
  });

  it('POST /v1/devices registra o aparelho', async () => {
    const id = randomUUID();
    const res = await request(app.getHttpServer())
      .post('/v1/devices')
      .set('Authorization', alice)
      .send({ id, platform: 'android', model: 'Moto G', appVersion: '1.0.0' })
      .expect(200);
    expect(res.body).toMatchObject({ id, platform: 'android' });
    await request(app.getHttpServer())
      .post('/v1/devices')
      .set('Authorization', bob)
      .send({ id, platform: 'android' })
      .expect(409);
  });

  it('rota inexistente = 404 no formato padrão', async () => {
    const res = await request(app.getHttpServer()).get(`/v1/routes/${randomUUID()}`).set('Authorization', alice).expect(404);
    expect(res.body.error).toBe('ROUTE_NOT_FOUND');
  });
});
