import 'package:rota_max/data/repositories/delivery_repository.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/delivery_event.dart';
import 'package:rota_max/models/delivery_route.dart';

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

  final List<Delivery> _items = [];
  final List<DeliveryEvent> _events = [];
  final List<DeliveryRoute> _routes = [];

  /// routeId -> (deliveryId -> posição)
  final Map<int, Map<int, int>> _stops = {};
  int _nextId = 1;
  int _nextRouteId = 1;

  DeliveryRoute? get _active {
    for (final route in _routes.reversed) {
      if (route.status == RouteStatus.active) {
        return route;
      }
    }
    return null;
  }

  Delivery _withOrder(Delivery item) {
    final route = _active;
    final position = route == null ? null : _stops[route.id]?[item.id];
    return position == null
        ? item.copyWith(clearRouteOrder: true)
        : item.copyWith(routeOrder: position);
  }

  @override
  Future<List<Delivery>> getAll() async {
    final copy = _items.map(_withOrder).toList();
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
    final index = _items.indexWhere((item) => item.id == id);
    return index < 0 ? null : _withOrder(_items[index]);
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
    final index = _items.indexWhere((item) => item.id == delivery.id);
    if (index < 0) {
      return;
    }
    final current = _items[index];
    _items[index] = delivery.copyWith(
      status: current.status,
      failureReason: current.failureReason,
      clearFailureReason: current.failureReason == null,
      attempts: current.attempts,
      deliveredAt: current.deliveredAt,
      clearDeliveredAt: current.deliveredAt == null,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
      clearRouteOrder: true,
    );
  }

  @override
  Future<void> delete(int id) async {
    _items.removeWhere((item) => item.id == id);
    _events.removeWhere((item) => item.deliveryId == id);
    for (final stops in _stops.values) {
      stops.remove(id);
    }
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
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) {
      throw StateError('Entrega $id não existe.');
    }
    final now = DateTime.now();
    // Valida antes de mexer em qualquer coisa (equivale ao rollback).
    final next = applyTransition(_items[index], to, reason: reason, now: now);

    if (to == DeliveryStatus.inProgress) {
      for (var i = 0; i < _items.length; i++) {
        final other = _items[i];
        if (other.id != id && other.status == DeliveryStatus.inProgress) {
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
        from: _items[index].status,
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
        final max = stops.values.fold<int>(0, (a, b) => a > b ? a : b);
        stops[id] = max + 1;
      }
    }
    return _withOrder(next);
  }

  @override
  Future<List<DeliveryEvent>> eventsFor(int deliveryId) async =>
      _events.where((item) => item.deliveryId == deliveryId).toList();

  @override
  Future<DeliveryRoute?> activeRoute() async => _active;

  @override
  Future<DeliveryRoute> saveRouteOrder(
    List<Delivery> orderedOpen, {
    double? originLat,
    double? originLng,
    double? estimatedKm,
    int? estimatedMinutes,
  }) async {
    final now = DateTime.now();
    var route = _active;
    if (route != null) {
      final stops = _stops[route.id]!;
      final anyOpen = stops.keys.any(
        (id) => _items.any((item) => item.id == id && item.isOpen),
      );
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

    final stops = _stops[route.id]!;
    stops.removeWhere(
      (id, _) => _items.any((item) => item.id == id && item.isOpen),
    );
    var position = stops.values.fold<int>(0, (a, b) => a > b ? a : b);
    for (final item in orderedOpen) {
      final current = _items.where((d) => d.id == item.id);
      if (item.id == null || current.isEmpty || !current.first.isOpen) {
        continue;
      }
      stops[item.id!] = ++position;
    }
    final updated = route.copyWith(
      originLat: originLat,
      originLng: originLng,
      estimatedKm: estimatedKm,
      estimatedMinutes: estimatedMinutes,
    );
    _replaceRoute(updated);
    return updated;
  }

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
