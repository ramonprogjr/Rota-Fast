import 'dart:math';

import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/services/routing/distance_matrix.dart';
import 'package:rota_max/services/routing/route_plan_input.dart';

const origin = GeoPoint(-23.6944, -46.5654);

Delivery stop(
  int id, {
  double? lat,
  double? lng,
  DeliveryPriority priority = DeliveryPriority.normal,
  DateTime? createdAt,
}) {
  return Delivery(
    id: id,
    customerName: 'Cliente $id',
    address: 'Rua $id',
    latitude: lat,
    longitude: lng,
    priority: priority,
    createdAt: createdAt ?? DateTime(2026, 1, 1, 8, 0, id),
  );
}

/// Entrega deslocada da origem em graus.
Delivery offset(
  int id,
  double dLat,
  double dLng, {
  DeliveryPriority priority = DeliveryPriority.normal,
}) => stop(
  id,
  lat: origin.latitude + dLat,
  lng: origin.longitude + dLng,
  priority: priority,
);

List<Delivery> randomStops(Random random, int count, {double spread = 0.05}) {
  return [
    for (var i = 0; i < count; i++)
      offset(
        i + 1,
        (random.nextDouble() - 0.5) * spread,
        (random.nextDouble() - 0.5) * spread,
      ),
  ];
}

/// Provedor de matriz controlado pelo teste.
class FakeMatrixProvider implements DistanceMatrixProvider {
  FakeMatrixProvider(this.builder);

  final TravelMatrix Function(List<GeoPoint> points) builder;
  int calls = 0;

  @override
  Future<TravelMatrix> matrix(
    List<GeoPoint> points,
    RoutingProfile profile,
  ) async {
    calls++;
    return builder(points);
  }
}

class ThrowingMatrixProvider implements DistanceMatrixProvider {
  @override
  Future<TravelMatrix> matrix(
    List<GeoPoint> points,
    RoutingProfile profile,
  ) async {
    throw Exception('falhou');
  }
}

/// Segmentos AB e CD se cruzam (interseção própria, plano lat/lng).
bool segmentsCross(GeoPoint a, GeoPoint b, GeoPoint c, GeoPoint d) {
  double orient(GeoPoint p, GeoPoint q, GeoPoint r) =>
      (q.longitude - p.longitude) * (r.latitude - p.latitude) -
      (q.latitude - p.latitude) * (r.longitude - p.longitude);
  final o1 = orient(a, b, c);
  final o2 = orient(a, b, d);
  final o3 = orient(c, d, a);
  final o4 = orient(c, d, b);
  return o1 * o2 < 0 && o3 * o4 < 0;
}

GeoPoint pointOf(Delivery d) => GeoPoint(d.latitude!, d.longitude!);
