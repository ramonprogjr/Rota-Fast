import 'dart:typed_data';

import 'package:rota_max/models/delivery.dart';

/// Núcleo puro da otimização (sem Flutter, sem objetos de domínio), para
/// rodar num isolate via `compute()`.
///
/// ## Função de custo (minimizada)
///
/// ```
/// custo = Σ tempo_de_viagem(trechos)                       (segundos)
///       + Σ peso(prioridade_i) × chegada_i                  (segundos)
/// ```
///
/// - `chegada_i` = soma das viagens até a parada `i` mais
///   [RouteSolverInput.serviceSeconds] (tempo de atendimento) por parada
///   anterior. O atendimento só entra na penalidade, não no tempo total.
/// - Pesos ([priorityPenaltyWeight]): urgente 0,8; alta 0,2; normal 0.
///   Sem prioridades o problema é puro "menor tempo de viagem".
///   A prioridade é uma preferência leve: adianta a parada quando o desvio
///   é pequeno, mas não faz a rota atravessar a cidade e voltar (com pesos
///   3,0/1,5 o cenário do site ficou 30–50% mais longo, em zigue-zague).
///   Para obrigar uma parada a sair primeiro, use o alfinete (posição fixa).
/// - Com ponto final, o último trecho (última parada → fim) entra na viagem.
///
/// ## Algoritmo
/// 1. Solução inicial = melhor entre vizinho mais próximo (tempo × fator de
///    prioridade) e a ordem atual.
/// 2. Busca local: 2-opt (inverter trechos) + Or-opt (realocar blocos de
///    1–3 paradas) até não melhorar ou atingir o limite de tempo/iterações.
/// 3. Posições fixas ([RouteSolverInput.fixedSlots]) nunca se movem; só as
///    posições livres são otimizadas.
class RouteSolverInput {
  RouteSolverInput({
    required this.stopCount,
    required this.seconds,
    required this.hasEnd,
    required this.weights,
    required this.fixedSlots,
    required this.initialOrder,
    this.serviceSeconds = defaultServiceSeconds,
    this.timeBudgetMs = 200,
    this.maxIterations = 5000,
  });

  static const defaultServiceSeconds = 120.0;

  /// Número de paradas `n`.
  final int stopCount;

  /// Matriz achatada `m × m`, `m = n + 1 (+1 com fim)`. Índice 0 = origem,
  /// `1..n` = paradas, `n + 1` = fim. Sem nulos.
  final Float64List seconds;
  final bool hasEnd;

  /// Peso de penalidade por parada (ver [priorityPenaltyWeight]).
  final List<double> weights;

  /// Por posição na rota: índice da parada (0..n-1) presa nela, ou -1.
  final List<int> fixedSlots;

  /// Ordem atual das paradas (índices 0..n-1), respeitando [fixedSlots].
  final List<int> initialOrder;
  final double serviceSeconds;
  final int timeBudgetMs;
  final int maxIterations;

  int get size => stopCount + 1 + (hasEnd ? 1 : 0);
}

/// Peso da chegada na penalidade de prioridade.
double priorityPenaltyWeight(DeliveryPriority priority) {
  switch (priority) {
    case DeliveryPriority.urgent:
      return 0.8;
    case DeliveryPriority.high:
      return 0.2;
    case DeliveryPriority.normal:
      return 0.0;
  }
}

/// Fator do vizinho mais próximo (só para a solução inicial).
double _greedyFactor(double weight) {
  if (weight >= 0.5) {
    return 0.7;
  }
  if (weight > 0) {
    return 0.9;
  }
  return 1.0;
}

/// Custo da ordem completa (índices de parada 0..n-1).
double routeCost(RouteSolverInput input, List<int> order) {
  final m = input.size;
  final sec = input.seconds;
  final weights = input.weights;
  var clock = 0.0;
  var cost = 0.0;
  var prev = 0;
  for (var k = 0; k < order.length; k++) {
    final node = order[k] + 1;
    final t = sec[prev * m + node];
    clock += t;
    cost += t + weights[order[k]] * clock;
    clock += input.serviceSeconds;
    prev = node;
  }
  if (input.hasEnd) {
    cost += sec[prev * m + (m - 1)];
  }
  return cost;
}

/// Vizinho mais próximo respeitando as posições fixas.
List<int> nearestNeighbour(RouteSolverInput input) {
  final n = input.stopCount;
  final m = input.size;
  final fixedStops = input.fixedSlots.where((s) => s >= 0).toSet();
  final remaining = [
    for (var i = 0; i < n; i++)
      if (!fixedStops.contains(i)) i,
  ];
  final order = <int>[];
  var prev = 0;
  for (var pos = 0; pos < n; pos++) {
    final fixed = input.fixedSlots[pos];
    if (fixed >= 0) {
      order.add(fixed);
      prev = fixed + 1;
      continue;
    }
    var bestIdx = 0;
    var bestScore = double.infinity;
    for (var r = 0; r < remaining.length; r++) {
      final stop = remaining[r];
      final score =
          input.seconds[prev * m + stop + 1] *
          _greedyFactor(input.weights[stop]);
      if (score < bestScore) {
        bestScore = score;
        bestIdx = r;
      }
    }
    final next = remaining.removeAt(bestIdx);
    order.add(next);
    prev = next + 1;
  }
  return order;
}

