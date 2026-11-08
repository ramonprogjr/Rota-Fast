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

/// Colunas editáveis que mudaram entre [before] e [after] (nomes do banco).
/// `updated_at` não conta.
List<String> changedEditableFields(Delivery before, Delivery after) {
  final a = before.toEditableMap()..remove('updated_at');
  final b = after.toEditableMap()..remove('updated_at');
  return [
    for (final key in a.keys)
      if (a[key] != b[key]) key,
  ];
}

/// Valida a lista completa de paradas abertas para [DeliveryRepository.reorder].
/// Lança [ArgumentError] com mensagem para o motorista.
void validateReorder(List<int> ids, Set<int> openIds) {
  if (ids.toSet().length != ids.length) {
    throw ArgumentError('A nova ordem tem paradas repetidas.');
  }
  if (ids.length != openIds.length || !ids.every(openIds.contains)) {
    throw ArgumentError(
      'A lista de paradas mudou enquanto você editava. Abra a edição de novo.',
    );
  }
}

abstract class DeliveryRepository {
  /// Todas as entregas não excluídas. `routeOrder`, `locked` e
  /// `fixedPosition` vêm da parada na rota ativa.
  /// Ordem: as que estão na rota primeiro (pela posição), depois as demais.
  Future<List<Delivery>> getAll();

  /// Null se não existe ou foi excluída.
  Future<Delivery?> getById(int id);

  /// Grava uma entrega nova como PENDING e registra o evento de criação.
  Future<Delivery> insert(Delivery delivery);

  /// Atualiza só os dados editáveis (endereço, cliente, coordenadas...).
  /// Status nunca muda por aqui: use [transition]. Se algo mudou, grava um
  /// evento `edit` com a lista de campos alterados.
  Future<void> update(Delivery delivery);

  /// Exclusão lógica: grava `deleted_at`, tira a entrega da rota ativa e
  /// registra um evento `edit` (campo `deleted_at`). O histórico fica.
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

  /// Eventos da entrega (inclusive de excluídas), do mais antigo ao novo.
  Future<List<DeliveryEvent>> eventsFor(int deliveryId);

  Future<DeliveryRoute?> activeRoute();

  /// Grava a nova ordem calculada das paradas abertas na rota ativa.
  /// - As concluídas mantêm a posição.
  /// - Paradas abertas da rota que não vierem em [orderedOpen] vão para o
  ///   fim, na ordem em que estavam (nunca perdem a posição).
  /// - Trava e posição fixa das paradas que continuam são preservadas.
  /// - `manually_edited` volta a 0 (é uma ordem calculada).
  /// Se não houver rota ativa, ou se a ativa já terminou (nenhuma parada
  /// aberta), ela é concluída e uma nova é criada.
  Future<DeliveryRoute> saveRouteOrder(
    List<Delivery> orderedOpen, {
    double? originLat,
    double? originLng,
    double? estimatedKm,
    int? estimatedMinutes,
  });

  /// Ordem manual. [openIdsInOrder] precisa ter exatamente todas as
  /// entregas abertas (as que aparecem em "Na rota"), sem repetir; senão
  /// lança [ArgumentError] e nada muda. Uma transação. Marca a rota ativa
  /// como `manually_edited`.
  Future<DeliveryRoute> reorder(List<int> openIdsInOrder);

  /// Trava a parada na posição atual. Se a entrega ainda não estiver na rota
  /// ativa, ela e as outras abertas fora da rota entram no fim, na ordem de
  /// cadastro (a mesma da tela), para nada mudar de lugar.
  Future<void> setLock(int deliveryId, bool locked);

  /// Fixa a parada numa posição (0 = primeira entre as abertas). Null solta.
  Future<void> setFixedPosition(int deliveryId, int? position);

  /// Define (ou limpa, com null) o ponto final da rota ativa.
  Future<void> setEndPoint(double? latitude, double? longitude);

  /// Histórico de rotas, da mais nova para a mais antiga.
  Future<List<RouteSummary>> listRoutes();

  /// Paradas de uma rota (abertas e concluídas), pela posição. `routeOrder`
  /// é a posição nessa rota.
  Future<List<Delivery>> stopsOf(int routeId);

  /// Reativa a rota [id]. A ativa atual (se for outra) é concluída.
  Future<DeliveryRoute> openRoute(int id);

  /// Apaga a rota, as paradas e os planos dela. Entregas nunca são
  /// apagadas: as abertas só saem da rota e voltam para a lista.
  Future<void> deleteRoute(int id);

  /// Registra a economia de um "Organizar rota".
  Future<RoutePlan> savePlan({
    required int routeId,
    required int stops,
    required double baselineKm,
    required int baselineMinutes,
    required double optimizedKm,
    required int optimizedMinutes,
  });

  Future<List<RoutePlan>> plansFor(int routeId);

  /// Marca o início da rota ativa (primeira vez que o motorista sai).
  Future<void> startActiveRoute();

  Future<void> completeActiveRoute();
}
