import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/services/routing/distance_matrix.dart';
import 'package:rota_max/services/routing/ors_matrix_client.dart';
import 'package:rota_max/services/routing/route_plan_input.dart';

/// Ponto `i` codificado na latitude para o mock reconstruir o índice global.
GeoPoint _point(int i) => GeoPoint(-23.0 - i * 0.001, -46.5);
int _indexOf(List<dynamic> lngLat) =>
    ((-23.0 - (lngLat[1] as num)) / 0.001).round();

/// Mock que responde como a ORS: duração = origem*1000 + destino.
MockClient _encodingClient(List<Map<String, dynamic>> bodies) {
  return MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    bodies.add(body);
    final locations = body['locations'] as List<dynamic>;
    final sources =
        (body['sources'] as List<dynamic>?)?.cast<int>() ??
        List<int>.generate(locations.length, (i) => i);
    final destinations =
        (body['destinations'] as List<dynamic>?)?.cast<int>() ??
        List<int>.generate(locations.length, (i) => i);
    final durations = [
      for (final s in sources)
        [
          for (final d in destinations)
            _indexOf(locations[s] as List) * 1000.0 +
                _indexOf(locations[d] as List),
        ],
    ];
    return http.Response(
      jsonEncode({
        'durations': durations,
        'distances': [
          for (final row in durations) [for (final v in row) v * 10],
        ],
      }),
      200,
    );
  });
}

void main() {
  test('monta URL, cabeçalhos e corpo como a ORS espera', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'durations': [
            [0, 60.5],
            [null, 0],
          ],
          'distances': [
            [0, 500],
            [null, 0],
          ],
        }),
        200,
      );
    });
    final ors = OrsMatrixClient(apiKey: 'minha-chave', client: client);
    final matrix = await ors.matrix(const [
      GeoPoint(-23.1, -46.2),
      GeoPoint(-23.3, -46.4),
    ], RoutingProfile.hgv);

    expect(captured.method, 'POST');
    expect(
      captured.url.toString(),
      'https://api.openrouteservice.org/v2/matrix/driving-hgv',
    );
    expect(captured.headers['Authorization'], 'minha-chave');
    expect(captured.headers['Content-Type'], startsWith('application/json'));
    expect(captured.headers['User-Agent'], contains('RotaMax'));
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['locations'], [
      [-46.2, -23.1],
      [-46.4, -23.3],
    ]);
    expect(body['metrics'], ['distance', 'duration']);
    expect(body['units'], 'm');
    expect(body.containsKey('sources'), isFalse);

    expect(matrix.seconds[0][1], 60.5);
    expect(matrix.meters[0][1], 500);
    expect(matrix.seconds[1][0], isNull);
    expect(matrix.meters[1][0], isNull);
  });

  test('perfil car usa driving-car', () {
    final ors = OrsMatrixClient(
      apiKey: 'k',
      client: MockClient((_) async {
        return http.Response('', 500);
      }),
    );
    expect(ors.endpoint(RoutingProfile.car).path, '/v2/matrix/driving-car');
  });

  test('mais de 50 pontos: divide em blocos e costura', () async {
    final bodies = <Map<String, dynamic>>[];
    final ors = OrsMatrixClient(apiKey: 'k', client: _encodingClient(bodies));
    final points = List<GeoPoint>.generate(60, _point);
    final matrix = await ors.matrix(points, RoutingProfile.car);

    expect(bodies, hasLength(9)); // blocos 25 + 25 + 10 → 3 × 3
    for (final body in bodies) {
      expect((body['locations'] as List).length, lessThanOrEqualTo(50));
    }
    for (var i = 0; i < 60; i++) {
      for (var j = 0; j < 60; j++) {
        expect(matrix.seconds[i][j], i * 1000.0 + j);
        expect(matrix.meters[i][j], (i * 1000.0 + j) * 10);
      }
    }
  });

  test('até 50 pontos: uma única requisição', () async {
    final bodies = <Map<String, dynamic>>[];
    final ors = OrsMatrixClient(apiKey: 'k', client: _encodingClient(bodies));
    final matrix = await ors.matrix(
      List<GeoPoint>.generate(50, _point),
      RoutingProfile.car,
    );
    expect(bodies, hasLength(1));
    expect(matrix.seconds[49][3], 49003);
  });

  test('cache evita segunda chamada; outro perfil chama de novo', () async {
    final bodies = <Map<String, dynamic>>[];
    final ors = OrsMatrixClient(apiKey: 'k', client: _encodingClient(bodies));
    final points = List<GeoPoint>.generate(3, _point);
    await ors.matrix(points, RoutingProfile.car);
    // Diferença abaixo da 5ª casa decimal cai na mesma chave.
    await ors.matrix([
      GeoPoint(points[0].latitude + 0.000001, points[0].longitude),
      points[1],
      points[2],
    ], RoutingProfile.car);
    expect(bodies, hasLength(1));
    await ors.matrix(points, RoutingProfile.hgv);
    expect(bodies, hasLength(2));
  });

  test('HTTP de erro vira RoutingException com status', () async {
    final ors = OrsMatrixClient(
      apiKey: 'k',
      client: MockClient((_) async => http.Response('limite', 429)),
    );
    await expectLater(
      ors.matrix(const [GeoPoint(0, 0), GeoPoint(1, 1)], RoutingProfile.car),
      throwsA(
        isA<RoutingException>().having((e) => e.statusCode, 'statusCode', 429),
      ),
    );
  });

  test('timeout vira RoutingException', () async {
    final ors = OrsMatrixClient(
      apiKey: 'k',
      client: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 30),
    );
    await expectLater(
      ors.matrix(const [GeoPoint(0, 0), GeoPoint(1, 1)], RoutingProfile.car),
      throwsA(isA<RoutingException>()),
    );
  });

  test('resposta inválida vira RoutingException', () async {
    final ors = OrsMatrixClient(
      apiKey: 'k',
      client: MockClient((_) async => http.Response('{"durations": 3}', 200)),
    );
    await expectLater(
      ors.matrix(const [GeoPoint(0, 0), GeoPoint(1, 1)], RoutingProfile.car),
      throwsA(isA<RoutingException>()),
    );
  });

  test('sem chave nem tenta a rede', () async {
    var calls = 0;
    final ors = OrsMatrixClient(
      apiKey: '',
      client: MockClient((_) async {
        calls++;
        return http.Response('', 200);
      }),
    );
    await expectLater(
      ors.matrix(const [GeoPoint(0, 0)], RoutingProfile.car),
      throwsA(isA<RoutingException>()),
    );
    expect(calls, 0);
  });
}
