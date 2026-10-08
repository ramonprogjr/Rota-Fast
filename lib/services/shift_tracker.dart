import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rota_pizza/core/utils/haversine.dart';
import 'package:rota_pizza/data/repositories/shift_repository.dart';
import 'package:rota_pizza/models/geo_result.dart';
import 'package:rota_pizza/models/shift.dart';

class ShiftTracker {
  ShiftTracker(this._repo);

  final ShiftRepository _repo;
  StreamSubscription<Position>? _subscription;
  TrackPoint? _lastPoint;

  Future<void> attach(Shift shift) async {
    await _subscription?.cancel();
    if (shift.id == null) {
      return;
    }
    final existing = await _repo.pointsFor(shift.id!);
    _lastPoint = existing.isEmpty ? null : existing.last;
    final LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
        intervalDuration: const Duration(seconds: 15),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Rota Food — turno ativo',
          notificationText:
              'Registrando km do dia. Não force o fechamento do app.',
          enableWakeLock: true,
        ),
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      );
    }
    _subscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen((position) => _onPosition(shift.id!, position));
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _lastPoint = null;
  }

  Future<void> _onPosition(int shiftId, Position position) async {
    final last = _lastPoint;
    final km = last == null
        ? 0.0
        : haversineKm(
            last.latitude,
            last.longitude,
            position.latitude,
            position.longitude,
          );
    if (last != null && (km < 0.015 || km > 2.5)) {
      return;
    }
    final point = TrackPoint(
      shiftId: shiftId,
      latitude: position.latitude,
      longitude: position.longitude,
      recordedAt: DateTime.now(),
    );
    await _repo.addPoint(point);
    _lastPoint = point;
    if (km >= 0.015) {
      final current = await _repo.openShift();
      if (current != null && current.id == shiftId) {
        await _repo.update(current.copyWith(gpsKm: current.gpsKm + km));
      }
    }
  }

  GeoPoint? lastLocation() {
    final last = _lastPoint;
    if (last == null) {
      return null;
    }
    return GeoPoint(last.latitude, last.longitude);
  }
}
