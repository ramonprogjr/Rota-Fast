import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rota_max/services/location_service.dart';

import 'helpers/fake_geolocator.dart';

void main() {
  final now = DateTime(2026, 11, 8, 10, 0);

  LocationService serviceWith(FakeGeolocator fake, {List<Duration>? slept}) =>
      LocationService(
        adapter: fake,
        clock: () => now,
        sleep: (duration) async => slept?.add(duration),
      );

  test('ok devolve posição atual sem marcar desatualizada', () async {
    final fake = FakeGeolocator(current: LocationFix(-23.6, -46.5, now));
    final reading = await serviceWith(fake).read();
    expect(reading.status, LocationStatus.ok);
    expect(reading.point!.latitude, -23.6);
    expect(reading.stale, isFalse);
    expect(reading.at, now);
  });

  test('GPS desligado', () async {
    final fake = FakeGeolocator(serviceEnabled: false);
    final reading = await serviceWith(fake).read();
    expect(reading.status, LocationStatus.disabled);
    expect(reading.point, isNull);
    expect(fake.currentCalls, 0);
  });

  test('permissão negada pede de novo e continua negada', () async {
    final fake = FakeGeolocator(permission: LocationPermission.denied);
    final reading = await serviceWith(fake).read();
    expect(reading.status, LocationStatus.denied);
    expect(fake.requestCalls, 1);
  });

  test('permissão concedida no pedido segue para a leitura', () async {
    final fake = FakeGeolocator(
      permission: LocationPermission.denied,
      permissionAfterRequest: LocationPermission.whileInUse,
      current: LocationFix(-23.6, -46.5, now),
    );
    final reading = await serviceWith(fake).read();
    expect(reading.status, LocationStatus.ok);
  });

  test('negada para sempre não pede de novo', () async {
    final fake = FakeGeolocator(permission: LocationPermission.deniedForever);
    final reading = await serviceWith(fake).read();
    expect(reading.status, LocationStatus.deniedForever);
    expect(fake.requestCalls, 0);
  });

  test('timeout usa a última posição conhecida marcada como antiga', () async {
    final old = now.subtract(const Duration(minutes: 7));
    final fake = FakeGeolocator(
      currentError: TimeoutException('demorou'),
      lastKnown: LocationFix(-23.7, -46.6, old),
    );
    final reading = await serviceWith(fake).read();
    expect(reading.status, LocationStatus.timeout);
    expect(reading.point!.latitude, -23.7);
    expect(reading.stale, isTrue);
    expect(reading.age(now), const Duration(minutes: 7));
  });

  test('timeout sem última posição', () async {
    final fake = FakeGeolocator(currentError: TimeoutException('demorou'));
    final reading = await serviceWith(fake).read();
    expect(reading.status, LocationStatus.timeout);
    expect(reading.point, isNull);
  });

  test('fix antigo (> 2 min) vem marcado como desatualizado', () async {
    final fake = FakeGeolocator(
      current: LocationFix(
        -23.6,
        -46.5,
        now.subtract(const Duration(minutes: 3)),
      ),
    );
    final reading = await serviceWith(fake).read();
    expect(reading.status, LocationStatus.ok);
    expect(reading.stale, isTrue);
  });

  test('erro do plugin vira unavailable, sem exceção', () async {
    final fake = FakeGeolocator(currentError: StateError('plugin'));
    final reading = await serviceWith(fake).read();
    expect(reading.status, LocationStatus.unavailable);
  });

  test('serviço desligado durante a leitura vira disabled', () async {
    final fake = FakeGeolocator(
      currentError: const LocationServiceDisabledException(),
    );
    final reading = await serviceWith(fake).read();
    expect(reading.status, LocationStatus.disabled);
  });

  test('current() continua devolvendo só o ponto', () async {
    final fake = FakeGeolocator(current: LocationFix(-23.6, -46.5, now));
    final point = await serviceWith(fake).current();
    expect(point!.longitude, -46.5);
    final none =
        await serviceWith(FakeGeolocator(serviceEnabled: false)).current();
    expect(none, isNull);
  });

  test('retry tenta de novo com espera crescente até conseguir', () async {
    final slept = <Duration>[];
    final fake = FakeGeolocator()
      ..currentQueue.addAll([
        TimeoutException('1'),
        TimeoutException('2'),
        LocationFix(-23.6, -46.5, now),
      ]);
    final reading = await serviceWith(fake, slept: slept).retry();
    expect(reading.status, LocationStatus.ok);
    expect(fake.currentCalls, 3);
    expect(slept, [const Duration(seconds: 1), const Duration(seconds: 2)]);
  });

  test('retry desiste após as tentativas e mantém a última conhecida',
      () async {
    final slept = <Duration>[];
    final fake = FakeGeolocator(
      currentError: TimeoutException('x'),
      lastKnown: LocationFix(-23.7, -46.6, now),
    );
    final reading = await serviceWith(fake, slept: slept).retry(attempts: 3);
    expect(fake.currentCalls, 3);
    expect(slept, hasLength(2));
    expect(reading.status, LocationStatus.timeout);
    expect(reading.stale, isTrue);
  });

  test('retry não insiste com GPS desligado', () async {
    final slept = <Duration>[];
    final fake = FakeGeolocator(serviceEnabled: false);
    final reading = await serviceWith(fake, slept: slept).retry();
    expect(reading.status, LocationStatus.disabled);
    expect(slept, isEmpty);
  });

  test('abre os ajustes pelo adaptador', () async {
    final fake = FakeGeolocator();
    final service = serviceWith(fake);
    expect(await service.openLocationSettings(), isTrue);
    expect(await service.openAppSettings(), isTrue);
    expect(fake.openedLocationSettings, 1);
    expect(fake.openedAppSettings, 1);
  });
}
