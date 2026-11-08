import 'package:sqflite/sqflite.dart';
import 'package:rota_max/data/repositories/delivery_repository.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/delivery_event.dart';
import 'package:rota_max/models/delivery_route.dart';

class SqliteDeliveryRepository implements DeliveryRepository {
  SqliteDeliveryRepository(this._db);

  final Database _db;

  static const _openCodes = "('PENDING','IN_PROGRESS','SKIPPED')";
  static const _activeRouteId =
      "(SELECT id FROM routes WHERE status = 'active' ORDER BY id DESC LIMIT 1)";

  @override
  Future<List<Delivery>> getAll() async {
    final rows = await _db.rawQuery('''
      SELECT d.*, rs.position AS route_order
      FROM deliveries d
      LEFT JOIN route_stops rs
        ON rs.delivery_id = d.id AND rs.route_id = $_activeRouteId
      ORDER BY
        CASE WHEN d.status IN $_openCodes THEN 0 ELSE 1 END,
        rs.position IS NULL,
        rs.position ASC,
        d.created_at ASC
    ''');
    return rows.map(Delivery.fromMap).toList();
  }

  @override
  Future<Delivery?> getById(int id) => _getById(_db, id);

  Future<Delivery?> _getById(DatabaseExecutor db, int id) async {
    final rows = await db.rawQuery('''
      SELECT d.*, rs.position AS route_order
      FROM deliveries d
      LEFT JOIN route_stops rs
        ON rs.delivery_id = d.id AND rs.route_id = $_activeRouteId
      WHERE d.id = ?
    ''', [id]);
    return rows.isEmpty ? null : Delivery.fromMap(rows.first);
  }

  @override
  Future<Delivery> insert(Delivery delivery) async {
    final now = DateTime.now();
    final fresh = delivery.copyWith(
      status: DeliveryStatus.pending,
      createdAt: delivery.createdAt,
      updatedAt: now,
    );
    return _db.transaction((txn) async {
      final id = await txn.insert('deliveries', fresh.toMap()..remove('id'));
      await txn.insert(
        'delivery_events',
        DeliveryEvent(
          deliveryId: id,
          to: DeliveryStatus.pending,
          createdAt: now,
        ).toMap()
          ..remove('id'),
      );
      return fresh.copyWith(id: id);
    });
  }

