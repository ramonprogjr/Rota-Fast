import 'package:sqflite/sqflite.dart';
import 'package:rota_max/models/geo_result.dart';

/// Preferências simples em chave/valor (tabela `settings`).
abstract class SettingsRepository {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}

class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(this._db);

  final Database _db;

  @override
  Future<String?> get(String key) async {
    final rows = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  @override
  Future<void> set(String key, String value) async {
    await _db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

class MemorySettingsRepository implements SettingsRepository {
  MemorySettingsRepository([Map<String, String>? seed])
      : _values = {...?seed};

  final Map<String, String> _values;

  @override
  Future<String?> get(String key) async => _values[key];

  @override
  Future<void> set(String key, String value) async {
    _values[key] = value;
  }
}

abstract class GeocodeCacheRepository {
  Future<GeoResult?> get(String query);
  Future<void> put(String query, GeoResult result);
}

class SqliteGeocodeCacheRepository implements GeocodeCacheRepository {
  SqliteGeocodeCacheRepository(this._db);

  final Database _db;

  String _key(String query) => query.trim().toLowerCase();

  @override
  Future<GeoResult?> get(String query) async {
    final rows = await _db.query(
      'geocode_cache',
      where: 'query = ?',
      whereArgs: [_key(query)],
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return GeoResult(
      latitude: (row['latitude'] as num).toDouble(),
      longitude: (row['longitude'] as num).toDouble(),
      displayName: row['display_name'] as String?,
      confirmed: true,
    );
  }

  @override
  Future<void> put(String query, GeoResult result) async {
    await _db.insert(
      'geocode_cache',
      {
        'query': _key(query),
        'latitude': result.latitude,
        'longitude': result.longitude,
        'display_name': result.displayName,
        'cached_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

class MemoryGeocodeCacheRepository implements GeocodeCacheRepository {
  final Map<String, GeoResult> _cache = {};

  @override
  Future<GeoResult?> get(String query) async =>
      _cache[query.trim().toLowerCase()];

  @override
  Future<void> put(String query, GeoResult result) async {
    _cache[query.trim().toLowerCase()] = result;
  }
}
