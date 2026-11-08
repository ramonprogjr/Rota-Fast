import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rota_max/core/constants/app_constants.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/services/routing/distance_matrix.dart';
import 'package:rota_max/services/routing/route_plan_input.dart';

/// Matriz de tempo e distância pela malha viária da OpenRouteService.
///
/// - Limite do plano gratuito: 50 locais por requisição e 3500 elementos.
///   Acima de [maxLocations] pontos a matriz é montada em blocos
///   origem × destino de [blockSize] pontos e costurada.
/// - Cache em memória pela combinação perfil + coordenadas (5 casas).
/// - Qualquer falha (HTTP, tempo esgotado, resposta inválida) vira
///   [RoutingException]; quem chama decide o fallback.
class OrsMatrixClient implements DistanceMatrixProvider {
  OrsMatrixClient({
    required this.apiKey,
    http.Client? client,
    this.baseUrl = AppConstants.orsBaseUrl,
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client();

  static const maxLocations = 50;
  static const blockSize = 25;

  final String apiKey;
  final String baseUrl;
  final Duration timeout;
  final http.Client _client;
  final Map<String, TravelMatrix> _cache = {};

  static String orsProfile(RoutingProfile profile) {
    switch (profile) {
      case RoutingProfile.car:
        return 'driving-car';
      case RoutingProfile.hgv:
        return 'driving-hgv';
    }
  }

  Uri endpoint(RoutingProfile profile) =>
      Uri.parse('$baseUrl/${orsProfile(profile)}');

  static String cacheKey(List<GeoPoint> points, RoutingProfile profile) {
    final coords = points
        .map((p) =>
            '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}')
        .join(';');
    return '${profile.name}|$coords';
  }

  @override
  Future<TravelMatrix> matrix(
    List<GeoPoint> points,
    RoutingProfile profile,
  ) async {
    if (apiKey.trim().isEmpty) {
      throw RoutingException('Chave da OpenRouteService não configurada.');
    }
    final n = points.length;
    if (n == 0) {
      return TravelMatrix(seconds: const [], meters: const []);
    }
    final key = cacheKey(points, profile);
    final cached = _cache[key];
    if (cached != null) {
      return cached;
    }

    final seconds = List.generate(n, (_) => List<double?>.filled(n, null));
    final meters = List.generate(n, (_) => List<double?>.filled(n, null));

    if (n <= maxLocations) {
      final indices = List<int>.generate(n, (i) => i);
      await _fetchBlock(points, indices, indices, profile, seconds, meters);
    } else {
      final blocks = <List<int>>[];
      for (var start = 0; start < n; start += blockSize) {
        final end = start + blockSize > n ? n : start + blockSize;
        blocks.add(List<int>.generate(end - start, (i) => start + i));
      }
      for (final sources in blocks) {
        for (final destinations in blocks) {
          await _fetchBlock(
            points,
            sources,
            destinations,
            profile,
            seconds,
            meters,
          );
        }
      }
    }

    final result = TravelMatrix(seconds: seconds, meters: meters);
    _cache[key] = result;
    return result;
  }

  /// Busca a submatriz [sources] × [destinations] (índices globais) e grava
  /// em [seconds]/[meters].
  Future<void> _fetchBlock(
    List<GeoPoint> points,
    List<int> sources,
    List<int> destinations,
    RoutingProfile profile,
    List<List<double?>> seconds,
    List<List<double?>> meters,
  ) async {
    final same = identical(sources, destinations);
    final locationIndices = same ? sources : [...sources, ...destinations];
    final body = <String, Object?>{
      'locations': [
        for (final i in locationIndices)
          [points[i].longitude, points[i].latitude],
      ],
      'metrics': ['distance', 'duration'],
      'units': 'm',
      if (!same) ...{
        'sources': List<int>.generate(sources.length, (i) => i),
        'destinations': List<int>.generate(
          destinations.length,
          (i) => sources.length + i,
        ),
      },
    };

    http.Response response;
    try {
      response = await _client
          .post(
            endpoint(profile),
            headers: {
              'Authorization': apiKey,
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': AppConstants.nominatimUserAgent,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw RoutingException('Tempo esgotado ao consultar a malha viária.');
    } catch (error) {
      throw RoutingException('Sem conexão com a malha viária: $error');
    }

    if (response.statusCode != 200) {
      throw RoutingException(
        'Malha viária indisponível.',
        statusCode: response.statusCode,
      );
    }

    final parsed = parseResponse(
      response.body,
      rows: sources.length,
      cols: destinations.length,
    );
    for (var r = 0; r < sources.length; r++) {
      for (var c = 0; c < destinations.length; c++) {
        seconds[sources[r]][destinations[c]] = parsed.seconds[r][c];
        meters[sources[r]][destinations[c]] = parsed.meters[r][c];
      }
    }
  }

  /// Lê `durations` e `distances` da resposta. `null` permanece `null`.
  static TravelMatrix parseResponse(
    String body, {
    required int rows,
    required int cols,
  }) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('resposta não é objeto');
      }
      final seconds = _readGrid(decoded['durations'], rows, cols);
      final meters = _readGrid(decoded['distances'], rows, cols);
      return TravelMatrix(seconds: seconds, meters: meters);
    } on RoutingException {
      rethrow;
    } catch (error) {
      throw RoutingException('Resposta inválida da malha viária: $error');
    }
  }

  static List<List<double?>> _readGrid(Object? raw, int rows, int cols) {
    if (raw is! List || raw.length != rows) {
      throw RoutingException('Matriz com tamanho inesperado.');
    }
    return [
      for (final row in raw)
        if (row is List && row.length == cols)
          [for (final value in row) value is num ? value.toDouble() : null]
        else
          throw RoutingException('Linha da matriz com tamanho inesperado.'),
    ];
  }
}
