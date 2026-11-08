import 'package:rota_max/models/delivery.dart';

/// Tipo do evento: troca de status ou edição de dados (inclui exclusão,
/// registrada como edição do campo `deleted_at`).
enum DeliveryEventKind {
  status,
  edit;

  static DeliveryEventKind fromName(Object? value) =>
      value == 'edit' ? DeliveryEventKind.edit : DeliveryEventKind.status;
}

/// Uma linha de `delivery_events`: troca de status ou edição.
class DeliveryEvent {
  const DeliveryEvent({
    this.id,
    required this.deliveryId,
    this.kind = DeliveryEventKind.status,
    this.from,
    required this.to,
    this.reason,
    this.note,
    this.latitude,
    this.longitude,
    this.changedFields = const [],
    required this.createdAt,
  });

  /// Evento de edição: o status não muda (`from` = `to` = status atual).
  factory DeliveryEvent.edit({
    required int deliveryId,
    required DeliveryStatus status,
    required List<String> changedFields,
    String? note,
    required DateTime createdAt,
  }) =>
      DeliveryEvent(
        deliveryId: deliveryId,
        kind: DeliveryEventKind.edit,
        from: status,
        to: status,
        note: note,
        changedFields: changedFields,
        createdAt: createdAt,
      );

  final int? id;
  final int deliveryId;
  final DeliveryEventKind kind;
  final DeliveryStatus? from;
  final DeliveryStatus to;
  final FailureReason? reason;
  final String? note;
  final double? latitude;
  final double? longitude;

  /// Colunas alteradas num evento `edit` (nomes do banco).
  final List<String> changedFields;
  final DateTime createdAt;

  bool get isEdit => kind == DeliveryEventKind.edit;

  bool get isDeletion => isEdit && changedFields.contains('deleted_at');

  /// Título curto para o histórico da entrega.
  String get title {
    if (isDeletion) {
      return 'Excluída';
    }
    if (isEdit) {
      return 'Dados editados';
    }
    return from == null ? 'Cadastrada' : to.label;
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'delivery_id': deliveryId,
        'kind': kind.name,
        'from_status': from?.code,
        'to_status': to.code,
        'reason': reason?.code,
        'note': note,
        'latitude': latitude,
        'longitude': longitude,
        'changed_fields': changedFields.isEmpty ? null : changedFields.join(','),
        'created_at': createdAt.toIso8601String(),
      };

  factory DeliveryEvent.fromMap(Map<String, Object?> map) {
    final fields = map['changed_fields'] as String?;
    return DeliveryEvent(
      id: map['id'] as int?,
      deliveryId: map['delivery_id'] as int,
      kind: DeliveryEventKind.fromName(map['kind']),
      from: map['from_status'] == null
          ? null
          : DeliveryStatus.fromCode(map['from_status']),
      to: DeliveryStatus.fromCode(map['to_status']),
      reason: FailureReason.fromCode(map['reason']),
      note: map['note'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      changedFields: fields == null || fields.isEmpty
          ? const []
          : fields.split(','),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
