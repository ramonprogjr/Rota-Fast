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
  static const _select = '''
    SELECT d.*, rs.position AS route_order, rs.locked AS stop_locked,
      rs.fixed_position AS stop_fixed_position
    FROM deliveries d
    LEFT JOIN route_stops rs
      ON rs.delivery_id = d.id AND rs.route_id = $_activeRouteId
  ''';

  @override
  Future<List<Delivery>> getAll() async {
    final rows = await _db.rawQuery('''
      $_select
      WHERE d.deleted_at IS NULL
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
    final rows = await db.rawQuery(
      '$_select WHERE d.id = ? AND d.deleted_at IS NULL',
      [id],
    );
    return rows.isEmpty ? null : Delivery.fromMap(rows.first);
  }

  @override
  Future<Delivery> insert(Delivery delivery) async {
    final now = DateTime.now();
    final fresh = delivery.copyWith(
      status: DeliveryStatus.pending,
      createdAt: delivery.createdAt,
      updatedAt: now,
      clearRouteOrder: true,
    );
    return _db.transaction((txn) async {
      final id = await txn.insert('deliveries', fresh.toMap()..remove('id'));
      await _event(
        txn,
        DeliveryEvent(
          deliveryId: id,
          to: DeliveryStatus.pending,
          createdAt: now,
        ),
      );
      return fresh.copyWith(id: id);
    });
  }

  Future<void> _event(DatabaseExecutor db, DeliveryEvent event) =>
      db.insert('delivery_events', event.toMap()..remove('id'));

  @override
  Future<void> update(Delivery delivery) async {
    if (delivery.id == null) {
      return;
    }
    await _db.transaction((txn) async {
      final current = await _getById(txn, delivery.id!);
      if (current == null) {
        return;
      }
      final changed = changedEditableFields(current, delivery);
      if (changed.isEmpty) {
        return;
      }
      final now = DateTime.now();
      final map = delivery.toEditableMap()
        ..['updated_at'] = now.toIso8601String();
      await txn.update(
        'deliveries',
        map,
        where: 'id = ?',
        whereArgs: [delivery.id],
      );
      await _event(
        txn,
        DeliveryEvent.edit(
          deliveryId: delivery.id!,
          status: current.status,
          changedFields: changed,
          createdAt: now,
        ),
      );
    });
  }

  @override
  Future<void> delete(int id) async {
    await _db.transaction((txn) async {
      final current = await _getById(txn, id);
      if (current == null) {
        return;
      }
      final now = DateTime.now();
      await txn.update(
        'deliveries',
        {
          'deleted_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.rawDelete(
        'DELETE FROM route_stops WHERE delivery_id = ? AND route_id = $_activeRouteId',
        [id],
      );
      await _event(
        txn,
        DeliveryEvent.edit(
          deliveryId: id,
          status: current.status,
          changedFields: const ['deleted_at'],
          note: 'Excluída',
          createdAt: now,
        ),
      );
    });
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
        throw StateError('Essa entrega não existe mais.');
      }
      final now = DateTime.now();

      if (to == DeliveryStatus.inProgress) {
        final others = await txn.query(
          'deliveries',
          columns: ['id'],
          where: "status = 'IN_PROGRESS' AND id != ? AND deleted_at IS NULL",
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
    await _event(
      txn,
      DeliveryEvent(
        deliveryId: current.id!,
        from: current.status,
        to: to,
        reason: reason,
        note: note,
        latitude: latitude,
        longitude: longitude,
        createdAt: now,
      ),
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

  /// Rota ativa que ainda tem trabalho. Se a ativa já terminou (tinha
  /// paradas e nenhuma aberta), ela é concluída e nasce outra.
  Future<DeliveryRoute> _ensureRoute(Transaction txn, DateTime now) async {
    final route = await _activeRoute(txn);
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
              AND d.deleted_at IS NULL
          ''', [route.id])) ??
          0;
      if (stops == 0 || openStops > 0) {
        return route;
      }
      await _complete(txn, route.id!, now);
    }
    final fresh = DeliveryRoute(createdAt: now);
    final id = await txn.insert('routes', fresh.toMap()..remove('id'));
    return fresh.copyWith(id: id);
  }

  /// Regrava as posições das paradas abertas da rota [routeId] na ordem
  /// [ids] (só as abertas contam). Abertas que já estavam na rota e não
  /// vieram em [ids] vão para o fim, na ordem antiga. Trava e posição fixa
  /// são preservadas.
  Future<void> _writeOrder(Transaction txn, int routeId, List<int> ids) async {
    final rows = await txn.rawQuery('''
      SELECT rs.delivery_id, rs.position, rs.locked, rs.fixed_position,
        CASE WHEN d.status IN $_openCodes AND d.deleted_at IS NULL
          THEN 1 ELSE 0 END AS is_open
      FROM route_stops rs
      JOIN deliveries d ON d.id = rs.delivery_id
      WHERE rs.route_id = ?
      ORDER BY rs.position ASC
    ''', [routeId]);
    final flags = <int, (int, int?)>{};
    final previousOpen = <int>[];
    var base = 0;
    for (final row in rows) {
      final id = row['delivery_id'] as int;
      if (row['is_open'] == 1) {
        flags[id] = (row['locked'] as int, row['fixed_position'] as int?);
        previousOpen.add(id);
      } else {
        final position = row['position'] as int;
        if (position > base) {
          base = position;
        }
      }
    }
    final openNow = (await txn.rawQuery(
      "SELECT id FROM deliveries WHERE status IN $_openCodes AND deleted_at IS NULL",
    ))
        .map((row) => row['id'] as int)
        .toSet();

    final order = <int>[];
    final seen = <int>{};
    for (final id in [...ids, ...previousOpen]) {
      if (openNow.contains(id) && seen.add(id)) {
        order.add(id);
      }
    }

    await txn.rawDelete('''
      DELETE FROM route_stops
      WHERE route_id = ? AND delivery_id IN (
        SELECT id FROM deliveries
        WHERE status IN $_openCodes AND deleted_at IS NULL
      )
    ''', [routeId]);
    var position = base;
    for (final id in order) {
      position++;
      final flag = flags[id];
      await txn.insert('route_stops', {
        'route_id': routeId,
        'delivery_id': id,
        'position': position,
        'locked': flag?.$1 ?? 0,
        'fixed_position': flag?.$2,
      });
    }
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
      final route = await _ensureRoute(txn, DateTime.now());
      await _writeOrder(
        txn,
        route.id!,
        [
          for (final item in orderedOpen)
            if (item.id != null) item.id!,
        ],
      );
      final updated = route.copyWith(
        originLat: originLat,
        originLng: originLng,
        estimatedKm: estimatedKm,
        estimatedMinutes: estimatedMinutes,
        manuallyEdited: false,
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

  @override
  Future<DeliveryRoute> reorder(List<int> openIdsInOrder) {
    return _db.transaction((txn) async {
      final open = (await txn.rawQuery(
        "SELECT id FROM deliveries WHERE status IN $_openCodes AND deleted_at IS NULL",
      ))
          .map((row) => row['id'] as int)
          .toSet();
      validateReorder(openIdsInOrder, open);
      final route = await _ensureRoute(txn, DateTime.now());
      await _writeOrder(txn, route.id!, openIdsInOrder);
      await txn.update(
        'routes',
        {'manually_edited': 1},
        where: 'id = ?',
        whereArgs: [route.id],
      );
      return route.copyWith(manuallyEdited: true);
    });
  }

  /// Garante que a entrega aberta tem parada na rota ativa e devolve o id
  /// da rota. Se faltar, entram no fim todas as abertas fora da rota.
  Future<int> _ensureStop(Transaction txn, int deliveryId) async {
    final delivery = await _getById(txn, deliveryId);
    if (delivery == null) {
      throw StateError('Essa entrega não existe mais.');
    }
    if (!delivery.isOpen) {
      throw ArgumentError('Só dá para travar paradas que ainda estão na rota.');
    }
    final route = await _ensureRoute(txn, DateTime.now());
    final exists = await txn.query(
      'route_stops',
      where: 'route_id = ? AND delivery_id = ?',
      whereArgs: [route.id, deliveryId],
    );
    if (exists.isEmpty) {
      // Entra junto com as outras abertas que ainda não estão na rota, na
      // ordem em que aparecem na tela (cadastro), para nada pular de lugar.
      var max = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COALESCE(MAX(position), 0) FROM route_stops WHERE route_id = ?',
            [route.id],
          )) ??
          0;
      final missing = await txn.rawQuery('''
        SELECT id FROM deliveries
        WHERE status IN $_openCodes AND deleted_at IS NULL
          AND id NOT IN (SELECT delivery_id FROM route_stops WHERE route_id = ?)
        ORDER BY created_at ASC, id ASC
      ''', [route.id]);
      for (final row in missing) {
        await txn.insert('route_stops', {
          'route_id': route.id,
          'delivery_id': row['id'],
          'position': ++max,
        });
      }
    }
    return route.id!;
  }

  @override
  Future<void> setLock(int deliveryId, bool locked) {
    return _db.transaction((txn) async {
      final routeId = await _ensureStop(txn, deliveryId);
      await txn.update(
        'route_stops',
        {'locked': locked ? 1 : 0},
        where: 'route_id = ? AND delivery_id = ?',
        whereArgs: [routeId, deliveryId],
      );
    });
  }

  @override
  Future<void> setFixedPosition(int deliveryId, int? position) async {
    if (position != null && position < 0) {
      throw ArgumentError('Posição inválida.');
    }
    await _db.transaction((txn) async {
      final routeId = await _ensureStop(txn, deliveryId);
      await txn.update(
        'route_stops',
        {'fixed_position': position},
        where: 'route_id = ? AND delivery_id = ?',
        whereArgs: [routeId, deliveryId],
      );
    });
  }

  @override
  Future<void> setEndPoint(double? latitude, double? longitude) {
    return _db.transaction((txn) async {
      final route = await _ensureRoute(txn, DateTime.now());
      await txn.update(
        'routes',
        {
          'end_lat': latitude == null || longitude == null ? null : latitude,
          'end_lng': latitude == null || longitude == null ? null : longitude,
        },
        where: 'id = ?',
        whereArgs: [route.id],
      );
    });
  }

  @override
  Future<List<RouteSummary>> listRoutes() async {
    final rows = await _db.rawQuery('''
      SELECT r.*,
        (SELECT COUNT(*) FROM route_stops rs
          JOIN deliveries d ON d.id = rs.delivery_id
          WHERE rs.route_id = r.id AND d.deleted_at IS NULL) AS stops_count,
        (SELECT COUNT(*) FROM route_stops rs
          JOIN deliveries d ON d.id = rs.delivery_id
          WHERE rs.route_id = r.id AND d.deleted_at IS NULL
            AND d.status = 'DELIVERED') AS delivered_count,
        (SELECT COUNT(*) FROM route_stops rs
          JOIN deliveries d ON d.id = rs.delivery_id
          WHERE rs.route_id = r.id AND d.deleted_at IS NULL
            AND d.status = 'FAILED') AS failed_count
      FROM routes r
      ORDER BY r.created_at DESC, r.id DESC
    ''');
    final plans = <int, List<RoutePlan>>{};
    for (final row in await _db.query('route_plans')) {
      final plan = RoutePlan.fromMap(row);
      plans.putIfAbsent(plan.routeId, () => []).add(plan);
    }
    return [
      for (final row in rows)
        RouteSummary(
          route: DeliveryRoute.fromMap(row),
          stops: row['stops_count'] as int,
          delivered: row['delivered_count'] as int,
          failed: row['failed_count'] as int,
          bestPlan: RoutePlan.best(plans[row['id']] ?? const []),
        ),
    ];
  }

  @override
  Future<List<Delivery>> stopsOf(int routeId) async {
    final rows = await _db.rawQuery('''
      SELECT d.*, rs.position AS route_order, rs.locked AS stop_locked,
        rs.fixed_position AS stop_fixed_position
      FROM route_stops rs
      JOIN deliveries d ON d.id = rs.delivery_id
      WHERE rs.route_id = ? AND d.deleted_at IS NULL
      ORDER BY rs.position ASC
    ''', [routeId]);
    return rows.map(Delivery.fromMap).toList();
  }

  @override
  Future<DeliveryRoute> openRoute(int id) {
    return _db.transaction((txn) async {
      final rows = await txn.query('routes', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) {
        throw StateError('Essa rota não existe mais.');
      }
      final now = DateTime.now();
      final current = await _activeRoute(txn);
      if (current != null && current.id != id) {
        await _complete(txn, current.id!, now);
      }
      await txn.update(
        'routes',
        {'status': 'active', 'completed_at': null},
        where: 'id = ?',
        whereArgs: [id],
      );
      return DeliveryRoute.fromMap(rows.first).copyWith(
        status: RouteStatus.active,
        clearCompletedAt: true,
      );
    });
  }

  @override
  Future<void> deleteRoute(int id) async {
    // route_stops e route_plans saem junto (ON DELETE CASCADE). As entregas
    // ficam: as abertas só deixam de ter posição.
    await _db.delete('routes', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<RoutePlan> savePlan({
    required int routeId,
    required int stops,
    required double baselineKm,
    required int baselineMinutes,
    required double optimizedKm,
    required int optimizedMinutes,
  }) async {
    final plan = RoutePlan(
      routeId: routeId,
      createdAt: DateTime.now(),
      stops: stops,
      baselineKm: baselineKm,
      baselineMinutes: baselineMinutes,
      optimizedKm: optimizedKm,
      optimizedMinutes: optimizedMinutes,
    );
    final id = await _db.insert('route_plans', plan.toMap()..remove('id'));
    return plan.copyWith(id: id);
  }

  @override
  Future<List<RoutePlan>> plansFor(int routeId) async {
    final rows = await _db.query(
      'route_plans',
      where: 'route_id = ?',
      whereArgs: [routeId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(RoutePlan.fromMap).toList();
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
