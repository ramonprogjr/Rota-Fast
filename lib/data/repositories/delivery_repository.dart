import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/delivery_event.dart';
import 'package:rota_max/models/delivery_route.dart';

class InvalidTransition implements Exception {
  InvalidTransition(this.from, this.to);

  final DeliveryStatus from;
  final DeliveryStatus to;

  @override
  String toString() =>
      'Não dá para passar de "${from.label}" para "${to.label}".';
}

/// Regra única de troca de status, usada pelas duas implementações.
/// Lança [InvalidTransition] fora da máquina de estados e [ArgumentError]
/// se faltar o motivo de uma falha.
Delivery applyTransition(
  Delivery delivery,
  DeliveryStatus to, {
  FailureReason? reason,
  DateTime? now,
}) {
  if (!delivery.status.canGoTo(to)) {
    throw InvalidTransition(delivery.status, to);
  }
  if (to == DeliveryStatus.failed && reason == null) {
    throw ArgumentError('Informe o motivo de não ter entregado.');
  }
  final at = now ?? DateTime.now();
  return delivery.copyWith(
    status: to,
    updatedAt: at,
    deliveredAt: to == DeliveryStatus.delivered ? at : null,
    clearDeliveredAt: to != DeliveryStatus.delivered,
    failureReason: to == DeliveryStatus.failed ? reason : null,
    clearFailureReason: to != DeliveryStatus.failed,
    attempts: to == DeliveryStatus.failed
        ? delivery.attempts + 1
        : delivery.attempts,
  );
}

abstract class DeliveryRepository {
  /// Todas as entregas. `routeOrder` vem da posição na rota ativa.
  /// Ordem: as que estão na rota primeiro (pela posição), depois as demais.
  Future<List<Delivery>> getAll();

  Future<Delivery?> getById(int id);

  /// Grava uma entrega nova como PENDING e registra o evento de criação.
  Future<Delivery> insert(Delivery delivery);

  /// Atualiza só os dados editáveis (endereço, cliente, coordenadas...).
  /// Status nunca muda por aqui: use [transition].
  Future<void> update(Delivery delivery);

  Future<void> delete(int id);

  /// Troca o status e grava o evento na mesma transação.
  /// - IN_PROGRESS: a que estava em andamento volta para PENDING.
  /// - SKIPPED: a parada vai para o fim da rota ativa.
  Future<Delivery> transition(
    int id,
    DeliveryStatus to, {
    FailureReason? reason,
    String? note,
    double? latitude,
    double? longitude,
  });

  Future<List<DeliveryEvent>> eventsFor(int deliveryId);

  Future<DeliveryRoute?> activeRoute();

  /// Grava a nova ordem das paradas abertas na rota ativa. As concluídas
  /// mantêm a posição. Se não houver rota ativa, ou se a ativa já terminou
  /// (nenhuma parada aberta), ela é concluída e uma nova é criada.
  Future<DeliveryRoute> saveRouteOrder(
    List<Delivery> orderedOpen, {
    double? originLat,
    double? originLng,
    double? estimatedKm,
    int? estimatedMinutes,
  });

  /// Marca o início da rota ativa (primeira vez que o motorista sai).
  Future<void> startActiveRoute();

  Future<void> completeActiveRoute();
}
