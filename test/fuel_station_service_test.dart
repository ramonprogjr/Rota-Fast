import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rota_max/services/fuel_station_service.dart';

const _body = '''
{
  "elements": [
    {"type": "node", "id": 1, "lat": -23.60, "lon": -46.50,
     "tags": {"amenity": "fuel", "name": "Posto Central", "brand": "Shell",
              "fuel:diesel": "yes"}},
    {"type": "way", "id": 2, "center": {"lat": -23.61, "lon": -46.51},
     "tags": {"amenity": "fuel", "brand": "Ipiranga"}},
    {"type": "relation", "id": 3,
     "tags": {"amenity": "fuel", "name": "Sem centro"}}
  ]
}
''';

void main() {
  test('parse lê node, way com center e a tag de diesel', () {
    final stations = FuelStationService.parse(_body);
    expect(stations, hasLength(2));
    final node = stations[0];
    expect(node.id, 'node/1');
    expect(node.latitude, -23.60);
    expect(node.label, 'Posto Central (Shell)');
    expect(node.hasDiesel, isTrue);
    final way = stations[1];
    expect(way.latitude, -23.61);
    expect(way.longitude, -46.51);
    expect(way.label, 'Ipiranga');
    expect(way.hasDiesel, isFalse);
  });

  test('consulta Overpass com raio, User-Agent e corpo em form', () async {
    http.Request? sent;
    final client = MockClient((request) async {
      sent = request;
      return http.Response.bytes(utf8.encode(_body), 200);
    });
    final service = FuelStationService(client: client);
    final result = await service.nearby(-23.6012, -46.5034);
    expect(result.ok, isTrue);
    expect(result.stations, hasLength(2));
    expect(sent!.method, 'POST');
    expect(sent!.url.toString(), FuelStationService.endpoint);
    expect(sent!.headers['User-Agent'], contains('RotaMax'));
    final data = sent!.bodyFields['data']!;
    expect(data, startsWith('[out:json][timeout:25];'));
    expect(
      data,
      contains('nwr["amenity"="fuel"](around:3000,-23.6012,-46.5034);'),
    );
    expect(data, endsWith('out center 30;'));
  });

  test('cache de 10 min por área (coordenadas em 2 casas)', () async {
    var calls = 0;
    var now = DateTime(2026, 11, 8, 10);
    final client = MockClient((request) async {
      calls++;
      return http.Response(_body, 200);
    });
    final service = FuelStationService(client: client, clock: () => now);
    await service.nearby(-23.6012, -46.5034);
    final again = await service.nearby(-23.6049, -46.5001);
    expect(calls, 1);
    expect(again.fromCache, isTrue);
    expect(again.stations, hasLength(2));

    await service.nearby(-23.70, -46.50);
    expect(calls, 2);

    now = now.add(const Duration(minutes: 11));
    final expired = await service.nearby(-23.6012, -46.5034);
    expect(calls, 3);
    expect(expired.fromCache, isFalse);
  });

  test('erro HTTP vira mensagem, sem exceção nem cache', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('busy', 429);
    });
    final service = FuelStationService(client: client);
    final result = await service.nearby(-23.6, -46.5);
    expect(result.ok, isFalse);
    expect(result.error, isNotEmpty);
    // Tentou os 3 servidores; nada vai para o cache.
    expect(calls, 3);
    expect(result.error, contains('ocupado'));
    await service.nearby(-23.6, -46.5);
    expect(calls, 6);
  });

  test('servidor principal fora (502): usa o espelho', () async {
    final asked = <String>[];
    final client = MockClient((request) async {
      asked.add(request.url.host);
      return request.url.host == 'overpass-api.de'
          ? http.Response('bad gateway', 502)
          : http.Response(_body, 200);
    });
    final result = await FuelStationService(client: client).nearby(-23.6, -46.5);
    expect(result.ok, isTrue);
    expect(result.stations, hasLength(2));
    expect(asked, ['overpass-api.de', 'maps.mail.ru']);
  });

  test('servidor principal lento: o espelho entra depois da espera', () async {
    final asked = <String>[];
    final client = MockClient((request) {
      asked.add(request.url.host);
      if (request.url.host == 'overpass-api.de') {
        return Completer<http.Response>().future; // nunca responde
      }
      return Future.value(http.Response(_body, 200));
    });
    final service = FuelStationService(
      client: client,
      hedgeDelay: const Duration(milliseconds: 20),
    );
    final result = await service.nearby(-23.6, -46.5);
    expect(result.ok, isTrue);
    expect(asked, ['overpass-api.de', 'maps.mail.ru']);
  });

  test('sem internet e timeout viram mensagem', () async {
    final offline = FuelStationService(
      client: MockClient((request) async => throw http.ClientException('x')),
    );
    expect((await offline.nearby(-23.6, -46.5)).error, contains('internet'));

    final slow = FuelStationService(
      client: MockClient((request) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 10),
    );
    expect((await slow.nearby(-23.6, -46.5)).error, contains('demorou'));
  });
}