  @override
  Future<void> update(Delivery delivery) async {
    final map = delivery.toEditableMap()
      ..['updated_at'] = DateTime.now().toIso8601String();
    await _db.update(
      'deliveries',
      map,
      where: 'id = ?',
      whereArgs: [delivery.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete('deliveries', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<Delivery> transition(
    int id,
    DeliveryStatus to, {
    FailureReason? reason,
    String? note,
    double? latitude,
    double? longitude,
  }) {
    return _db.transaction((txn) async {
      final current = await _getById(txn, id);
      if (current == null) {
        throw StateError('Entrega $id não existe.');
      }
      final now = DateTime.now();

      if (to == DeliveryStatus.inProgress) {
        final others = await txn.query(
          'deliveries',
          columns: ['id'],
          where: "status = 'IN_PROGRESS' AND id != ?",
          whereArgs: [id],
        );
        for (final row in others) {
          await _write(
            txn,
            (await _getById(txn, row['id'] as int))!,
            DeliveryStatus.pending,
            now: now,
          );
        }
      }

      final next = await _write(
        txn,
        current,
        to,
        reason: reason,
        note: note,
        latitude: latitude,
        longitude: longitude,
        now: now,
      );

      if (to == DeliveryStatus.skipped) {
        await txn.rawUpdate('''
          UPDATE route_stops
          SET position = (
            SELECT COALESCE(MAX(position), 0) + 1 FROM route_stops
            WHERE route_id = $_activeRouteId
          )
          WHERE delivery_id = ? AND route_id = $_activeRouteId
        ''', [id]);
      }
      return (await _getById(txn, id)) ?? next;
    });
  }

  Future<Delivery> _write(
    Transaction txn,
    Delivery current,
    DeliveryStatus to, {
    FailureReason? reason,
    String? note,
    double? latitude,
    double? longitude,
    required DateTime now,
  }) async {
    final next = applyTransition(current, to, reason: reason, now: now);
    await txn.update(
      'deliveries',
      {
        'status': next.status.code,
        'failure_reason': next.failureReason?.code,
        'attempts': next.attempts,
        'delivered_at': next.deliveredAt?.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [current.id],
    );
    await txn.insert(
      'delivery_events',
      DeliveryEvent(
        deliveryId: current.id!,
        from: current.status,
        to: to,
        reason: reason,
        note: note,
        latitude: latitude,
        longitude: longitude,
        createdAt: now,
      ).toMap()
        ..remove('id'),
    );
    return next;
  }

  @override
  Future<List<DeliveryEvent>> eventsFor(int deliveryId) async {
    final rows = await _db.query(
      'delivery_events',
      where: 'delivery_id = ?',
      whereArgs: [deliveryId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(DeliveryEvent.fromMap).toList();
  }

  @override
  Future<DeliveryRoute?> activeRoute() => _activeRoute(_db);

  Future<DeliveryRoute?> _activeRoute(DatabaseExecutor db) async {
    final rows = await db.query(
      'routes',
      where: "status = 'active'",
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : DeliveryRoute.fromMap(rows.first);
  }

  @override
  Future<DeliveryRoute> saveRouteOrder(
    List<Delivery> orderedOpen, {
    double? originLat,
    double? originLng,
    double? estimatedKm,
    int? estimatedMinutes,
  }) {
    return _db.transaction((txn) async {
      final now = DateTime.now();
      var route = await _activeRoute(txn);
      if (route != null) {
        final stops = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM route_stops WHERE route_id = ?',
              [route.id],
            )) ??
            0;
        final openStops = Sqflite.firstIntValue(await txn.rawQuery('''
              SELECT COUNT(*) FROM route_stops rs
              JOIN deliveries d ON d.id = rs.delivery_id
              WHERE rs.route_id = ? AND d.status IN $_openCodes
            ''', [route.id])) ??
            0;
        if (stops > 0 && openStops == 0) {
          await _complete(txn, route.id!, now);
          route = null;
        }
      }
      route ??= await _createRoute(txn, now);

      await txn.rawDelete('''
        DELETE FROM route_stops
        WHERE route_id = ? AND delivery_id IN (
          SELECT id FROM deliveries WHERE status IN $_openCodes
        )
      ''', [route.id]);
      final base = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COALESCE(MAX(position), 0) FROM route_stops WHERE route_id = ?',
            [route.id],
          )) ??
          0;
      var position = base;
      for (final item in orderedOpen) {
        if (item.id == null || !item.isOpen) {
          continue;
        }
        position++;
        await txn.insert('route_stops', {
          'route_id': route.id,
          'delivery_id': item.id,
          'position': position,
        });
      }
      final updated = route.copyWith(
        originLat: originLat,
        originLng: originLng,
        estimatedKm: estimatedKm,
        estimatedMinutes: estimatedMinutes,
      );
      await txn.update(
        'routes',
        updated.toMap()..remove('id'),
        where: 'id = ?',
        whereArgs: [route.id],
      );
      return updated;
    });
  }

  Future<DeliveryRoute> _createRoute(Transaction txn, DateTime now) async {
    final route = DeliveryRoute(createdAt: now);
    final id = await txn.insert('routes', route.toMap()..remove('id'));
    return route.copyWith(id: id);
  }

  Future<void> _complete(Transaction txn, int routeId, DateTime now) {
    return txn.update(
      'routes',
      {'status': 'completed', 'completed_at': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [routeId],
    );
  }

  @override
  Future<void> startActiveRoute() async {
    await _db.rawUpdate(
      "UPDATE routes SET started_at = ? WHERE status = 'active' AND started_at IS NULL",
      [DateTime.now().toIso8601String()],
    );
  }

  @override
  Future<void> completeActiveRoute() async {
    await _db.transaction((txn) async {
      final route = await _activeRoute(txn);
      if (route != null) {
        await _complete(txn, route.id!, DateTime.now());
      }
    });
  }
}
