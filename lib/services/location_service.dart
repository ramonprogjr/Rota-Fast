import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:rota_max/models/geo_result.dart';

/// Situação da última tentativa de ler o GPS.
enum LocationStatus { ok, disabled, denied, deniedForever, timeout, unavailable }

/// Resultado de uma leitura de posição. Falha de GPS nunca vira exceção:
/// vem como [status] e, quando der, com a última posição conhecida
/// ([stale] = true).
class LocationReading {
  const LocationReading({
    this.point,
    required this.status,
    this.at,
    this.stale = false,
  });

  final GeoPoint? point;
  final LocationStatus status;

  /// Quando a posição foi obtida pelo aparelho.
  final DateTime? at;

  /// Posição antiga ou de fallback (não é uma leitura nova).
  final bool stale;

  bool get isOk => status == LocationStatus.ok;
  bool get hasPoint => point != null;

  /// Idade da posição em relação a [now].
  Duration? age([DateTime? now]) =>
      at == null ? null : (now ?? DateTime.now()).difference(at!);

  @override
  String toString() =>
      'LocationReading($status, ${point?.latitude},${point?.longitude}, '
      'at: $at, stale: $stale)';
}

/// Uma posição do aparelho, sem depender da classe Position do plugin
/// (facilita os testes).
class LocationFix {
  const LocationFix(this.latitude, this.longitude, this.at);

  final double latitude;
  final double longitude;
  final DateTime at;

  GeoPoint get point => GeoPoint(latitude, longitude);
}

/// Ponte para o plugin Geolocator. Os testes implementam esta classe
/// com um fake; o app usa a implementação padrão.
class GeolocatorAdapter {
  const GeolocatorAdapter();

  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  Future<LocationFix> currentPosition(Duration timeLimit) async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: timeLimit,
      ),
    );
    return _fix(position);
  }

  Future<LocationFix?> lastKnownPosition() async {
    final position = await Geolocator.getLastKnownPosition();
    return position == null ? null : _fix(position);
  }

  Stream<LocationFix> positionStream(LocationSettings settings) =>
      Geolocator.getPositionStream(locationSettings: settings).map(_fix);

  /// true quando o serviço de localização volta a ficar ligado.
  Stream<bool> serviceStatusStream() => Geolocator.getServiceStatusStream()
      .map((status) => status == ServiceStatus.enabled);

  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  static LocationFix _fix(Position position) =>
      LocationFix(position.latitude, position.longitude, position.timestamp);
}

DateTime _systemNow() => DateTime.now();

Future<void> _systemSleep(Duration duration) => Future.delayed(duration);

class LocationService {
  const LocationService({
    this.adapter = const GeolocatorAdapter(),
    this.clock = _systemNow,
    this.sleep = _systemSleep,
  });

  final GeolocatorAdapter adapter;
  final DateTime Function() clock;
  final Future<void> Function(Duration) sleep;

  /// Posição com mais de 2 min é considerada desatualizada.
  static const staleAfter = Duration(minutes: 2);
  static const defaultTimeout = Duration(seconds: 8);

  /// Atalho antigo: só a coordenada (null quando não deu para ler).
  Future<GeoPoint?> current() async => (await read()).point;

  /// Confere serviço ligado e permissão (pedindo, se [request]).
  /// Retorna null quando está tudo liberado; senão, o motivo.
  Future<LocationStatus?> checkAccess({bool request = true}) async {
    try {
      if (!await adapter.isServiceEnabled()) {
        return LocationStatus.disabled;
      }
      var permission = await adapter.checkPermission();
      if (permission == LocationPermission.denied && request) {
        permission = await adapter.requestPermission();
      }
      switch (permission) {
        case LocationPermission.deniedForever:
          return LocationStatus.deniedForever;
        case LocationPermission.denied:
        case LocationPermission.unableToDetermine:
          return LocationStatus.denied;
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          return null;
      }
    } catch (_) {
      return LocationStatus.unavailable;
    }
  }

  /// Lê a posição atual. Se o GPS demorar ou falhar, devolve a última
  /// posição conhecida marcada como desatualizada.
  Future<LocationReading> read({Duration timeout = defaultTimeout}) async {
    final blocked = await checkAccess();
    if (blocked != null) {
      return LocationReading(status: blocked);
    }
    LocationStatus failure;
    try {
      final fix = await adapter.currentPosition(timeout).timeout(
            // Margem extra caso o plugin ignore o timeLimit.
            timeout + const Duration(seconds: 2),
          );
      final age = clock().difference(fix.at);
      return LocationReading(
        point: fix.point,
        status: LocationStatus.ok,
        at: fix.at,
        stale: age > staleAfter,
      );
    } on TimeoutException {
      failure = LocationStatus.timeout;
    } on LocationServiceDisabledException {
      return const LocationReading(status: LocationStatus.disabled);
    } on PermissionDeniedException {
      return const LocationReading(status: LocationStatus.denied);
    } catch (_) {
      failure = LocationStatus.unavailable;
    }
    return _withLastKnown(failure);
  }

  /// Tenta [attempts] vezes, esperando mais a cada falha (1 s, 2 s, 4 s...).
  /// GPS desligado ou permissão negada não adiantam repetir.
  Future<LocationReading> retry({
    int attempts = 3,
    Duration initialDelay = const Duration(seconds: 1),
    Duration timeout = defaultTimeout,
  }) async {
    var delay = initialDelay;
    LocationReading reading = const LocationReading(
      status: LocationStatus.unavailable,
    );
    for (var i = 0; i < attempts; i++) {
      reading = await read(timeout: timeout);
      if (!_worthRetrying(reading.status)) {
        return reading;
      }
      if (i < attempts - 1) {
        await sleep(delay);
        delay *= 2;
      }
    }
    return reading;
  }

  Future<bool> openLocationSettings() async {
    try {
      return await adapter.openLocationSettings();
    } catch (_) {
      return false;
    }
  }

  Future<bool> openAppSettings() async {
    try {
      return await adapter.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  static bool _worthRetrying(LocationStatus status) =>
      status == LocationStatus.timeout || status == LocationStatus.unavailable;

  Future<LocationReading> _withLastKnown(LocationStatus failure) async {
    try {
      final last = await adapter.lastKnownPosition();
      if (last != null) {
        return LocationReading(
          point: last.point,
          status: failure,
          at: last.at,
          stale: true,
        );
      }
    } catch (_) {
      // Sem última posição: segue só com o motivo.
    }
    return LocationReading(status: failure);
  }
}
