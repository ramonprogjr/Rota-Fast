enum UserRole { driver, manager, admin }
enum DriverStatus { available, busy, offline }

class Company {
  Company({
    this.id,
    required this.name,
    this.city = 'São Bernardo do Campo',
    this.plan = 'starter',
    this.isActive = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String? id;
  final String name;
  final String city;
  final String plan;
  final bool isActive;
  final DateTime createdAt;

  Company copyWith({
    String? id,
    String? name,
    String? city,
    String? plan,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return Company(
      id: id ?? this.id,
      name: name ?? this.name,
      city: city ?? this.city,
      plan: plan ?? this.plan,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'city': city,
      'plan': plan,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Company.fromMap(Map<String, Object?> map) {
    return Company(
      id: map['id'] as String?,
      name: map['name'] as String? ?? 'Empresa',
      city: map['city'] as String? ?? 'São Bernardo do Campo',
      plan: map['plan'] as String? ?? 'starter',
      isActive: (map['is_active'] as int?) == 1 ||
          (map['is_active'] as bool? ?? false),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class DriverProfile {
  DriverProfile({
    this.id,
    required this.companyId,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.vehicleType,
    this.status = DriverStatus.available,
    this.isActive = true,
  });

  final String? id;
  final String companyId;
  final String fullName;
  final String phone;
  final UserRole role;
  final String vehicleType;
  final DriverStatus status;
  final bool isActive;

  bool get isAvailableForRoute => isActive && status == DriverStatus.available;

  bool get canManageTeam => role == UserRole.manager || role == UserRole.admin;

  DriverProfile copyWith({
    String? id,
    String? companyId,
    String? fullName,
    String? phone,
    UserRole? role,
    String? vehicleType,
    DriverStatus? status,
    bool? isActive,
  }) {
    return DriverProfile(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      vehicleType: vehicleType ?? this.vehicleType,
      status: status ?? this.status,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'full_name': fullName,
      'phone': phone,
      'role': role.name,
      'vehicle_type': vehicleType,
      'status': status.name,
      'is_active': isActive ? 1 : 0,
    };
  }

  factory DriverProfile.fromMap(Map<String, Object?> map) {
    return DriverProfile(
      id: map['id'] as String?,
      companyId: map['company_id'] as String? ?? '',
      fullName: map['full_name'] as String? ?? 'Entregador',
      phone: map['phone'] as String? ?? '',
      role: UserRole.values.firstWhere(
        (item) => item.name == map['role'],
        orElse: () => UserRole.driver,
      ),
      vehicleType: map['vehicle_type'] as String? ?? 'Moto',
      status: DriverStatus.values.firstWhere(
        (item) => item.name == map['status'],
        orElse: () => DriverStatus.available,
      ),
      isActive: (map['is_active'] as int?) == 1 ||
          (map['is_active'] as bool? ?? false),
    );
  }
}

class OperationMetrics {
  const OperationMetrics({
    required this.date,
    required this.deliveries,
    required this.earnings,
    required this.km,
    required this.driversActive,
  });

  final String date;
  final int deliveries;
  final double earnings;
  final double km;
  final int driversActive;

  double get avgEarningsPerDelivery =>
      deliveries == 0 ? 0 : earnings / deliveries;

  double get kmPerDelivery => deliveries == 0 ? 0 : km / deliveries;

  double get avgDeliveriesPerDriver =>
      driversActive == 0 ? 0 : deliveries / driversActive;
}
