import 'package:rota_max/models/delivery.dart';

/// Uma troca de status registrada em `delivery_events`.
class DeliveryEvent {
  const DeliveryEvent({
    this.id,
    required this.deliveryId,
    this.from,
    required this.to,
    this.reason,
    this.note,
    this.latitude,
    this.longitude,
    required this.createdAt,
  });

  final int? id;
  final int deliveryId;
  final DeliveryStatus? from;
  final DeliveryStatus to;
  final FailureReason? reason;
  final String? note;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'delivery_id': deliveryId,
        'from_status': from?.code,
        'to_status': to.code,
        'reason': reason?.code,
        'note': note,
        'latitude': latitude,
        'longitude': longitude,
        'created_at': createdAt.toIso8601String(),
      };

  factory DeliveryEvent.fromMap(Map<String, Object?> map) => DeliveryEvent(
        id: map['id'] as int?,
        deliveryId: map['delivery_id'] as int,
        from: map['from_status'] == null
            ? null
            : DeliveryStatus.fromCode(map['from_status']),
        to: DeliveryStatus.fromCode(map['to_status']),
        reason: FailureReason.fromCode(map['reason']),
        note: map['note'] as String?,
        latitude: (map['latitude'] as num?)?.toDouble(),
        longitude: (map['longitude'] as num?)?.toDouble(),
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
}
