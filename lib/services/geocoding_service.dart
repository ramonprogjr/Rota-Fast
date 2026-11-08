import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rota_max/core/constants/app_constants.dart';
import 'package:rota_max/data/repositories/settings_repository.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/services/address_autocomplete_service.dart';

class GeocodingException implements Exception {
  GeocodingException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Endereço -> coordenadas.
///
/// Ordem: cache local (pontos já confirmados) -> Nominatim -> OpenRouteService
/// (só se houver chave e o Nominatim não achar nada).
///
/// O Nominatim não aceita `q` junto com os campos estruturados (street, city,
/// ...): devolve HTTP 400. Por isso cada requisição usa **ou** texto livre
/// **ou** campos estruturados, nunca os dois.
class GeocodingService {
  GeocodingService({
    required this._cache,
    http.Client? client,
    String? orsApiKey,
    this.timeout = const Duration(seconds: 12),
    this.minInterval = AppConstants.nominatimMinInterval,
  }) : _client = client ?? http.Client(),
       orsApiKey = orsApiKey ?? kOrsApiKey;

  final GeocodeCacheRepository _cache;
  final http.Client _client;

  /// Chave do OpenRouteService (segunda fonte). Vazia = desligado.
  final String orsApiKey;
  final Duration timeout;

  /// Intervalo mínimo entre chamadas ao Nominatim (política: 1 req/s).
  final Duration minInterval;
  DateTime? _lastRequestAt;

  /// Cidade usada quando a busca não traz cidade. O AppState atualiza com a
  /// cidade do ponto de saída.
  String fallbackCity = AppConstants.defaultCity;

  Future<GeoResult?> geocode(String rawQuery) async {
    final results = await search(rawQuery);
    if (results.isEmpty) {
      return null;
    }
    return results.first;
  }

  /// Busca candidatos. Com [street] preenchido usa a busca estruturada do
  /// Nominatim (rua, cidade, UF, CEP); se ela não achar nada, tenta o texto
  /// livre. Sem [street], só texto livre.
  Future<List<GeoResult>> search(
    String rawQuery, {
    String? street,
    String? number,
    String? neighborhood,
    String? city,
    String? state,
    String? postalCode,
  }) async {
    final freeText = buildFreeText(
      rawQuery: rawQuery,
      street: street,
      number: number,
      neighborhood: neighborhood,
      city: city,
      state: state,
    );
    if (freeText.length < 5) {
      throw GeocodingException('Endereço muito curto para localizar.');
    }

    final cached = await _readCache([rawQuery, freeText]);
    if (cached != null) {
      return [cached];
    }

    var results = <GeoResult>[];
    if (_has(street)) {
      results = await _nominatim(
        buildStructuredParams(
          street: street!,
          number: number,
          city: _has(city) ? city : fallbackCity,
          state: state,
          postalCode: postalCode,
        ),
      );
    }
    if (results.isEmpty) {
      results = await _nominatim(buildFreeTextParams(freeText));
    }
    if (results.isEmpty && orsApiKey.trim().isNotEmpty) {
      results = await _orsSearch(freeText);
    }
    return results;
  }

  Future<void> cacheConfirmed(String query, GeoResult result) {
    return _cache.put(query, result);
  }

  /// Parâmetros da busca em texto livre (só `q`).
  static Map<String, String> buildFreeTextParams(String query) => {
    'q': query,
    ..._commonParams,
  };

  /// Parâmetros da busca estruturada (sem `q`).
  static Map<String, String> buildStructuredParams({
    required String street,
    String? number,
    String? city,
    String? state,
    String? postalCode,
  }) {
    final streetLine = [
      if (_has(number)) number!.trim(),
      street.trim(),
    ].join(' ');
    final cep = (postalCode ?? '').replaceAll(RegExp(r'\D'), '');
    return {
      'street': streetLine,
      if (_has(city)) 'city': city!.trim(),
      if (_has(state)) 'state': state!.trim(),
      if (cep.length == 8)
        'postalcode': '${cep.substring(0, 5)}-${cep.substring(5)}',
      'country': 'Brasil',
      ..._commonParams,
    };
  }

  static const _commonParams = {
    'format': 'json',
    'limit': '5',
    'addressdetails': '1',
    'countrycodes': 'br',
    'accept-language': 'pt-BR',
  };

