import 'package:sqflite/sqflite.dart';
import 'package:rota_pizza/models/pizzeria.dart';

abstract class PizzeriaRepository {
  Future<Pizzeria> get();
  Future<void> save(Pizzeria pizzeria);
}

class SqlitePizzeriaRepository implements PizzeriaRepository {
  SqlitePizzeriaRepository(this._db);

  final Database _db;

  @override
  Future<Pizzeria> get() async {
    final rows = await _db.query('pizzeria', where: 'id = ?', whereArgs: [1]);
    if (rows.isEmpty) {
      return Pizzeria();
    }
    return Pizzeria.fromMap(rows.first);
  }

  @override
  Future<void> save(Pizzeria pizzeria) async {
    await _db.insert(
      'pizzeria',
      pizzeria.copyWith(id: 1).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

class MemoryPizzeriaRepository implements PizzeriaRepository {
  MemoryPizzeriaRepository([Pizzeria? seed]) : _pizzeria = seed ?? Pizzeria();

  Pizzeria _pizzeria;

  @override
  Future<Pizzeria> get() async => _pizzeria;

  @override
  Future<void> save(Pizzeria pizzeria) async {
    _pizzeria = pizzeria;
  }
}
