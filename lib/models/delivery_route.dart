/// Uma rota do dia (tabela `routes`). Só uma fica `active` por vez.
enum RouteStatus { draft, active, completed }

class DeliveryRoute {
  const DeliveryRoute({
    this.id,
    this.status = RouteStatus.active,
    this.originLat,
    this.originLng,
    this.estimatedKm,
    this.estimatedMinutes,
    this.navApp,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
  });

  final int? id;
  final RouteStatus status;
  final double? originLat;
  final double? originLng;
  final double? estimatedKm;
  final int? estimatedMinutes;
  final String? navApp;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  bool get isStarted => startedAt != null;

  DeliveryRoute copyWith({
    int? id,
    RouteStatus? status,
    double? originLat,
    double? originLng,
    double? estimatedKm,
    int? estimatedMinutes,
    String? navApp,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return DeliveryRoute(
      id: id ?? this.id,
      status: status ?? this.status,
      originLat: originLat ?? this.originLat,
      originLng: originLng ?? this.originLng,
      estimatedKm: estimatedKm ?? this.estimatedKm,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      navApp: navApp ?? this.navApp,
      createdAt: createdAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'status': status.name,
        'origin_lat': originLat,
        'origin_lng': originLng,
        'estimated_km': estimatedKm,
        'estimated_minutes': estimatedMinutes,
        'nav_app': navApp,
        'created_at': createdAt.toIso8601String(),
        'started_at': startedAt?.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
      };

  factory DeliveryRoute.fromMap(Map<String, Object?> map) => DeliveryRoute(
        id: map['id'] as int?,
        status: RouteStatus.values.firstWhere(
          (item) => item.name == map['status'],
          orElse: () => RouteStatus.active,
        ),
        originLat: (map['origin_lat'] as num?)?.toDouble(),
        originLng: (map['origin_lng'] as num?)?.toDouble(),
        estimatedKm: (map['estimated_km'] as num?)?.toDouble(),
        estimatedMinutes: map['estimated_minutes'] as int?,
        navApp: map['nav_app'] as String?,
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
        startedAt: DateTime.tryParse(map['started_at'] as String? ?? ''),
        completedAt: DateTime.tryParse(map['completed_at'] as String? ?? ''),
      );
}
