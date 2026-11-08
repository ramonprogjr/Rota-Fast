import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rota_max/core/utils/haversine.dart';
import 'package:rota_max/data/repositories/shift_repository.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/models/shift.dart';
import 'package:rota_max/services/location_service.dart';

/// Rastreia o turno ativo (km por GPS) e publica a situação do GPS em
/// [status]. Falha de GPS nunca derruba o turno nem a rota: o tracker
/// só para de somar km e volta sozinho quando o serviço religa.
class ShiftTracker {
  ShiftTracker(
    this._repo, {
    this._location = const LocationService(),
  });

  final ShiftRepository _repo;
  final LocationService _location;
  StreamSubscription<LocationFix>? _subscription;
  StreamSubscription<bool>? _serviceSubscription;
  TrackPoint? _lastPoint;
  int? _shiftId;
  Timer? _retryTimer;

  /// Espera antes de reabrir o stream depois de um erro sem sinal.
  static const retryDelay = Duration(seconds: 30);

  /// Situação atual do GPS durante o turno (null antes do primeiro sinal).
  final ValueNotifier<LocationReading?> status = ValueNotifier(null);

  /// Última leitura (posição + situação) do rastreio.
  LocationReading? get lastReading => status.value;

  bool get isTracking => _subscription != null;

  GeolocatorAdapter get _adapter => _location.adapter;

  Future<void> attach(Shift shift) async {
    await _cancelPositions();
    await _serviceSubscription?.cancel();
    _serviceSubscription = null;
    _shiftId = shift.id;
    if (shift.id == null) {
      return;
    }
    final existing = await _repo.pointsFor(shift.id!);
    _lastPoint = existing.isEmpty ? null : existing.last;
    _listenServiceStatus();
    await _subscribe();
  }

  Future<void> stop() async {
    _shiftId = null;
    await _cancelPositions();
    await _serviceSubscription?.cancel();
    _serviceSubscription = null;
    _lastPoint = null;
  }

  void dispose() {
    _retryTimer?.cancel();
    _subscription?.cancel();
    _serviceSubscription?.cancel();
    status.dispose();
  }

  Future<void> _cancelPositions() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    await _subscription?.cancel();
    _subscription = null;
  }

  LocationSettings _settings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
        intervalDuration: const Duration(seconds: 15),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Rota Max — turno ativo',
          notificationText:
              'Registrando km do dia. Não force o fechamento do app.',
          enableWakeLock: true,
        ),
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15,
    );
  }

  /// Confere serviço e permissão antes de abrir o stream de posições.
  Future<void> _subscribe() async {
    final shiftId = _shiftId;
    if (shiftId == null || _subscription != null) {
      return;
    }
    final blocked = await _location.checkAccess();
    if (_shiftId != shiftId || _subscription != null) {
      return;
    }
    if (blocked != null) {
      _publishFailure(blocked);
      return;
    }
    try {
      _subscription = _adapter.positionStream(_settings()).listen(
            (fix) => _onPosition(shiftId, fix),
            onError: _onError,
            cancelOnError: true,
          );
    } catch (error) {
      _onError(error);
    }
  }

  void _listenServiceStatus() {
    try {
      _serviceSubscription = _adapter.serviceStatusStream().listen(
        (enabled) {
          if (!enabled) {
            _cancelPositions();
            _publishFailure(LocationStatus.disabled);
          } else if (_shiftId != null && _subscription == null) {
            // Serviço voltou: reabre o rastreio.
            _subscribe();
          }
        },
        onError: (_) {},
      );
    } catch (_) {
      // Sem stream de status (plataforma sem suporte): segue sem ele.
    }
  }

  void _onError(Object error) {
    _subscription = null;
    final LocationStatus reason;
    if (error is LocationServiceDisabledException) {
      reason = LocationStatus.disabled;
    } else if (error is PermissionDeniedException) {
      reason = LocationStatus.denied;
    } else if (error is TimeoutException) {
      reason = LocationStatus.timeout;
    } else {
      reason = LocationStatus.unavailable;
    }
    _publishFailure(reason);
    if (reason == LocationStatus.timeout ||
        reason == LocationStatus.unavailable) {
      _retryTimer?.cancel();
      _retryTimer = Timer(retryDelay, () {
        _retryTimer = null;
        _subscribe();
      });
    }
  }

  void _publishFailure(LocationStatus reason) {
    final last = _lastPoint;
    final previous = status.value;
    final point = previous?.point ??
        (last == null ? null : GeoPoint(last.latitude, last.longitude));
    status.value = LocationReading(
      point: point,
      status: reason,
      at: previous?.at ?? last?.recordedAt,
      stale: point != null,
    );
  }

  /// Tenta reabrir o rastreio (botão "Tentar de novo").
  Future<void> resubscribe() async {
    await _cancelPositions();
    await _subscribe();
  }

  Future<void> _onPosition(int shiftId, LocationFix position) async {
    status.value = LocationReading(
      point: position.point,
      status: LocationStatus.ok,
      at: position.at,
    );
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

  /// Último ponto gravado no turno. Com [maxAge], ignora pontos antigos.
  GeoPoint? lastLocation({Duration? maxAge}) {
    final last = _lastPoint;
    if (last == null) {
      return null;
    }
    if (maxAge != null &&
        DateTime.now().difference(last.recordedAt) > maxAge) {
      return null;
    }
    return GeoPoint(last.latitude, last.longitude);
  }
}
