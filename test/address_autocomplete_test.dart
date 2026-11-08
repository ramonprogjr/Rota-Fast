import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/services/address_autocomplete_service.dart';

const _body = '''
{"type":"FeatureCollection","features":[
  {"type":"Feature","geometry":{"type":"Point","coordinates":[-46.5654,-23.6944]},
   "properties":{"label":"Rua Marechal Deodoro, 1500, Centro, São Bernardo do Campo, SP",
     "name":"Rua Marechal Deodoro, 1500","street":"Rua Marechal Deodoro",
     "housenumber":"1500","neighbourhood":"Centro","locality":"São Bernardo do Campo",
     "region_a":"SP","postalcode":"09710-000","layer":"address"}},
  {"type":"Feature","geometry":{"type":"Point","coordinates":[-46.57,-23.70]},
   "properties":{"label":"Rua Marechal Rondon, Rudge Ramos","name":"Rua Marechal Rondon",
     "borough":"Rudge Ramos","localadmin":"São Bernardo do Campo","layer":"street"}}
]}
''';

http.Response _ok(String body) => http.Response(
  body,
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('lê rua, número, bairro, cidade, UF, CEP e coordenadas', () {
    final items = AddressAutocompleteService.parseFeatures(_body);
    expect(items, hasLength(2));
    final first = items.first;
    expect(first.street, 'Rua Marechal Deodoro');
    expect(first.number, '1500');
    expect(first.neighborhood, 'Centro');
    expect(first.city, 'São Bernardo do Campo');
    expect(first.state, 'SP');
    expect(first.postalCode, '09710000');
    expect(first.lat, closeTo(-23.6944, 1e-6));
    expect(first.lng, closeTo(-46.5654, 1e-6));

    final second = items.last;
    expect(second.street, 'Rua Marechal Rondon');
    expect(second.number, isNull);
    expect(second.neighborhood, 'Rudge Ramos');
    expect(second.city, 'São Bernardo do Campo');
  });

  test('JSON inválido vira lista vazia', () {
    expect(AddressAutocompleteService.parseFeatures('oops'), isEmpty);
    expect(AddressAutocompleteService.parseFeatures('{}'), isEmpty);
  });

  test('monta a URL do ORS com país, foco e camadas', () async {
    Uri? called;
    final service = AddressAutocompleteService(
      apiKey: 'k',
      client: MockClient((request) async {
        called = request.url;
        return _ok(_body);
      }),
    );
    final items = await service.suggest(
      'Rua Marechal',
      focus: const GeoPoint(-23.69, -46.56),
    );
    expect(items, hasLength(2));
    expect(called!.host, 'api.openrouteservice.org');
    expect(called!.path, '/geocode/autocomplete');
    final params = called!.queryParameters;
    expect(params['api_key'], 'k');
    expect(params['text'], 'Rua Marechal');
    expect(params['boundary.country'], 'BR');
    expect(params['focus.point.lat'], '-23.69');
    expect(params['focus.point.lon'], '-46.56');
    expect(params['size'], '5');
    expect(params['layers'], 'address,street,venue');
  });

  test('sem chave, texto curto ou erro devolve lista vazia sem rede', () async {
    var calls = 0;
    final noKey = AddressAutocompleteService(
      apiKey: '',
      client: MockClient((_) async {
        calls++;
        return _ok(_body);
      }),
    );
    expect(await noKey.suggest('Rua Marechal'), isEmpty);
    expect(calls, 0);

    final service = AddressAutocompleteService(
      apiKey: 'k',
      client: MockClient((_) async {
        calls++;
        return _ok(_body);
      }),
    );
    expect(await service.suggest('Rua'), isEmpty);
    expect(calls, 0);

    final failing = AddressAutocompleteService(
      apiKey: 'k',
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    expect(await failing.suggest('Rua Marechal'), isEmpty);

    final serverError = AddressAutocompleteService(
      apiKey: 'k',
      client: MockClient((_) async => http.Response('erro', 500)),
    );
    expect(await serverError.suggest('Rua Marechal'), isEmpty);
  });

  test('cache em memória evita repetir a mesma busca', () async {
    var calls = 0;
    final service = AddressAutocompleteService(
      apiKey: 'k',
      client: MockClient((_) async {
        calls++;
        return _ok(_body);
      }),
    );
    await service.suggest('Rua Marechal');
    final again = await service.suggest('rua marechal ');
    expect(again, hasLength(2));
    expect(calls, 1);
  });

  test('só a última busca vale (resposta atrasada é descartada)', () async {
    final slow = Completer<http.Response>();
    final service = AddressAutocompleteService(
      apiKey: 'k',
      client: MockClient((request) {
        if (request.url.queryParameters['text'] == 'Rua Mare') {
          return slow.future;
        }
        return Future.value(_ok(_body));
      }),
    );
    final first = service.suggest('Rua Mare');
    final second = service.suggest('Rua Marechal');
    expect(await second, hasLength(2));
    slow.complete(_ok(_body));
    expect(await first, isEmpty);
  });
}
