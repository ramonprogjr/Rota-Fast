import 'package:rota_pizza/models/delivery.dart';

abstract class DeliveryRepository {
  Future<List<Delivery>> getAll();
  Future<Delivery> insert(Delivery delivery);
  Future<void> update(Delivery delivery);
  Future<void> delete(int id);
  Future<void> replaceRouteOrder(List<Delivery> orderedPending);
}
