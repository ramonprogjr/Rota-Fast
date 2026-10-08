enum DeliveryStatus { pending, done }

enum DeliveryPriority { normal, high, urgent }

class Delivery {
  Delivery({
    this.id,
    this.orderNumber,
    required this.customerName,
    this.phone,
    required this.address,
    this.number,
    this.complement,
    this.neighborhood,
    this.city = 'São Bernardo do Campo',
    this.latitude,
    this.longitude,
    this.value,
    this.priority = DeliveryPriority.normal,
    this.status = DeliveryStatus.pending,
    this.routeOrder,
    this.locationConfirmed = false,
    DateTime? createdAt,
    this.deliveredAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final int? id;
  final String? orderNumber;
  final String customerName;
  final String? phone;
  final String address;
  final String? number;
  final String? complement;
  final String? neighborhood;
  final String city;
  final double? latitude;
  final double? longitude;
  final double? value;
  final DeliveryPriority priority;
  final DeliveryStatus status;
  final int? routeOrder;
  final bool locationConfirmed;
  final DateTime createdAt;
  final DateTime? deliveredAt;

  bool get hasCoordinates => latitude != null && longitude != null;

  bool get isPending => status == DeliveryStatus.pending;

  String get displayName =>
      customerName.trim().isEmpty ? 'Sem nome' : customerName.trim();

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
    String? customerName,
    String? phone,
    String? address,
    String? number,
    String? complement,
    String? neighborhood,
    String? city,
    double? latitude,
    double? longitude,
    double? value,
    DeliveryPriority? priority,
    DeliveryStatus? status,
    int? routeOrder,
    bool? locationConfirmed,
    DateTime? createdAt,
    DateTime? deliveredAt,
    bool clearRouteOrder = false,
    bool clearDeliveredAt = false,
    bool clearCoordinates = false,
  }) {
    return Delivery(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      customerName: customerName ?? this.customerName,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      number: number ?? this.number,
      complement: complement ?? this.complement,
      neighborhood: neighborhood ?? this.neighborhood,
      city: city ?? this.city,
      latitude: clearCoordinates ? null : (latitude ?? this.latitude),
      longitude: clearCoordinates ? null : (longitude ?? this.longitude),
      value: value ?? this.value,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      routeOrder: clearRouteOrder ? null : (routeOrder ?? this.routeOrder),
      locationConfirmed: locationConfirmed ?? this.locationConfirmed,
      createdAt: createdAt ?? this.createdAt,
      deliveredAt: clearDeliveredAt ? null : (deliveredAt ?? this.deliveredAt),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'order_number': orderNumber,
      'customer_name': customerName,
      'phone': phone,
      'address': address,
      'number': number,
      'complement': complement,
      'neighborhood': neighborhood,
      'city': city,
      'latitude': latitude,
      'longitude': longitude,
      'value': value,
      'priority': priority.name,
      'status': status.name,
      'route_order': routeOrder,
      'location_confirmed': locationConfirmed ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
    };
  }

  factory Delivery.fromMap(Map<String, Object?> map) {
    return Delivery(
      id: map['id'] as int?,
      orderNumber: map['order_number'] as String?,
      customerName: (map['customer_name'] as String?) ?? '',
      phone: map['phone'] as String?,
      address: (map['address'] as String?) ?? '',
      number: map['number'] as String?,
      complement: map['complement'] as String?,
      neighborhood: map['neighborhood'] as String?,
      city: (map['city'] as String?) ?? 'São Bernardo do Campo',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      value: (map['value'] as num?)?.toDouble(),
      priority: DeliveryPriority.values.firstWhere(
        (item) => item.name == map['priority'],
        orElse: () => DeliveryPriority.normal,
      ),
      status: DeliveryStatus.values.firstWhere(
        (item) => item.name == map['status'],
        orElse: () => DeliveryStatus.pending,
      ),
      routeOrder: map['route_order'] as int?,
      locationConfirmed: (map['location_confirmed'] as int?) == 1,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      deliveredAt: DateTime.tryParse(map['delivered_at'] as String? ?? ''),
    );
  }
}
