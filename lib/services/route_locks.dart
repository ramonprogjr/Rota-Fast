import 'package:rota_max/core/utils/haversine.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/geo_result.dart';

/// Km em linha reta percorrendo [stops] na ordem dada, saindo de [start]
/// (se houver) e terminando em [end] (se houver). Paradas sem coordenada
/// são puladas. O(n), sem otimizar nada.
double routeDistanceKm(GeoPoint? start, List<Delivery> stops, {GeoPoint? end}) {
  var km = 0.0;
  var lat = start?.latitude;
  var lng = start?.longitude;
  for (final item in stops) {
    if (!item.hasCoordinates) {
      continue;
    }
    if (lat != null && lng != null) {
      km += haversineKm(lat, lng, item.latitude!, item.longitude!);
    }
    lat = item.latitude;
    lng = item.longitude;
  }
  if (end != null && lat != null && lng != null) {
    km += haversineKm(lat, lng, end.latitude, end.longitude);
  }
  return km;
}

/// Restrição de uma parada ao recalcular a rota. Mesmo significado do
/// `StopConstraint` do motor de rotas:
/// - `locked`: fica no índice em que está hoje entre as abertas;
/// - `fixedPosition`: índice fixo (0 = primeira). Vale mais que `locked`.
typedef StopLock = ({bool locked, int? fixedPosition});

/// Restrições das paradas abertas, lidas de `route_stops`.
Map<int, StopLock> locksOf(Iterable<Delivery> open) => {
  for (final item in open)
    if (item.id != null && item.hasConstraint)
      item.id!: (locked: item.locked, fixedPosition: item.fixedPosition),
};

/// Junta a ordem otimizada com as travas.
///
/// [current] é a ordem atual das paradas abertas; o resultado tem sempre as
/// mesmas paradas de [current], cada uma uma vez. Paradas com posição fixa
/// vão para o índice pedido (limitado ao tamanho da lista); travadas ficam
/// no índice atual; se dois pedirem o mesmo lugar, o segundo vai para o
/// lugar livre mais próximo. As demais preenchem os lugares livres na ordem
/// de [optimized] (as que não estiverem em [optimized] vão no fim, na ordem
/// atual).
List<Delivery> applyLocks(
  List<Delivery> optimized,
  List<Delivery> current,
  Map<int, StopLock> constraints,
) {
  final n = current.length;
  if (n == 0) {
    return const [];
  }
  final slots = List<Delivery?>.filled(n, null);
  final placed = <int?>{};

  int nearestFree(int wanted) {
    final start = wanted.clamp(0, n - 1);
    for (var distance = 0; distance < n; distance++) {
      final after = start + distance;
      if (after < n && slots[after] == null) {
        return after;
      }
      final before = start - distance;
      if (before >= 0 && slots[before] == null) {
        return before;
      }
    }
    return -1;
  }

  void place(Delivery item, int wanted) {
    final slot = nearestFree(wanted);
    if (slot >= 0) {
      slots[slot] = item;
      placed.add(item.id);
    }
  }

  // 1) Posição fixa, pela posição pedida (empate: ordem atual).
  final fixed = <(int, Delivery)>[];
  final locked = <(int, Delivery)>[];
  for (var i = 0; i < n; i++) {
    final item = current[i];
    final rule = constraints[item.id];
    if (rule == null) {
      continue;
    }
    if (rule.fixedPosition != null) {
      fixed.add((i, item));
    } else if (rule.locked) {
      locked.add((i, item));
    }
  }
  fixed.sort((a, b) {
    final pa = constraints[a.$2.id]!.fixedPosition!;
    final pb = constraints[b.$2.id]!.fixedPosition!;
    return pa != pb ? pa.compareTo(pb) : a.$1.compareTo(b.$1);
  });
  for (final (_, item) in fixed) {
    place(item, constraints[item.id]!.fixedPosition!);
  }
  // 2) Travadas, no índice atual.
  for (final (index, item) in locked) {
    place(item, index);
  }

  // 3) O resto, na ordem otimizada.
  final currentIds = {for (final item in current) item.id};
  final rest = <Delivery>[
    for (final item in optimized)
      if (currentIds.contains(item.id) && !placed.contains(item.id)) item,
  ];
  final restIds = {for (final item in rest) item.id};
  rest.addAll(
    current.where(
      (item) => !placed.contains(item.id) && !restIds.contains(item.id),
    ),
  );
  final seen = <int?>{};
  var cursor = 0;
  for (final item in rest) {
    if (!seen.add(item.id)) {
      continue;
    }
    while (cursor < n && slots[cursor] != null) {
      cursor++;
    }
    if (cursor >= n) {
      break;
    }
    slots[cursor] = item;
  }
  return slots.whereType<Delivery>().toList();
}

/// Nova ordem com a parada [deliveryId] tirada de onde está e inserida na
/// posição [targetIndex]. Devolve `null` se a parada não está na lista, a
/// posição é inválida ou nada muda.
List<Delivery>? moveStopTo(
  List<Delivery> stops,
  int deliveryId,
  int targetIndex,
) {
  final from = stops.indexWhere((item) => item.id == deliveryId);
  if (from < 0 || targetIndex < 0 || targetIndex >= stops.length) {
    return null;
  }
  if (from == targetIndex) {
    return null;
  }
  final next = [...stops];
  final item = next.removeAt(from);
  next.insert(targetIndex, item);
  return next;
}
