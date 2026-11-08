import 'package:flutter_test/flutter_test.dart';
import 'package:rota_max/data/database.dart';
import 'package:rota_max/data/repositories/vehicle_repository.dart';
import 'package:rota_max/models/vehicle.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_state.dart';

typedef RepoFactory =
    Future<(VehicleRepository, Future<void> Function())> Function();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final factories = <String, RepoFactory>{
    // O banco novo já vem com "Minha moto" ativa.
    'sqlite': () async {
      final db = await AppDatabase.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      return (SqliteVehicleRepository(db) as VehicleRepository, db.close);
    },
    'memória': () async =>
        (MemoryVehicleRepository() as VehicleRepository, () async {}),
  };

  for (final entry in factories.entries) {
    group(entry.key, () {
      late VehicleRepository repo;
      late Future<void> Function() close;

      setUp(() async {
        (repo, close) = await entry.value();
      });

      tearDown(() => close());

      test('começa com uma moto ativa', () async {
        final active = await repo.active();
        expect(active, isNotNull);
        expect(active!.type, VehicleType.motorcycle);
        expect(active.oilIntervalKm, 1000);
      });

      test('veículo novo não rouba o ativo; ativar deixa só um', () async {
        final van = await repo.save(
          Vehicle(name: 'Van', type: VehicleType.van),
        );
        expect(van.isActive, isFalse);
        expect(van.fuelType, FuelType.diesel);
        expect(van.oilIntervalKm, 10000);

        await repo.activate(van.id!);
        final all = await repo.getAll();
        expect(all.where((v) => v.isActive), hasLength(1));
        expect((await repo.active())!.id, van.id);
      });

      test('km do turno somam no odômetro', () async {
        final moto = (await repo.active())!;
        await repo.addKm(moto.id!, 42.5);
        await repo.addKm(moto.id!, -3); // ignorado
        expect((await repo.active())!.odometerKm, moto.odometerKm + 42.5);
      });

      test('troca de óleo zera a contagem e fica no histórico', () async {
        final moto = (await repo.active())!;
        await repo.save(moto.copyWith(odometerKm: 1950));
        expect((await repo.active())!.oilWarning, isTrue);

        await repo.registerOilChange(moto.id!, 1950);
        final after = (await repo.active())!;
        expect(after.kmSinceOil, 0);
        expect(after.oilRemainingKm, 1000);
        expect(after.oilWarning, isFalse);
        expect(await repo.oilChanges(moto.id!), hasLength(1));
      });

      test('apagar o ativo passa o ativo para outro', () async {
        final moto = (await repo.active())!;
        final carro = await repo.save(
          Vehicle(name: 'Carro', type: VehicleType.car),
        );
        await repo.delete(moto.id!);
        final active = await repo.active();
        expect(active!.id, carro.id);
        expect(active.isActive, isTrue);
      });
    });
  }

  test('turno leva os km para o veículo com que começou', () async {
    final vehicles = MemoryVehicleRepository([
      Vehicle(name: 'Moto', type: VehicleType.motorcycle, isActive: true),
      Vehicle(name: 'Van', type: VehicleType.van, odometerKm: 1000),
    ]);
    final state = buildTestState(vehicles: vehicles);
    await state.load();
    final moto = state.vehicle;

    await state.startShift();
    // Troca o ativo no meio do turno.
    await state.activateVehicle(
      state.vehicles.firstWhere((v) => v.name == 'Van'),
    );
    await state.endShift(odometerEnd: 37);

    final all = await vehicles.getAll();
    expect(all.firstWhere((v) => v.id == moto.id).odometerKm, 37);
    expect(all.firstWhere((v) => v.name == 'Van').odometerKm, 1000);
  });
}
