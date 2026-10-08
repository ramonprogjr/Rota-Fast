import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:rota_pizza/core/constants/app_constants.dart';
import 'package:rota_pizza/core/utils/address_parser.dart';
import 'package:rota_pizza/core/utils/haversine.dart';
import 'package:rota_pizza/core/utils/maintenance.dart';
import 'package:rota_pizza/data/repositories/delivery_repository.dart';
import 'package:rota_pizza/data/repositories/pizzeria_repository.dart';
import 'package:rota_pizza/data/repositories/settings_repository.dart';
import 'package:rota_pizza/data/repositories/shift_repository.dart';
import 'package:rota_pizza/models/delivery.dart';
import 'package:rota_pizza/models/geo_result.dart';
import 'package:rota_pizza/models/pizzeria.dart';
import 'package:rota_pizza/models/shift.dart';
import 'package:rota_pizza/models/shift_summary.dart';
import 'package:rota_pizza/services/geocoding_service.dart';
import 'package:rota_pizza/services/location_service.dart';
import 'package:rota_pizza/services/maps_service.dart';
import 'package:rota_pizza/services/route_optimizer.dart';
import 'package:rota_pizza/services/shift_tracker.dart';

class BatchImportResult {
  const BatchImportResult({
    required this.saved,
    required this.located,
    required this.failedLocate,
    this.duplicates = 0,
  });

  final int saved;
  final int located;
  final int failedLocate;
  final int duplicates;
}

class AppState extends ChangeNotifier {
  AppState({
    required DeliveryRepository deliveryRepository,
    required PizzeriaRepository pizzeriaRepository,
    required SettingsRepository settingsRepository,
    required GeocodingService geocodingService,
    LocationService locationService = const LocationService(),
    MapsService mapsService = const MapsService(),
    this._optimizer = const RouteOptimizer(),
    ShiftRepository? shiftRepository,
  })  : _deliveries = deliveryRepository,
        _pizzerias = pizzeriaRepository,
        _settings = settingsRepository,
        _geocoding = geocodingService,
        _shifts = shiftRepository ?? MemoryShiftRepository(),
        _location = locationService,
        maps = mapsService {
    _tracker = ShiftTracker(_shifts);
  }

  final DeliveryRepository _deliveries;
  final PizzeriaRepository _pizzerias;
  final SettingsRepository _settings;
  final GeocodingService _geocoding;
  final ShiftRepository _shifts;
  final LocationService _location;
  final MapsService maps;
  final RouteOptimizer _optimizer;
  late final ShiftTracker _tracker;

  bool loading = true;
  bool busy = false;
  String? message;
  List<Delivery> items = [];
  Pizzeria pizzeria = Pizzeria();
  bool motorcycleMode = true;
  Shift? activeShift;
  Shift? lastEndedShift;
  VehicleSettings vehicle = const VehicleSettings();

