import 'package:flutter_test/flutter_test.dart';
import 'package:rota_pizza/core/utils/haversine.dart';

void main() {
  test('calcula distância conhecida entre dois pontos', () {
    final km = haversineKm(-23.6944, -46.5654, -23.6632, -46.5385);
    expect(km, greaterThan(3));
    expect(km, lessThan(6));
  });

  test('distância nula no mesmo ponto', () {
    expect(haversineKm(-23.69, -46.56, -23.69, -46.56), closeTo(0, 0.0001));
  });

  test('formata km e duração', () {
    expect(formatKm(0.05), '50 m');
    expect(formatKm(12.7), '12,7 km');
    expect(formatDuration(const Duration(minutes: 42)), '~42 min');
    expect(formatDuration(const Duration(minutes: 75)), '~1h 15min');
  });

  test('estima tempo com 28 km/h', () {
    final duration = estimateTravelTime(14, speedKmh: 28);
    expect(duration.inMinutes, 30);
  });
}
