import 'package:flutter_test/flutter_test.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/services/route_locks.dart';

void main() {
  Delivery stop(int id, {bool locked = false, int? fixed, double? lat}) =>
      Delivery(
        id: id,
        customerName: 'C$id',
        address: 'Rua $id',
        locked: locked,
        fixedPosition: fixed,
        latitude: lat,
        longitude: lat == null ? null : -46.5,
      );

  List<int?> ids(List<Delivery> list) => list.map((d) => d.id).toList();

  final current = [stop(1), stop(2), stop(3), stop(4), stop(5)];
  final optimized = [stop(5), stop(4), stop(3), stop(2), stop(1)];

  test('sem travas, devolve a ordem otimizada', () {
    expect(ids(applyLocks(optimized, current, const {})), [5, 4, 3, 2, 1]);
  });

  test('travada fica no índice atual', () {
    final result = applyLocks(optimized, current, {
      2: (locked: true, fixedPosition: null),
    });
    expect(ids(result), [5, 2, 4, 3, 1]);
  });

  test('posição fixa vai para o índice pedido', () {
    final result = applyLocks(optimized, current, {
      1: (locked: false, fixedPosition: 0),
      3: (locked: false, fixedPosition: 4),
    });
    expect(ids(result), [1, 5, 4, 2, 3]);
  });

  test('posição fixa vale mais que trava', () {
    final result = applyLocks(optimized, current, {
      2: (locked: true, fixedPosition: 4),
    });
    expect(ids(result), [5, 4, 3, 1, 2]);
  });

  test('posição além do fim vai para o último lugar', () {
    final result = applyLocks(optimized, current, {
      5: (locked: false, fixedPosition: 99),
    });
    expect(ids(result), [4, 3, 2, 1, 5]);
  });

  test('conflito: o segundo vai para o lugar livre mais próximo', () {
    final result = applyLocks(optimized, current, {
      1: (locked: false, fixedPosition: 2),
      4: (locked: false, fixedPosition: 2),
      3: (locked: true, fixedPosition: null),
    });
    // 1 e 4 pedem o índice 2 (empate: 1 vem antes na ordem atual) e 3 está
    // travado no índice 2 também.
    expect(result, hasLength(5));
    expect(result.toSet(), hasLength(5));
    expect(result[2].id, 1);
    expect({result[1].id, result[3].id}, {4, 3});
  });

  test('parada que o otimizador não devolveu não some', () {
    final result = applyLocks([stop(3), stop(1)], current, {
      2: (locked: true, fixedPosition: null),
    });
    expect(ids(result), [3, 2, 1, 4, 5]);
  });

  test('ignora paradas do otimizado que não estão na lista atual', () {
    final result = applyLocks([stop(9), ...optimized], current, const {});
    expect(ids(result), [5, 4, 3, 2, 1]);
  });

  test('lista vazia', () {
    expect(applyLocks(optimized, const [], const {}), isEmpty);
  });

  test('locksOf lê trava e alfinete das entregas', () {
    final locks = locksOf([stop(1, locked: true), stop(2), stop(3, fixed: 0)]);
    expect(locks.keys, [1, 3]);
    expect(locks[1]!.locked, isTrue);
    expect(locks[3]!.fixedPosition, 0);
  });

  test('routeDistanceKm anda na ordem dada e pula sem coordenada', () {
    const origin = GeoPoint(-23.0, -46.5);
    final a = stop(1, lat: -23.01);
    final b = stop(2);
    final c = stop(3, lat: -23.02);
    final straight = routeDistanceKm(origin, [a, b, c]);
    expect(straight, closeTo(2.22, 0.05));
    final back = routeDistanceKm(origin, [c, a]);
    expect(back, greaterThan(straight));
    expect(routeDistanceKm(null, [a, c]), closeTo(1.11, 0.05));
    expect(
      routeDistanceKm(origin, [a], end: origin),
      closeTo(2.22, 0.05),
    );
  });
}
