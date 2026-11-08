import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:rota_max/core/constants/app_constants.dart';
import 'package:rota_max/core/utils/address_parser.dart';
import 'package:rota_max/core/utils/haversine.dart';
import 'package:rota_max/core/utils/maintenance.dart';
import 'package:rota_max/data/repositories/delivery_repository.dart';
import 'package:rota_max/data/repositories/base_location_repository.dart';
import 'package:rota_max/data/repositories/settings_repository.dart';
import 'package:rota_max/data/repositories/shift_repository.dart';
import 'package:rota_max/data/repositories/vehicle_repository.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/delivery_event.dart';
import 'package:rota_max/models/delivery_route.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/models/base_location.dart';
import 'package:rota_max/models/shift.dart';
import 'package:rota_max/models/shift_summary.dart';
import 'package:rota_max/models/vehicle.dart';
import 'package:rota_max/services/draft_store.dart';
import 'package:rota_max/services/geocoding_service.dart';
import 'package:rota_max/services/location_service.dart';
import 'package:rota_max/services/maps_service.dart';
import 'package:rota_max/services/route_optimizer.dart';
import 'package:rota_max/services/shift_tracker.dart';

class BatchImportResult {
  const BatchImportResult({
    required this.saved,
    required this.located,
    required this.failedLocate,
    this.duplicates = 0,
    this.duplicateItems = const [],
  });

  final int saved;
  final int located;
  final int failedLocate;

  /// Quantas linhas pareciam repetidas (salvas ou não, ver [duplicateItems]).
  final int duplicates;

  /// Linhas prováveis duplicadas que **não** foram salvas
  /// (`includeDuplicates: false`). A tela pode oferecê-las de novo.
  final List<ParsedDelivery> duplicateItems;
}

/// Tentativa de salvar um endereço que já existe (aberto ou de hoje).
class DuplicateAddressException implements Exception {
  DuplicateAddressException(this.existing);

  final Delivery existing;

  @override
  String toString() =>
      'Esse endereço já está na lista (${existing.displayName}, ${existing.shortAddress}).';
}

class AppState extends ChangeNotifier {
  AppState({
    required DeliveryRepository deliveryRepository,
    required BaseLocationRepository baseLocationRepository,
    required SettingsRepository settingsRepository,
    required GeocodingService geocodingService,
    LocationService locationService = const LocationService(),
    MapsService mapsService = const MapsService(),
    this._optimizer = const RouteOptimizer(),
    ShiftRepository? shiftRepository,
    VehicleRepository? vehicleRepository,
  })  : _deliveries = deliveryRepository,
        _vehicles = vehicleRepository ?? MemoryVehicleRepository(),
        _baseLocations = baseLocationRepository,
        _settings = settingsRepository,
        _geocoding = geocodingService,
        _shifts = shiftRepository ?? MemoryShiftRepository(),
        _location = locationService,
        maps = mapsService {
    _tracker = ShiftTracker(_shifts);
  }

  final DeliveryRepository _deliveries;
  final BaseLocationRepository _baseLocations;
  final SettingsRepository _settings;
  final GeocodingService _geocoding;
  final ShiftRepository _shifts;
  final VehicleRepository _vehicles;
  final LocationService _location;
  final MapsService maps;
  final RouteOptimizer _optimizer;
  late final ShiftTracker _tracker;

  /// Rascunhos de formulário.
  // TODO(integração): trocar por AppState.saveDraft/loadDraft (pacote C).
  late final DraftStore drafts = SettingsDraftStore(_settings);

  bool loading = true;
  bool busy = false;
  String? message;
  List<Delivery> items = [];
  BaseLocation baseLocation = BaseLocation();
  Shift? activeShift;
  Shift? lastEndedShift;

  /// Veículo ativo (o turno e o ETA usam este).
  Vehicle vehicle = Vehicle.fallback();

  /// App de navegação preferido: 'google', 'waze' ou 'ask'.
  String navApp = 'google';
  List<Vehicle> vehicles = [];

  DeliveryRoute? activeRoute;

