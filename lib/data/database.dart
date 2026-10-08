import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:rota_pizza/data/demo_shift_seed.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  Future<Database>? _opening;

  Future<Database> get database {
    if (_db != null) {
      return Future.value(_db);
    }
    _opening ??= _open();
    return _opening!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'rota_pizza.db');
    final db = await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    _db = db;
    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE pizzeria (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        address TEXT NOT NULL,
        city TEXT NOT NULL,
        latitude REAL,
        longitude REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE deliveries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_number TEXT,
        customer_name TEXT NOT NULL,
        phone TEXT,
        address TEXT NOT NULL,
        number TEXT,
        complement TEXT,
        neighborhood TEXT,
        city TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        value REAL,
        priority TEXT NOT NULL DEFAULT 'normal',
        status TEXT NOT NULL DEFAULT 'pending',
        route_order INTEGER,
        location_confirmed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        delivered_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE geocode_cache (
        query TEXT PRIMARY KEY,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        display_name TEXT,
        cached_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await _createShiftTables(db);
    await db.insert('pizzeria', {
      'id': 1,
      'name': 'Estabelecimento',
      'address': '',
      'city': 'São Bernardo do Campo',
      'latitude': null,
      'longitude': null,
    });
    await db.insert('settings', {
      'key': 'motorcycle_mode',
      'value': '1',
    });
    await _seedVehicleSettings(db);
    await DemoShiftSeeder.seedIfNeeded(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE deliveries ADD COLUMN location_confirmed INTEGER NOT NULL DEFAULT 0',
      );
      await _createShiftTables(db);
      await _seedVehicleSettings(db);
    }
    if (oldVersion < 3) {
      await DemoShiftSeeder.seedIfNeeded(db);
    }
  }

  Future<void> _createShiftTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        gps_km REAL NOT NULL DEFAULT 0,
        odometer_start REAL,
        odometer_end REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS track_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shift_id INTEGER NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        recorded_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _seedVehicleSettings(Database db) async {
    Future<void> put(String key, String value) async {
      await db.insert(
        'settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await put('gas_price_liter', '6.0');
    await put('km_per_liter', '30.0');
    await put('odometer_km', '0');
    await put('last_oil_change_km', '0');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _opening = null;
  }
}
