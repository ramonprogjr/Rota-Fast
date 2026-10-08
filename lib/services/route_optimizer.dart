import 'package:rota_pizza/core/constants/app_constants.dart';
import 'package:rota_pizza/core/utils/haversine.dart';
import 'package:rota_pizza/models/delivery.dart';
import 'package:rota_pizza/models/geo_result.dart';
import 'package:rota_pizza/models/shift_summary.dart';

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

  OptimizedRoute optimize({
    required GeoPoint origin,
    required List<Delivery> pending,
  }) {
    final withCoords = pending.where((item) => item.hasCoordinates).toList();
    final withoutCoords =
        pending.where((item) => !item.hasCoordinates).toList();

    final remaining = [...withCoords];
    final ordered = <Delivery>[];
    var currentLat = origin.latitude;
    var currentLng = origin.longitude;
    var totalKm = 0.0;

    while (remaining.isNotEmpty) {
      var bestIndex = 0;
      var bestScore = double.infinity;
      var bestDistance = 0.0;
      for (var i = 0; i < remaining.length; i++) {
        final item = remaining[i];
        final distance = haversineKm(
          currentLat,
          currentLng,
          item.latitude!,
          item.longitude!,
        );
        final score = distance * priorityWeight(item.priority);
        if (score < bestScore) {
          bestScore = score;
          bestIndex = i;
          bestDistance = distance;
        }
      }
      final next = remaining.removeAt(bestIndex);
      ordered.add(next);
      totalKm += bestDistance;
      currentLat = next.latitude!;
      currentLng = next.longitude!;
    }

    ordered.addAll(withoutCoords);

    return OptimizedRoute(
      ordered: ordered,
      totalKm: totalKm,
      estimatedDuration: estimateTravelTime(
        totalKm,
        speedKmh: AppConstants.motoSpeedKmh,
      ),
      skippedWithoutCoords: withoutCoords,
    );
  }

  ShiftSummary summarize({
    required GeoPoint? origin,
    required List<Delivery> all,
  }) {
    final pending = all.where((item) => item.isPending).toList();
    final done = all.where((item) => !item.isPending).toList();
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
      final route = optimize(origin: origin, pending: pending);
      estimatedKm = route.totalKm;
      estimated = route.estimatedDuration;
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
}
