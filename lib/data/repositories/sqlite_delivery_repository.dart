import 'package:sqflite/sqflite.dart';
import 'package:rota_pizza/data/repositories/delivery_repository.dart';
import 'package:rota_pizza/models/delivery.dart';

class SqliteDeliveryRepository implements DeliveryRepository {
  SqliteDeliveryRepository(this._db);

  final Database _db;

  @override
  Future<List<Delivery>> getAll() async {
    final rows = await _db.query(
      'deliveries',
      orderBy: '''
        CASE status WHEN 'pending' THEN 0 ELSE 1 END,
        route_order IS NULL,
        route_order ASC,
        created_at ASC
      ''',
    );
    return rows.map(Delivery.fromMap).toList();
  }

  @override
  Future<Delivery> insert(Delivery delivery) async {
    final id = await _db.insert('deliveries', delivery.toMap()..remove('id'));
    return delivery.copyWith(id: id);
  }

  @override
  Future<void> update(Delivery delivery) async {
    await _db.update(
      'deliveries',
      delivery.toMap(),
      where: 'id = ?',
      whereArgs: [delivery.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete('deliveries', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> replaceRouteOrder(List<Delivery> orderedPending) async {
    await _db.transaction((txn) async {
      await txn.rawUpdate(
        "UPDATE deliveries SET route_order = NULL WHERE status = 'pending'",
      );
      for (var i = 0; i < orderedPending.length; i++) {
        final item = orderedPending[i];
        if (item.id == null) {
          continue;
        }
        await txn.update(
          'deliveries',
          {'route_order': i + 1},
          where: 'id = ?',
          whereArgs: [item.id],
        );
      }
    });
  }
}
