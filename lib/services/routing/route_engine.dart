import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:rota_max/core/constants/app_constants.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/services/routing/distance_matrix.dart';
import 'package:rota_max/services/routing/haversine_matrix.dart';
import 'package:rota_max/services/routing/ors_matrix_client.dart';
import 'package:rota_max/services/routing/route_plan_input.dart';
import 'package:rota_max/services/routing/route_solver.dart';

/// Motor padrão: matriz da malha viária (ORS) quando disponível, senão
/// estimativa local (linha reta × fator de ruas). Otimiza num isolate.
///
/// Nunca lança exceção: qualquer falha vira um resultado com [RoutingResult.
/// warning] preenchido (no pior caso, a ordem atual com números estimados).
class DefaultRouteEngine implements RouteEngine {
  DefaultRouteEngine({
    this.roadProvider,
    this.roadFactor = AppConstants.roadFactor,
    this.useIsolate = true,
    this.timeBudgetMs = 200,
    this.maxIterations = 5000,
  });

  /// Usa a ORS se houver `ORS_API_KEY` (via `--dart-define`); senão só a
  /// estimativa local.
  factory DefaultRouteEngine.fromEnvironment({http.Client? client}) {
    const key = AppConstants.orsApiKey;
    return DefaultRouteEngine(
      roadProvider: key.isEmpty
          ? null
          : OrsMatrixClient(apiKey: key, client: client),
    );
  }

  static const estimatedWarning = 'Rota estimada (sem dados de ruas)';
  static const failedWarning =
      'Não foi possível otimizar agora. Mantida a ordem atual.';

  /// `null` quando não há chave da ORS.
  final DistanceMatrixProvider? roadProvider;
  final double roadFactor;

  /// Roda a otimização em outro isolate (`compute`). Desligue só em testes.
  final bool useIsolate;
  final int timeBudgetMs;
  final int maxIterations;

  @override
  Future<RoutingResult> plan(RoutingRequest request) async {
    try {
      return await _plan(request);
    } catch (_) {
      return _keepCurrentOrder(request, failedWarning);
    }
  }

  Future<RoutingResult> _plan(RoutingRequest request) async {
    final routable = <Delivery>[];
    final unroutable = <Delivery>[];
    for (final stop in request.stops) {
      (stop.hasCoordinates ? routable : unroutable).add(stop);
    }
    final fallback = HaversineMatrix(request.speedKmh, roadFactor: roadFactor);
    final points = <GeoPoint>[
      request.origin,
      for (final stop in routable) GeoPoint(stop.latitude!, stop.longitude!),
      if (request.end != null) request.end!,
    ];

    // 1. Matriz: malha viária ou estimativa.
    TravelMatrix? road;
    String? warning;
    if (roadProvider == null) {
      warning = estimatedWarning;
    } else {
      try {
        road = await roadProvider!.matrix(points, request.profile);
        if (!_validShape(road, points.length) ||
            !_endpointsReachable(road, request.end != null)) {
          road = null;
        }
      } catch (_) {
        road = null;
      }
      warning = road == null ? estimatedWarning : null;
    }

    // 2. Paradas inalcançáveis na malha saem da rota.
    final kept = <int>[];
    for (var i = 0; i < routable.length; i++) {
      if (road == null || _reachable(road, i + 1)) {
        kept.add(i);
      } else {
        unroutable.add(routable[i]);
      }
    }
    final stops = [for (final i in kept) routable[i]];
    final n = stops.length;

    // 3. Matrizes achatadas só com origem, paradas mantidas e fim.
    final nodes = <int>[
      0,
      for (final i in kept) i + 1,
      if (request.end != null) points.length - 1,
    ];
    final m = nodes.length;
    final seconds = Float64List(m * m);
    final meters = Float64List(m * m);
    for (var a = 0; a < m; a++) {
      for (var b = 0; b < m; b++) {
        if (a == b) {
          continue;
        }
        final pa = points[nodes[a]];
        final pb = points[nodes[b]];
        final roadMeters = road?.meters[nodes[a]][nodes[b]];
        final roadSeconds = road?.seconds[nodes[a]][nodes[b]];
        final estMeters = fallback.meters(pa, pb);
        meters[a * m + b] = roadMeters ?? estMeters;
        seconds[a * m + b] = roadSeconds ?? fallback.secondsFor(estMeters);
      }
    }

    // 4. Restrições e otimização.
    final fixedSlots = resolveFixedSlots(
      stopCount: n,
      fixedPosition: [
        for (final s in stops) request.constraints[s.id]?.fixedPosition,
      ],
      locked: [
        for (final s in stops) request.constraints[s.id]?.locked ?? false,
      ],
    );
    final currentOrder = List<int>.generate(n, (i) => i);
    final input = RouteSolverInput(
      stopCount: n,
      seconds: seconds,
      hasEnd: request.end != null,
      weights: [for (final s in stops) priorityPenaltyWeight(s.priority)],
      fixedSlots: fixedSlots,
      initialOrder: applyFixedSlots(fixedSlots, currentOrder),
      timeBudgetMs: timeBudgetMs,
      maxIterations: maxIterations,
    );

    List<int> order;
    try {
      order = useIsolate && n > 3
          ? await compute(solveRoute, input)
          : solveRoute(input);
      if (!_isPermutation(order, n)) {
        throw StateError('ordem inválida');
      }
    } catch (_) {
      order = currentOrder;
      warning = failedWarning;
    }

    // 5. Totais e linha de base (ordem de cadastro).
    final baselineOrder = [...currentOrder]
      ..sort((a, b) {
        final byDate = stops[a].createdAt.compareTo(stops[b].createdAt);
        return byDate != 0 ? byDate : a.compareTo(b);
      });
    final total = _walk(order, meters, seconds, m, request.end != null);
    final baseline =
        _walk(baselineOrder, meters, seconds, m, request.end != null);

    return RoutingResult(
      ordered: [for (final i in order) stops[i]],
      totalKm: total.km,
      totalTime: total.time,
      baselineKm: baseline.km,
      baselineTime: baseline.time,
      unroutable: unroutable,
      usedRoadNetwork: road != null,
      warning: warning,
    );
  }

