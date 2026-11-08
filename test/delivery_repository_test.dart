import 'package:flutter_test/flutter_test.dart';
import 'package:rota_max/data/database.dart';
import 'package:rota_max/data/repositories/delivery_repository.dart';
import 'package:rota_max/data/repositories/memory_delivery_repository.dart';
import 'package:rota_max/data/repositories/sqlite_delivery_repository.dart';
import 'package:rota_max/models/delivery.dart';
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

      test('apagar entrega remove da rota e do histórico', () async {
        final a = await add('Ana');
        final b = await add('Bia');
        await repo.saveRouteOrder([a, b]);
        await repo.delete(a.id!);
        final all = await repo.getAll();
        expect(all.map((d) => d.customerName), ['Bia']);
        expect(await repo.eventsFor(a.id!), isEmpty);
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
