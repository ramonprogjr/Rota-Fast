import 'package:rota_max/core/constants/app_constants.dart';

/// Situação da entrega (PRD §3.2 e §13.1). O valor gravado no banco é [code].
enum DeliveryStatus {
  pending('PENDING', 'Pendente'),
  inProgress('IN_PROGRESS', 'A caminho'),
  delivered('DELIVERED', 'Entregue'),
  failed('FAILED', 'Não entregue'),
  skipped('SKIPPED', 'Pulada');

  const DeliveryStatus(this.code, this.label);

  final String code;
  final String label;

  static DeliveryStatus fromCode(Object? value) {
    final text = '$value'.toUpperCase();
    for (final item in values) {
      if (item.code == text) {
        return item;
      }
    }
    return DeliveryStatus.pending;
  }

  /// Ainda faz parte da rota (entra na otimização e na lista "Na rota").
  bool get isOpen =>
      this == pending || this == inProgress || this == skipped;

  /// Transições permitidas. Ver docs/DATABASE.md.
  bool canGoTo(DeliveryStatus next) {
    if (next == this) {
      return false;
    }
    switch (this) {
      case pending:
      case inProgress:
      case skipped:
        return true;
      case failed:
        return next == pending;
      case delivered:
        // Só pela ação explícita "Reabrir".
        return next == pending;
    }
  }
}

/// Motivos de insucesso (PRD §7.2).
enum FailureReason {
  recipientAbsent('ABSENT', 'Destinatário ausente'),
  addressNotFound('ADDRESS_NOT_FOUND', 'Endereço não localizado'),
  refused('REFUSED', 'Cliente recusou'),
  closed('CLOSED', 'Local fechado'),
  accessProblem('ACCESS', 'Problema de acesso'),
  other('OTHER', 'Outros');

  const FailureReason(this.code, this.label);

  final String code;
  final String label;

  static FailureReason? fromCode(Object? value) {
    if (value == null) {
      return null;
    }
    for (final item in values) {
      if (item.code == value) {
        return item;
      }
    }
    return FailureReason.other;
  }
}

enum DeliveryPriority { normal, high, urgent }