  /// Texto livre: rua e número, bairro, cidade e UF. O CEP fica de fora porque
  /// no OSM ele costuma faltar e derruba resultados bons.
  String buildFreeText({
    required String rawQuery,
    String? street,
    String? number,
    String? neighborhood,
    String? city,
    String? state,
  }) {
    final raw = rawQuery.trim();
    final lowerRaw = raw.toLowerCase();
    bool missing(String? value) =>
        _has(value) &&
        !RegExp(
          '(^|[^a-zà-ÿ0-9])${RegExp.escape(value!.trim().toLowerCase())}(\$|[^a-zà-ÿ0-9])',
        ).hasMatch(lowerRaw);

    final parts = <String>[];
    if (raw.isNotEmpty) {
      parts.add(raw);
    } else if (_has(street)) {
      parts.add([street!.trim(), if (_has(number)) number!.trim()].join(', '));
    }
    if (missing(neighborhood)) {
      parts.add(neighborhood!.trim());
    }
    if (_has(city)) {
      if (missing(city)) {
        parts.add(city!.trim());
      }
    } else if (!lowerRaw.contains(fallbackCity.toLowerCase())) {
      parts.add(fallbackCity);
    }
    if (missing(state)) {
      parts.add(state!.trim());
    }
    return parts.join(', ');
  }

  Future<GeoResult?> _readCache(List<String> keys) async {
    for (final key in keys) {
      if (key.trim().isEmpty) {
        continue;
      }
      try {
        final hit = await _cache.get(key);
        if (hit != null) {
          return hit;
        }
      } catch (_) {
        // Cache é otimização; falha nele não impede a busca.
      }
    }
    return null;
  }

  Future<List<GeoResult>> _nominatim(Map<String, String> params) async {
    await _respectRateLimit();
    final uri = Uri.parse(AppConstants.nominatimSearchUrl)
        .replace(queryParameters: params);

    http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: {
              'User-Agent': AppConstants.nominatimUserAgent,
              'Accept': 'application/json',
            },
          )
          .timeout(timeout);
    } on TimeoutException {
      throw GeocodingException(
        'A busca demorou demais. O endereço foi salvo; tente localizar depois.',
      );
    } catch (_) {
      throw GeocodingException(
        'Sem internet. O endereço foi salvo, mas a localização fica para depois.',
      );
    }

    if (response.statusCode == 429) {
      throw GeocodingException(
        'Muitas buscas seguidas. Espere um instante e tente de novo.',
      );
    }
    if (response.statusCode != 200) {
      throw GeocodingException(
        'Não foi possível localizar o endereço agora (${response.statusCode}).',
      );
    }

    try {
      return parseNominatimResults(response.body);
    } on FormatException {
      return [];
    }
  }

  Future<List<GeoResult>> _orsSearch(String text) async {
    final uri = Uri.parse(kOrsSearchUrl).replace(
      queryParameters: {
        'api_key': orsApiKey,
        'text': text,
        'boundary.country': 'BR',
        'size': '5',
      },
    );
    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'User-Agent': AppConstants.nominatimUserAgent,
              'Accept': 'application/json',
            },
          )
          .timeout(timeout);
      if (response.statusCode != 200) {
        return [];
      }
      return AddressAutocompleteService.parseFeatures(response.body)
          .map((item) => item.toGeoResult())
          .toList();
    } catch (_) {
      // Segunda fonte: se falhar, fica o resultado (vazio) do Nominatim.
      return [];
    }
  }

  static List<GeoResult> parseNominatimResults(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List || decoded.isEmpty) {
      return [];
    }
    final results = <GeoResult>[];
    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }
      final lat = double.tryParse('${item['lat']}');
      final lon = double.tryParse('${item['lon']}');
      if (lat == null || lon == null) {
        continue;
      }
      results.add(
        GeoResult(
          latitude: lat,
          longitude: lon,
          displayName: item['display_name'] as String?,
        ),
      );
    }
    return results;
  }

  static bool _has(String? value) => value != null && value.trim().isNotEmpty;

  Future<void> _respectRateLimit() async {
    final last = _lastRequestAt;
    if (last != null) {
      final elapsed = DateTime.now().difference(last);
      final wait = minInterval - elapsed;
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
    }
    _lastRequestAt = DateTime.now();
  }
}
