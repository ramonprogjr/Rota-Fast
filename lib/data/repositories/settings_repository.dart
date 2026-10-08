import 'package:sqflite/sqflite.dart';
import 'package:rota_pizza/models/geo_result.dart';
import 'package:rota_pizza/models/shift.dart';

abstract class SettingsRepository {
  Future<bool> motorcycleMode();
  Future<void> setMotorcycleMode(bool enabled);
  Future<VehicleSettings> vehicle();
  Future<void> saveVehicle(VehicleSettings settings);
}

class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(this._db);

  final Database _db;

  Future<String> _get(String key, String fallback) async {
    final rows = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) {
      return fallback;
    }
    return rows.first['value'] as String? ?? fallback;
  }

  Future<void> _put(String key, String value) async {
    await _db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<bool> motorcycleMode() async {
    return await _get('motorcycle_mode', '1') == '1';
  }

  @override
  Future<void> setMotorcycleMode(bool enabled) =>
      _put('motorcycle_mode', enabled ? '1' : '0');

  @override
  Future<VehicleSettings> vehicle() async {
    return VehicleSettings(
      gasPriceLiter: double.tryParse(await _get('gas_price_liter', '6.0')) ?? 6,
      kmPerLiter: double.tryParse(await _get('km_per_liter', '30.0')) ?? 30,
      odometerKm: double.tryParse(await _get('odometer_km', '0')) ?? 0,
      lastOilChangeKm:
          double.tryParse(await _get('last_oil_change_km', '0')) ?? 0,
    );
  }

  @override
  Future<void> saveVehicle(VehicleSettings settings) async {
    await _put('gas_price_liter', settings.gasPriceLiter.toString());
    await _put('km_per_liter', settings.kmPerLiter.toString());
    await _put('odometer_km', settings.odometerKm.toString());
    await _put('last_oil_change_km', settings.lastOilChangeKm.toString());
  }
}

class MemorySettingsRepository implements SettingsRepository {
  MemorySettingsRepository({
    this.motorcycleEnabled = true,
    VehicleSettings? vehicle,
  }) : vehicleSettings = vehicle ?? const VehicleSettings();

  bool motorcycleEnabled;
  VehicleSettings vehicleSettings;

  @override
  Future<bool> motorcycleMode() async => motorcycleEnabled;

  @override
  Future<void> setMotorcycleMode(bool enabled) async {
    motorcycleEnabled = enabled;
  }

  @override
  Future<VehicleSettings> vehicle() async => vehicleSettings;

  @override
  Future<void> saveVehicle(VehicleSettings settings) async {
    vehicleSettings = settings;
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
