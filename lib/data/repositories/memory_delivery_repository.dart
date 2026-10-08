import 'package:rota_pizza/data/repositories/delivery_repository.dart';
import 'package:rota_pizza/models/delivery.dart';

class MemoryDeliveryRepository implements DeliveryRepository {
  MemoryDeliveryRepository([List<Delivery>? seed]) {
    if (seed != null) {
      _items.addAll(seed);
      for (final item in _items) {
        final id = item.id ?? 0;
        if (id >= _nextId) {
          _nextId = id + 1;
        }
      }
    }
  }

  final List<Delivery> _items = [];
  int _nextId = 1;

  @override
  Future<List<Delivery>> getAll() async {
    final copy = [..._items];
    copy.sort((a, b) {
      if (a.isPending != b.isPending) {
        return a.isPending ? -1 : 1;
      }
      final ao = a.routeOrder ?? 9999;
      final bo = b.routeOrder ?? 9999;
      return ao.compareTo(bo);
    });
    return copy;
  }

  @override
  Future<Delivery> insert(Delivery delivery) async {
    final saved = delivery.copyWith(id: _nextId++);
    _items.add(saved);
    return saved;
  }

  @override
  Future<void> update(Delivery delivery) async {
    final index = _items.indexWhere((item) => item.id == delivery.id);
    if (index >= 0) {
      _items[index] = delivery;
    }
  }

  @override
  Future<void> delete(int id) async {
    _items.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> replaceRouteOrder(List<Delivery> orderedPending) async {
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].isPending) {
        _items[i] = _items[i].copyWith(clearRouteOrder: true);
      }
    }
    for (var i = 0; i < orderedPending.length; i++) {
      final current = orderedPending[i];
      final index = _items.indexWhere((item) => item.id == current.id);
      if (index >= 0) {
        _items[index] = _items[index].copyWith(routeOrder: i + 1);
      }
    }
  }
}