  /// Último recurso: ordem atual, números pela estimativa local.
  RoutingResult _keepCurrentOrder(RoutingRequest request, String warning) {
    try {
      final routable = request.stops.where((s) => s.hasCoordinates).toList();
      final unroutable =
          request.stops.where((s) => !s.hasCoordinates).toList();
      final fallback =
          HaversineMatrix(request.speedKmh, roadFactor: roadFactor);
      final current = _legs(request, routable, fallback);
      final byDate = [...routable]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final baseline = _legs(request, byDate, fallback);
      return RoutingResult(
        ordered: routable,
        totalKm: current.km,
        totalTime: current.time,
        baselineKm: baseline.km,
        baselineTime: baseline.time,
        unroutable: unroutable,
        usedRoadNetwork: false,
        warning: warning,
      );
    } catch (_) {
      return RoutingResult(
        ordered: const [],
        totalKm: 0,
        totalTime: Duration.zero,
        baselineKm: 0,
        baselineTime: Duration.zero,
        unroutable: request.stops,
        usedRoadNetwork: false,
        warning: warning,
      );
    }
  }

  static _Totals _legs(
    RoutingRequest request,
    List<Delivery> order,
    HaversineMatrix fallback,
  ) {
    var meters = 0.0;
    var prev = request.origin;
    for (final stop in order) {
      final point = GeoPoint(stop.latitude!, stop.longitude!);
      meters += fallback.meters(prev, point);
      prev = point;
    }
    if (request.end != null) {
      meters += fallback.meters(prev, request.end!);
    }
    return _Totals(
      meters / 1000,
      Duration(seconds: fallback.secondsFor(meters).round()),
    );
  }

  static _Totals _walk(
    List<int> order,
    Float64List meters,
    Float64List seconds,
    int m,
    bool hasEnd,
  ) {
    var totalMeters = 0.0;
    var totalSeconds = 0.0;
    var prev = 0;
    for (final stop in order) {
      final node = stop + 1;
      totalMeters += meters[prev * m + node];
      totalSeconds += seconds[prev * m + node];
      prev = node;
    }
    if (hasEnd) {
      totalMeters += meters[prev * m + m - 1];
      totalSeconds += seconds[prev * m + m - 1];
    }
    return _Totals(
      totalMeters / 1000,
      Duration(seconds: totalSeconds.round()),
    );
  }

  static bool _validShape(TravelMatrix matrix, int size) {
    if (matrix.seconds.length != size || matrix.meters.length != size) {
      return false;
    }
    for (var i = 0; i < size; i++) {
      if (matrix.seconds[i].length != size || matrix.meters[i].length != size) {
        return false;
      }
    }
    return true;
  }

  /// Origem precisa sair para algum lugar; o fim precisa ser alcançável.
  static bool _endpointsReachable(TravelMatrix matrix, bool hasEnd) {
    final size = matrix.size;
    if (size <= 1) {
      return true;
    }
    if (!_reachable(matrix, 0, checkColumn: false)) {
      return false;
    }
    if (hasEnd && !_reachable(matrix, size - 1, checkRow: false)) {
      return false;
    }
    return true;
  }

  /// Um nó é inalcançável se toda a linha (saídas) ou toda a coluna
  /// (chegadas) for nula, desconsiderando a diagonal.
  static bool _reachable(
    TravelMatrix matrix,
    int node, {
    bool checkRow = true,
    bool checkColumn = true,
  }) {
    final size = matrix.size;
    if (size <= 1) {
      return true;
    }
    var anyOut = false;
    var anyIn = false;
    for (var j = 0; j < size; j++) {
      if (j == node) {
        continue;
      }
      if (matrix.seconds[node][j] != null) {
        anyOut = true;
      }
      if (matrix.seconds[j][node] != null) {
        anyIn = true;
      }
    }
    return (!checkRow || anyOut) && (!checkColumn || anyIn);
  }

  static bool _isPermutation(List<int> order, int n) {
    if (order.length != n) {
      return false;
    }
    final seen = <int>{};
    for (final i in order) {
      if (i < 0 || i >= n || !seen.add(i)) {
        return false;
      }
    }
    return true;
  }
}

class _Totals {
  const _Totals(this.km, this.time);

  final double km;
  final Duration time;
}
