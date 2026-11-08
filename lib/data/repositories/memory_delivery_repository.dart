import 'package:rota_max/data/repositories/delivery_repository.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/delivery_event.dart';
import 'package:rota_max/models/delivery_route.dart';

class _Stop {
  _Stop(this.position, {this.locked = false, this.fixedPosition});

  int position;
  bool locked;
  int? fixedPosition;
}

/// Implementação em memória com as mesmas regras do SQLite. Usada nos testes.
class MemoryDeliveryRepository implements DeliveryRepository {
  MemoryDeliveryRepository([List<Delivery>? seed]) {
    if (seed != null) {
      for (final item in seed) {
        final id = item.id ?? _nextId;
        _items.add(item.copyWith(id: id, clearRouteOrder: true));
        if (id >= _nextId) {
          _nextId = id + 1;
        }
      }
    }
  }

  /// Inclui as excluídas (ver [_deleted]).
  final List<Delivery> _items = [];
  final Set<int> _deleted = {};
  final List<DeliveryEvent> _events = [];
  final List<DeliveryRoute> _routes = [];
  final List<RoutePlan> _plans = [];

  /// routeId -> (deliveryId -> parada)
  final Map<int, Map<int, _Stop>> _stops = {};
  int _nextId = 1;
  int _nextRouteId = 1;
  int _nextPlanId = 1;

  Iterable<Delivery> get _visible =>
      _items.where((item) => !_deleted.contains(item.id));

