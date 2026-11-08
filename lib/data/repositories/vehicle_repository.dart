import 'package:sqflite/sqflite.dart';
import 'package:rota_max/models/vehicle.dart';

abstract class VehicleRepository {
  Future<List<Vehicle>> getAll();

  /// Veículo ativo. Se nenhum estiver marcado, ativa o primeiro.
  Future<Vehicle?> active();

  /// Insere ou atualiza os dados (não muda qual é o ativo).
  Future<Vehicle> save(Vehicle vehicle);

  /// Torna [id] o único ativo.
  Future<void> activate(int id);

  /// Apaga o veículo. Se era o ativo, outro passa a ser.
  Future<void> delete(int id);

  /// Soma km rodados ao odômetro (fim do turno).
  Future<void> addKm(int id, double km);

  /// Registra a troca de óleo no odômetro informado e zera a contagem.
  Future<void> registerOilChange(int id, double odometerKm, {String? note});

  Future<List<OilChange>> oilChanges(int vehicleId);
}

class SqliteVehicleRepository implements VehicleRepository {
  SqliteVehicleRepository(this._db);

  final Database _db;

  @override
  Future<List<Vehicle>> getAll() async {
    final rows =
        await _db.query('vehicles', orderBy: 'is_active DESC, created_at ASC');
    return rows.map(Vehicle.fromMap).toList();
  }

  @override
  Future<Vehicle?> active() async {
    final rows = await _db.query('vehicles', where: 'is_active = 1', limit: 1);
    if (rows.isNotEmpty) {
      return Vehicle.fromMap(rows.first);
    }
    final any = await _db.query('vehicles', orderBy: 'id ASC', limit: 1);
    if (any.isEmpty) {
      return null;
    }
    final first = Vehicle.fromMap(any.first);
    await activate(first.id!);
    return first.copyWith(isActive: true);
  }

  @override
  Future<Vehicle> save(Vehicle vehicle) async {
    final map = vehicle.toMap()..remove('id')..remove('is_active');
    if (vehicle.id == null) {
      final count = Sqflite.firstIntValue(
            await _db.rawQuery('SELECT COUNT(*) FROM vehicles'),
          ) ??
          0;
      map['is_active'] = count == 0 ? 1 : 0;
      final id = await _db.insert('vehicles', map);
      return vehicle.copyWith(id: id, isActive: count == 0);
    }
    await _db.update(
      'vehicles',
      map,
      where: 'id = ?',
      whereArgs: [vehicle.id],
    );
    return vehicle;
  }

  @override
  Future<void> activate(int id) async {
    await _db.transaction((txn) async {
      await txn.update('vehicles', {'is_active': 0}, where: 'is_active = 1');
      await txn.update(
        'vehicles',
        {'is_active': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  @override
  Future<void> delete(int id) async {
    await _db.transaction((txn) async {
      await txn.delete('vehicles', where: 'id = ?', whereArgs: [id]);
      final active = await txn.query('vehicles', where: 'is_active = 1');
      if (active.isEmpty) {
        await txn.rawUpdate(
          'UPDATE vehicles SET is_active = 1 '
          'WHERE id = (SELECT MIN(id) FROM vehicles)',
        );
      }
    });
  }

  @override
  Future<void> addKm(int id, double km) async {
    if (km <= 0) {
      return;
    }
    await _db.rawUpdate(
      'UPDATE vehicles SET odometer_km = odometer_km + ? WHERE id = ?',
      [km, id],
    );
  }

  @override
  Future<void> registerOilChange(
    int id,
    double odometerKm, {
    String? note,
  }) async {
    await _db.transaction((txn) async {
      await txn.insert(
        'oil_changes',
        OilChange(
          vehicleId: id,
          odometerKm: odometerKm,
          changedAt: DateTime.now(),
          note: note,
        ).toMap()
          ..remove('id'),
      );
      await txn.rawUpdate(
        'UPDATE vehicles SET last_oil_change_km = ?, '
        'odometer_km = MAX(odometer_km, ?) WHERE id = ?',
        [odometerKm, odometerKm, id],
      );
    });
  }

  @override
  Future<List<OilChange>> oilChanges(int vehicleId) async {
    final rows = await _db.query(
      'oil_changes',
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: 'changed_at DESC',
    );
    return rows.map(OilChange.fromMap).toList();
  }
}

/// Implementação em memória com as mesmas regras. Usada nos testes.
class MemoryVehicleRepository implements VehicleRepository {
  MemoryVehicleRepository([List<Vehicle>? seed]) {
    for (final item in seed ?? [Vehicle.fallback()]) {
      _items.add(item.copyWith(id: item.id ?? _nextId++));
    }
    if (_items.isNotEmpty && !_items.any((v) => v.isActive)) {
      _items[0] = _items[0].copyWith(isActive: true);
    }
  }

  final List<Vehicle> _items = [];
  final List<OilChange> _oil = [];
  int _nextId = 1;

  int _index(int id) => _items.indexWhere((item) => item.id == id);

  @override
  Future<List<Vehicle>> getAll() async => [..._items]
    ..sort((a, b) => a.isActive == b.isActive ? 0 : (a.isActive ? -1 : 1));

  @override
  Future<Vehicle?> active() async {
    for (final item in _items) {
      if (item.isActive) {
        return item;
      }
    }
    if (_items.isEmpty) {
      return null;
    }
    await activate(_items.first.id!);
    return _items.first;
  }

  @override
  Future<Vehicle> save(Vehicle vehicle) async {
    if (vehicle.id == null) {
      final saved = vehicle.copyWith(id: _nextId++, isActive: _items.isEmpty);
      _items.add(saved);
      return saved;
    }
    final index = _index(vehicle.id!);
    final kept = vehicle.copyWith(isActive: _items[index].isActive);
    _items[index] = kept;
    return kept;
  }

  @override
  Future<void> activate(int id) async {
    for (var i = 0; i < _items.length; i++) {
      _items[i] = _items[i].copyWith(isActive: _items[i].id == id);
    }
  }

  @override
  Future<void> delete(int id) async {
    _items.removeWhere((item) => item.id == id);
    _oil.removeWhere((item) => item.vehicleId == id);
    if (_items.isNotEmpty && !_items.any((v) => v.isActive)) {
      _items[0] = _items[0].copyWith(isActive: true);
    }
  }

  @override
  Future<void> addKm(int id, double km) async {
    if (km <= 0) {
      return;
    }
    final index = _index(id);
    if (index >= 0) {
      final item = _items[index];
      _items[index] = item.copyWith(odometerKm: item.odometerKm + km);
    }
  }

  @override
  Future<void> registerOilChange(
    int id,
    double odometerKm, {
    String? note,
  }) async {
    final index = _index(id);
    if (index < 0) {
      return;
    }
    _oil.add(
      OilChange(
        vehicleId: id,
        odometerKm: odometerKm,
        changedAt: DateTime.now(),
        note: note,
      ),
    );
    final item = _items[index];
    _items[index] = item.copyWith(
      lastOilChangeKm: odometerKm,
      odometerKm: odometerKm > item.odometerKm ? odometerKm : item.odometerKm,
    );
  }

  @override
  Future<List<OilChange>> oilChanges(int vehicleId) async =>
      _oil.where((item) => item.vehicleId == vehicleId).toList().reversed.toList();
}
