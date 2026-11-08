import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rota_max/core/errors/app_error.dart';
import 'package:rota_max/data/database.dart';
import 'package:rota_max/data/repositories/base_location_repository.dart';
import 'package:rota_max/data/repositories/delivery_repository.dart';
import 'package:rota_max/data/repositories/memory_delivery_repository.dart';
import 'package:rota_max/data/repositories/settings_repository.dart';
import 'package:rota_max/data/repositories/shift_repository.dart';
import 'package:rota_max/data/repositories/sqlite_delivery_repository.dart';
import 'package:rota_max/models/base_location.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/delivery_route.dart';
import 'package:rota_max/models/shift.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_state.dart';

/// Base em (-23.00, -46.5); paradas a cada ~1,1 km para o sul.
/// Cadastradas na ordem Caio, Ana, Bia; a rota otimizada é Ana, Bia, Caio.
List<Delivery> seed() {
  final t = DateTime(2026, 11, 8, 8);
  Delivery stop(int id, String name, double lat, int minute) => Delivery(
        id: id,
        customerName: name,
        address: 'Rua $name',
        number: '1',
        latitude: lat,
        longitude: -46.5,
        createdAt: t.add(Duration(minutes: minute)),
      );
  return [
    stop(1, 'Ana', -23.01, 1),
    stop(2, 'Bia', -23.02, 2),
    stop(3, 'Caio', -23.03, 0),
  ];
}

AppState stateWith(
  DeliveryRepository repo, {
  SettingsRepository? settings,
  ShiftRepository? shifts,
}) {
  return AppState(
    deliveryRepository: repo,
    baseLocationRepository: MemoryBaseLocationRepository(
      BaseLocation(
        name: 'Base',
        address: 'Rua Central, 1',
        latitude: -23.0,
        longitude: -46.5,
      ),
    ),
    settingsRepository: settings ?? MemorySettingsRepository(),
    geocodingService: FakeGeocodingService(),
    shiftRepository: shifts,
  );
}

List<String> names(List<Delivery> list) =>
    list.map((d) => d.customerName).toList();

Delivery byName(AppState state, String name) =>
    state.items.firstWhere((d) => d.customerName == name);

class FlakyRepository extends MemoryDeliveryRepository {
  FlakyRepository([super.seed]);

  bool failSave = false;
  bool failInsert = false;
  bool failReorder = false;

  @override
  Future<Delivery> insert(Delivery delivery) {
    if (failInsert) {
      throw Exception('disco cheio');
    }
    return super.insert(delivery);
  }

  @override
  Future<DeliveryRoute> saveRouteOrder(
    List<Delivery> orderedOpen, {
    double? originLat,
    double? originLng,
    double? estimatedKm,
    int? estimatedMinutes,
  }) {
    if (failSave) {
      throw Exception('disco cheio');
    }
    return super.saveRouteOrder(
      orderedOpen,
      originLat: originLat,
      originLng: originLng,
      estimatedKm: estimatedKm,
      estimatedMinutes: estimatedMinutes,
    );
  }

  @override
  Future<DeliveryRoute> reorder(List<int> openIdsInOrder) {
    if (failReorder) {
      throw Exception('disco cheio');
    }
    return super.reorder(openIdsInOrder);
  }
}

class CountingShifts extends MemoryShiftRepository {
  int starts = 0;

