import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/services/routing/haversine_matrix.dart';
import 'package:rota_max/services/routing/route_solver.dart';

import 'routing_helpers.dart';

RouteSolverInput _input(
  List<Delivery> stops, {
  GeoPoint? end,
  List<int>? fixedSlots,
}) {
  final estimate = HaversineMatrix(28);
  final points = [
    origin,
    for (final s in stops) pointOf(s),
    ?end,
  ];
  final m = points.length;
  final seconds = Float64List(m * m);
  for (var a = 0; a < m; a++) {
    for (var b = 0; b < m; b++) {
      if (a != b) {
        seconds[a * m + b] = estimate.secondsFor(
          estimate.meters(points[a], points[b]),
        );
      }
    }
  }
  final n = stops.length;
  return RouteSolverInput(
    stopCount: n,
    seconds: seconds,
    hasEnd: end != null,
    weights: [for (final s in stops) priorityPenaltyWeight(s.priority)],
    fixedSlots: fixedSlots ?? List<int>.filled(n, -1),
    initialOrder: List<int>.generate(n, (i) => i),
  );
}

void main() {
  test(
    '2-opt/Or-opt nunca piora o vizinho mais próximo (instâncias aleatórias)',
    () {
      final random = Random(42);
      for (var round = 0; round < 25; round++) {
        final count = 5 + random.nextInt(30);
        final stops = [
          for (final s in randomStops(random, count))
            offset(
              s.id!,
              s.latitude! - origin.latitude,
              s.longitude! - origin.longitude,
              priority: DeliveryPriority.values[random.nextInt(3)],
            ),
        ];
        final input = _input(stops);
        final greedy = nearestNeighbour(input);
        final improved = improveRoute(input, greedy);
        final solved = solveRoute(input);
        expect(
          routeCost(input, improved),
          lessThanOrEqualTo(routeCost(input, greedy) + 1e-6),
        );
        expect(
          routeCost(input, solved),
          lessThanOrEqualTo(routeCost(input, greedy) + 1e-6),
        );
        expect(solved.toSet(), hasLength(count));
      }
    },
  );

  test('busca local melhora rota ruim (cruzada)', () {
    final random = Random(7);
    final stops = randomStops(random, 20);
    final input = _input(stops);
    final bad = List<int>.generate(20, (i) => i);
    final improved = improveRoute(input, bad);
    expect(routeCost(input, improved), lessThan(routeCost(input, bad)));
  });

  test('posições fixas não se movem na busca local', () {
    final random = Random(3);
    final stops = randomStops(random, 12);
    final fixed = List<int>.filled(12, -1)
      ..[0] = 11
      ..[5] = 2
      ..[11] = 0;
    final input = _input(stops, fixedSlots: fixed);
    final order = solveRoute(input);
    expect(order[0], 11);
    expect(order[5], 2);
    expect(order[11], 0);
    expect(order.toSet(), hasLength(12));
  });

  test('resolveFixedSlots: fixedPosition vence locked e é limitado', () {
    final slots = resolveFixedSlots(
      stopCount: 4,
      fixedPosition: [null, 0, 99, null],
      locked: [true, true, false, true],
    );
    // parada 1 -> posição 0 (fixed vence o locked); parada 2 -> 3 (limitado);
    // parada 0 travada em 0, mas 0 já ocupado -> fica livre;
    // parada 3 travada em 3, já ocupado -> livre.
    expect(slots, [1, -1, -1, 2]);
  });

  test('applyFixedSlots preenche livres na ordem atual', () {
    expect(applyFixedSlots([-1, 3, -1, -1], [0, 1, 2, 3]), [0, 3, 1, 2]);
  });

  test('sem paradas devolve vazio', () {
    expect(solveRoute(_input(const [])), isEmpty);
  });
}
