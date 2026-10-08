import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:rota_pizza/core/utils/haversine.dart';
import 'package:rota_pizza/models/delivery.dart';
import 'package:rota_pizza/models/shift.dart';

/// Turno de demonstração (domingo 30/08/2026) para print / LinkedIn.
class DemoShiftData {
  static const flagKey = 'demo_linkedin_shift_v1';
  static const gpsKm = 62.1;
  static const gasPriceLiter = 6.49;
  static const kmPerLiter = 35.0;
  static const odometerEnd = 24862.0;
  static const lastOilChangeKm = 24120.0;

  static final startedAt = DateTime(2026, 8, 30, 18, 35);
  static final endedAt = DateTime(2026, 8, 30, 23, 8);

  static const originLat = -23.6939;
  static const originLng = -46.5648;

  static List<Delivery> deliveries() {
    return [
      _stop(
        order: '1841',
        name: 'Marina Alves',
        phone: '11987654321',
        street: 'Rua João de Barros',
        number: '412',
        neighborhood: 'Jardim do Mar',
        lat: -23.6860,
        lng: -46.5480,
        value: 10,
        hour: 18,
        minute: 52,
      ),
      _stop(
        order: '1842',
        name: 'Carlos Menezes',
        phone: '11981234567',
        street: 'Avenida Senador Vergueiro',
        number: '890',
        neighborhood: 'Assunção',
        lat: -23.6745,
        lng: -46.5520,
        value: 12,
        hour: 19,
        minute: 18,
      ),
      _stop(
        order: '1843',
        name: 'Fernanda Costa',
        phone: '11979881234',
        street: 'Rua Marechal Deodoro',
        number: '221',
        neighborhood: 'Rudge Ramos',
        lat: -23.6550,
        lng: -46.5720,
        value: 10,
        hour: 19,
        minute: 47,
      ),
      _stop(
        order: '1844',
        name: 'Paulo Henrique',
        phone: '11976543210',
        street: 'Rua das Palmeiras',
        number: '77',
        neighborhood: 'Planalto',
        lat: -23.6810,
        lng: -46.5900,
        value: 15,
        hour: 20,
        minute: 31,
      ),
      _stop(
        order: '1845',
        name: 'Juliana Rocha',
        phone: '11988776655',
        street: 'Rua Marechal Deodoro',
        number: '1104',
        neighborhood: 'Centro',
        lat: -23.6910,
        lng: -46.5655,
        value: 10,
        hour: 21,
        minute: 5,
      ),
      _stop(
        order: '1846',
        name: 'Ricardo Nunes',
        phone: '11983456789',
        street: 'Rua José Bonifácio',
        number: '350',
        neighborhood: 'Nova Petrópolis',
        lat: -23.7080,
        lng: -46.5460,
        value: 14,
        hour: 21,
        minute: 48,
      ),
      _stop(
        order: '1847',
        name: 'Beatriz Lima',
        phone: '11982345678',
        street: 'Rua das Flores',
        number: '58',
        neighborhood: 'Anchieta',
        lat: -23.6690,
        lng: -46.5420,
        value: 12,
        hour: 22,
        minute: 26,
      ),
    ];
  }

  static Delivery _stop({
    required String order,
    required String name,
    required String phone,
    required String street,
    required String number,
    required String neighborhood,
    required double lat,
    required double lng,
    required double value,
    required int hour,
    required int minute,
  }) {
    final delivered = DateTime(2026, 8, 30, hour, minute);
    return Delivery(
      orderNumber: order,
      customerName: name,
      phone: phone,
      address: street,
      number: number,
      neighborhood: neighborhood,
      city: 'São Bernardo do Campo',
      latitude: lat,
      longitude: lng,
      value: value,
      status: DeliveryStatus.done,
      locationConfirmed: true,
      createdAt: delivered.subtract(const Duration(minutes: 25)),
      deliveredAt: delivered,
    );
  }

  static List<TrackPoint> trackPoints(int shiftId) {
    final waypoints = <List<double>>[
      [originLat, originLng],
    ];
    for (final stop in deliveries()) {
      waypoints.add([stop.latitude!, stop.longitude!]);
      waypoints.add([originLat, originLng]);
    }

    final path = <List<double>>[];
    for (var i = 0; i < waypoints.length - 1; i++) {
      path.addAll(_interpolate(waypoints[i], waypoints[i + 1], 0.35));
    }
    path.add(waypoints.last);

    final span = endedAt.difference(startedAt);
    return [
      for (var i = 0; i < path.length; i++)
        TrackPoint(
          shiftId: shiftId,
          latitude: path[i][0],
          longitude: path[i][1],
          recordedAt: startedAt.add(
            Duration(
              milliseconds: path.length == 1
                  ? 0
                  : (span.inMilliseconds * i / (path.length - 1)).round(),
            ),
          ),
        ),
    ];
  }

  static List<List<double>> _interpolate(
    List<double> from,
    List<double> to,
    double stepKm,
  ) {
    final dist = haversineKm(from[0], from[1], to[0], to[1]);
    final steps = max(1, (dist / stepKm).ceil());
    return [
      for (var i = 0; i < steps; i++)
        [
          from[0] + (to[0] - from[0]) * (i / steps),
          from[1] + (to[1] - from[1]) * (i / steps),
        ],
    ];
  }
}

class DemoShiftSeeder {
  static Future<void> seedIfNeeded(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='shifts'",
    );
    if (tables.isEmpty) {
      return;
    }
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM shifts'),
        ) ??
        0;
    if (count > 0) {
      return;
    }

    await db.transaction((txn) async {
      await txn.insert(
        'pizzeria',
        {
          'id': 1,
          'name': 'Forno da Vila',
          'address': 'Rua Marechal Deodoro, 980',
          'city': 'São Bernardo do Campo',
          'latitude': DemoShiftData.originLat,
          'longitude': DemoShiftData.originLng,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      Future<void> put(String key, String value) async {
        await txn.insert(
          'settings',
          {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await put('gas_price_liter', '${DemoShiftData.gasPriceLiter}');
      await put('km_per_liter', '${DemoShiftData.kmPerLiter}');
      await put('odometer_km', '${DemoShiftData.odometerEnd}');
      await put('last_oil_change_km', '${DemoShiftData.lastOilChangeKm}');

      final shiftId = await txn.insert('shifts', {
        'started_at': DemoShiftData.startedAt.toIso8601String(),
        'ended_at': DemoShiftData.endedAt.toIso8601String(),
        'gps_km': DemoShiftData.gpsKm,
        'odometer_start': DemoShiftData.odometerEnd - DemoShiftData.gpsKm,
        'odometer_end': DemoShiftData.odometerEnd,
      });

      for (final point in DemoShiftData.trackPoints(shiftId)) {
        await txn.insert('track_points', point.toMap()..remove('id'));
      }

      for (final delivery in DemoShiftData.deliveries()) {
        await txn.insert('deliveries', delivery.toMap()..remove('id'));
      }

      await put(DemoShiftData.flagKey, '1');
    });
  }
}
