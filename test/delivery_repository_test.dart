import 'package:flutter_test/flutter_test.dart';
import 'package:rota_max/data/database.dart';
import 'package:rota_max/data/repositories/delivery_repository.dart';
import 'package:rota_max/data/repositories/memory_delivery_repository.dart';
import 'package:rota_max/data/repositories/sqlite_delivery_repository.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/delivery_event.dart';
import 'package:rota_max/models/delivery_route.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

typedef RepoFactory = Future<(DeliveryRepository, Future<void> Function())>
    Function();

/// As mesmas regras valem para o SQLite e para a versão em memória.
void main() {
  sqfliteFfiInit();

  final factories = <String, RepoFactory>{
    'sqlite': () async {
      final db = await AppDatabase.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      return (SqliteDeliveryRepository(db) as DeliveryRepository, db.close);
    },
    'memória': () async =>
        (MemoryDeliveryRepository() as DeliveryRepository, () async {}),
  };

  for (final entry in factories.entries) {
    group(entry.key, () {
      late DeliveryRepository repo;
      late Future<void> Function() close;

      setUp(() async {
        (repo, close) = await entry.value();
      });

      tearDown(() => close());

      Future<Delivery> add(String name) => repo.insert(
            Delivery(customerName: name, address: 'Rua $name', number: '10'),
          );

      test('entrega nova começa pendente com evento de criação', () async {
        final saved = await add('Ana');
        expect(saved.status, DeliveryStatus.pending);
        final events = await repo.eventsFor(saved.id!);
        expect(events, hasLength(1));
        expect(events.single.from, isNull);
        expect(events.single.to, DeliveryStatus.pending);
      });

      test('entregue grava data e evento', () async {
        final saved = await add('Ana');
        final done = await repo.transition(saved.id!, DeliveryStatus.delivered);
        expect(done.status, DeliveryStatus.delivered);
        expect(done.deliveredAt, isNotNull);
        final events = await repo.eventsFor(saved.id!);
        expect(events.last.from, DeliveryStatus.pending);
        expect(events.last.to, DeliveryStatus.delivered);
      });

      test('não entregue exige motivo e conta tentativa', () async {
        final saved = await add('Ana');
        await expectLater(
          repo.transition(saved.id!, DeliveryStatus.failed),
          throwsArgumentError,
        );
        final failed = await repo.transition(
          saved.id!,
          DeliveryStatus.failed,
          reason: FailureReason.recipientAbsent,
          note: 'Portão fechado',
        );
        expect(failed.failureReason, FailureReason.recipientAbsent);
        expect(failed.attempts, 1);
        final events = await repo.eventsFor(saved.id!);
        expect(events.last.note, 'Portão fechado');
        expect(events.last.reason, FailureReason.recipientAbsent);

        final again = await repo.transition(saved.id!, DeliveryStatus.pending);
        expect(again.failureReason, isNull);
        expect(again.attempts, 1);
      });

      test('transição inválida não muda nada nem grava evento', () async {
        final saved = await add('Ana');
        await repo.transition(saved.id!, DeliveryStatus.delivered);
        final before = (await repo.eventsFor(saved.id!)).length;

        await expectLater(
          repo.transition(
            saved.id!,
            DeliveryStatus.failed,
            reason: FailureReason.other,
          ),
          throwsA(isA<InvalidTransition>()),
        );

        final current = await repo.getById(saved.id!);
        expect(current!.status, DeliveryStatus.delivered);
        expect(await repo.eventsFor(saved.id!), hasLength(before));
      });

      test('só uma parada fica "a caminho" por vez', () async {
        final a = await add('Ana');
        final b = await add('Bia');
        await repo.transition(a.id!, DeliveryStatus.inProgress);
        await repo.transition(b.id!, DeliveryStatus.inProgress);
        expect((await repo.getById(a.id!))!.status, DeliveryStatus.pending);
        expect((await repo.getById(b.id!))!.status, DeliveryStatus.inProgress);
      });

      test('update de dados não altera o status', () async {
        final saved = await add('Ana');
        await repo.transition(saved.id!, DeliveryStatus.delivered);
        await repo.update(
          saved.copyWith(
            customerName: 'Ana Paula',
            status: DeliveryStatus.pending,
          ),
        );
        final current = await repo.getById(saved.id!);
        expect(current!.customerName, 'Ana Paula');
        expect(current.status, DeliveryStatus.delivered);
      });

      test('ordem da rota fica salva e reotimizar preserva concluídas',
          () async {
        final a = await add('Ana');
        final b = await add('Bia');
        final c = await add('Caio');
        await repo.saveRouteOrder([c, a, b], estimatedKm: 12);

        var all = await repo.getAll();
        expect(all.map((d) => d.customerName), ['Caio', 'Ana', 'Bia']);
        expect(all.map((d) => d.routeOrder), [1, 2, 3]);
        expect((await repo.activeRoute())!.estimatedKm, 12);

        await repo.transition(c.id!, DeliveryStatus.delivered);
        await repo.saveRouteOrder([b, a]);

        all = await repo.getAll();
        final open = all.where((d) => d.isOpen).map((d) => d.customerName);
        expect(open, ['Bia', 'Ana']);
        final caio = all.firstWhere((d) => d.id == c.id);
        expect(caio.status, DeliveryStatus.delivered);
        expect(caio.routeOrder, 1);
      });

      test('pular manda a parada para o fim da rota', () async {
        final a = await add('Ana');
        final b = await add('Bia');
        final c = await add('Caio');
        await repo.saveRouteOrder([a, b, c]);

        await repo.transition(a.id!, DeliveryStatus.skipped);

        final open = (await repo.getAll()).where((d) => d.isOpen).toList();
        expect(open.map((d) => d.customerName), ['Bia', 'Caio', 'Ana']);
        expect(open.last.status, DeliveryStatus.skipped);
      });

      test('rota com todas as paradas fechadas vira histórico e nasce outra',
          () async {
        final a = await add('Ana');
        await repo.saveRouteOrder([a]);
        final first = await repo.activeRoute();
        await repo.transition(a.id!, DeliveryStatus.delivered);

        final b = await add('Bia');
        await repo.saveRouteOrder([b]);
        final second = await repo.activeRoute();

        expect(second!.id, isNot(first!.id));
        final all = await repo.getAll();
        expect(all.firstWhere((d) => d.id == b.id).routeOrder, 1);
        // Ana ficou na rota antiga.
        expect(all.firstWhere((d) => d.id == a.id).routeOrder, isNull);
      });

      // Mudou de propósito: a exclusão agora é lógica (deleted_at) e o
      // histórico de eventos fica, com um evento de exclusão no fim.
      test('apagar entrega tira da rota e das leituras, mas guarda o histórico',
          () async {
        final a = await add('Ana');
        final b = await add('Bia');
        await repo.saveRouteOrder([a, b]);
        await repo.delete(a.id!);
        final all = await repo.getAll();
        expect(all.map((d) => d.customerName), ['Bia']);
        expect(all.single.routeOrder, isNotNull);
        expect(await repo.getById(a.id!), isNull);
        final events = await repo.eventsFor(a.id!);
        expect(events, hasLength(2));
        expect(events.last.kind, DeliveryEventKind.edit);
        expect(events.last.isDeletion, isTrue);
        await expectLater(
          repo.transition(a.id!, DeliveryStatus.delivered),
          throwsStateError,
        );
        // Excluída não conta como parada aberta na edição manual.
        await repo.reorder([b.id!]);
      });

      test('editar dados grava evento edit com os campos alterados', () async {
        final a = await add('Ana');
        await repo.update(a.copyWith(customerName: 'Ana Paula', number: '22'));
        var events = await repo.eventsFor(a.id!);
        expect(events.last.kind, DeliveryEventKind.edit);
        expect(
          events.last.changedFields,
          containsAll(['customer_name', 'number']),
        );
        expect(events.last.changedFields, hasLength(2));
        expect(events.last.to, DeliveryStatus.pending);

        // Sem mudança, sem evento.
        await repo.update((await repo.getById(a.id!))!);
        events = await repo.eventsFor(a.id!);
        expect(events, hasLength(2));
      });

      group('edição manual', () {
        late Delivery a;
        late Delivery b;
        late Delivery c;

        setUp(() async {
          a = await add('Ana');
          b = await add('Bia');
          c = await add('Caio');
          await repo.saveRouteOrder([a, b, c]);
        });

        Future<List<String>> openNames() async => (await repo.getAll())
            .where((d) => d.isOpen)
            .map((d) => d.customerName)
            .toList();

        test('reorder grava a ordem e marca a rota como editada', () async {
          expect((await repo.activeRoute())!.manuallyEdited, isFalse);
          final route = await repo.reorder([c.id!, a.id!, b.id!]);
          expect(route.manuallyEdited, isTrue);
          expect(await openNames(), ['Caio', 'Ana', 'Bia']);
          expect((await repo.activeRoute())!.manuallyEdited, isTrue);
        });

        test('reorder exige a lista completa e sem repetição', () async {
          await expectLater(
            repo.reorder([c.id!, a.id!]),
            throwsArgumentError,
          );
          await expectLater(
            repo.reorder([c.id!, a.id!, a.id!]),
            throwsArgumentError,
          );
          await expectLater(
            repo.reorder([c.id!, a.id!, b.id!, 999]),
            throwsArgumentError,
          );
          // Nada mudou.
          expect(await openNames(), ['Ana', 'Bia', 'Caio']);
          expect((await repo.activeRoute())!.manuallyEdited, isFalse);
        });

        test('reorder inclui entrega nova que ainda não estava na rota',
            () async {
          final d = await add('Duda');
          await repo.reorder([d.id!, a.id!, b.id!, c.id!]);
          expect(await openNames(), ['Duda', 'Ana', 'Bia', 'Caio']);
        });

        test('reorder mantém concluídas na posição', () async {
          await repo.transition(a.id!, DeliveryStatus.delivered);
          await repo.reorder([c.id!, b.id!]);
          final all = await repo.getAll();
          expect(all.firstWhere((d) => d.id == a.id).routeOrder, 1);
          expect(await openNames(), ['Caio', 'Bia']);
        });

        test('travas e posição fixa ficam salvas', () async {
          await repo.setLock(b.id!, true);
          await repo.setFixedPosition(c.id!, 0);
          var all = await repo.getAll();
          expect(all.firstWhere((d) => d.id == b.id).locked, isTrue);
          expect(all.firstWhere((d) => d.id == c.id).fixedPosition, 0);
          expect(all.firstWhere((d) => d.id == a.id).hasConstraint, isFalse);

          await repo.setLock(b.id!, false);
          await repo.setFixedPosition(c.id!, null);
          all = await repo.getAll();
          expect(all.any((d) => d.hasConstraint), isFalse);
          await expectLater(
            repo.setFixedPosition(a.id!, -1),
            throwsArgumentError,
          );
        });

        test('saveRouteOrder preserva travas e não perde paradas omitidas',
            () async {
          await repo.setLock(b.id!, true);
          await repo.setFixedPosition(c.id!, 2);
          await repo.reorder([b.id!, a.id!, c.id!]);
          // Só Caio e Ana vieram: Bia vai para o fim, sem perder a trava.
          final route = await repo.saveRouteOrder([c, a]);
          expect(route.manuallyEdited, isFalse);
          final open = (await repo.getAll()).where((d) => d.isOpen).toList();
          expect(open.map((d) => d.customerName), ['Caio', 'Ana', 'Bia']);
          expect(open.last.locked, isTrue);
          expect(open.first.fixedPosition, 2);
        });

        test('travar entrega fora da rota coloca no fim', () async {
          final d = await add('Duda');
          await repo.setLock(d.id!, true);
          final all = await repo.getAll();
          expect(all.firstWhere((x) => x.id == d.id).routeOrder, 4);
          expect(all.firstWhere((x) => x.id == d.id).locked, isTrue);
        });

        test('não dá para travar parada concluída', () async {
          await repo.transition(a.id!, DeliveryStatus.delivered);
          await expectLater(repo.setLock(a.id!, true), throwsArgumentError);
        });

        test('ponto final da rota ativa', () async {
          await repo.setEndPoint(-23.6, -46.5);
          var route = await repo.activeRoute();
          expect(route!.hasEndPoint, isTrue);
          expect(route.endLat, -23.6);
          await repo.setEndPoint(null, null);
          route = await repo.activeRoute();
          expect(route!.hasEndPoint, isFalse);
        });
      });

      group('histórico de rotas', () {
        test('lista rotas com contagens e melhor plano', () async {
          final a = await add('Ana');
          final b = await add('Bia');
          final first = await repo.saveRouteOrder([a, b], estimatedKm: 9);
          await repo.savePlan(
            routeId: first.id!,
            stops: 1,
            baselineKm: 5,
            baselineMinutes: 10,
            optimizedKm: 4,
            optimizedMinutes: 8,
          );
          await repo.savePlan(
            routeId: first.id!,
            stops: 2,
            baselineKm: 12,
            baselineMinutes: 26,
            optimizedKm: 9,
            optimizedMinutes: 20,
          );
          await repo.transition(a.id!, DeliveryStatus.delivered);
          await repo.transition(
            b.id!,
            DeliveryStatus.failed,
            reason: FailureReason.closed,
          );
          final c = await add('Caio');
          final second = await repo.saveRouteOrder([c]);
          expect(second.id, isNot(first.id));

          final routes = await repo.listRoutes();
          expect(routes, hasLength(2));
          final old = routes.firstWhere((r) => r.id == first.id);
          expect(old.stops, 2);
          expect(old.delivered, 1);
          expect(old.failed, 1);
          expect(old.estimatedKm, 9);
          expect(old.bestPlan!.stops, 2);
          expect(old.savedKm, closeTo(3, 0.001));
          expect(old.route.status, RouteStatus.completed);
          final current = routes.firstWhere((r) => r.id == second.id);
          expect(current.stops, 1);
          expect(current.bestPlan, isNull);

          final plans = await repo.plansFor(first.id!);
          expect(plans, hasLength(2));
          expect(plans.first.savedMinutes, 2);

          final stops = await repo.stopsOf(first.id!);
          expect(stops.map((d) => d.customerName), ['Ana', 'Bia']);
          expect(stops.map((d) => d.routeOrder), [1, 2]);
        });

        test('reabrir rota conclui a atual e reativa a escolhida', () async {
          final a = await add('Ana');
          final first = await repo.saveRouteOrder([a]);
          await repo.transition(a.id!, DeliveryStatus.delivered);
          final b = await add('Bia');
          final second = await repo.saveRouteOrder([b]);

          final reopened = await repo.openRoute(first.id!);
          expect(reopened.status, RouteStatus.active);
          expect(reopened.completedAt, isNull);
          expect((await repo.activeRoute())!.id, first.id);

          final routes = await repo.listRoutes();
          final old = routes.firstWhere((r) => r.id == second.id);
          expect(old.route.status, RouteStatus.completed);
          expect(
            routes.where((r) => r.route.status == RouteStatus.active),
            hasLength(1),
          );
          // A posição agora vem da rota reaberta.
          final all = await repo.getAll();
          expect(all.firstWhere((d) => d.id == a.id).routeOrder, 1);
          expect(all.firstWhere((d) => d.id == b.id).routeOrder, isNull);

          await expectLater(repo.openRoute(999), throwsStateError);
        });

        test('excluir rota não apaga entregas', () async {
          final a = await add('Ana');
          final b = await add('Bia');
          final route = await repo.saveRouteOrder([a, b]);
          await repo.savePlan(
            routeId: route.id!,
            stops: 2,
            baselineKm: 3,
            baselineMinutes: 6,
            optimizedKm: 2,
            optimizedMinutes: 4,
          );
          await repo.transition(a.id!, DeliveryStatus.delivered);

          await repo.deleteRoute(route.id!);

          expect(await repo.listRoutes(), isEmpty);
          expect(await repo.plansFor(route.id!), isEmpty);
          expect(await repo.activeRoute(), isNull);
          final all = await repo.getAll();
          expect(all, hasLength(2));
          final bia = all.firstWhere((d) => d.id == b.id);
          expect(bia.isOpen, isTrue);
          expect(bia.routeOrder, isNull);
          expect(all.firstWhere((d) => d.id == a.id).isDelivered, isTrue);
        });

        test('excluir rota antiga mantém a ativa intacta', () async {
          final a = await add('Ana');
          final first = await repo.saveRouteOrder([a]);
          await repo.transition(a.id!, DeliveryStatus.delivered);
          final b = await add('Bia');
          final second = await repo.saveRouteOrder([b]);

          await repo.deleteRoute(first.id!);

          expect((await repo.activeRoute())!.id, second.id);
          expect((await repo.getById(b.id!))!.routeOrder, 1);
          expect(await repo.getById(a.id!), isNotNull);
        });
      });
    });
  }

  test('máquina de estados: entregue só volta por "Reabrir"', () {
    expect(DeliveryStatus.delivered.canGoTo(DeliveryStatus.skipped), isFalse);
    expect(
      DeliveryStatus.delivered.canGoTo(DeliveryStatus.inProgress),
      isFalse,
    );
    expect(DeliveryStatus.delivered.canGoTo(DeliveryStatus.pending), isTrue);
    expect(DeliveryStatus.failed.canGoTo(DeliveryStatus.delivered), isFalse);
    expect(DeliveryStatus.failed.canGoTo(DeliveryStatus.pending), isTrue);
  });
}