class Delivery {
  Delivery({
    this.id,
    this.orderNumber,
    this.packageId,
    required this.customerName,
    this.phone,
    required this.address,
    this.number,
    this.complement,
    this.neighborhood,
    this.postalCode,
    this.city = AppConstants.defaultCity,
    this.state,
    this.latitude,
    this.longitude,
    this.value,
    this.notes,
    this.priority = DeliveryPriority.normal,
    this.status = DeliveryStatus.pending,
    this.failureReason,
    this.attempts = 0,
    this.routeOrder,
    this.locked = false,
    this.fixedPosition,
    this.locationConfirmed = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deliveredAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final int? id;
  final String? orderNumber;
  final String? packageId;
  final String customerName;
  final String? phone;

  /// Logradouro (PRD: `street`). A coluna no banco continua `address`.
  final String address;
  final String? number;
  final String? complement;
  final String? neighborhood;

  /// CEP só com dígitos.
  final String? postalCode;
  final String city;

  /// UF.
  final String? state;
  final double? latitude;
  final double? longitude;
  final double? value;
  final String? notes;
  final DeliveryPriority priority;
  final DeliveryStatus status;
  final FailureReason? failureReason;
  final int attempts;

  /// Posição na rota ativa. Vem de `route_stops`, não da tabela de entregas.
  final int? routeOrder;

  /// Trava da parada na rota ativa (`route_stops.locked`): ao recalcular,
  /// ela continua na posição em que está.
  final bool locked;

  /// Posição fixa (0 = primeira entre as paradas abertas) na rota ativa
  /// (`route_stops.fixed_position`). Null = livre.
  final int? fixedPosition;

  bool get hasConstraint => locked || fixedPosition != null;
  final bool locationConfirmed;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deliveredAt;

  String get street => address;

  bool get hasCoordinates => latitude != null && longitude != null;

  bool get isOpen => status.isOpen;

  bool get isDelivered => status == DeliveryStatus.delivered;

  bool get isFailed => status == DeliveryStatus.failed;

  String get displayName =>
      customerName.trim().isEmpty ? 'Sem nome' : customerName.trim();

  /// Falta algo para um entregador achar o lugar.
  bool get isIncomplete =>
      address.trim().isEmpty || (number == null || number!.trim().isEmpty);

  String get fullAddress {
    final parts = <String>[
      address.trim(),
      if (number != null &&
          number!.trim().isNotEmpty &&
          !address.contains(number!))
        number!.trim(),
      if (complement != null && complement!.trim().isNotEmpty)
        complement!.trim(),
      if (neighborhood != null && neighborhood!.trim().isNotEmpty)
        neighborhood!.trim(),
      if (city.trim().isNotEmpty) city.trim(),
      if (state != null && state!.trim().isNotEmpty) state!.trim(),
    ];
    return parts.join(', ');
  }

  String get shortAddress {
    final street = [
      address.trim(),
      if (number != null && number!.trim().isNotEmpty) number!.trim(),
    ].join(', ');
    return street;
  }

  Delivery copyWith({
    int? id,
    String? orderNumber,
    String? packageId,
    String? customerName,
    String? phone,
    String? address,
    String? number,
    String? complement,
    String? neighborhood,
    String? postalCode,
    String? city,
    String? state,
    double? latitude,
    double? longitude,
    double? value,
    String? notes,
    DeliveryPriority? priority,
    DeliveryStatus? status,
    FailureReason? failureReason,
    int? attempts,
    int? routeOrder,
    bool? locked,
    int? fixedPosition,
    bool? locationConfirmed,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deliveredAt,
    bool clearRouteOrder = false,
    bool clearFixedPosition = false,
    bool clearDeliveredAt = false,
    bool clearCoordinates = false,
    bool clearFailureReason = false,
  }) {
    return Delivery(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      packageId: packageId ?? this.packageId,
      customerName: customerName ?? this.customerName,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      number: number ?? this.number,
      complement: complement ?? this.complement,
      neighborhood: neighborhood ?? this.neighborhood,
      postalCode: postalCode ?? this.postalCode,
      city: city ?? this.city,
      state: state ?? this.state,
      latitude: clearCoordinates ? null : (latitude ?? this.latitude),
      longitude: clearCoordinates ? null : (longitude ?? this.longitude),
      value: value ?? this.value,
      notes: notes ?? this.notes,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      failureReason:
          clearFailureReason ? null : (failureReason ?? this.failureReason),
      attempts: attempts ?? this.attempts,
      routeOrder: clearRouteOrder ? null : (routeOrder ?? this.routeOrder),
      locked: clearRouteOrder ? false : (locked ?? this.locked),
      fixedPosition: clearRouteOrder || clearFixedPosition
          ? null
          : (fixedPosition ?? this.fixedPosition),
      locationConfirmed: locationConfirmed ?? this.locationConfirmed,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deliveredAt: clearDeliveredAt ? null : (deliveredAt ?? this.deliveredAt),
    );
  }

  /// Colunas da tabela `deliveries`. `routeOrder`, `locked` e
  /// `fixedPosition` ficam em `route_stops`, não aqui.
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'order_number': orderNumber,
      'package_id': packageId,
      'customer_name': customerName,
      'phone': phone,
      'address': address,
      'number': number,
      'complement': complement,
      'neighborhood': neighborhood,
      'postal_code': postalCode,
      'city': city,
      'state': state,
      'latitude': latitude,
      'longitude': longitude,
      'location_confirmed': locationConfirmed ? 1 : 0,
      'value': value,
      'notes': notes,
      'priority': priority.name,
      'status': status.code,
      'failure_reason': failureReason?.code,
      'attempts': attempts,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
    };
  }

  /// Campos que o usuário edita. Status, motivo, tentativas e data de entrega
  /// só mudam por transição (ver DeliveryRepository.transition).
  Map<String, Object?> toEditableMap() {
    final map = toMap()
      ..remove('id')
      ..remove('status')
      ..remove('failure_reason')
      ..remove('attempts')
      ..remove('delivered_at')
      ..remove('created_at');
    return map;
  }

  factory Delivery.fromMap(Map<String, Object?> map) {
    final created =
        DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now();
    return Delivery(
      id: map['id'] as int?,
      orderNumber: map['order_number'] as String?,
      packageId: map['package_id'] as String?,
      customerName: (map['customer_name'] as String?) ?? '',
      phone: map['phone'] as String?,
      address: (map['address'] as String?) ?? '',
      number: map['number'] as String?,
      complement: map['complement'] as String?,
      neighborhood: map['neighborhood'] as String?,
      postalCode: map['postal_code'] as String?,
      city: (map['city'] as String?) ?? AppConstants.defaultCity,
      state: map['state'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      value: (map['value'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      priority: DeliveryPriority.values.firstWhere(
        (item) => item.name == map['priority'],
        orElse: () => DeliveryPriority.normal,
      ),
      status: DeliveryStatus.fromCode(map['status']),
      failureReason: FailureReason.fromCode(map['failure_reason']),
      attempts: (map['attempts'] as int?) ?? 0,
      routeOrder: map['route_order'] as int?,
      locked: (map['stop_locked'] as int?) == 1,
      fixedPosition: map['stop_fixed_position'] as int?,
      locationConfirmed: (map['location_confirmed'] as int?) == 1,
      createdAt: created,
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? created,
      deliveredAt: DateTime.tryParse(map['delivered_at'] as String? ?? ''),
    );
  }
}