/// Busca local (2-opt + Or-opt) sobre as posições livres de [start].
List<int> improveRoute(RouteSolverInput input, List<int> start) {
  final n = input.stopCount;
  if (n < 2) {
    return [...start];
  }
  final freeSlots = [
    for (var p = 0; p < n; p++)
      if (input.fixedSlots[p] < 0) p,
  ];
  final k = freeSlots.length;
  if (k < 2) {
    return [...start];
  }
  final order = [...start];
  final free = [for (final p in freeSlots) order[p]];
  final candidate = List<int>.filled(k, 0);
  final full = [...order];

  double evaluate(List<int> freeSeq) {
    for (var i = 0; i < k; i++) {
      full[freeSlots[i]] = freeSeq[i];
    }
    return routeCost(input, full);
  }

  final watch = Stopwatch()..start();
  var best = evaluate(free);
  var iterations = 0;
  const epsilon = 1e-6;
  bool outOfBudget() =>
      iterations >= input.maxIterations ||
      watch.elapsedMilliseconds >= input.timeBudgetMs;

  var improved = true;
  while (improved && !outOfBudget()) {
    improved = false;

    // 2-opt: inverte free[a..b].
    for (var a = 0; a < k - 1 && !outOfBudget(); a++) {
      for (var b = a + 1; b < k; b++) {
        for (var i = 0; i < k; i++) {
          candidate[i] = (i < a || i > b) ? free[i] : free[a + b - i];
        }
        final cost = evaluate(candidate);
        if (cost < best - epsilon) {
          best = cost;
          free.setAll(0, candidate);
          improved = true;
          iterations++;
        }
      }
    }

    // Or-opt: move bloco de 1–3 paradas para outra posição.
    for (var len = 1; len <= 3 && len < k; len++) {
      for (var a = 0; a + len <= k && !outOfBudget(); a++) {
        final rest = <int>[...free.sublist(0, a), ...free.sublist(a + len)];
        final block = free.sublist(a, a + len);
        for (var dest = 0; dest <= k - len; dest++) {
          if (dest == a) {
            continue;
          }
          var w = 0;
          for (var i = 0; i < dest; i++) {
            candidate[w++] = rest[i];
          }
          for (final s in block) {
            candidate[w++] = s;
          }
          for (var i = dest; i < rest.length; i++) {
            candidate[w++] = rest[i];
          }
          final cost = evaluate(candidate);
          if (cost < best - epsilon) {
            best = cost;
            free.setAll(0, candidate);
            improved = true;
            iterations++;
            // [rest]/[block] mudaram; segue para o próximo bloco.
            break;
          }
        }
      }
    }
  }

  for (var i = 0; i < k; i++) {
    order[freeSlots[i]] = free[i];
  }
  return order;
}

/// Ponto de entrada do isolate. Devolve a ordem (índices de parada).
List<int> solveRoute(RouteSolverInput input) {
  final n = input.stopCount;
  if (n == 0) {
    return const [];
  }
  final greedy = nearestNeighbour(input);
  final current = input.initialOrder.length == n ? input.initialOrder : greedy;
  final start = routeCost(input, current) < routeCost(input, greedy)
      ? current
      : greedy;
  return improveRoute(input, start);
}

/// Monta a ordem inicial: paradas fixas nas suas posições e as livres na
/// ordem em que aparecem em [currentOrder].
List<int> applyFixedSlots(List<int> fixedSlots, List<int> currentOrder) {
  final fixedStops = fixedSlots.where((s) => s >= 0).toSet();
  final freeInOrder = currentOrder
      .where((s) => !fixedStops.contains(s))
      .iterator;
  return [
    for (final slot in fixedSlots)
      if (slot >= 0) slot else (freeInOrder..moveNext()).current,
  ];
}

/// Resolve as restrições em posições fixas. [fixedPosition] e [locked] vêm
/// por parada (índice 0..n-1, ordem atual). `fixedPosition` é processado
/// primeiro e vence `locked`; posições fora do intervalo são ajustadas para
/// a mais próxima válida; se a posição já estiver ocupada, a parada fica
/// livre.
List<int> resolveFixedSlots({
  required int stopCount,
  required List<int?> fixedPosition,
  required List<bool> locked,
}) {
  final slots = List<int>.filled(stopCount, -1);
  final assigned = <int>{};
  for (var i = 0; i < stopCount; i++) {
    final pos = fixedPosition[i];
    if (pos == null) {
      continue;
    }
    final clamped = pos < 0 ? 0 : (pos >= stopCount ? stopCount - 1 : pos);
    if (slots[clamped] < 0) {
      slots[clamped] = i;
      assigned.add(i);
    }
  }
  for (var i = 0; i < stopCount; i++) {
    if (!locked[i] || assigned.contains(i)) {
      continue;
    }
    if (slots[i] < 0) {
      slots[i] = i;
      assigned.add(i);
    }
  }
  return slots;
}