  /// Paradas ainda na rota (pendente, a caminho ou pulada), na ordem da rota.
  List<Delivery> get pending {
    final list = items.where((item) => item.isOpen).toList();
    list.sort((a, b) {
      final ao = a.routeOrder ?? 1 << 30;
      final bo = b.routeOrder ?? 1 << 30;
      final byOrder = ao.compareTo(bo);
      if (byOrder != 0) {
        return byOrder;
      }
      return a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  /// Próxima parada: a que está a caminho ou, se nenhuma, a primeira pendente.
  Delivery? get nextStop {
    final list = pending;
    for (final item in list) {
      if (item.status == DeliveryStatus.inProgress) {
        return item;
      }
    }
    for (final item in list) {
      if (item.status == DeliveryStatus.pending) {
        return item;
      }
    }
    return list.isEmpty ? null : list.first;
  }

  /// Entregas que não deram certo e esperam nova tentativa.
  List<Delivery> get problems => items.where((item) => item.isFailed).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  List<Delivery> get doneToday {
    final now = DateTime.now();
    return items.where((item) {
      if (!item.isDelivered) {
        return false;
      }
      final at = item.deliveredAt ?? item.createdAt;
      return at.year == now.year && at.month == now.month && at.day == now.day;
    }).toList()
      ..sort((a, b) => (b.deliveredAt ?? b.createdAt)
          .compareTo(a.deliveredAt ?? a.createdAt));
  }

  GeoPoint? get originPoint {
    if (baseLocation.hasCoordinates) {
      return GeoPoint(baseLocation.latitude!, baseLocation.longitude!);
    }
    return null;
  }

  ShiftSummary get summary => _optimizer.summarize(
        origin: originPoint,
        all: items,
        speedKmh: vehicle.avgSpeedKmh,
      );

  bool get oilWarning => vehicle.oilWarning;

  NumberFormat get money =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  Future<void> load() async {
    loading = true;
    notifyListeners();
    items = await _deliveries.getAll();
    activeRoute = await _deliveries.activeRoute();
    baseLocation = await _baseLocations.get();
    _geocoding.fallbackCity = cityHint();
    await _loadVehicles();
    navApp = await _settings.get('nav_app') ?? 'google';
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
    activeRoute = await _deliveries.activeRoute();
    baseLocation = await _baseLocations.get();
    _geocoding.fallbackCity = cityHint();
    await _loadVehicles();
    activeShift = await _shifts.openShift();
    lastEndedShift = activeShift ?? await _shifts.latestEnded();
    notifyListeners();
  }

  /// Entregas contra as quais procuramos duplicidade: as que ainda estão na
  /// rota e todas as de hoje (qualquer status).
  Iterable<Delivery> get _duplicatePool {
    final now = DateTime.now();
    bool today(DateTime? at) =>
        at != null &&
        at.year == now.year &&
        at.month == now.month &&
        at.day == now.day;
    return items.where(
      (item) =>
          item.isOpen ||
          today(item.createdAt) ||
          today(item.updatedAt) ||
          today(item.deliveredAt),
    );
  }

  /// Mesmo local provável: endereço completo igual, ou rua + número + cidade
  /// iguais, ou CEP + número iguais.
  static bool sameAddress(Delivery a, Delivery b) {
    final numberA = AddressParser.normalizeAddress(a.number ?? '');
    final numberB = AddressParser.normalizeAddress(b.number ?? '');
    if (numberA.isNotEmpty && numberA == numberB) {
      final cepA = AddressParser.normalizePostalCode(a.postalCode);
      final cepB = AddressParser.normalizePostalCode(b.postalCode);
      if (cepA != null && cepA == cepB) {
        return true;
      }
      if (AddressParser.normalizeAddress(a.address) ==
              AddressParser.normalizeAddress(b.address) &&
          AddressParser.normalizeAddress(a.city) ==
              AddressParser.normalizeAddress(b.city)) {
        return true;
      }
    }
    final fullA = AddressParser.normalizeAddress(a.fullAddress);
    return fullA.isNotEmpty &&
        fullA == AddressParser.normalizeAddress(b.fullAddress);
  }

  /// Entrega já cadastrada no mesmo endereço (aberta ou de hoje), ou null.
  /// [extra] entra na comparação (ex.: linhas do mesmo lote ainda não salvas).
  Delivery? findDuplicate(
    Delivery candidate, {
    int? ignoreId,
    Iterable<Delivery> extra = const [],
  }) {
    final ignore = ignoreId ?? candidate.id;
    for (final item in [..._duplicatePool, ...extra]) {
      if (ignore != null && item.id == ignore) {
        continue;
      }
      if (sameAddress(candidate, item)) {
        return item;
      }
    }
    return null;
  }

  /// Compatível com o uso antigo: compara só o texto do endereço completo.
  bool isDuplicateAddress(String address, {int? ignoreId}) {
    final needle = AddressParser.normalizeAddress(address);
    if (needle.isEmpty) {
      return false;
    }
    return _duplicatePool.any((item) {
      if (ignoreId != null && item.id == ignoreId) {
        return false;
      }
      return AddressParser.normalizeAddress(item.fullAddress) == needle;
    });
  }

  /// Para cada linha do lote, a entrega que ela provavelmente repete (já
  /// cadastrada ou uma linha anterior do próprio lote), ou null.
  List<Delivery?> duplicatesFor(List<ParsedDelivery> parsed) {
    final seen = <Delivery>[];
    final result = <Delivery?>[];
    for (final item in parsed) {
      final candidate = item.toDelivery();
      result.add(findDuplicate(candidate, extra: seen));
      seen.add(candidate);
    }
    return result;
  }

  Future<List<GeoResult>> searchAddress({
    required String query,
    String? street,
    String? number,
    String? neighborhood,
    String? city,
    String? state,
    String? postalCode,
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
        state: state,
        postalCode: postalCode,
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

  /// Salva (insere ou atualiza) a entrega.
  ///
  /// Endereço repetido (aberto ou de hoje) lança [DuplicateAddressException],
  /// a menos que [allowDuplicate] seja true ("Salvar mesmo assim").
  /// Se o endereço de uma entrega existente mudou e o pino não foi refeito,
  /// as coordenadas antigas são apagadas.
  Future<Delivery> saveDelivery(
    Delivery delivery, {
    bool locate = false,
    bool allowDuplicate = false,
  }) async {
    final duplicate = findDuplicate(delivery, ignoreId: delivery.id);
    if (duplicate != null && !allowDuplicate) {
      throw DuplicateAddressException(duplicate);
    }
    busy = true;
    message = null;
    notifyListeners();
    var saved = _dropStalePin(delivery);
    try {
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

  /// Endereço mudou mas as coordenadas são as mesmas de antes: o pino é do
  /// endereço antigo e levaria a rota para o lugar errado.
  Delivery _dropStalePin(Delivery next) {
    if (next.id == null || !next.hasCoordinates) {
      return next;
    }
    Delivery? previous;
    for (final item in items) {
      if (item.id == next.id) {
        previous = item;
        break;
      }
    }
    if (previous == null || !previous.hasCoordinates) {
      return next;
    }
    final moved = AddressParser.locationSignature(
          street: previous.address,
          number: previous.number,
          neighborhood: previous.neighborhood,
          city: previous.city,
          postalCode: previous.postalCode,
        ) !=
        AddressParser.locationSignature(
          street: next.address,
          number: next.number,
          neighborhood: next.neighborhood,
          city: next.city,
          postalCode: next.postalCode,
        );
    final samePin = previous.latitude == next.latitude &&
        previous.longitude == next.longitude;
    if (moved && samePin) {
      return next.copyWith(clearCoordinates: true, locationConfirmed: false);
    }
    return next;
  }

  Future<void> deleteDelivery(int id) async {
    await _deliveries.delete(id);
    await refresh();
  }

  /// Troca de status com tratamento de erro para a interface.
  Future<bool> _transition(
    Delivery delivery,
    DeliveryStatus to, {
    FailureReason? reason,
    String? note,
  }) async {
    if (delivery.id == null) {
      return false;
    }
    try {
      // Posição do rastreio do turno, sem nova leitura de GPS (não atrasa
      // o toque do motorista). Sem turno ativo, o evento fica sem posição.
      final here = to == DeliveryStatus.delivered || to == DeliveryStatus.failed
          ? _tracker.lastLocation(maxAge: const Duration(minutes: 5))
          : null;
      await _deliveries.transition(
        delivery.id!,
        to,
        reason: reason,
        note: note,
        latitude: here?.latitude,
        longitude: here?.longitude,
      );
      return true;
    } on InvalidTransition catch (error) {
      message = error.toString();
      return false;
    } on ArgumentError catch (error) {
      message = '${error.message}';
      return false;
    } finally {
      await refresh();
    }
  }

  /// Reorganiza o que sobrou a partir do ponto onde o motorista está.
  Future<void> _reoptimizeFrom(Delivery delivery) async {
    final origin = delivery.hasCoordinates
        ? GeoPoint(delivery.latitude!, delivery.longitude!)
        : originPoint;
    if (origin != null && pending.isNotEmpty) {
      await organizeRoute(originOverride: origin, silent: true);
    }
  }

  Future<void> markDelivered(Delivery delivery) async {
    if (await _transition(delivery, DeliveryStatus.delivered)) {
      await _reoptimizeFrom(delivery);
    }
  }

  Future<void> markFailed(
    Delivery delivery,
    FailureReason reason, {
    String? note,
  }) async {
    if (await _transition(
      delivery,
      DeliveryStatus.failed,
      reason: reason,
      note: note,
    )) {
      await _reoptimizeFrom(delivery);
    }
  }

  /// Pula a parada: ela vai para o fim da rota.
  Future<void> skip(Delivery delivery) =>
      _transition(delivery, DeliveryStatus.skipped);

  /// Falhou ou pulou: volta para a rota como pendente.
  Future<void> retry(Delivery delivery) =>
      _transition(delivery, DeliveryStatus.pending);

  /// Entregue por engano: volta a pendente (fica registrado no histórico).
  Future<void> reopen(Delivery delivery) =>
      _transition(delivery, DeliveryStatus.pending, note: 'Reaberta');

  /// Motorista saiu para esta parada. Marca a rota como iniciada.
  Future<void> startStop(Delivery delivery) async {
    if (delivery.status == DeliveryStatus.inProgress) {
      return;
    }
    await _deliveries.startActiveRoute();
    await _transition(delivery, DeliveryStatus.inProgress);
  }

  /// Abre a navegação para a parada e a marca como "a caminho".
  /// Retorna false se nenhum app de navegação abriu.
  Future<bool> navigateTo(Delivery delivery) async {
    if (delivery.isOpen) {
      await startStop(delivery);
    }
    return maps.navigate(address: delivery.fullAddress);
  }

  Future<List<DeliveryEvent>> eventsFor(Delivery delivery) async =>
      delivery.id == null ? [] : _deliveries.eventsFor(delivery.id!);

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
            'Cadastre o ponto de saída (com endereço localizado) para calcular a rota.';
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
        speedKmh: vehicle.avgSpeedKmh,
      );
      await _deliveries.saveRouteOrder(
        route.ordered,
        originLat: origin.latitude,
        originLng: origin.longitude,
        estimatedKm: route.totalKm,
        estimatedMinutes: route.estimatedDuration.inMinutes,
      );
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

  Future<void> saveBaseLocation(BaseLocation next, {bool locate = true}) async {
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
              'Não achei o ponto de saída nesse endereço. Confirme no mapa ou ajuste o texto.';
        }
      }
      await _baseLocations.save(saved);
      await refresh();
      if (saved.hasCoordinates) {
        message = 'Ponto de saída salvo.';
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> setNavApp(String value) async {
    await _settings.set('nav_app', value);
    navApp = value;
    notifyListeners();
  }

  Future<void> _loadVehicles() async {
    vehicles = await _vehicles.getAll();
    vehicle = await _vehicles.active() ?? Vehicle.fallback();
  }

  Future<Vehicle> saveVehicle(Vehicle next) async {
    final saved = await _vehicles.save(next);
    await _loadVehicles();
    notifyListeners();
    return saved;
  }

  /// Troca o veículo ativo. Com turno aberto, os km do turno continuam
  /// indo para o veículo com que ele começou.
  Future<void> activateVehicle(Vehicle next) async {
    if (next.id == null) {
      return;
    }
    await _vehicles.activate(next.id!);
    await _loadVehicles();
    notifyListeners();
  }

  Future<void> deleteVehicle(Vehicle target) async {
    if (target.id == null) {
      return;
    }
    await _vehicles.delete(target.id!);
    await _loadVehicles();
    notifyListeners();
  }

  /// "Troquei o óleo": zera a contagem no odômetro informado.
  Future<void> registerOilChange(
    Vehicle target,
    double odometerKm, {
    String? note,
  }) async {
    if (target.id == null) {
      return;
    }
    await _vehicles.registerOilChange(target.id!, odometerKm, note: note);
    await _loadVehicles();
    notifyListeners();
  }

  Future<List<OilChange>> oilChanges(Vehicle target) async =>
      target.id == null ? [] : _vehicles.oilChanges(target.id!);

  Vehicle _vehicleFor(Shift shift) {
    for (final item in vehicles) {
      if (item.id == shift.vehicleId) {
        return item;
      }
    }
    return vehicle;
  }

  /// Salva as linhas importadas (colar texto / OCR).
  ///
  /// Linhas que repetem uma entrega aberta, de hoje ou do próprio lote não
  /// são salvas, a menos que [includeDuplicates] seja true; elas voltam em
  /// [BatchImportResult.duplicateItems] para a tela perguntar.
  Future<BatchImportResult> importParsed(
    List<ParsedDelivery> parsed, {
    bool locate = false,
    bool includeDuplicates = false,
  }) async {
    busy = true;
    message = null;
    notifyListeners();
    var saved = 0;
    var located = 0;
    var failed = 0;
    var duplicates = 0;
    final skipped = <ParsedDelivery>[];
    final batch = <Delivery>[];
    try {
      for (final item in parsed) {
        var delivery = item.toDelivery();
        if (findDuplicate(delivery, extra: batch) != null) {
          duplicates++;
          if (!includeDuplicates) {
            skipped.add(item);
            continue;
          }
        }
        if (locate) {
          try {
            final results = await _geocoding.search(
              delivery.fullAddress,
              postalCode: delivery.postalCode,
              state: delivery.state,
            );
            if (results.isNotEmpty) {
              delivery = delivery.copyWith(
                latitude: results.first.latitude,
                longitude: results.first.longitude,
                locationConfirmed: results.first.confirmed,
              );
              located++;
            } else {
              failed++;
            }
          } on GeocodingException {
            failed++;
          }
        }
        batch.add(await _deliveries.insert(delivery));
        saved++;
      }
      await refresh();
      final parts = <String>['$saved entrega(s) adicionada(s).'];
      if (locate) {
        parts.add('$located localizada(s), $failed sem localização.');
      }
      if (skipped.isNotEmpty) {
        parts.add('${skipped.length} repetida(s) não salva(s).');
      } else if (duplicates > 0) {
        parts.add('$duplicates repetida(s) salva(s) mesmo assim.');
      }
      if (located > 0) {
        parts.add('Confirme os pontos no mapa.');
      }
      message = parts.join(' ');
      return BatchImportResult(
        saved: saved,
        located: located,
        failedLocate: failed,
        duplicates: duplicates,
        duplicateItems: skipped,
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
        vehicleId: vehicle.id,
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
    final used = _vehicleFor(current);
    final ended = current.copyWith(
      endedAt: DateTime.now(),
      gpsKm: gpsKm,
      odometerEnd: odometerEnd ?? (used.odometerKm + gpsKm),
    );
    await _shifts.update(ended);
    // Os km do turno vão para o veículo com que ele começou.
    if (used.id != null) {
      if (odometerEnd != null) {
        await _vehicles.save(used.copyWith(odometerKm: odometerEnd));
      } else {
        await _vehicles.addKm(used.id!, gpsKm);
      }
    }
    await _loadVehicles();
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
    final used = _vehicleFor(shift);
    final gas = used.fuelCost(shift.gpsKm);
    return DayReport(
      shift: shift,
      points: points,
      deliveries: completed.length,
      completed: completed,
      earnings: earnings,
      gpsKm: shift.gpsKm,
      gasCost: gas,
      oilKmSinceChange: used.kmSinceOil,
      oilKmRemaining: used.oilRemainingKm,
      oilIntervalKm: used.oilIntervalKm,
      vehicleName: used.name,
    );
  }

  List<Delivery> _deliveriesInShift(Shift shift) {
    final start = shift.startedAt;
    final end = shift.endedAt ?? DateTime.now().add(const Duration(minutes: 1));
    return items.where((item) {
      if (!item.isDelivered) {
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
      oilIntervalKm: report.oilIntervalKm,
      vehicleName: report.vehicleName,
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
        if (!item.isDelivered) {
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
    final done = items.where((item) => item.isDelivered || item.isFailed).toList()
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

  String cityHint() => baseLocation.city.trim().isEmpty
      ? AppConstants.defaultCity
      : baseLocation.city.trim();
}
