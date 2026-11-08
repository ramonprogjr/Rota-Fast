import 'package:flutter_test/flutter_test.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/services/routing/route_engine.dart';
import 'package:rota_max/services/routing/route_plan_input.dart';

/// Cenário do site de visualização (8 entregas em São Bernardo, uma urgente
/// ao sul e uma alta ao norte). Com pesos de prioridade altos demais a rota
/// ia e voltava pela cidade e ficava 30–50% mais longa.
void main() {
  Delivery stop(
    int id,
    double lat,
    double lng, [
    DeliveryPriority priority = DeliveryPriority.normal,
  ]) => Delivery(
    id: id,
    customerName: 'Parada $id',
    address: 'Rua $id',
    latitude: lat,
    longitude: lng,
    priority: priority,
    createdAt: DateTime(2026, 1, 1, 10, id),
  );

  List<Delivery> stops({required bool withPriority}) => [
    stop(1, -23.6860, -46.5480),
    stop(2, -23.6905, -46.5530),
    stop(
      3,
      -23.7105,
      -46.5520,
      withPriority ? DeliveryPriority.urgent : DeliveryPriority.normal,
    ),
    stop(4, -23.6995, -46.5560),
    stop(
      5,
      -23.6790,
      -46.5650,
      withPriority ? DeliveryPriority.high : DeliveryPriority.normal,
    ),
    stop(6, -23.6700, -46.5720),
    stop(7, -23.7020, -46.5430),
    stop(8, -23.7060, -46.5600),
  ];

  const origins = {
    'GPS ao sudoeste': GeoPoint(-23.732, -46.602),
    'base no centro': GeoPoint(-23.6939, -46.5648),
  };

  for (final entry in origins.entries) {
    test('prioridade não vira zigue-zague (${entry.key})', () async {
      final engine = DefaultRouteEngine(useIsolate: false);
      Future<RoutingResult> plan(bool withPriority) => engine.plan(
        RoutingRequest(
          origin: entry.value,
          stops: stops(withPriority: withPriority),
          speedKmh: 22,
        ),
      );
      final withPriority = await plan(true);
      final shortest = await plan(false);

      // Custa no máximo 10% a mais que a rota mais curta.
      expect(withPriority.totalKm, lessThan(shortest.totalKm * 1.10));
      // A urgente sai entre as duas primeiras.
      final urgentAt = withPriority.ordered.indexWhere((d) => d.id == 3);
      expect(urgentAt, lessThan(2));
      // A "alta" do outro lado da cidade não é puxada para o começo.
      final highAt = withPriority.ordered.indexWhere((d) => d.id == 5);
      expect(highAt, greaterThan(3));
    });
  }
}
