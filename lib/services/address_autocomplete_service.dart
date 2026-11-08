import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rota_max/models/geo_result.dart';

/// Chave do OpenRouteService passada no build:
/// `flutter run --dart-define=ORS_API_KEY=...`.
// TODO(integração): trocar por AppConstants.orsApiKey (pacote A).
const String kOrsApiKey = String.fromEnvironment('ORS_API_KEY');

const String kOrsAutocompleteUrl =
    'https://api.openrouteservice.org/geocode/autocomplete';
const String kOrsSearchUrl = 'https://api.openrouteservice.org/geocode/search';

/// Sugestão de endereço vinda do OpenRouteService (Pelias).
class AddressSuggestion {
  const AddressSuggestion({
    required this.label,
    this.street,
    this.number,
    this.neighborhood,
    this.city,
    this.state,
    this.postalCode,
    required this.lat,
    required this.lng,
  });

  final String label;
  final String? street;
  final String? number;
  final String? neighborhood;
  final String? city;

  /// UF (ex.: SP).
  final String? state;

  /// CEP só com dígitos.
  final String? postalCode;
  final double lat;
  final double lng;

  GeoResult toGeoResult() =>
      GeoResult(latitude: lat, longitude: lng, displayName: label);

  @override
  String toString() => label;
}

/// Autocompletar de endereço (OpenRouteService). O Nominatim proíbe
/// autocompletar na política de uso, por isso ele não é usado aqui.
///
/// Nunca lança exceção: sem chave, sem rede ou com erro devolve lista vazia.
class AddressAutocompleteService {
  AddressAutocompleteService({
    http.Client? client,
    String? apiKey,
    this.timeout = const Duration(seconds: 6),
    this.minChars = 4,
    this.maxResults = 5,
    this.cacheSize = 40,
  }) : _client = client ?? http.Client(),
       apiKey = apiKey ?? kOrsApiKey;

  /// Instância compartilhada pelas telas (usa a chave do build).
  static final AddressAutocompleteService shared = AddressAutocompleteService();

  final http.Client _client;
  final String apiKey;
  final Duration timeout;
  final int minChars;
  final int maxResults;
  final int cacheSize;

  final _cache = <String, List<AddressSuggestion>>{};
  int _generation = 0;
  Completer<void>? _abort;

  bool get enabled => apiKey.trim().isNotEmpty;

  /// Sugestões para [text]. Só a chamada mais recente vale: se outra
  /// começar antes desta terminar, esta devolve lista vazia.
  Future<List<AddressSuggestion>> suggest(
    String text, {
    GeoPoint? focus,
  }) async {
    final query = text.trim();
    final generation = ++_generation;
    _cancelPending();
    if (!enabled || query.length < minChars) {
      return const [];
    }
    final key = _cacheKey(query, focus);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }

    final params = <String, String>{
      'api_key': apiKey,
      'text': query,
      'boundary.country': 'BR',
      'size': '$maxResults',
      'layers': 'address,street,venue',
    };
    if (focus != null) {
      params['focus.point.lon'] = '${focus.longitude}';
      params['focus.point.lat'] = '${focus.latitude}';
    }
    final uri = Uri.parse(kOrsAutocompleteUrl).replace(queryParameters: params);
    final abort = Completer<void>();
    _abort = abort;
    try {
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      )..headers['Accept'] = 'application/json';
      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed)
          .timeout(timeout);
      if (generation != _generation) {
        return const [];
      }
      if (response.statusCode != 200) {
        return const [];
      }
      final results = parseFeatures(response.body).take(maxResults).toList();
      _cache[key] = results;
      while (_cache.length > cacheSize) {
        _cache.remove(_cache.keys.first);
      }
      return results;
    } catch (_) {
      return const [];
    } finally {
      if (identical(_abort, abort)) {
        _abort = null;
      }
    }
  }

  /// Descarta a busca em andamento (ex.: o usuário escolheu uma sugestão).
  void cancel() {
    _generation++;
    _cancelPending();
  }

  void _cancelPending() {
    final pending = _abort;
    _abort = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  String _cacheKey(String query, GeoPoint? focus) {
    final where = focus == null
        ? ''
        : '@${focus.latitude.toStringAsFixed(2)},${focus.longitude.toStringAsFixed(2)}';
    return '${query.toLowerCase()}$where';
  }

  /// Lê o GeoJSON do Pelias (autocomplete e search têm o mesmo formato).
  static List<AddressSuggestion> parseFeatures(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['features'] is! List) {
        return const [];
      }
      final results = <AddressSuggestion>[];
      for (final feature in decoded['features'] as List) {
        if (feature is! Map) {
          continue;
        }
        final geometry = feature['geometry'];
        final props = feature['properties'];
        if (geometry is! Map || props is! Map) {
          continue;
        }
        final coords = geometry['coordinates'];
        if (coords is! List || coords.length < 2) {
          continue;
        }
        final lng = (coords[0] as num?)?.toDouble();
        final lat = (coords[1] as num?)?.toDouble();
        if (lat == null || lng == null) {
          continue;
        }
        String? text(String key) {
          final value = props[key];
          if (value == null) {
            return null;
          }
          final clean = '$value'.trim();
          return clean.isEmpty ? null : clean;
        }

        final layer = text('layer');
        final street =
            text('street') ?? (layer == 'street' ? text('name') : null);
        final postal = (text('postalcode') ?? '').replaceAll(RegExp(r'\D'), '');
        results.add(
          AddressSuggestion(
            label: text('label') ?? text('name') ?? '',
            street: street,
            number: text('housenumber'),
            neighborhood: text('neighbourhood') ?? text('borough'),
            city: text('locality') ?? text('localadmin') ?? text('county'),
            state: _uf(text('region_a')),
            postalCode: postal.length == 8 ? postal : null,
            lat: lat,
            lng: lng,
          ),
        );
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  static String? _uf(String? value) {
    if (value == null) {
      return null;
    }
    final upper = value.toUpperCase();
    // Pelias às vezes devolve "BR-SP".
    final parts = upper.split('-');
    final last = parts.last.trim();
    return last.length == 2 ? last : null;
  }
}
