import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rota_max/core/constants/app_constants.dart';
import 'package:rota_max/data/repositories/settings_repository.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/services/geocoding_service.dart';

const _nominatimHit = '''
[{"lat":"-23.71","lon":"-46.55","display_name":"Rua Marechal Deodoro, 1500, Centro"}]
''';

const _orsHit = '''
{"type":"FeatureCollection","features":[
  {"type":"Feature","geometry":{"type":"Point","coordinates":[-46.56,-23.72]},
   "properties":{"label":"Rua Java, 100, São Bernardo do Campo, SP, Brasil",
     "street":"Rua Java","housenumber":"100","locality":"São Bernardo do Campo",
     "region_a":"SP","postalcode":"09721-000","layer":"address"}}
]}
''';

GeocodingService _service(
  List<Uri> calls, {
  required String Function(Uri uri) respond,
  GeocodeCacheRepository? cache,
  String orsKey = '',
}) {
  return GeocodingService(
    cache: cache ?? MemoryGeocodeCacheRepository(),
    orsApiKey: orsKey,
    minInterval: Duration.zero,
    client: MockClient((request) async {
      calls.add(request.url);
      expect(request.headers['User-Agent'] ?? '', isNotEmpty);
      return http.Response(
        respond(request.url),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

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

  test('texto livre manda só q, sem campos estruturados', () async {
    final calls = <Uri>[];
    final service = _service(calls, respond: (_) => _nominatimHit);
    final results = await service.search('Rua Marechal Deodoro, 1500, Centro');
    expect(results, hasLength(1));
    expect(calls, hasLength(1));
    final params = calls.single.queryParameters;
    expect(params['q'], contains('Marechal Deodoro'));
    expect(params['q'], contains(AppConstants.defaultCity));
    for (final key in ['street', 'city', 'state', 'postalcode', 'country']) {
      expect(params.containsKey(key), isFalse, reason: key);
    }
  });

  test('busca estruturada manda rua, cidade, UF e CEP, sem q', () async {
    final calls = <Uri>[];
    final service = _service(calls, respond: (_) => _nominatimHit);
    await service.search(
      'Rua Marechal Deodoro, 1500, Centro',
      street: 'Rua Marechal Deodoro',
      number: '1500',
      neighborhood: 'Centro',
      city: 'São Bernardo do Campo',
      state: 'SP',
      postalCode: '09710000',
    );
    expect(calls, hasLength(1));
    final params = calls.single.queryParameters;
    expect(params.containsKey('q'), isFalse);
    expect(params['street'], '1500 Rua Marechal Deodoro');
    expect(params['city'], 'São Bernardo do Campo');
    expect(params['state'], 'SP');
    expect(params['postalcode'], '09710-000');
    expect(params['countrycodes'], 'br');
  });

  test(
    'estruturada sem resultado cai para texto livre (nunca os dois juntos)',
    () async {
      final calls = <Uri>[];
      final service = _service(
        calls,
        respond: (uri) =>
            uri.queryParameters.containsKey('q') ? _nominatimHit : '[]',
      );
      final results = await service.search(
        '',
        street: 'Rua Marechal Deodoro',
        number: '1500',
        city: 'São Bernardo do Campo',
      );
      expect(results, hasLength(1));
      expect(calls, hasLength(2));
      for (final uri in calls) {
        final params = uri.queryParameters;
        final structured =
            params.containsKey('street') ||
            params.containsKey('city') ||
            params.containsKey('postalcode');
        expect(params.containsKey('q') && structured, isFalse);
      }
      expect(
        calls.last.queryParameters['q'],
        'Rua Marechal Deodoro, 1500, São Bernardo do Campo',
      );
    },
  );

  test('cache confirmado evita a rede', () async {
    final calls = <Uri>[];
    final cache = MemoryGeocodeCacheRepository();
    final service = _service(
      calls,
      respond: (_) => _nominatimHit,
      cache: cache,
    );
    await service.cacheConfirmed(
      'Rua Java, 100, São Bernardo do Campo',
      const GeoResult(latitude: -23.7, longitude: -46.5, confirmed: true),
    );
    final results = await service.search(
      'Rua Java, 100, São Bernardo do Campo',
    );
    expect(calls, isEmpty);
    expect(results.single.latitude, -23.7);
    expect(results.single.confirmed, isTrue);
  });

  test('sem resultado no Nominatim tenta o OpenRouteService', () async {
    final calls = <Uri>[];
    final service = _service(
      calls,
      orsKey: 'chave-teste',
      respond: (uri) => uri.host == 'api.openrouteservice.org' ? _orsHit : '[]',
    );
    final results = await service.search('Rua Java, 100');
    expect(calls.map((uri) => uri.host).toList(), [
      'nominatim.openstreetmap.org',
      'api.openrouteservice.org',
    ]);
    expect(calls.last.path, '/geocode/search');
    expect(calls.last.queryParameters['api_key'], 'chave-teste');
    expect(results.single.latitude, closeTo(-23.72, 1e-6));
    expect(results.single.longitude, closeTo(-46.56, 1e-6));
  });

  test('sem chave do ORS não chama a segunda fonte', () async {
    final calls = <Uri>[];
    final service = _service(calls, respond: (_) => '[]');
    expect(await service.search('Rua Java, 100'), isEmpty);
    expect(calls, hasLength(1));
  });

  test('erro de rede vira GeocodingException', () async {
    final service = GeocodingService(
      cache: MemoryGeocodeCacheRepository(),
      orsApiKey: '',
      minInterval: Duration.zero,
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    expect(
      () => service.search('Rua Java, 100'),
      throwsA(isA<GeocodingException>()),
    );
  });
}
