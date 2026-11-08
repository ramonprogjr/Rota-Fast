/// Uma rota do dia (tabela `routes`). Só uma fica `active` por vez.
enum RouteStatus { draft, active, completed }

class DeliveryRoute {
  const DeliveryRoute({
    this.id,
    this.name,
    this.status = RouteStatus.active,
    this.originLat,
    this.originLng,
    this.endLat,
    this.endLng,
    this.manuallyEdited = false,
    this.estimatedKm,
    this.estimatedMinutes,
    this.navApp,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
  });

  final int? id;

  /// Nome opcional dado pelo motorista. Sem nome, a tela usa a data.
  final String? name;
  final RouteStatus status;
  final double? originLat;
  final double? originLng;

  /// Ponto final opcional (ex.: voltar para a base).
  final double? endLat;
  final double? endLng;

  /// O motorista mudou a ordem na mão. Enquanto for true, a rota não é
  /// reotimizada sozinha depois de cada entrega.
  final bool manuallyEdited;
  final double? estimatedKm;
  final int? estimatedMinutes;
  final String? navApp;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  bool get isStarted => startedAt != null;

  bool get isActive => status == RouteStatus.active;

  bool get hasEndPoint => endLat != null && endLng != null;

  DeliveryRoute copyWith({
    int? id,
    String? name,
    RouteStatus? status,
    double? originLat,
    double? originLng,
    double? endLat,
    double? endLng,
    bool? manuallyEdited,
    double? estimatedKm,
    int? estimatedMinutes,
    String? navApp,
    DateTime? startedAt,
    DateTime? completedAt,
    bool clearEndPoint = false,
    bool clearCompletedAt = false,
  }) {
    return DeliveryRoute(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      originLat: originLat ?? this.originLat,
      originLng: originLng ?? this.originLng,
      endLat: clearEndPoint ? null : (endLat ?? this.endLat),
      endLng: clearEndPoint ? null : (endLng ?? this.endLng),
      manuallyEdited: manuallyEdited ?? this.manuallyEdited,
      estimatedKm: estimatedKm ?? this.estimatedKm,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      navApp: navApp ?? this.navApp,
      createdAt: createdAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'status': status.name,
        'origin_lat': originLat,
        'origin_lng': originLng,
        'end_lat': endLat,
        'end_lng': endLng,
        'manually_edited': manuallyEdited ? 1 : 0,
        'estimated_km': estimatedKm,
        'estimated_minutes': estimatedMinutes,
        'nav_app': navApp,
        'created_at': createdAt.toIso8601String(),
        'started_at': startedAt?.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
      };

  factory DeliveryRoute.fromMap(Map<String, Object?> map) => DeliveryRoute(
        id: map['id'] as int?,
        name: map['name'] as String?,
        status: RouteStatus.values.firstWhere(
          (item) => item.name == map['status'],
          orElse: () => RouteStatus.active,
        ),
        originLat: (map['origin_lat'] as num?)?.toDouble(),
        originLng: (map['origin_lng'] as num?)?.toDouble(),
        endLat: (map['end_lat'] as num?)?.toDouble(),
        endLng: (map['end_lng'] as num?)?.toDouble(),
        manuallyEdited: (map['manually_edited'] as int?) == 1,
        estimatedKm: (map['estimated_km'] as num?)?.toDouble(),
        estimatedMinutes: map['estimated_minutes'] as int?,
        navApp: map['nav_app'] as String?,
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
        startedAt: DateTime.tryParse(map['started_at'] as String? ?? ''),
        completedAt: DateTime.tryParse(map['completed_at'] as String? ?? ''),
      );
}

/// Uma linha de `route_plans`: quanto o "Organizar rota" economizou em
/// relação à ordem em que as paradas foram cadastradas.
class RoutePlan {
  const RoutePlan({
    this.id,
    required this.routeId,
    required this.createdAt,
    required this.stops,
    required this.baselineKm,
    required this.baselineMinutes,
    required this.optimizedKm,
    required this.optimizedMinutes,
  });

  final int? id;
  final int routeId;
  final DateTime createdAt;
  final int stops;
  final double baselineKm;
  final int baselineMinutes;
  final double optimizedKm;
  final int optimizedMinutes;

  double get savedKm =>
      (baselineKm - optimizedKm) < 0 ? 0 : baselineKm - optimizedKm;

  int get savedMinutes => (baselineMinutes - optimizedMinutes) < 0
      ? 0
      : baselineMinutes - optimizedMinutes;

  RoutePlan copyWith({int? id}) => RoutePlan(
        id: id ?? this.id,
        routeId: routeId,
        createdAt: createdAt,
        stops: stops,
        baselineKm: baselineKm,
        baselineMinutes: baselineMinutes,
        optimizedKm: optimizedKm,
        optimizedMinutes: optimizedMinutes,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'route_id': routeId,
        'created_at': createdAt.toIso8601String(),
        'stops': stops,
        'baseline_km': baselineKm,
        'baseline_minutes': baselineMinutes,
        'optimized_km': optimizedKm,
        'optimized_minutes': optimizedMinutes,
      };

  factory RoutePlan.fromMap(Map<String, Object?> map) => RoutePlan(
        id: map['id'] as int?,
        routeId: map['route_id'] as int,
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
        stops: map['stops'] as int,
        baselineKm: (map['baseline_km'] as num).toDouble(),
        baselineMinutes: map['baseline_minutes'] as int,
        optimizedKm: (map['optimized_km'] as num).toDouble(),
        optimizedMinutes: map['optimized_minutes'] as int,
      );

  /// O relatório usa, por rota, o plano com mais paradas (empate: o mais
  /// recente), para não contar a mesma rota duas vezes.
  static RoutePlan? best(Iterable<RoutePlan> plans) {
    RoutePlan? best;
    for (final plan in plans) {
      if (best == null ||
          plan.stops > best.stops ||
          (plan.stops == best.stops &&
              !plan.createdAt.isBefore(best.createdAt))) {
        best = plan;
      }
    }
    return best;
  }
}

/// Linha do histórico de rotas.
class RouteSummary {
  const RouteSummary({
    required this.route,
    required this.stops,
    required this.delivered,
    required this.failed,
    this.bestPlan,
  });

  final DeliveryRoute route;
  final int stops;
  final int delivered;
  final int failed;
  final RoutePlan? bestPlan;

  int get id => route.id!;

  int get open => stops - delivered - failed;

  double? get estimatedKm => route.estimatedKm;

  double get savedKm => bestPlan?.savedKm ?? 0;
}
