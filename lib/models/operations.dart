enum ShiftStatus { planned, active, completed, cancelled }

class OperationShift {
  OperationShift({
    this.id,
    required this.companyId,
    required this.driverId,
    required this.startedAt,
    this.endedAt,
    this.title,
    this.status = ShiftStatus.planned,
    this.routeKm = 0,
    this.earnings = 0,
    this.deliveriesCompleted = 0,
    this.deliveriesPending = 0,
    this.notes,
  });

  final String? id;
  final String companyId;
  final String driverId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? title;
  final ShiftStatus status;
  final double routeKm;
  final double earnings;
  final int deliveriesCompleted;
  final int deliveriesPending;
  final String? notes;

  bool get isActive => status == ShiftStatus.active;
  bool get isCompleted => status == ShiftStatus.completed;

  double get avgEarningsPerDelivery =>
      deliveriesCompleted == 0 ? 0 : earnings / deliveriesCompleted;

  OperationShift copyWith({
    String? id,
    String? companyId,
    String? driverId,
    DateTime? startedAt,
    DateTime? endedAt,
    String? title,
    ShiftStatus? status,
    double? routeKm,
    double? earnings,
    int? deliveriesCompleted,
    int? deliveriesPending,
    String? notes,
    bool clearEndedAt = false,
  }) {
    return OperationShift(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      driverId: driverId ?? this.driverId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
      title: title ?? this.title,
      status: status ?? this.status,
      routeKm: routeKm ?? this.routeKm,
      earnings: earnings ?? this.earnings,
      deliveriesCompleted: deliveriesCompleted ?? this.deliveriesCompleted,
      deliveriesPending: deliveriesPending ?? this.deliveriesPending,
      notes: notes ?? this.notes,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'driver_id': driverId,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'title': title,
      'status': status.name,
      'route_km': routeKm,
      'earnings': earnings,
      'deliveries_completed': deliveriesCompleted,
      'deliveries_pending': deliveriesPending,
      'notes': notes,
    };
  }

  factory OperationShift.fromMap(Map<String, Object?> map) {
    return OperationShift(
      id: map['id'] as String?,
      companyId: map['company_id'] as String? ?? '',
      driverId: map['driver_id'] as String? ?? '',
      startedAt: DateTime.tryParse(map['started_at'] as String? ?? '') ??
          DateTime.now(),
      endedAt: DateTime.tryParse(map['ended_at'] as String? ?? ''),
      title: map['title'] as String?,
      status: ShiftStatus.values.firstWhere(
        (item) => item.name == map['status'],
        orElse: () => ShiftStatus.planned,
      ),
      routeKm: (map['route_km'] as num?)?.toDouble() ?? 0,
      earnings: (map['earnings'] as num?)?.toDouble() ?? 0,
      deliveriesCompleted:
          (map['deliveries_completed'] as num?)?.toInt() ?? 0,
      deliveriesPending: (map['deliveries_pending'] as num?)?.toInt() ?? 0,
      notes: map['notes'] as String?,
    );
  }
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.companyId,
    required this.date,
    required this.totalDeliveries,
    required this.totalEarnings,
    required this.totalKm,
    required this.activeDrivers,
    required this.completedShifts,
  });

  final String companyId;
  final String date;
  final int totalDeliveries;
  final double totalEarnings;
  final double totalKm;
  final int activeDrivers;
  final int completedShifts;

  double get avgDeliveriesPerDriver =>
      activeDrivers == 0 ? 0 : totalDeliveries / activeDrivers;

  double get earningsPerKm => totalKm == 0 ? 0 : totalEarnings / totalKm;
}
