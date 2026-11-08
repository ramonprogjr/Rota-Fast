import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:rota_max/core/constants/app_constants.dart';

typedef Migration = Future<void> Function(Transaction txn);

/// Banco local do Rota Max. Regras em docs/DATABASE.md:
/// toda mudança de estrutura é uma migration nova no fim de [migrations];
/// nunca editar uma migration já publicada.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const fileName = 'rota_max.db';

  /// Lista ordenada. A versão do banco é o tamanho da lista.
  static final List<Migration> migrations = [_v1];

  static int get version => migrations.length;

  Database? _db;
  Future<Database>? _opening;

  Future<Database> get database {
    if (_db != null) {
      return Future.value(_db);
    }
    _opening ??= _openDefault();
    return _opening!;
  }

  Future<Database> _openDefault() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final db = await open(p.join(dir.path, fileName));
      _db = db;
      return db;
    } catch (_) {
      // Deixa o "Tentar de novo" abrir do zero.
      _opening = null;
      rethrow;
    }
  }

  /// Abre (ou cria) o banco em [path]. [factory] permite usar o sqflite_ffi
  /// nos testes.
  static Future<Database> open(String path, {DatabaseFactory? factory}) {
    final options = OpenDatabaseOptions(
      version: version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) => _migrate(db, 0, version),
      onUpgrade: _migrate,
    );
    return (factory ?? databaseFactory).openDatabase(path, options: options);
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    for (var v = from + 1; v <= to; v++) {
      await db.transaction((txn) => migrations[v - 1](txn));
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _opening = null;
  }

  /// Apaga entregas, rotas, turnos, cache e configurações e recria os
  /// valores padrão. O banco continua aberto.
  static Future<void> wipe(Database db) async {
    await db.transaction((txn) async {
      for (final table in [
        'delivery_events',
        'route_stops',
        'route_plans',
        'routes',
        'oil_changes',
        'vehicles',
        'deliveries',
        'track_points',
        'shifts',
        'geocode_cache',
        'settings',
        'base_location',
        'error_log',
      ]) {
        await txn.delete(table);
      }
      await _seedDefaults(txn);
    });
  }

  static Future<void> _v1(Transaction txn) async {
    await txn.execute('''
      CREATE TABLE base_location (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        address TEXT NOT NULL,
        city TEXT NOT NULL,
        latitude REAL,
        longitude REAL
      )
    ''');
    await txn.execute('''
      CREATE TABLE deliveries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_number TEXT,
        package_id TEXT,
        customer_name TEXT NOT NULL,
        phone TEXT,
        address TEXT NOT NULL,
        number TEXT,
        complement TEXT,
        neighborhood TEXT,
        postal_code TEXT,
        city TEXT NOT NULL,
        state TEXT,
        latitude REAL,
        longitude REAL,
        location_confirmed INTEGER NOT NULL DEFAULT 0,
        value REAL,
        notes TEXT,
        priority TEXT NOT NULL DEFAULT 'normal',
        status TEXT NOT NULL DEFAULT 'PENDING'
          CHECK (status IN ('PENDING','IN_PROGRESS','DELIVERED','FAILED','SKIPPED')),
        failure_reason TEXT,
        attempts INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        delivered_at TEXT,
        deleted_at TEXT
      )
    ''');
    await txn.execute('''
      CREATE TABLE routes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        status TEXT NOT NULL DEFAULT 'active'
          CHECK (status IN ('draft','active','completed')),
        origin_lat REAL,
        origin_lng REAL,
        end_lat REAL,
        end_lng REAL,
        manually_edited INTEGER NOT NULL DEFAULT 0,
        estimated_km REAL,
        estimated_minutes INTEGER,
        nav_app TEXT,
        created_at TEXT NOT NULL,
        started_at TEXT,
        completed_at TEXT
      )
    ''');
    await txn.execute('''
      CREATE TABLE route_stops (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        route_id INTEGER NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
        delivery_id INTEGER NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        locked INTEGER NOT NULL DEFAULT 0,
        fixed_position INTEGER,
        UNIQUE (route_id, delivery_id)
      )
    ''');
    await txn.execute('''
      CREATE TABLE delivery_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        delivery_id INTEGER NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
        kind TEXT NOT NULL DEFAULT 'status'
          CHECK (kind IN ('status','edit')),
        from_status TEXT,
        to_status TEXT NOT NULL,
        reason TEXT,
        note TEXT,
        latitude REAL,
        longitude REAL,
        changed_fields TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await txn.execute('''
      CREATE TABLE geocode_cache (
        query TEXT PRIMARY KEY,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        display_name TEXT,
        cached_at TEXT NOT NULL
      )
    ''');
    await txn.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await txn.execute('''
      CREATE TABLE route_plans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        route_id INTEGER NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
        created_at TEXT NOT NULL,
        stops INTEGER NOT NULL,
        baseline_km REAL NOT NULL,
        baseline_minutes INTEGER NOT NULL,
        optimized_km REAL NOT NULL,
        optimized_minutes INTEGER NOT NULL
      )
    ''');
    await txn.execute('''
      CREATE TABLE vehicles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL
          CHECK (type IN ('motorcycle','car','utility','van','truck')),
        plate TEXT,
        fuel_type TEXT NOT NULL DEFAULT 'gasoline'
          CHECK (fuel_type IN ('gasoline','ethanol','flex','diesel')),
        km_per_liter REAL NOT NULL,
        fuel_price REAL NOT NULL,
        avg_speed_kmh REAL NOT NULL,
        odometer_km REAL NOT NULL DEFAULT 0,
        oil_interval_km REAL NOT NULL,
        last_oil_change_km REAL NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await txn.execute('''
      CREATE TABLE oil_changes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        vehicle_id INTEGER NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
        odometer_km REAL NOT NULL,
        changed_at TEXT NOT NULL,
        note TEXT
      )
    ''');
    await txn.execute('''
      CREATE TABLE shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        vehicle_id INTEGER REFERENCES vehicles(id) ON DELETE SET NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        gps_km REAL NOT NULL DEFAULT 0,
        odometer_start REAL,
        odometer_end REAL
      )
    ''');
    await txn.execute('''
      CREATE TABLE track_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shift_id INTEGER NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        recorded_at TEXT NOT NULL
      )
    ''');
    // Últimos erros do app (sem dados pessoais), para o relatório de erros.
    await txn.execute('''
      CREATE TABLE error_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source TEXT NOT NULL,
        error_type TEXT NOT NULL,
        location TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await txn.execute(
      'CREATE INDEX idx_deliveries_status ON deliveries(status, created_at)',
    );
    await txn.execute(
      'CREATE INDEX idx_route_stops_route ON route_stops(route_id, position)',
    );
    await txn.execute(
      'CREATE INDEX idx_route_stops_delivery ON route_stops(delivery_id)',
    );
    await txn.execute(
      'CREATE INDEX idx_events_delivery ON delivery_events(delivery_id, created_at)',
    );
    await txn.execute(
      'CREATE INDEX idx_track_points_shift ON track_points(shift_id)',
    );
    await txn.execute('CREATE INDEX idx_routes_status ON routes(status)');
    await txn.execute(
      'CREATE INDEX idx_route_plans_route ON route_plans(route_id)',
    );
    await txn.execute(
      'CREATE INDEX idx_oil_changes_vehicle ON oil_changes(vehicle_id, changed_at)',
    );
    // Só um veículo ativo por vez.
    await txn.execute(
      'CREATE UNIQUE INDEX idx_vehicles_one_active ON vehicles(is_active) WHERE is_active = 1',
    );
    await _seedDefaults(txn);
  }

  static Future<void> _seedDefaults(DatabaseExecutor db) async {
    await db.insert(
      'base_location',
      {
        'id': 1,
        'name': AppConstants.defaultBaseName,
        'address': '',
        'city': AppConstants.defaultCity,
        'latitude': null,
        'longitude': null,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.insert(
      'settings',
      {'key': 'nav_app', 'value': 'google'},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    final vehicles = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM vehicles'),
        ) ??
        0;
    if (vehicles == 0) {
      await db.insert('vehicles', {
        'name': 'Minha moto',
        'type': 'motorcycle',
        'fuel_type': 'gasoline',
        'km_per_liter': 35.0,
        'fuel_price': 6.0,
        'avg_speed_kmh': 28.0,
        'odometer_km': 0.0,
        'oil_interval_km': 1000.0,
        'last_oil_change_km': 0.0,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }
}
