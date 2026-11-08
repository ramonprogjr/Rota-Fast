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
    this.timeout = const Duration(seconds: 15),
    DateTime Function()? clock,
  })  : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  /// Instância compartilhada (o cache sobrevive entre aberturas do mapa).
  static final FuelStationService shared = FuelStationService();

  static const endpoint = 'https://overpass-api.de/api/interpreter';

  final http.Client _client;
  final DateTime Function() _clock;
  final int radiusMeters;
  final Duration cacheTtl;
  final Duration timeout;
  final Map<String, _CacheEntry> _cache = {};

  static String buildQuery(double lat, double lng, {int radius = 3000}) =>
      '[out:json][timeout:15];'
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
    try {
      final response = await _client
          .post(
            Uri.parse(endpoint),
            headers: {
              'User-Agent': AppConstants.nominatimUserAgent,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {'data': buildQuery(lat, lng, radius: radiusMeters)},
          )
          .timeout(timeout);
      if (response.statusCode == 429 || response.statusCode == 504) {
        return const FuelStationResult(
          error: 'Serviço de postos ocupado. Tente de novo em instantes.',
        );
      }
      if (response.statusCode != 200) {
        return FuelStationResult(
          error: 'Não foi possível buscar postos (${response.statusCode}).',
        );
      }
      final stations = parse(utf8.decode(response.bodyBytes));
      _cache[key] = _CacheEntry(stations, _clock());
      return FuelStationResult(stations: stations);
    } on TimeoutException {
      return const FuelStationResult(
        error: 'A busca de postos demorou demais. Verifique a internet.',
      );
    } on FormatException {
      return const FuelStationResult(
        error: 'Resposta inválida do serviço de postos.',
      );
    } catch (_) {
      return const FuelStationResult(
        error: 'Sem internet para buscar postos.',
      );
    }
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
