import 'package:flutter_test/flutter_test.dart';
import 'package:rota_pizza/data/demo_shift_seed.dart';
import 'package:rota_pizza/data/repositories/memory_delivery_repository.dart';
import 'package:rota_pizza/data/repositories/pizzeria_repository.dart';
import 'package:rota_pizza/data/repositories/settings_repository.dart';
import 'package:rota_pizza/data/repositories/shift_repository.dart';
import 'package:rota_pizza/models/pizzeria.dart';
import 'package:rota_pizza/models/shift.dart';
import 'package:rota_pizza/providers/app_state.dart';
import 'package:rota_pizza/services/geocoding_service.dart';

void main() {
  test('demo do domingo tem 7 pizzas e 62,1 km', () {
    final items = DemoShiftData.deliveries();
    expect(items, hasLength(7));
    expect(
      items.fold<double>(0, (sum, item) => sum + (item.value ?? 0)),
      83,
    );
    expect(DemoShiftData.gpsKm, 62.1);
    final track = DemoShiftData.trackPoints(1);
    expect(track.length, greaterThan(20));
    expect(track.first.latitude, closeTo(DemoShiftData.originLat, 0.0001));
  });

  test('relatório conta entregas do turno, não só as de hoje', () async {
    final shifts = MemoryShiftRepository();
    final created = await shifts.start(
      Shift(startedAt: DemoShiftData.startedAt, gpsKm: DemoShiftData.gpsKm),
    );
    await shifts.update(
      created.copyWith(endedAt: DemoShiftData.endedAt, gpsKm: 62.1),
    );

    final state = AppState(
      deliveryRepository: MemoryDeliveryRepository(DemoShiftData.deliveries()),
      pizzeriaRepository: MemoryPizzeriaRepository(
        Pizzeria(
          name: 'Forno da Vila',
          address: 'Rua Marechal Deodoro, 980',
          latitude: DemoShiftData.originLat,
          longitude: DemoShiftData.originLng,
        ),
      ),
      settingsRepository: MemorySettingsRepository(
        vehicle: const VehicleSettings(
          gasPriceLiter: DemoShiftData.gasPriceLiter,
          kmPerLiter: DemoShiftData.kmPerLiter,
          odometerKm: DemoShiftData.odometerEnd,
          lastOilChangeKm: DemoShiftData.lastOilChangeKm,
        ),
      ),
      geocodingService: GeocodingService(cache: MemoryGeocodeCacheRepository()),
      shiftRepository: shifts,
    );
    await state.load();

    final report = await state.latestReport();
    expect(report, isNotNull);
    expect(report!.deliveries, 7);
    expect(report.completed, hasLength(7));
    expect(report.gpsKm, 62.1);
    expect(report.earnings, 83);
    expect(report.oilKmRemaining, 258);
  });
}
