import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:rota_max/services/location_service.dart';

/// Geolocator falso: nada de GPS nem plugin nos testes.
class FakeGeolocator implements GeolocatorAdapter {
  FakeGeolocator({
    this.serviceEnabled = true,
    this.permission = LocationPermission.whileInUse,
    this.permissionAfterRequest,
    this.current,
    this.currentError,
    this.lastKnown,
  });

  bool serviceEnabled;
  LocationPermission permission;
  LocationPermission? permissionAfterRequest;
  LocationFix? current;
  Object? currentError;
  LocationFix? lastKnown;

  /// Respostas em sequência para currentPosition (sobrepõe [current]).
  final List<Object> currentQueue = [];

  int currentCalls = 0;
  int requestCalls = 0;
  int streamListens = 0;
  int openedLocationSettings = 0;
  int openedAppSettings = 0;

  final positions = StreamController<LocationFix>.broadcast();
  final services = StreamController<bool>.broadcast();

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requestCalls++;
    permission = permissionAfterRequest ?? permission;
    return permission;
  }

  @override
  Future<LocationFix> currentPosition(Duration timeLimit) async {
    currentCalls++;
    if (currentQueue.isNotEmpty) {
      final next = currentQueue.removeAt(0);
      if (next is LocationFix) {
        return next;
      }
      throw next;
    }
    if (currentError != null) {
      throw currentError!;
    }
    if (current == null) {
      throw TimeoutException('sem fix');
    }
    return current!;
  }

  @override
  Future<LocationFix?> lastKnownPosition() async => lastKnown;

  @override
  Stream<LocationFix> positionStream(LocationSettings settings) {
    streamListens++;
    return positions.stream;
  }

  @override
  Stream<bool> serviceStatusStream() => services.stream;

  @override
  Future<bool> openLocationSettings() async {
    openedLocationSettings++;
    return true;
  }

  @override
  Future<bool> openAppSettings() async {
    openedAppSettings++;
    return true;
  }
}
