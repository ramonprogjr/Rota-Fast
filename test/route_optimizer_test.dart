import 'package:flutter_test/flutter_test.dart';
import 'package:rota_pizza/models/delivery.dart';
import 'package:rota_pizza/models/geo_result.dart';
import 'package:rota_pizza/models/shift_summary.dart';
import 'package:rota_pizza/services/route_optimizer.dart';

Delivery _delivery({
  required int id,
  required String name,
  required double lat,
  required double lng,
  DeliveryPriority priority = DeliveryPriority.normal,
}) {
  return Delivery(
    id: id,
    customerName: name,
    address: 'Rua $name',
    latitude: lat,
    longitude: lng,
    priority: priority,
  );
}

void main() {
  const optimizer = RouteOptimizer();
  const origin = GeoPoint(-23.6944, -46.5654);

  test('vizinho mais próximo visita o ponto mais perto primeiro', () {
    final a = _delivery(id: 1, name: 'Longe', lat: -23.7500, lng: -46.6200);
    final b = _delivery(id: 2, name: 'Perto', lat: -23.6960, lng: -46.5670);
    final route = optimizer.optimize(origin: origin, pending: [a, b]);
    expect(route.ordered.map((item) => item.customerName).toList(), [
      'Perto',
      'Longe',
    ]);
    expect(route.totalKm, greaterThan(0));
    expect(route.skippedWithoutCoords, isEmpty);
  });

  test('urgente sobe na fila mesmo um pouco mais longe', () {
    final near = _delivery(
      id: 1,
      name: 'Normal perto',
      lat: origin.latitude + 0.004,
      lng: origin.longitude,
    );
    final urgent = _delivery(
      id: 2,
      name: 'Urgente',
      lat: origin.latitude + 0.008,
      lng: origin.longitude,
      priority: DeliveryPriority.urgent,
    );
    final route = optimizer.optimize(origin: origin, pending: [near, urgent]);
    expect(route.ordered.first.customerName, 'Urgente');
  });

  test('entregas sem coordenada ficam no fim', () {
    final located = _delivery(id: 1, name: 'Com GPS', lat: -23.70, lng: -46.56);
    final missing = Delivery(
      id: 2,
      customerName: 'Sem GPS',
      address: 'Rua desconhecida',
    );
    final route = optimizer.optimize(
      origin: origin,
      pending: [missing, located],
    );
    expect(route.ordered.last.customerName, 'Sem GPS');
    expect(route.skippedWithoutCoords, hasLength(1));
  });

  test('resumo do turno calcula métricas de produtividade', () {
    const summary = ShiftSummary(
      pendingCount: 3,
      doneCount: 4,
      estimatedKm: 18.0,
      estimatedDuration: Duration(minutes: 45),
      earnings: 500,
      doneKm: 7.5,
    );

    expect(summary.avgDeliveryValue, closeTo(125.0, 0.001));
    expect(summary.earningsPerKm, closeTo(27.7777777778, 0.001));
    expect(summary.kmPerDelivery, closeTo(4.5, 0.001));
  });
}