  @override
  Future<Shift> start(Shift shift) async {
    starts++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return super.start(shift);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('AppState: organizar e painel', () {
    test('organizar grava plano e o painel segue a ordem salva', () async {
      final state = stateWith(MemoryDeliveryRepository(seed()));
      await state.load();
      expect(names(state.pending), ['Caio', 'Ana', 'Bia']);

      expect(await state.organizeRoute(), isTrue);
      expect(names(state.pending), ['Ana', 'Bia', 'Caio']);
      expect(state.message, contains('Rota organizada'));
      final route = state.activeRoute!;
      // 3,34 km em linha reta × 1,3 (fator de ruas da estimativa local).
      expect(route.estimatedKm, closeTo(4.34, 0.05));
      expect(route.manuallyEdited, isFalse);

      final plans = await state.plansOfRoute(route.id!);
      expect(plans, hasLength(1));
      expect(plans.single.stops, 3);
      // Cadastro: Caio (3,3) -> Ana (2,2) -> Bia (1,1) = 6,7 km × 1,3.
      expect(plans.single.baselineKm, closeTo(8.67, 0.05));
      expect(plans.single.savedKm, closeTo(4.33, 0.05));

      expect(state.summary.estimatedKm, closeTo(4.34, 0.05));
      expect(state.summary.plannedKm, closeTo(4.34, 0.05));

      // Ordem manual pior: o painel mostra o que vai ser percorrido.
      await state.reorderStops([
        byName(state, 'Caio'),
        byName(state, 'Ana'),
        byName(state, 'Bia'),
      ]);
      expect(state.summary.estimatedKm, closeTo(8.67, 0.05));
      expect(state.summary.pendingCount, 3);
    });

    test('painel conta o que falta a partir da última entrega', () async {
      final state = stateWith(MemoryDeliveryRepository(seed()));
      await state.load();
      await state.organizeRoute();
      await state.markDelivered(byName(state, 'Ana'));
      // De Ana: Bia (1,1) + Caio (1,1).
      expect(state.summary.estimatedKm, closeTo(2.22 * 1.3, 0.05));
      expect(state.summary.doneCount, 1);
    });
  });

  group('AppState: edição manual', () {
    test('reordenar e desfazer', () async {
      final state = stateWith(MemoryDeliveryRepository(seed()));
      await state.load();
      await state.organizeRoute();
      expect(state.canUndo, isTrue); // dá para voltar à ordem de antes

      final ok = await state.reorderStops([
        byName(state, 'Bia'),
        byName(state, 'Ana'),
        byName(state, 'Caio'),
      ]);
      expect(ok, isTrue);
      expect(names(state.pending), ['Bia', 'Ana', 'Caio']);
      expect(state.activeRoute!.manuallyEdited, isTrue);

      expect(await state.undoReorder(), isTrue);
      expect(names(state.pending), ['Ana', 'Bia', 'Caio']);
      expect(state.message, 'Ordem anterior restaurada.');

      expect(await state.undoReorder(), isTrue);
      expect(names(state.pending), ['Caio', 'Ana', 'Bia']);
      expect(state.canUndo, isFalse);
      expect(await state.undoReorder(), isFalse);
    });

    test('desfazer guarda no máximo 20 passos', () async {
      final state = stateWith(MemoryDeliveryRepository(seed()));
      await state.load();
      for (var i = 0; i < 25; i++) {
        final list = state.pending;
        await state.reorderStops([list[1], list[0], list[2]]);
      }
      var undos = 0;
      while (await state.undoReorder()) {
        undos++;
      }
      expect(undos, AppState.maxUndo);
    });

    test('desfazer depois de nova entrega mantém a nova no fim', () async {
      final state = stateWith(MemoryDeliveryRepository(seed()));
      await state.load();
      await state.reorderStops([
        byName(state, 'Bia'),
        byName(state, 'Ana'),
        byName(state, 'Caio'),
      ]);
      await state.saveDelivery(
        Delivery(customerName: 'Duda', address: 'Rua Duda', number: '9'),
      );
      expect(await state.undoReorder(), isTrue);
      expect(names(state.pending), ['Caio', 'Ana', 'Bia', 'Duda']);
    });

    test('edição manual não é desfeita ao entregar', () async {
      final state = stateWith(MemoryDeliveryRepository(seed()));
      await state.load();
      await state.organizeRoute();
      await state.reorderStops([
        byName(state, 'Caio'),
        byName(state, 'Ana'),
        byName(state, 'Bia'),
      ]);

      await state.markDelivered(byName(state, 'Caio'));

      // Otimizando a partir de Caio daria Bia, Ana. A ordem manual fica.
      expect(names(state.pending), ['Ana', 'Bia']);
      expect(state.nextStop!.customerName, 'Ana');
      expect(state.activeRoute!.manuallyEdited, isTrue);
    });

    test('sem edição manual, reotimiza respeitando o alfinete', () async {
      final state = stateWith(MemoryDeliveryRepository(seed()));
      await state.load();
      await state.organizeRoute();
      expect(await state.setFixedPosition(byName(state, 'Caio'), 0), isTrue);
      expect(byName(state, 'Caio').fixedPosition, 0);

      await state.markDelivered(byName(state, 'Ana'));

      expect(names(state.pending), ['Caio', 'Bia']);
      expect(state.activeRoute!.manuallyEdited, isFalse);
    });

    test('recalcular respeita cadeado', () async {
      final state = stateWith(MemoryDeliveryRepository(seed()));
      await state.load();
      // Caio está em 1º (ordem de cadastro) e fica travado ali.
      expect(await state.toggleLock(byName(state, 'Caio')), isTrue);
      expect(byName(state, 'Caio').locked, isTrue);
      await state.organizeRoute();
      // Caio fica em 1º; dali, voltar por Bia e depois Ana é o mais
      // curto (todas na mesma linha: base, Ana, Bia, Caio).
      expect(names(state.pending), ['Caio', 'Bia', 'Ana']);
      expect(state.message, contains('Travas respeitadas'));

      await state.toggleLock(byName(state, 'Caio'));
      await state.organizeRoute();
      expect(names(state.pending), ['Ana', 'Bia', 'Caio']);
    });

    test('alfinete fixa na posição atual e solta no segundo toque', () async {
      final state = stateWith(MemoryDeliveryRepository(seed()));
      await state.load();
      await state.togglePin(byName(state, 'Bia'));
      expect(byName(state, 'Bia').fixedPosition, 2);
      await state.togglePin(byName(state, 'Bia'));
      expect(byName(state, 'Bia').fixedPosition, isNull);
    });
  });

  group('AppState: erros viram mensagem', () {
    test('organizar com falha mantém a ordem e avisa', () async {
      final repo = FlakyRepository(seed());
      final state = stateWith(repo);
      await state.load();
      await state.organizeRoute();
      await state.reorderStops([
        byName(state, 'Bia'),
        byName(state, 'Caio'),
        byName(state, 'Ana'),
      ]);
      final before = ErrorReporter.reported;

      repo.failSave = true;
      final ok = await state.organizeRoute();

      expect(ok, isFalse);
      expect(
        state.message,
        'Não foi possível organizar a rota. A ordem atual foi mantida.',
      );
      expect(names(state.pending), ['Bia', 'Caio', 'Ana']);
      expect(state.busy, isFalse);
      expect(ErrorReporter.reported, greaterThan(before));
    });

    test('falha na reotimização silenciosa não aparece e mantém a ordem',
        () async {
      final repo = FlakyRepository(seed());
      final state = stateWith(repo);
      await state.load();
      await state.organizeRoute();
      repo.failSave = true;
      await state.markDelivered(byName(state, 'Ana'));
      expect(names(state.pending), ['Bia', 'Caio']);
      expect(state.message, isNull);
      expect(state.busy, isFalse);
    });

    test('salvar entrega com falha não lança', () async {
      final repo = FlakyRepository();
      final state = stateWith(repo);
      await state.load();
      repo.failInsert = true;
      final result = await state.saveDelivery(
        Delivery(customerName: 'Ana', address: 'Rua A', number: '1'),
      );
      expect(result.id, isNull);
      expect(state.message, 'Não foi possível salvar a entrega. Tente de novo.');
      expect(state.busy, isFalse);
      expect(state.items, isEmpty);
    });

    test('reordenar com falha volta para a ordem gravada', () async {
      final repo = FlakyRepository(seed());
      final state = stateWith(repo);
      await state.load();
      await state.organizeRoute();
      repo.failReorder = true;
      final ok = await state.reorderStops([
        byName(state, 'Caio'),
        byName(state, 'Bia'),
        byName(state, 'Ana'),
      ]);
      expect(ok, isFalse);
      expect(names(state.pending), ['Ana', 'Bia', 'Caio']);
      expect(state.message, contains('A anterior foi mantida'));
    });

    test('reordenar com lista incompleta vira mensagem', () async {
      final state = stateWith(MemoryDeliveryRepository(seed()));
      await state.load();
      final ok = await state.reorderStops([byName(state, 'Ana')]);
      expect(ok, isFalse);
      expect(state.message, contains('mudou enquanto você editava'));
    });

    test('toque duplo em "Iniciar turno" abre um turno só', () async {
      final shifts = CountingShifts();
      final state = stateWith(MemoryDeliveryRepository(), shifts: shifts);
      await state.load();
      await Future.wait([state.startShift(), state.startShift()]);
      expect(shifts.starts, 1);
      expect(state.activeShift, isNotNull);
      await state.endShift();
      expect(state.activeShift, isNull);
    });
  });

  group('AppState: histórico de rotas e rascunhos', () {
    test('lista, reabre e exclui rotas', () async {
      final state = stateWith(MemoryDeliveryRepository(seed()));
      await state.load();
      await state.organizeRoute();
      final first = state.activeRoute!.id!;
      for (final name in ['Ana', 'Bia', 'Caio']) {
        await state.markDelivered(byName(state, name));
      }
      await state.saveDelivery(
        Delivery(
          customerName: 'Duda',
          address: 'Rua Duda',
          latitude: -23.04,
          longitude: -46.5,
        ),
      );
      await state.organizeRoute();
      final second = state.activeRoute!.id!;
      expect(second, isNot(first));

      await state.loadRoutes();
      expect(state.routes.map((r) => r.id), [second, first]);
      expect(state.routes.last.delivered, 3);
      expect(state.routes.last.savedKm, greaterThan(0));

      expect(await state.openRoute(first), isTrue);
      expect(state.activeRoute!.id, first);
      expect(state.message, 'Rota reaberta.');

      expect(await state.deleteRoute(second), isTrue);
      expect(state.routes.map((r) => r.id), [first]);
      // Duda continua salva, fora de rota.
      expect(byName(state, 'Duda').routeOrder, isNull);
      expect(state.pending.map((d) => d.customerName), ['Duda']);

      expect(await state.openRoute(999), isFalse);
      expect(state.message, 'Essa rota não existe mais.');
    });

    test('rascunhos salvam, carregam e limpam', () async {
      final settings = MemorySettingsRepository();
      final state = stateWith(MemoryDeliveryRepository(), settings: settings);
      expect(await state.loadDraft(AppState.draftAddDelivery), isNull);
      await state.saveDraft(AppState.draftAddDelivery, '{"name":"Ana"}');
      expect(
        await state.loadDraft(AppState.draftAddDelivery),
        '{"name":"Ana"}',
      );
      expect(await state.loadDraft(AppState.draftScan), isNull);

      // Outra instância (app reaberto) com o mesmo armazenamento.
      final reopened = stateWith(MemoryDeliveryRepository(), settings: settings);
      expect(
        await reopened.loadDraft(AppState.draftAddDelivery),
        '{"name":"Ana"}',
      );
      await reopened.clearDraft(AppState.draftAddDelivery);
      expect(await state.loadDraft(AppState.draftAddDelivery), isNull);
    });
  });

  group('persistência no SQLite (app fechado e aberto de novo)', () {
    late Directory dir;
    late String path;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('rota_max_test');
      path = p.join(dir.path, 'rota_max.db');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    Future<Database> openDb() =>
        AppDatabase.open(path, factory: databaseFactoryFfiNoIsolate);

    test('ordem manual, cadeado e alfinete sobrevivem ao reinício', () async {
      var db = await openDb();
      var repo = SqliteDeliveryRepository(db);
      for (final item in seed()) {
        await repo.insert(item.copyWith(id: null));
      }
      var state = stateWith(repo);
      await state.load();
      await state.organizeRoute();
      await state.reorderStops([
        byName(state, 'Caio'),
        byName(state, 'Ana'),
        byName(state, 'Bia'),
      ]);
      await state.toggleLock(byName(state, 'Ana'));
      await state.setFixedPosition(byName(state, 'Bia'), 2);
      await db.close();

      // "Reinício": banco reaberto do arquivo, AppState novo.
      db = await openDb();
      repo = SqliteDeliveryRepository(db);
      state = stateWith(repo);
      await state.load();
      expect(names(state.pending), ['Caio', 'Ana', 'Bia']);
      expect(byName(state, 'Ana').locked, isTrue);
      expect(byName(state, 'Bia').fixedPosition, 2);
      expect(state.activeRoute!.manuallyEdited, isTrue);

      // Entregar não desfaz a ordem manual.
      await state.markDelivered(byName(state, 'Caio'));
      expect(names(state.pending), ['Ana', 'Bia']);

      final plans = await state.plansOfRoute(state.activeRoute!.id!);
      expect(plans, hasLength(1));

      // Excluída some depois do reinício, mas o histórico fica.
      final bia = byName(state, 'Bia');
      await state.deleteDelivery(bia.id!);
      await db.close();
      db = await openDb();
      state = stateWith(SqliteDeliveryRepository(db));
      await state.load();
      expect(names(state.pending), ['Ana']);
      final events = await state.eventsFor(bia);
      expect(events.last.isDeletion, isTrue);
      await db.close();
    });
  });
}
