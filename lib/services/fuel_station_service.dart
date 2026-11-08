import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rota_max/core/constants/app_constants.dart';
import 'package:rota_max/core/utils/haversine.dart';

/// Posto de combustível vindo do OpenStreetMap (sem preço: o OSM não tem).
class FuelStation {
  const FuelStation({
    required this.id,
    required this.latitude,
    required this.longitude,
    this.name,
    this.brand,
    this.hasDiesel = false,
  });

  final String id;
  final double latitude;
  final double longitude;
  final String? name;
  final String? brand;
  final bool hasDiesel;

  /// Nome para mostrar: nome, senão bandeira, senão "Posto".
  String get label {
    final n = name?.trim() ?? '';
    final b = brand?.trim() ?? '';
    if (n.isNotEmpty && b.isNotEmpty && !n.toLowerCase().contains(b.toLowerCase())) {
      return '$n ($b)';
    }
    if (n.isNotEmpty) {
      return n;
    }
    if (b.isNotEmpty) {
      return b;
    }
    return 'Posto';
  }

  double distanceKmFrom(double lat, double lng) =>
      haversineKm(lat, lng, latitude, longitude);
}

/// Resultado da busca: nunca lança exceção; em falha vem [error].
class FuelStationResult {
  const FuelStationResult({
    this.stations = const [],
    this.error,
    this.fromCache = false,
  });

  final List<FuelStation> stations;
  final String? error;
  final bool fromCache;

  bool get ok => error == null;
}

class _CacheEntry {
  _CacheEntry(this.stations, this.at);

  final List<FuelStation> stations;
  final DateTime at;
}

/// Busca postos próximos na Overpass API, com cache de 10 min por área.
class FuelStationService {
  FuelStationService({
    http.Client? client,
    this.radiusMeters = 3000,
    this.cacheTtl = const Duration(minutes: 10),
    this.timeout = const Duration(seconds: 30),
    this.hedgeDelay = const Duration(seconds: 4),
    this.endpoints = defaultEndpoints,
    DateTime Function()? clock,
  })  : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  /// Instância compartilhada (o cache sobrevive entre aberturas do mapa).
  static final FuelStationService shared = FuelStationService();

  /// Servidores Overpass públicos (gratuitos e muitas vezes lotados). A
  /// busca começa no primeiro; se ele falhar ou não responder em
  /// [hedgeDelay], o próximo entra na disputa e vale a primeira resposta boa.
  static const defaultEndpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  static String get endpoint => defaultEndpoints.first;

  final http.Client _client;
  final DateTime Function() _clock;
  final int radiusMeters;
  final Duration cacheTtl;
  /// Tempo total da busca, somando todos os servidores.
  final Duration timeout;

  /// Espera antes de chamar o próximo servidor em paralelo.
  final Duration hedgeDelay;
  final List<String> endpoints;
  final Map<String, _CacheEntry> _cache = {};

  static String buildQuery(double lat, double lng, {int radius = 3000}) =>
      '[out:json][timeout:25];'
      'nwr["amenity"="fuel"](around:$radius,$lat,$lng);'
      'out center 30;';

  /// Chave do cache: coordenadas arredondadas em 2 casas (~1 km).
  static String cacheKey(double lat, double lng) =>
      '${lat.toStringAsFixed(2)},${lng.toStringAsFixed(2)}';

  /// Converte a resposta JSON da Overpass em postos. Ignora itens sem
  /// coordenada (node usa lat/lon; way/relation usam `center`).
  static List<FuelStation> parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return [];
    }
    final elements = decoded['elements'];
    if (elements is! List) {
      return [];
    }
    final result = <FuelStation>[];
    for (final element in elements) {
      if (element is! Map<String, dynamic>) {
        continue;
      }
      double? lat = _toDouble(element['lat']);
      double? lon = _toDouble(element['lon']);
      final center = element['center'];
      if ((lat == null || lon == null) && center is Map<String, dynamic>) {
        lat = _toDouble(center['lat']);
        lon = _toDouble(center['lon']);
      }
      if (lat == null || lon == null) {
        continue;
      }
      final rawTags = element['tags'];
      final tags = rawTags is Map<String, dynamic> ? rawTags : const {};
      result.add(
        FuelStation(
          id: '${element['type'] ?? 'node'}/${element['id'] ?? result.length}',
          latitude: lat,
          longitude: lon,
          name: tags['name'] as String?,
          brand: tags['brand'] as String?,
          hasDiesel: tags['fuel:diesel'] == 'yes',
        ),
      );
    }
    return result;
  }

  /// Postos num raio de [radiusMeters] do ponto.
  Future<FuelStationResult> nearby(double lat, double lng) async {
    final key = cacheKey(lat, lng);
    final cached = _cache[key];
    if (cached != null && _clock().difference(cached.at) < cacheTtl) {
      return FuelStationResult(stations: cached.stations, fromCache: true);
    }
    final body = {'data': buildQuery(lat, lng, radius: radiusMeters)};
    final done = Completer<List<FuelStation>>();
    final failures = <Object>[];
    var started = 0;
    var finished = 0;
    Timer? hedge;

    void startNext() {
      if (done.isCompleted || started >= endpoints.length) {
        return;
      }
      final url = endpoints[started++];
      hedge?.cancel();
      if (started < endpoints.length) {
        hedge = Timer(hedgeDelay, startNext);
      }
      _fetch(url, body).then(
        (stations) {
          if (!done.isCompleted) {
            done.complete(stations);
          }
        },
        onError: (Object error) {
          failures.add(error);
          finished++;
          if (done.isCompleted) {
            return;
          }
          if (finished >= endpoints.length) {
            done.completeError(const _AllFailed());
          } else if (finished == started) {
            // Ninguém mais tentando: chama o próximo já.
            startNext();
          }
        },
      );
    }

    startNext();
    try {
      final stations = await done.future.timeout(timeout);
      _cache[key] = _CacheEntry(stations, _clock());
      return FuelStationResult(stations: stations);
    } on TimeoutException {
      return const FuelStationResult(
        error: 'A busca de postos demorou demais (servidores lentos). '
            'Tente de novo em instantes.',
      );
    } on _AllFailed {
      return FuelStationResult(error: _messageFor(failures));
    } finally {
      hedge?.cancel();
    }
  }

  Future<List<FuelStation>> _fetch(String url, Map<String, String> body) async {
    final response = await _client.post(
      Uri.parse(url),
      headers: {
        'User-Agent': AppConstants.nominatimUserAgent,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );
    if (response.statusCode != 200) {
      throw _HttpStatus(response.statusCode);
    }
    return parse(utf8.decode(response.bodyBytes));
  }

  static String _messageFor(List<Object> failures) {
    final statuses = failures.whereType<_HttpStatus>().toList();
    if (statuses.any((s) => s.busy)) {
      return 'Serviço de postos ocupado. Tente de novo em instantes.';
    }
    if (statuses.isNotEmpty) {
      return 'Não foi possível buscar postos (${statuses.first.code}).';
    }
    if (failures.any((f) => f is FormatException)) {
      return 'Resposta inválida do serviço de postos.';
    }
    return 'Sem internet para buscar postos.';
  }

  void clearCache() => _cache.clear();

  static double? _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }
}

class _HttpStatus implements Exception {
  const _HttpStatus(this.code);

  final int code;

  /// Servidor lotado ou fora do ar por instantes.
  bool get busy => code == 429 || (code >= 502 && code <= 504);
}

class _AllFailed implements Exception {
  const _AllFailed();
}