  Delivery? _find(int id) {
    for (final item in _visible) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  bool _isOpen(int id) => _find(id)?.isOpen ?? false;

  DeliveryRoute? get _active {
    for (final route in _routes.reversed) {
      if (route.status == RouteStatus.active) {
        return route;
      }
    }
    return null;
  }

  Delivery _withStop(Delivery item, _Stop? stop) => stop == null
      ? item.copyWith(clearRouteOrder: true)
      : item.copyWith(
          routeOrder: stop.position,
          locked: stop.locked,
          fixedPosition: stop.fixedPosition,
          clearFixedPosition: stop.fixedPosition == null,
        );

  Delivery _withOrder(Delivery item) {
    final route = _active;
    return _withStop(item, route == null ? null : _stops[route.id]?[item.id]);
  }

  @override
  Future<List<Delivery>> getAll() async {
    final copy = _visible.map(_withOrder).toList();
    copy.sort((a, b) {
      if (a.isOpen != b.isOpen) {
        return a.isOpen ? -1 : 1;
      }
      final ao = a.routeOrder ?? 1 << 30;
      final bo = b.routeOrder ?? 1 << 30;
      final byOrder = ao.compareTo(bo);
      return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
    });
    return copy;
  }

  @override
  Future<Delivery?> getById(int id) async {
    final item = _find(id);
    return item == null ? null : _withOrder(item);
  }

  @override
  Future<Delivery> insert(Delivery delivery) async {
    final saved = delivery.copyWith(
      id: _nextId++,
      status: DeliveryStatus.pending,
      clearRouteOrder: true,
    );
    _items.add(saved);
    _events.add(
      DeliveryEvent(
        deliveryId: saved.id!,
        to: DeliveryStatus.pending,
        createdAt: DateTime.now(),
      ),
    );
    return saved;
  }

  @override
  Future<void> update(Delivery delivery) async {
    final current = delivery.id == null ? null : _find(delivery.id!);
    if (current == null) {
      return;
    }
    final changed = changedEditableFields(current, delivery);
    if (changed.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final index = _items.indexOf(current);
    _items[index] = delivery.copyWith(
      status: current.status,
      failureReason: current.failureReason,
      clearFailureReason: current.failureReason == null,
      attempts: current.attempts,
      deliveredAt: current.deliveredAt,
      clearDeliveredAt: current.deliveredAt == null,
      createdAt: current.createdAt,
      updatedAt: now,
      clearRouteOrder: true,
    );
    _events.add(
      DeliveryEvent.edit(
        deliveryId: current.id!,
        status: current.status,
        changedFields: changed,
        createdAt: now,
      ),
    );
  }

  @override
  Future<void> delete(int id) async {
    final current = _find(id);
    if (current == null) {
      return;
    }
    final now = DateTime.now();
    _deleted.add(id);
    final route = _active;
    if (route != null) {
      _stops[route.id]?.remove(id);
    }
    _events.add(
      DeliveryEvent.edit(
        deliveryId: id,
        status: current.status,
        changedFields: const ['deleted_at'],
        note: 'Excluída',
        createdAt: now,
      ),
    );
  }

  @override
  Future<Delivery> transition(
    int id,
    DeliveryStatus to, {
    FailureReason? reason,
    String? note,
    double? latitude,
    double? longitude,
  }) async {
    final current = _find(id);
    if (current == null) {
      throw StateError('Essa entrega não existe mais.');
    }
    final index = _items.indexOf(current);
    final now = DateTime.now();
    // Valida antes de mexer em qualquer coisa (equivale ao rollback).
    final next = applyTransition(current, to, reason: reason, now: now);

    if (to == DeliveryStatus.inProgress) {
      for (var i = 0; i < _items.length; i++) {
        final other = _items[i];
        if (other.id != id &&
            !_deleted.contains(other.id) &&
            other.status == DeliveryStatus.inProgress) {
          _items[i] = applyTransition(other, DeliveryStatus.pending, now: now);
          _events.add(
            DeliveryEvent(
              deliveryId: other.id!,
              from: other.status,
              to: DeliveryStatus.pending,
              createdAt: now,
            ),
          );
        }
      }
    }

    _events.add(
      DeliveryEvent(
        deliveryId: id,
        from: current.status,
        to: to,
        reason: reason,
        note: note,
        latitude: latitude,
        longitude: longitude,
        createdAt: now,
      ),
    );
    _items[index] = next;

    final route = _active;
    if (to == DeliveryStatus.skipped && route != null) {
      final stops = _stops[route.id]!;
      if (stops.containsKey(id)) {
        stops[id]!.position = _maxPosition(stops.values) + 1;
      }
    }
    return _withOrder(next);
  }

  int _maxPosition(Iterable<_Stop> stops) =>
      stops.fold<int>(0, (a, b) => a > b.position ? a : b.position);

  @override
  Future<List<DeliveryEvent>> eventsFor(int deliveryId) async =>
      _events.where((item) => item.deliveryId == deliveryId).toList();

  @override
  Future<DeliveryRoute?> activeRoute() async => _active;

  DeliveryRoute _ensureRoute(DateTime now) {
    var route = _active;
    if (route != null) {
      final stops = _stops[route.id]!;
      final anyOpen = stops.keys.any(_isOpen);
      if (stops.isNotEmpty && !anyOpen) {
        _replaceRoute(route.copyWith(
          status: RouteStatus.completed,
          completedAt: now,
        ));
        route = null;
      }
    }
    if (route == null) {
      route = DeliveryRoute(id: _nextRouteId++, createdAt: now);
      _routes.add(route);
      _stops[route.id!] = {};
    }
    return route;
  }

  void _writeOrder(int routeId, List<int> ids) {
    final stops = _stops[routeId]!;
    final previousOpen = stops.entries
        .where((entry) => _isOpen(entry.key))
        .toList()
      ..sort((a, b) => a.value.position.compareTo(b.value.position));
    final flags = {for (final entry in previousOpen) entry.key: entry.value};
    stops.removeWhere((id, _) => _isOpen(id));
    var position = _maxPosition(stops.values);
    final seen = <int>{};
    for (final id in [...ids, ...previousOpen.map((entry) => entry.key)]) {
      if (!_isOpen(id) || !seen.add(id)) {
        continue;
      }
      final old = flags[id];
      stops[id] = _Stop(
        ++position,
        locked: old?.locked ?? false,
        fixedPosition: old?.fixedPosition,
      );
    }
  }

  @override
  Future<DeliveryRoute> saveRouteOrder(
    List<Delivery> orderedOpen, {
    double? originLat,
    double? originLng,
    double? estimatedKm,
    int? estimatedMinutes,
  }) async {
    final route = _ensureRoute(DateTime.now());
    _writeOrder(route.id!, [
      for (final item in orderedOpen)
        if (item.id != null) item.id!,
    ]);
    final updated = route.copyWith(
      originLat: originLat,
      originLng: originLng,
      estimatedKm: estimatedKm,
      estimatedMinutes: estimatedMinutes,
      manuallyEdited: false,
    );
    _replaceRoute(updated);
    return updated;
  }

  @override
  Future<DeliveryRoute> reorder(List<int> openIdsInOrder) async {
    validateReorder(
      openIdsInOrder,
      _visible.where((item) => item.isOpen).map((item) => item.id!).toSet(),
    );
    final route = _ensureRoute(DateTime.now());
    _writeOrder(route.id!, openIdsInOrder);
    final updated = route.copyWith(manuallyEdited: true);
    _replaceRoute(updated);
    return updated;
  }

  _Stop _ensureStop(int deliveryId) {
    final delivery = _find(deliveryId);
    if (delivery == null) {
      throw StateError('Essa entrega não existe mais.');
    }
    if (!delivery.isOpen) {
      throw ArgumentError('Só dá para travar paradas que ainda estão na rota.');
    }
    final route = _ensureRoute(DateTime.now());
    final stops = _stops[route.id]!;
    if (!stops.containsKey(deliveryId)) {
      // Entram todas as abertas fora da rota, na ordem de cadastro.
      final missing = _visible
          .where((item) => item.isOpen && !stops.containsKey(item.id))
          .toList()
        ..sort((a, b) {
          final byDate = a.createdAt.compareTo(b.createdAt);
          return byDate != 0 ? byDate : a.id!.compareTo(b.id!);
        });
      var position = _maxPosition(stops.values);
      for (final item in missing) {
        stops[item.id!] = _Stop(++position);
      }
    }
    return stops[deliveryId]!;
  }

  @override
  Future<void> setLock(int deliveryId, bool locked) async {
    _ensureStop(deliveryId).locked = locked;
  }

  @override
  Future<void> setFixedPosition(int deliveryId, int? position) async {
    if (position != null && position < 0) {
      throw ArgumentError('Posição inválida.');
    }
    _ensureStop(deliveryId).fixedPosition = position;
  }

  @override
  Future<void> setEndPoint(double? latitude, double? longitude) async {
    final route = _ensureRoute(DateTime.now());
    final clear = latitude == null || longitude == null;
    _replaceRoute(route.copyWith(
      endLat: latitude,
      endLng: longitude,
      clearEndPoint: clear,
    ));
  }

  @override
  Future<List<RouteSummary>> listRoutes() async {
    final routes = [..._routes]..sort((a, b) {
        final byDate = b.createdAt.compareTo(a.createdAt);
        return byDate != 0 ? byDate : b.id!.compareTo(a.id!);
      });
    return [
      for (final route in routes)
        () {
          final stops = _stops[route.id]!
              .keys
              .map(_find)
              .whereType<Delivery>()
              .toList();
          return RouteSummary(
            route: route,
            stops: stops.length,
            delivered: stops.where((item) => item.isDelivered).length,
            failed: stops.where((item) => item.isFailed).length,
            bestPlan: RoutePlan.best(
              _plans.where((plan) => plan.routeId == route.id),
            ),
          );
        }(),
    ];
  }

  @override
  Future<List<Delivery>> stopsOf(int routeId) async {
    final stops = _stops[routeId] ?? const <int, _Stop>{};
    final list = [
      for (final entry in stops.entries)
        if (_find(entry.key) != null) _withStop(_find(entry.key)!, entry.value),
    ]..sort((a, b) => a.routeOrder!.compareTo(b.routeOrder!));
    return list;
  }

  @override
  Future<DeliveryRoute> openRoute(int id) async {
    final index = _routes.indexWhere((route) => route.id == id);
    if (index < 0) {
      throw StateError('Essa rota não existe mais.');
    }
    final current = _active;
    if (current != null && current.id != id) {
      _replaceRoute(current.copyWith(
        status: RouteStatus.completed,
        completedAt: DateTime.now(),
      ));
    }
    final reopened = _routes[index].copyWith(
      status: RouteStatus.active,
      clearCompletedAt: true,
    );
    // A reaberta vira a mais recente entre as ativas.
    _routes
      ..removeAt(index)
      ..add(reopened);
    return reopened;
  }

  @override
  Future<void> deleteRoute(int id) async {
    _routes.removeWhere((route) => route.id == id);
    _stops.remove(id);
    _plans.removeWhere((plan) => plan.routeId == id);
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
    if (!_routes.any((route) => route.id == routeId)) {
      throw StateError('Essa rota não existe mais.');
    }
    final plan = RoutePlan(
      id: _nextPlanId++,
      routeId: routeId,
      createdAt: DateTime.now(),
      stops: stops,
      baselineKm: baselineKm,
      baselineMinutes: baselineMinutes,
      optimizedKm: optimizedKm,
      optimizedMinutes: optimizedMinutes,
    );
    _plans.add(plan);
    return plan;
  }

  @override
  Future<List<RoutePlan>> plansFor(int routeId) async =>
      _plans.where((plan) => plan.routeId == routeId).toList();

  void _replaceRoute(DeliveryRoute route) {
    final index = _routes.indexWhere((item) => item.id == route.id);
    _routes[index] = route;
  }

  @override
  Future<void> startActiveRoute() async {
    final route = _active;
    if (route != null && route.startedAt == null) {
      _replaceRoute(route.copyWith(startedAt: DateTime.now()));
    }
  }

  @override
  Future<void> completeActiveRoute() async {
    final route = _active;
    if (route != null) {
      _replaceRoute(route.copyWith(
        status: RouteStatus.completed,
        completedAt: DateTime.now(),
      ));
    }
  }
}
