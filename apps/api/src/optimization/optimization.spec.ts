import { createRouteWithStops, createServices, createUser, deliveryInput } from '../testing/fixtures';
import { applyLocks, optimize, type OptimizerStop, pathKm } from './route-optimizer';

const stop = (id: string, latitude: number, longitude: number, extra: Partial<OptimizerStop> = {}): OptimizerStop => ({
  id,
  latitude,
  longitude,
  ...extra,
});

describe('otimizador (vizinho mais próximo + 2-opt)', () => {
  // Pontos numa linha leste-oeste, embaralhados.
  const origin = { latitude: -23.7, longitude: -46.6 };
  const line = [
    stop('c', -23.7, -46.57),
    stop('a', -23.7, -46.59),
    stop('d', -23.7, -46.56),
    stop('b', -23.7, -46.58),
  ];

  it('encontra a ordem óbvia e nunca piora', () => {
    const result = optimize(line, { start: origin, speedKmh: 28 });
    expect(result.order).toEqual(['a', 'b', 'c', 'd']);
    expect(result.optimizedKm).toBeLessThan(result.baselineKm);
    expect(result.optimizedMinutes).toBeLessThanOrEqual(result.baselineMinutes);
  });

  it('usa haversine × 1,3', () => {
    const km = pathKm([stop('x', 0, 1)], { latitude: 0, longitude: 0 });
    expect(km).toBeCloseTo(111.19 * 1.3, 0);
  });

  it('paradas sem coordenada ficam no fim, na ordem atual', () => {
    const result = optimize([stop('n1', null as never, null as never), ...line, stop('n2', null as never, null as never)], {
      start: origin,
      speedKmh: 28,
    });
    expect(result.unlocated).toEqual(['n1', 'n2']);
    expect(result.order.slice(-2)).toEqual(['n1', 'n2']);
  });

  it('respeita posição fixa e trava (applyLocks)', () => {
    const current = [stop('a', 0, 0), stop('b', 0, 0, { locked: true }), stop('c', 0, 0, { fixedPosition: 0 }), stop('d', 0, 0)];
    const optimized = [current[3], current[0], current[1], current[2]];
    expect(applyLocks(optimized, current).map((s) => s.id)).toEqual(['c', 'b', 'd', 'a']);
  });

  it('com rota salva: propõe sem gravar nada (banco idêntico antes e depois)', async () => {
    const s = createServices();
    const user = await createUser(s);
    const route = await s.routes.create(user, { originLat: origin.latitude, originLng: origin.longitude });
    await s.routes.addStops(user, route.id, {
      deliveries: line.map((p) => deliveryInput({ latitude: p.latitude!, longitude: p.longitude!, customerName: p.id })),
    });
    const before = s.db.snapshot();
    const preview = await s.optimization.preview(user, { routeId: route.id });
    expect(s.db.snapshot()).toEqual(before);
    expect(preview.optimizedKm).toBeLessThan(preview.baselineKm);
    const detail = await s.routes.get(user, route.id);
    const names = Object.fromEntries(detail.stops.map((x) => [x.id, x.delivery.customerName]));
    expect(preview.order.map((id) => names[id])).toEqual(['a', 'b', 'c', 'd']);
    // A ordem salva continua a de cadastro.
    expect(detail.stops.map((x) => x.delivery.customerName)).toEqual(['c', 'a', 'd', 'b']);
    expect(detail.version).toBe(route.version);
  });

  it('rota de outro usuário = 404', async () => {
    const s = createServices();
    const alice = await createUser(s);
    const bob = await createUser(s);
    const { route } = await createRouteWithStops(s, alice, 2);
    await expect(s.optimization.preview(bob, { routeId: route.id })).rejects.toMatchObject({ code: 'ROUTE_NOT_FOUND' });
  });
});
