import 'package:flutter_test/flutter_test.dart';
import 'package:rota_max/data/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;

  setUp(() async {
    db = await AppDatabase.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
  });

  tearDown(() => db.close());

  Future<int> insertDelivery({String status = 'PENDING'}) {
    final now = DateTime.now().toIso8601String();
    return db.insert('deliveries', {
      'customer_name': 'Ana',
      'address': 'Rua A',
      'city': 'Santo André',
      'status': status,
      'created_at': now,
      'updated_at': now,
    });
  }

  test('banco novo fica na versão atual com todas as tabelas', () async {
    expect(await db.getVersion(), AppDatabase.version);
    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    )).map((row) => row['name']).toSet();
    expect(
      tables,
      containsAll([
        'base_location',
        'deliveries',
        'routes',
        'route_stops',
        'delivery_events',
        'geocode_cache',
        'settings',
        'shifts',
        'track_points',
      ]),
    );
  });

  test('cria ponto de saída e configurações padrão', () async {
    final base = await db.query('base_location');
    expect(base, hasLength(1));
    final settings = await db.query('settings');
    expect(settings.map((row) => row['key']), contains('km_per_liter'));
  });

  test('chaves estrangeiras estão ligadas', () async {
    final row = await db.rawQuery('PRAGMA foreign_keys');
    expect(row.first.values.first, 1);
    expect(
      () => db.insert('route_stops', {
        'route_id': 999,
        'delivery_id': 999,
        'position': 1,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('status fora da lista é recusado pelo banco', () async {
    expect(
      () => insertDelivery(status: 'done'),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('apagar entrega apaga eventos e paradas junto', () async {
    final id = await insertDelivery();
    final routeId = await db.insert('routes', {
      'created_at': DateTime.now().toIso8601String(),
    });
    await db.insert('route_stops', {
      'route_id': routeId,
      'delivery_id': id,
      'position': 1,
    });
    await db.insert('delivery_events', {
      'delivery_id': id,
      'to_status': 'PENDING',
      'created_at': DateTime.now().toIso8601String(),
    });

    await db.delete('deliveries', where: 'id = ?', whereArgs: [id]);

    expect(await db.query('route_stops'), isEmpty);
    expect(await db.query('delivery_events'), isEmpty);
  });

  test('banco novo já tem um veículo ativo', () async {
    final active = await db.query('vehicles', where: 'is_active = 1');
    expect(active, hasLength(1));
    expect(active.single['type'], 'motorcycle');
  });

  test('só um veículo pode ficar ativo', () async {
    expect(
      () => db.insert('vehicles', {
        'name': 'Van',
        'type': 'van',
        'km_per_liter': 8.0,
        'fuel_price': 6.0,
        'avg_speed_kmh': 20.0,
        'oil_interval_km': 10000.0,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('tipo de veículo fora da lista é recusado', () async {
    expect(
      () => db.insert('vehicles', {
        'name': 'Bike',
        'type': 'bicycle',
        'km_per_liter': 0.0,
        'fuel_price': 0.0,
        'avg_speed_kmh': 15.0,
        'oil_interval_km': 0.0,
        'created_at': DateTime.now().toIso8601String(),
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('wipe apaga tudo e recria os padrões', () async {
    await insertDelivery();
    await AppDatabase.wipe(db);
    expect(await db.query('deliveries'), isEmpty);
    expect(await db.query('base_location'), hasLength(1));
  });
}
