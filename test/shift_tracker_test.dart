import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rota_max/data/repositories/shift_repository.dart';
import 'package:rota_max/models/shift.dart';
import 'package:rota_max/services/location_service.dart';
import 'package:rota_max/services/shift_tracker.dart';

import 'helpers/fake_geolocator.dart';

void main() {
  late MemoryShiftRepository repo;
  late FakeGeolocator fake;
  late ShiftTracker tracker;
  late Shift shift;

  setUp(() async {
    repo = MemoryShiftRepository();
    fake = FakeGeolocator();
    tracker = ShiftTracker(repo, location: LocationService(adapter: fake));
    shift = await repo.start(Shift(startedAt: DateTime.now()));
  });

  tearDown(() => tracker.stop());

  test('posição do stream vira leitura ok e ponto gravado', () async {
    await tracker.attach(shift);
    expect(fake.streamListens, 1);
    fake.positions.add(LocationFix(-23.6, -46.5, DateTime.now()));
    await pumpEventQueue();
    expect(tracker.lastReading!.status, LocationStatus.ok);
    expect(tracker.lastLocation()!.latitude, -23.6);
    expect(await repo.pointsFor(shift.id!), hasLength(1));
  });

  test('erro no stream publica o status e mantém a última posição', () async {
    await tracker.attach(shift);
    fake.positions.add(LocationFix(-23.6, -46.5, DateTime.now()));
    await pumpEventQueue();
    fake.positions.addError(const LocationServiceDisabledException());
    await pumpEventQueue();
    final reading = tracker.lastReading!;
    expect(reading.status, LocationStatus.disabled);
    expect(reading.stale, isTrue);
    expect(reading.point!.latitude, -23.6);
    expect(tracker.isTracking, isFalse);
  });

  test('erro sem sinal agenda nova tentativa', () async {
    await tracker.attach(shift);
    fake.positions.addError(StateError('sem sinal'));
    await pumpEventQueue();
    expect(tracker.lastReading!.status, LocationStatus.unavailable);
    expect(tracker.lastReading!.point, isNull);
    expect(tracker.isTracking, isFalse);
    await tracker.resubscribe();
    expect(tracker.isTracking, isTrue);
    expect(fake.streamListens, 2);
  });

  test('não abre o stream sem permissão', () async {
    fake.permission = LocationPermission.deniedForever;
    await tracker.attach(shift);
    expect(fake.streamListens, 0);
    expect(tracker.lastReading!.status, LocationStatus.deniedForever);
  });

  test('GPS desligado e religado: reabre o rastreio', () async {
    fake.serviceEnabled = false;
    await tracker.attach(shift);
    expect(fake.streamListens, 0);
    expect(tracker.lastReading!.status, LocationStatus.disabled);

    fake.serviceEnabled = true;
    fake.services.add(true);
    await pumpEventQueue();
    expect(fake.streamListens, 1);
    expect(tracker.isTracking, isTrue);

    fake.services.add(false);
    await pumpEventQueue();
    expect(tracker.lastReading!.status, LocationStatus.disabled);
    expect(tracker.isTracking, isFalse);
  });
}
