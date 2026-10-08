import 'package:flutter_test/flutter_test.dart';
import 'package:rota_pizza/services/geocoding_service.dart';

void main() {
  test('parseia vários candidatos do Nominatim', () {
    const body = '''
[
  {"lat":"-23.6944","lon":"-46.5654","display_name":"Rua X, 123, Centro"},
  {"lat":"-23.7000","lon":"-46.5700","display_name":"Rua X, 123, Rudge Ramos"}
]
''';
    final results = GeocodingService.parseNominatimResults(body);
    expect(results, hasLength(2));
    expect(results.first.displayName, contains('Centro'));
    expect(results.last.latitude, closeTo(-23.7, 0.0001));
  });

  test('lista vazia vira nenhum candidato', () {
    expect(GeocodingService.parseNominatimResults('[]'), isEmpty);
  });
}
