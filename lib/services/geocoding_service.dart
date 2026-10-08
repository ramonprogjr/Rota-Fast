import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rota_pizza/core/constants/app_constants.dart';
import 'package:rota_pizza/data/repositories/settings_repository.dart';
import 'package:rota_pizza/models/geo_result.dart';

class GeocodingException implements Exception {
  GeocodingException(this.message);
  final String message;

  @override
  String toString() => message;
}

class GeocodingService {
  GeocodingService({
    required this._cache,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final GeocodeCacheRepository _cache;
  final http.Client _client;
  DateTime? _lastRequestAt;

  Future<GeoResult?> geocode(String rawQuery) async {
    final results = await search(rawQuery);
    if (results.isEmpty) {
      return null;
    }
    return results.first;
  }

  Future<List<GeoResult>> search(
    String rawQuery, {
    String? street,
    String? number,
    String? neighborhood,
    String? city,
  }) async {
    final query = _buildQuery(
      rawQuery: rawQuery,
      street: street,
      number: number,
      neighborhood: neighborhood,
      city: city,
    );
    if (query.length < 5) {
      throw GeocodingException('Endereço muito curto para localizar.');
    }

    await _respectRateLimit();
    final params = <String, String>{
      'q': query,
      'format': 'json',
      'limit': '5',
      'addressdetails': '1',
      'countrycodes': 'br',
      'accept-language': 'pt-BR',
    };
    if ((city ?? '').trim().isNotEmpty) {
      params['city'] = city!.trim();
    }
    if ((street ?? '').trim().isNotEmpty) {
      final streetLine = [
        street!.trim(),
        if ((number ?? '').trim().isNotEmpty) number!.trim(),
      ].join(' ');
      params['street'] = streetLine;
    }

    final uri = Uri.parse(AppConstants.nominatimSearchUrl).replace(
      queryParameters: params,
    );

    http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {
          'User-Agent': AppConstants.nominatimUserAgent,
          'Accept': 'application/json',
        },
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

    return parseNominatimResults(response.body);
  }

  Future<void> cacheConfirmed(String query, GeoResult result) {
    return _cache.put(query, result);
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

  String _buildQuery({
    required String rawQuery,
    String? street,
    String? number,
    String? neighborhood,
    String? city,
  }) {
    final parts = <String>[
      if (rawQuery.trim().isNotEmpty) rawQuery.trim(),
      if ((neighborhood ?? '').trim().isNotEmpty) neighborhood!.trim(),
      if ((city ?? '').trim().isNotEmpty) city!.trim() else AppConstants.defaultCity,
    ];
    if (rawQuery.trim().isEmpty && (street ?? '').trim().isNotEmpty) {
      parts.insert(
        0,
        [
          street!.trim(),
          if ((number ?? '').trim().isNotEmpty) number!.trim(),
        ].join(', '),
      );
    }
    return parts.join(', ');
  }

  Future<void> _respectRateLimit() async {
    final last = _lastRequestAt;
    if (last != null) {
      final elapsed = DateTime.now().difference(last);
      final wait = AppConstants.nominatimMinInterval - elapsed;
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
    }
    _lastRequestAt = DateTime.now();
  }
}
