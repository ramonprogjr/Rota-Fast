import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rota_max/core/utils/haversine.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/models/vehicle.dart';
import 'package:rota_max/services/routing/distance_matrix.dart';
import 'package:rota_max/services/routing/haversine_matrix.dart';
import 'package:rota_max/services/routing/ors_matrix_client.dart';
import 'package:rota_max/services/routing/route_engine.dart';
import 'package:rota_max/services/routing/route_plan_input.dart';

import 'routing_helpers.dart';

List<int> _ids(List<Delivery> list) => [for (final d in list) d.id!];

RoutingRequest _request(
  List<Delivery> stops, {
  GeoPoint? end,
  Map<int, StopConstraint> constraints = const {},
}) => RoutingRequest(
  origin: origin,
  end: end,
  stops: stops,
  constraints: constraints,
  speedKmh: 28,
);

void main() {
  final engine = DefaultRouteEngine();

  test('sem chave usa estimativa local com aviso', () async {
    final result = await engine.plan(
      _request([offset(1, 0.01, 0), offset(2, 0.002, 0)]),
    );
    expect(_ids(result.ordered), [2, 1]);
    expect(result.usedRoadNetwork, isFalse);
    expect(result.warning, 'Rota estimada (sem dados de ruas)');
    expect(result.totalKm, greaterThan(0));
    expect(result.totalTime, greaterThan(Duration.zero));
  });

  test('ponto final é respeitado (último trecho termina no fim)', () async {
    final a = offset(1, 0, 0.012);
    final b = offset(2, 0, -0.010);
    const end = GeoPoint(-23.6944, -46.5654 - 0.020);

    final open = await engine.plan(_request([a, b]));
    expect(_ids(open.ordered), [2, 1]);

    final closed = await engine.plan(_request([a, b], end: end));
    expect(_ids(closed.ordered), [1, 2]);

    // totalKm inclui o trecho última parada -> fim.
    double leg(GeoPoint p, GeoPoint q) =>
        haversineKm(p.latitude, p.longitude, q.latitude, q.longitude) * 1.3;
    final expected =
        leg(origin, pointOf(a)) +
        leg(pointOf(a), pointOf(b)) +
        leg(pointOf(b), end);
    expect(closed.totalKm, closeTo(expected, 1e-6));
  });

  test('locked e fixedPosition são respeitados', () async {
    final random = Random(11);
    final stops = randomStops(random, 10);
    final result = await engine.plan(
      _request(
        stops,
        constraints: {
          3: const StopConstraint(deliveryId: 3, locked: true), // índice 2
          7: const StopConstraint(deliveryId: 7, fixedPosition: 0),
          9: const StopConstraint(
            deliveryId: 9,
            locked: true,
            fixedPosition: 9,
          ),
        },
      ),
    );
    expect(result.ordered, hasLength(10));
    expect(result.ordered[0].id, 7);
    expect(result.ordered[2].id, 3);
    expect(result.ordered[9].id, 9);
    expect(_ids(result.ordered).toSet(), hasLength(10));
  });

  test('urgente vem antes de normais não muito mais perto', () async {
    final result = await engine.plan(
      _request([
        offset(1, 0.004, 0),
        offset(2, -0.004, 0.001),
        offset(3, 0, 0.006, priority: DeliveryPriority.urgent),
        offset(4, 0.003, -0.003),
      ]),
    );
    expect(result.ordered.first.id, 3);
  });

  test('urgente muito longe não atropela a distância', () async {
    final result = await engine.plan(
      _request([
        offset(1, 0.2, 0.2, priority: DeliveryPriority.urgent),
        offset(2, 0.002, 0),
      ]),
    );
    expect(_ids(result.ordered), [2, 1]);
  });

  test('sem coordenada e linha/coluna nula vão para unroutable', () async {
    final provider = FakeMatrixProvider((points) {
      final base = HaversineMatrix(28).build(points);
      // Parada de índice 2 na matriz (id 2) inalcançável.
      for (var i = 0; i < points.length; i++) {
        if (i != 2) {
          base.seconds[2][i] = null;
          base.seconds[i][2] = null;
          base.meters[2][i] = null;
          base.meters[i][2] = null;
        }
      }
      return base;
    });
    final roadEngine = DefaultRouteEngine(roadProvider: provider);
    final noCoords = stop(9);
    final result = await roadEngine.plan(
      _request([
        offset(1, 0.01, 0),
        offset(2, 0.02, 0),
        noCoords,
        offset(3, 0.03, 0),
      ]),
    );
    expect(result.usedRoadNetwork, isTrue);
    expect(result.warning, isNull);
    expect(_ids(result.ordered), [1, 3]);
    expect(_ids(result.unroutable).toSet(), {2, 9});
  });

  test('provedor que lança vira fallback sem exceção', () async {
    final result = await DefaultRouteEngine(
      roadProvider: ThrowingMatrixProvider(),
    ).plan(_request([offset(1, 0.01, 0), offset(2, 0.02, 0)]));
    expect(result.usedRoadNetwork, isFalse);
    expect(result.warning, 'Rota estimada (sem dados de ruas)');
    expect(result.ordered, hasLength(2));
  });

  test('ORS com HTTP 500 → fallback, sem exceção', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('erro', 500);
    });
    final result = await DefaultRouteEngine(
      roadProvider: OrsMatrixClient(apiKey: 'chave', client: client),
    ).plan(_request([offset(1, 0.01, 0), offset(2, 0.02, 0)]));
    expect(calls, 1);
    expect(result.usedRoadNetwork, isFalse);
    expect(result.warning, isNotNull);
    expect(_ids(result.ordered), [1, 2]);
  });

  test('ORS que não responde (timeout) → fallback, sem exceção', () async {
    final client = MockClient((request) => Completer<http.Response>().future);
    final result = await DefaultRouteEngine(
      roadProvider: OrsMatrixClient(
        apiKey: 'chave',
        client: client,
        timeout: const Duration(milliseconds: 50),
      ),
    ).plan(_request([offset(1, 0.01, 0)]));
    expect(result.usedRoadNetwork, isFalse);
    expect(result.warning, 'Rota estimada (sem dados de ruas)');
    expect(result.ordered, hasLength(1));
  });

  test(
    'ORS ok usa a malha e calcula baseline pela ordem de cadastro',
    () async {
      final provider = FakeMatrixProvider((points) {
        final n = points.length;
        // 1 km e 100 s entre quaisquer dois pontos.
        return TravelMatrix(
          seconds: [
            for (var i = 0; i < n; i++)
              [for (var j = 0; j < n; j++) i == j ? 0.0 : 100.0],
          ],
          meters: [
            for (var i = 0; i < n; i++)
              [for (var j = 0; j < n; j++) i == j ? 0.0 : 1000.0],
          ],
        );
      });
      final result = await DefaultRouteEngine(roadProvider: provider).plan(
        _request([offset(1, 0.01, 0), offset(2, 0.02, 0), offset(3, 0.03, 0)]),
      );
      expect(result.usedRoadNetwork, isTrue);
      expect(result.warning, isNull);
      expect(result.totalKm, closeTo(3, 1e-9));
      expect(result.totalTime, const Duration(seconds: 300));
      expect(result.baselineKm, closeTo(3, 1e-9));
      expect(result.baselineTime, const Duration(seconds: 300));
    },
  );

  test('baseline segue createdAt, não a ordem atual', () async {
    final far = stop(
      1,
      lat: origin.latitude + 0.05,
      lng: origin.longitude,
      createdAt: DateTime(2026, 1, 1, 8),
    );
    final near = stop(
      2,
      lat: origin.latitude + 0.01,
      lng: origin.longitude,
      createdAt: DateTime(2026, 1, 1, 9),
    );
    final result = await engine.plan(_request([near, far]));
    expect(_ids(result.ordered), [2, 1]);
    // Cadastro: far -> near = 0,05 + 0,04 graus; otimizado: 0,05 graus.
    expect(result.baselineKm, greaterThan(result.totalKm));
  });

  test('profileFor: van/caminhão → hgv, resto → car', () {
    expect(profileFor(VehicleType.van), RoutingProfile.hgv);
    expect(profileFor(VehicleType.truck), RoutingProfile.hgv);
    expect(profileFor(VehicleType.motorcycle), RoutingProfile.car);
    expect(profileFor(VehicleType.car), RoutingProfile.car);
    expect(profileFor(VehicleType.utility), RoutingProfile.car);
  });

  test(
    'desempenho: 40 paradas em menos de 300 ms (fallback, isolate)',
    () async {
      final stops = randomStops(Random(99), 40, spread: 0.1);
      final watch = Stopwatch()..start();
      final result = await engine.plan(_request(stops));
      watch.stop();
      expect(result.ordered, hasLength(40));
      expect(watch.elapsedMilliseconds, lessThan(300));
    },
  );

  test('QA-003: 20 paradas em 4 bairros, sem reentrar e sem cruzar', () async {
    final random = Random(2026);
    const centers = [
      [0.03, 0.03],
      [0.03, -0.03],
      [-0.03, -0.03],
      [-0.03, 0.03],
    ];
    final cluster = <int, int>{};
    final stops = <Delivery>[];
    var id = 1;
    for (var c = 0; c < centers.length; c++) {
      for (var k = 0; k < 5; k++) {
        cluster[id] = c;
        stops.add(
          offset(
            id++,
            centers[c][0] + (random.nextDouble() - 0.5) * 0.006,
            centers[c][1] + (random.nextDouble() - 0.5) * 0.006,
          ),
        );
      }
    }
    stops.shuffle(random);

    final result = await engine.plan(_request(stops));
    expect(result.ordered, hasLength(20));

    final sequence = [for (final d in result.ordered) cluster[d.id]!];
    final visited = <int>{};
    for (var i = 0; i < sequence.length; i++) {
      if (i > 0 && sequence[i] != sequence[i - 1]) {
        expect(
          visited.contains(sequence[i]),
          isFalse,
          reason: 'reentrou no bairro ${sequence[i]}: $sequence',
        );
      }
      visited.add(sequence[i]);
    }

    final path = [origin, for (final d in result.ordered) pointOf(d)];
    for (var i = 0; i < path.length - 1; i++) {
      for (var j = i + 2; j < path.length - 1; j++) {
        expect(
          segmentsCross(path[i], path[i + 1], path[j], path[j + 1]),
          isFalse,
          reason: 'trechos $i e $j se cruzam',
        );
      }
    }
    expect(result.totalKm, lessThan(result.baselineKm));
  });
}