  List<Delivery> get pending {
    final list = items.where((item) => item.isPending).toList();
    list.sort((a, b) {
      final ao = a.routeOrder ?? 9999;
      final bo = b.routeOrder ?? 9999;
      final byOrder = ao.compareTo(bo);
      if (byOrder != 0) {
        return byOrder;
      }
      return a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  List<Delivery> get doneToday {
    final now = DateTime.now();
    return items.where((item) {
      if (item.isPending) {
        return false;
      }
      final at = item.deliveredAt ?? item.createdAt;
      return at.year == now.year && at.month == now.month && at.day == now.day;
    }).toList()
      ..sort((a, b) => (b.deliveredAt ?? b.createdAt)
          .compareTo(a.deliveredAt ?? a.createdAt));
  }

  GeoPoint? get originPoint {
    if (pizzeria.hasCoordinates) {
      return GeoPoint(pizzeria.latitude!, pizzeria.longitude!);
    }
    return null;
  }

  ShiftSummary get summary => _optimizer.summarize(
        origin: originPoint,
        all: items,
      );

  bool get oilWarning => MaintenanceCalc.shouldWarnOil(
        odometerKm: vehicle.odometerKm,
        lastOilChangeKm: vehicle.lastOilChangeKm,
      );

  NumberFormat get money =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  Future<void> load() async {
    loading = true;
    notifyListeners();
    items = await _deliveries.getAll();
    pizzeria = await _pizzerias.get();
    motorcycleMode = await _settings.motorcycleMode();
    vehicle = await _settings.vehicle();
    activeShift = await _shifts.openShift();
    lastEndedShift = activeShift ?? await _shifts.latestEnded();
    if (activeShift != null) {
      await _tracker.attach(activeShift!);
    }
    loading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    items = await _deliveries.getAll();
    pizzeria = await _pizzerias.get();
    motorcycleMode = await _settings.motorcycleMode();
    vehicle = await _settings.vehicle();
    activeShift = await _shifts.openShift();
    lastEndedShift = activeShift ?? await _shifts.latestEnded();
    notifyListeners();
  }

  bool isDuplicateAddress(String address, {int? ignoreId}) {
    final needle = AddressParser.normalizeAddress(address);
    if (needle.isEmpty) {
      return false;
    }
    return pending.any((item) {
      if (ignoreId != null && item.id == ignoreId) {
        return false;
      }
      return AddressParser.normalizeAddress(item.fullAddress) == needle;
    });
  }

  Future<List<GeoResult>> searchAddress({
    required String query,
    String? street,
    String? number,
    String? neighborhood,
    String? city,
  }) async {
    busy = true;
    message = null;
    notifyListeners();
    try {
      final results = await _geocoding.search(
        query,
        street: street,
        number: number,
        neighborhood: neighborhood,
        city: city,
      );
      if (results.isEmpty) {
        message =
            'Endereço não encontrado. Ajuste rua, número, bairro e cidade.';
      }
      return results;
    } on GeocodingException catch (error) {
      message = error.message;
      return [];
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> confirmLocation(Delivery delivery, GeoResult result) async {
    final updated = delivery.copyWith(
      latitude: result.latitude,
      longitude: result.longitude,
      locationConfirmed: true,
    );
    await _deliveries.update(updated);
    await _geocoding.cacheConfirmed(delivery.fullAddress, result);
    await refresh();
  }

  Future<Delivery> saveDelivery(Delivery delivery, {bool locate = false}) async {
    busy = true;
    message = null;
    notifyListeners();
    var saved = delivery;
    try {
      if (isDuplicateAddress(saved.fullAddress, ignoreId: saved.id)) {
        message = 'Esse endereço já está nas pendentes.';
      }
      if (locate && !saved.hasCoordinates) {
        final results = await _geocoding.search(saved.fullAddress);
        if (results.isNotEmpty) {
          saved = saved.copyWith(
            latitude: results.first.latitude,
            longitude: results.first.longitude,
            locationConfirmed: false,
          );
        }
      }
      if (saved.id == null) {
        saved = await _deliveries.insert(saved);
      } else {
        await _deliveries.update(saved);
      }
      await refresh();
      return saved;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> deleteDelivery(int id) async {
    await _deliveries.delete(id);
    await refresh();
  }

  Future<void> markDelivered(Delivery delivery) async {
    final done = delivery.copyWith(
      status: DeliveryStatus.done,
      deliveredAt: DateTime.now(),
    );
    await _deliveries.update(done);
    await refresh();
    final origin = done.hasCoordinates
        ? GeoPoint(done.latitude!, done.longitude!)
        : originPoint;
    if (origin != null && pending.isNotEmpty) {
      await organizeRoute(originOverride: origin, silent: true);
    }
  }

  Future<void> reopen(Delivery delivery) async {
    await _deliveries.update(
      delivery.copyWith(
        status: DeliveryStatus.pending,
        clearDeliveredAt: true,
        clearRouteOrder: true,
      ),
    );
    await refresh();
  }

  Future<bool> organizeRoute({
    GeoPoint? originOverride,
    bool useGps = false,
    bool silent = false,
  }) async {
    busy = true;
    if (!silent) {
      message = null;
    }
    notifyListeners();
    try {
      GeoPoint? origin = originOverride;
      if (origin == null && useGps) {
        origin = await _location.current();
      }
      origin ??= originPoint;
      if (origin == null) {
        message =
            'Cadastre o estabelecimento (com endereço localizado) para calcular a rota.';
        notifyListeners();
        return false;
      }
      final currentPending = pending;
      if (currentPending.isEmpty) {
        message = 'Não há entregas pendentes.';
        notifyListeners();
        return false;
      }
      final route = _optimizer.optimize(
        origin: origin,
        pending: currentPending,
      );
      await _deliveries.replaceRouteOrder(route.ordered);
      await refresh();
      if (!silent) {
        final km = formatKm(route.totalKm);
        final time = formatDuration(route.estimatedDuration);
        final skipped = route.skippedWithoutCoords.length;
        final unconfirmed = currentPending
            .where((item) => item.hasCoordinates && !item.locationConfirmed)
            .length;
        var text = skipped == 0
            ? 'Rota organizada: $km · $time (estimativa em linha reta).'
            : 'Rota organizada: $km · $time. $skipped endereço(s) sem localização ficaram no fim.';
        if (unconfirmed > 0) {
          text += ' $unconfirmed ponto(s) ainda sem confirmação no mapa.';
        }
        message = text;
      }
      return true;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> recalculateFrom(Delivery delivery) async {
    if (!delivery.hasCoordinates) {
      message = 'Essa entrega ainda não tem coordenadas.';
      notifyListeners();
      return;
    }
    await organizeRoute(
      originOverride: GeoPoint(delivery.latitude!, delivery.longitude!),
    );
  }

  Future<GeoResult?> locateAddress(String query) async {
    final results = await searchAddress(query: query);
    if (results.isEmpty) {
      return null;
    }
    return results.first;
  }

  Future<void> savePizzeria(Pizzeria next, {bool locate = true}) async {
    busy = true;
    message = null;
    notifyListeners();
    var saved = next;
    try {
      if (locate && saved.address.trim().isNotEmpty && !saved.hasCoordinates) {
        final results = await _geocoding.search(saved.fullAddress);
        if (results.isNotEmpty) {
          saved = saved.copyWith(
            latitude: results.first.latitude,
            longitude: results.first.longitude,
          );
        } else {
          message ??=
              'Não achei o estabelecimento nesse endereço. Confirme no mapa ou ajuste o texto.';
        }
      }
      await _pizzerias.save(saved);
      await refresh();
      if (saved.hasCoordinates) {
        message = 'Estabelecimento salvo.';
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> setMotorcycleMode(bool enabled) async {
    await _settings.setMotorcycleMode(enabled);
    motorcycleMode = enabled;
    notifyListeners();
  }

  Future<void> saveVehicle(VehicleSettings next) async {
    await _settings.saveVehicle(next);
    vehicle = next;
    notifyListeners();
  }

  Future<BatchImportResult> importParsed(
    List<ParsedDelivery> parsed, {
    bool locate = false,
  }) async {
    busy = true;
    message = null;
    notifyListeners();
    var saved = 0;
    var located = 0;
    var failed = 0;
    var duplicates = 0;
    try {
      for (final item in parsed) {
        var delivery = Delivery(
          orderNumber: item.orderNumber,
          customerName: item.customerName ?? 'Cliente',
          phone: item.phone,
          address: item.address,
          number: item.number,
          neighborhood: item.neighborhood,
          city: item.city,
          value: item.value,
        );
        if (isDuplicateAddress(delivery.fullAddress)) {
          duplicates++;
          continue;
        }
        if (locate) {
          try {
            final results = await _geocoding.search(delivery.fullAddress);
            if (results.isNotEmpty) {
              delivery = delivery.copyWith(
                latitude: results.first.latitude,
                longitude: results.first.longitude,
                locationConfirmed: false,
              );
              located++;
            } else {
              failed++;
            }
          } on GeocodingException {
            failed++;
          }
        }
        await _deliveries.insert(delivery);
        saved++;
      }
      await refresh();
      message =
          '$saved entrega(s) adicionada(s). $located localizada(s), $failed sem coordenada, $duplicates duplicata(s). Confirme os pontos no mapa.';
      return BatchImportResult(
        saved: saved,
        located: located,
        failedLocate: failed,
        duplicates: duplicates,
      );
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> startShift() async {
    if (activeShift != null) {
      return;
    }
    final shift = await _shifts.start(
      Shift(
        startedAt: DateTime.now(),
        odometerStart: vehicle.odometerKm,
      ),
    );
    activeShift = shift;
    await _tracker.attach(shift);
    notifyListeners();
  }

  Future<Shift?> endShift({double? odometerEnd}) async {
    final current = activeShift;
    if (current == null) {
      return null;
    }
    await _tracker.stop();
    var gpsKm = current.gpsKm;
    final points = await _shifts.pointsFor(current.id!);
    if (points.length >= 2) {
      gpsKm = 0;
      for (var i = 1; i < points.length; i++) {
        final step = haversineKm(
          points[i - 1].latitude,
          points[i - 1].longitude,
          points[i].latitude,
          points[i].longitude,
        );
        if (step >= 0.015 && step <= 2.5) {
          gpsKm += step;
        }
      }
    }
    final ended = current.copyWith(
      endedAt: DateTime.now(),
      gpsKm: gpsKm,
      odometerEnd: odometerEnd ?? (vehicle.odometerKm + gpsKm),
    );
    await _shifts.update(ended);
    final nextOdo = ended.odometerEnd ?? vehicle.odometerKm;
    await saveVehicle(vehicle.copyWith(odometerKm: nextOdo));
    activeShift = null;
    lastEndedShift = ended;
    notifyListeners();
    return ended;
  }

  Future<DayReport?> reportFor(Shift shift) async {
    if (shift.id == null) {
      return null;
    }
    final points = await _shifts.pointsFor(shift.id!);
    final completed = _deliveriesInShift(shift);
    final earnings = completed.fold<double>(
      0,
      (sum, item) => sum + (item.value ?? 0),
    );
    final gas = MaintenanceCalc.gasCost(
      km: shift.gpsKm,
      kmPerLiter: vehicle.kmPerLiter,
      pricePerLiter: vehicle.gasPriceLiter,
    );
    return DayReport(
      shift: shift,
      points: points,
      deliveries: completed.length,
      completed: completed,
      earnings: earnings,
      gpsKm: shift.gpsKm,
      gasCost: gas,
      oilKmSinceChange: MaintenanceCalc.kmSinceOil(
        odometerKm: vehicle.odometerKm,
        lastOilChangeKm: vehicle.lastOilChangeKm,
      ),
      oilKmRemaining: MaintenanceCalc.oilRemainingKm(
        odometerKm: vehicle.odometerKm,
        lastOilChangeKm: vehicle.lastOilChangeKm,
      ),
    );
  }

  List<Delivery> _deliveriesInShift(Shift shift) {
    final start = shift.startedAt;
    final end = shift.endedAt ?? DateTime.now().add(const Duration(minutes: 1));
    return items.where((item) {
      if (item.isPending) {
        return false;
      }
      final at = item.deliveredAt ?? item.createdAt;
      return !at.isBefore(start) && !at.isAfter(end);
    }).toList()
      ..sort(
        (a, b) => (a.deliveredAt ?? a.createdAt)
            .compareTo(b.deliveredAt ?? b.createdAt),
      );
  }

  Future<DayReport?> latestReport() async {
    final shift = activeShift ?? await _shifts.latestEnded();
    if (shift == null) {
      return null;
    }
    return reportFor(shift);
  }

  String whatsAppReportText(DayReport report) {
    return MaintenanceCalc.whatsAppReport(
      dateLabel: DateFormat("dd/MM", 'pt_BR').format(report.shift.startedAt),
      deliveries: report.deliveries,
      earnings: report.earnings,
      gpsKm: report.gpsKm,
      gasCostValue: report.gasCost,
      oilRemaining: report.oilKmRemaining,
      money: money.format,
    );
  }

  List<DayStats> weekStats() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return List.generate(7, (index) {
      final day = start.add(Duration(days: index));
      final ofDay = items.where((item) {
        if (item.isPending) {
          return false;
        }
        final at = item.deliveredAt ?? item.createdAt;
        return at.year == day.year &&
            at.month == day.month &&
            at.day == day.day;
      }).toList();
      final earnings =
          ofDay.fold<double>(0, (sum, item) => sum + (item.value ?? 0));
      return DayStats(
        day: day,
        deliveries: ofDay.length,
        earnings: earnings,
        km: 0,
      );
    });
  }

  Map<String, List<Delivery>> historyByDay() {
    final done = items.where((item) => !item.isPending).toList()
      ..sort((a, b) => (b.deliveredAt ?? b.createdAt)
          .compareTo(a.deliveredAt ?? a.createdAt));
    final map = <String, List<Delivery>>{};
    for (final item in done) {
      final at = item.deliveredAt ?? item.createdAt;
      final key = DateFormat("yyyy-MM-dd").format(at);
      map.putIfAbsent(key, () => []).add(item);
    }
    return map;
  }

  double? distanceFromPrevious(Delivery delivery) {
    final origin = originPoint;
    if (!delivery.hasCoordinates) {
      return null;
    }
    final list = pending;
    final index = list.indexWhere((item) => item.id == delivery.id);
    if (index < 0) {
      return null;
    }
    if (index == 0) {
      if (origin == null) {
        return null;
      }
      return haversineKm(
        origin.latitude,
        origin.longitude,
        delivery.latitude!,
        delivery.longitude!,
      );
    }
    final previous = list[index - 1];
    if (!previous.hasCoordinates) {
      return null;
    }
    return haversineKm(
      previous.latitude!,
      previous.longitude!,
      delivery.latitude!,
      delivery.longitude!,
    );
  }

  String cityHint() => AppConstants.defaultCity;
}
