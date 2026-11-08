import 'dart:typed_data';

import 'package:rota_max/core/constants/app_constants.dart';
import 'package:rota_max/core/utils/haversine.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/models/shift_summary.dart';
import 'package:rota_max/services/routing/haversine_matrix.dart';
import 'package:rota_max/services/routing/route_solver.dart';

class OptimizedRoute {
  const OptimizedRoute({
    required this.ordered,
    required this.totalKm,
    required this.estimatedDuration,
    required this.skippedWithoutCoords,
  });

  final List<Delivery> ordered;
  final double totalKm;
  final Duration estimatedDuration;
  final List<Delivery> skippedWithoutCoords;
}

class RouteOptimizer {
  const RouteOptimizer();

  /// Fator legado de prioridade (multiplica a distância). Mantido por
  /// compatibilidade; a otimização usa `priorityPenaltyWeight`.
  static double priorityWeight(DeliveryPriority priority) {
    switch (priority) {
      case DeliveryPriority.urgent:
        return 0.4;
      case DeliveryPriority.high:
        return 0.7;
      case DeliveryPriority.normal:
        return 1.0;
    }
  }

  /// Ordem sugerida pela estimativa local (linha reta × fator de ruas),
  /// com vizinho mais próximo + 2-opt/Or-opt. Síncrono e sem rede; o motor
  /// completo (malha viária, isolate, restrições) é `DefaultRouteEngine`.
  ///
  /// `totalKm` já inclui o fator de ruas ([AppConstants.roadFactor]).
  /// Entregas sem coordenada vão para o fim de [OptimizedRoute.ordered].
  OptimizedRoute optimize({
    required GeoPoint origin,
    required List<Delivery> pending,
    double speedKmh = AppConstants.motoSpeedKmh,
  }) {
    final withCoords = pending.where((item) => item.hasCoordinates).toList();
    final withoutCoords =
        pending.where((item) => !item.hasCoordinates).toList();

    final estimate = HaversineMatrix(speedKmh);
    final points = [
      origin,
      for (final item in withCoords) GeoPoint(item.latitude!, item.longitude!),
    ];
    final n = withCoords.length;
    final m = points.length;
    final seconds = Float64List(m * m);
    final meters = Float64List(m * m);
    for (var a = 0; a < m; a++) {
      for (var b = a + 1; b < m; b++) {
        final dist = estimate.meters(points[a], points[b]);
        final time = estimate.secondsFor(dist);
        meters[a * m + b] = dist;
        meters[b * m + a] = dist;
        seconds[a * m + b] = time;
        seconds[b * m + a] = time;
      }
    }
    final order = solveRoute(
      RouteSolverInput(
        stopCount: n,
        seconds: seconds,
        hasEnd: false,
        weights: [
          for (final item in withCoords) priorityPenaltyWeight(item.priority),
        ],
        fixedSlots: List<int>.filled(n, -1),
        initialOrder: List<int>.generate(n, (i) => i),
        timeBudgetMs: 100,
      ),
    );

    var totalMeters = 0.0;
    var prev = 0;
    for (final stop in order) {
      totalMeters += meters[prev * m + stop + 1];
      prev = stop + 1;
    }
    final totalKm = totalMeters / 1000;

    return OptimizedRoute(
      ordered: [
        for (final i in order) withCoords[i],
        ...withoutCoords,
      ],
      totalKm: totalKm,
      estimatedDuration: estimateTravelTime(
        totalKm,
        speedKmh: speedKmh,
      ),
      skippedWithoutCoords: withoutCoords,
    );
  }

  ShiftSummary summarize({
    required GeoPoint? origin,
    required List<Delivery> all,
    double speedKmh = AppConstants.motoSpeedKmh,
  }) {
    final pending = all.where((item) => item.isOpen).toList();
    final done = all.where((item) => item.isDelivered).toList();
    final today = DateTime.now();
    final doneToday = done.where((item) {
      final at = item.deliveredAt ?? item.createdAt;
      return at.year == today.year &&
          at.month == today.month &&
          at.day == today.day;
    }).toList();

    var estimatedKm = 0.0;
    var estimated = Duration.zero;
    if (origin != null) {
      estimatedKm = remainingKm(origin: origin, open: pending);
      estimated = estimateTravelTime(estimatedKm, speedKmh: speedKmh);
    }

    final earnings = doneToday.fold<double>(
      0,
      (sum, item) => sum + (item.value ?? 0),
    );

    return ShiftSummary(
      pendingCount: pending.length,
      doneCount: doneToday.length,
      estimatedKm: estimatedKm,
      estimatedDuration: estimated,
      earnings: earnings,
      doneKm: 0,
    );
  }

  /// Km restantes percorrendo as paradas abertas na ordem salva
  /// (`routeOrder`; sem ordem vão para o fim, na ordem recebida) a partir de
  /// [origin], com o fator de ruas. Barato: não otimiza nada.
  static double remainingKm({
    required GeoPoint origin,
    required List<Delivery> open,
    double roadFactor = AppConstants.roadFactor,
  }) {
    final indexed = [
      for (var i = 0; i < open.length; i++)
        if (open[i].hasCoordinates) (i, open[i]),
    ]..sort((a, b) {
        final ra = a.$2.routeOrder;
        final rb = b.$2.routeOrder;
        if (ra != null && rb != null && ra != rb) {
          return ra.compareTo(rb);
        }
        if (ra != null && rb == null) {
          return -1;
        }
        if (ra == null && rb != null) {
          return 1;
        }
        return a.$1.compareTo(b.$1);
      });
    var km = 0.0;
    var lat = origin.latitude;
    var lng = origin.longitude;
    for (final (_, item) in indexed) {
      km += haversineKm(lat, lng, item.latitude!, item.longitude!);
      lat = item.latitude!;
      lng = item.longitude!;
    }
    return km * roadFactor;
  }
}
