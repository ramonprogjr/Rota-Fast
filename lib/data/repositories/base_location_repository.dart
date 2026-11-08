import 'package:sqflite/sqflite.dart';
import 'package:rota_max/models/base_location.dart';

abstract class BaseLocationRepository {
  Future<BaseLocation> get();
  Future<void> save(BaseLocation baseLocation);
}

class SqliteBaseLocationRepository implements BaseLocationRepository {
  SqliteBaseLocationRepository(this._db);

  final Database _db;

  @override
  Future<BaseLocation> get() async {
    final rows = await _db.query('base_location', where: 'id = ?', whereArgs: [1]);
    if (rows.isEmpty) {
      return BaseLocation();
    }
    return BaseLocation.fromMap(rows.first);
  }

  @override
  Future<void> save(BaseLocation baseLocation) async {
    await _db.insert(
      'base_location',
      baseLocation.copyWith(id: 1).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

class MemoryBaseLocationRepository implements BaseLocationRepository {
  MemoryBaseLocationRepository([BaseLocation? seed]) : _baseLocation = seed ?? BaseLocation();

  BaseLocation _baseLocation;

  @override
  Future<BaseLocation> get() async => _baseLocation;

  @override
  Future<void> save(BaseLocation baseLocation) async {
    _baseLocation = baseLocation;
  }
}
