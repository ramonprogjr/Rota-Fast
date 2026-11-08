import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:rota_max/core/constants/app_constants.dart';
import 'package:rota_max/core/errors/app_error.dart';
import 'package:rota_max/core/utils/address_parser.dart';
import 'package:rota_max/core/utils/haversine.dart';
import 'package:rota_max/core/utils/maintenance.dart';
import 'package:rota_max/data/repositories/delivery_repository.dart';
import 'package:rota_max/data/repositories/error_log_repository.dart';
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
import 'package:rota_max/services/geocoding_service.dart';
import 'package:rota_max/services/location_service.dart';
import 'package:rota_max/services/maps_service.dart';
import 'package:rota_max/services/route_locks.dart';
import 'package:rota_max/services/route_optimizer.dart';
import 'package:rota_max/services/shift_tracker.dart';

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
    required BaseLocationRepository baseLocationRepository,
    required SettingsRepository settingsRepository,
    required GeocodingService geocodingService,
    LocationService locationService = const LocationService(),
    MapsService mapsService = const MapsService(),
    this._optimizer = const RouteOptimizer(),
    ShiftRepository? shiftRepository,
    VehicleRepository? vehicleRepository,
    ErrorLogRepository? errorLogRepository,
  })  : _errorLog = errorLogRepository,
        _deliveries = deliveryRepository,
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
  final ErrorLogRepository? _errorLog;
  late final ShiftTracker _tracker;

  /// Rascunhos de formulário (as telas de cadastro usam).
  static const draftAddDelivery = 'draft_add_delivery';
  static const draftScan = 'draft_scan';

  /// Quantos passos de "Desfazer" a edição de ordem guarda.
  static const maxUndo = 20;

  /// Ordens anteriores das paradas abertas (ids), a mais recente no fim.
  final List<List<int>> _undo = [];

  /// Histórico de rotas (carregado por [loadRoutes]).
  List<RouteSummary> routes = [];

  /// Erros guardados no aparelho (Ajustes > Relatório de erros).
  int errorCount = 0;

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

  GeoPoint? get _endPoint {
    final route = activeRoute;
    return route != null && route.hasEndPoint
        ? GeoPoint(route.endLat!, route.endLng!)
        : null;
  }

  /// De onde contar o que falta: a última parada concluída da rota ativa
  /// (onde o motorista está), senão a origem da rota, senão a base.
  GeoPoint? get _remainingStart {
    Delivery? last;
    for (final item in items) {
      if (item.routeOrder == null || item.isOpen || !item.hasCoordinates) {
        continue;
      }
      if (last == null || item.updatedAt.isAfter(last.updatedAt)) {
        last = item;
      }
    }
    if (last != null) {
      return GeoPoint(last.latitude!, last.longitude!);
    }
    final route = activeRoute;
    if (route?.originLat != null && route?.originLng != null) {
      return GeoPoint(route!.originLat!, route.originLng!);
    }
    return originPoint;
  }

  /// Números do painel. Barato: anda pelas paradas na ordem GRAVADA (a
  /// mesma que o motorista vê), sem otimizar nada.
  ShiftSummary get summary {
    final open = pending;
    final today = doneToday;
    final km = routeDistanceKm(_remainingStart, open, end: _endPoint);
    final route = activeRoute;
    return ShiftSummary(
      pendingCount: open.length,
      doneCount: today.length,
      estimatedKm: km,
      estimatedDuration: estimateTravelTime(km, speedKmh: vehicle.avgSpeedKmh),
      earnings: today.fold<double>(0, (sum, item) => sum + (item.value ?? 0)),
      doneKm: 0,
      plannedKm: route?.estimatedKm,
      plannedDuration: route?.estimatedMinutes == null
          ? null
          : Duration(minutes: route!.estimatedMinutes!),
    );
  }

  bool get canUndo => _undo.isNotEmpty;

  // ---------------------------------------------------------------------
  // Tratamento de erros: nenhuma ação do usuário deixa exceção chegar na
  // tela. O erro vira [message] em português e fica no registro local.
  // ---------------------------------------------------------------------

  Future<void> _report(Object error, StackTrace stack, String source) async {
    await ErrorReporter.report(error, stack, source: source);
    try {
      errorCount = await _errorLog?.count() ?? errorCount;
    } catch (_) {
      // Sem contagem: não atrapalha o motorista.
    }
  }

  /// Recarrega sem deixar erro escapar (usado depois de uma falha).
  Future<void> _safeRefresh() async {
    try {
      await refresh();
    } catch (error, stack) {
      await _report(error, stack, 'refresh');
    }
  }

  /// Roda uma ação do usuário.
  /// - [lock]: usa [busy] como trava contra toque duplo (se já estiver
  ///   ocupado, devolve [orElse] sem fazer nada).
  /// - Qualquer erro vira [message] ([failure] quando não houver mensagem
  ///   melhor), a tela é recarregada do banco e devolve [orElse].
  Future<T> _action<T>(
    String name,
    Future<T> Function() body, {
    required T orElse,
    required String failure,
    bool lock = true,
    bool clearMessage = true,
  }) async {
    if (lock && busy) {
      return orElse;
    }
    if (lock) {
      busy = true;
    }
    if (clearMessage) {
      message = null;
    }
    // Leituras (sem trava e sem limpar mensagem) não avisam a tela antes:
    // podem ser chamadas durante o build/initState.
    if (lock || clearMessage) {
      notifyListeners();
    }
    try {
      return await body();
    } catch (error, stack) {
      await _report(error, stack, name);
      message = friendlyMessage(error, fallback: failure);
      await _safeRefresh();
      return orElse;
    } finally {
      if (lock) {
        busy = false;
      }
      notifyListeners();
    }
  }

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
    try {
      errorCount = await _errorLog?.count() ?? 0;
    } catch (_) {
      errorCount = 0;
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
    } catch (error, stack) {
      await _report(error, stack, 'searchAddress');
      message = friendlyMessage(
        error,
        fallback: 'Não foi possível buscar o endereço agora.',
      );
      return [];
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> confirmLocation(Delivery delivery, GeoResult result) {
    return _action(
      'confirmLocation',
      () async {
        if (delivery.id == null) {
          throw const AppError('Salve a entrega antes de confirmar o ponto.');
        }
        final updated = delivery.copyWith(
          latitude: result.latitude,
          longitude: result.longitude,
          locationConfirmed: true,
        );
        await _deliveries.update(updated);
        try {
          await _geocoding.cacheConfirmed(delivery.fullAddress, result);
        } catch (error, stack) {
          // Sem cache o ponto continua salvo na entrega.
          await _report(error, stack, 'geocodeCache');
        }
        await refresh();
      },
      orElse: null,
      failure: 'Não foi possível salvar o ponto. Tente de novo.',
      lock: false,
    );
  }

  /// Salva (nova ou editada). Se falhar, devolve [delivery] como veio (sem
  /// id, se era nova) e deixa a explicação em [message].
  Future<Delivery> saveDelivery(Delivery delivery, {bool locate = false}) {
    return _action(
      'saveDelivery',
      () async {
        var saved = delivery;
        if (isDuplicateAddress(saved.fullAddress, ignoreId: saved.id)) {
          message = 'Esse endereço já está nas pendentes.';
        }
        if (locate && !saved.hasCoordinates) {
          try {
            final results = await _geocoding.search(saved.fullAddress);
            if (results.isNotEmpty) {
              saved = saved.copyWith(
                latitude: results.first.latitude,
                longitude: results.first.longitude,
                locationConfirmed: false,
              );
            }
          } on GeocodingException {
            // Sem localização agora: salva assim mesmo e confirma depois.
          }
        }
        if (saved.id == null) {
          saved = await _deliveries.insert(saved);
        } else {
          await _deliveries.update(saved);
        }
        await refresh();
        return saved;
      },
      orElse: delivery,
      failure: 'Não foi possível salvar a entrega. Tente de novo.',
    );
  }

  Future<void> deleteDelivery(int id) {
    return _action(
      'deleteDelivery',
      () async {
        await _deliveries.delete(id);
        _undo.clear();
        await refresh();
      },
      orElse: null,
      failure: 'Não foi possível excluir a entrega.',
    );
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
    } catch (error, stack) {
      await _report(error, stack, 'transition');
      message = friendlyMessage(
        error,
        fallback: 'Não foi possível registrar. Tente de novo.',
      );
      return false;
    } finally {
      await _safeRefresh();
    }
  }

  /// Depois de entregue/não entregue:
  /// - rota editada na mão: a ordem fica como o motorista deixou (só a
  ///   próxima parada avança);
  /// - senão reorganiza o que sobrou a partir de onde ele está, respeitando
  ///   travas. Falha aqui não aparece para o motorista: a ordem atual fica.
  Future<void> _reoptimizeFrom(Delivery delivery) async {
    if (activeRoute?.manuallyEdited ?? false) {
      return;
    }
    final origin = delivery.hasCoordinates
        ? GeoPoint(delivery.latitude!, delivery.longitude!)
        : originPoint;
    if (origin == null || pending.isEmpty) {
      return;
    }
    try {
      await _organize(origin, silent: true);
    } catch (error, stack) {
      await _report(error, stack, 'reoptimize');
      await _safeRefresh();
    }
  }

  Future<void> markDelivered(Delivery delivery) async {
    if (busy) {
      return;
    }
    busy = true;
    message = null;
    try {
      if (await _transition(delivery, DeliveryStatus.delivered)) {
        await _reoptimizeFrom(delivery);
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> markFailed(
    Delivery delivery,
    FailureReason reason, {
    String? note,
  }) async {
    if (busy) {
      return;
    }
    busy = true;
    message = null;
    try {
      if (await _transition(
        delivery,
        DeliveryStatus.failed,
        reason: reason,
        note: note,
      )) {
        await _reoptimizeFrom(delivery);
      }
    } finally {
      busy = false;
      notifyListeners();
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
    try {
      await _deliveries.startActiveRoute();
    } catch (error, stack) {
      await _report(error, stack, 'startActiveRoute');
    }
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

  /// "Organizar rota" / "Recalcular respeitando travas". Sempre respeita
  /// travas e posições fixas. Se falhar, a ordem atual fica como estava.
  Future<bool> organizeRoute({
    GeoPoint? originOverride,
    bool useGps = false,
    bool silent = false,
  }) {
    return _action(
      'organizeRoute',
      () async {
        GeoPoint? origin = originOverride;
        if (origin == null && useGps) {
          try {
            origin = await _location.current();
          } catch (error, stack) {
            // Sem GPS: sai da base.
            await _report(error, stack, 'gps');
          }
        }
        origin ??= originPoint;
        if (origin == null) {
          message =
              'Cadastre o ponto de saída (com endereço localizado) para calcular a rota.';
          return false;
        }
        return _organize(origin, silent: silent);
      },
      orElse: false,
      failure: 'Não foi possível organizar a rota. A ordem atual foi mantida.',
      clearMessage: !silent,
    );
  }

  /// Calcula e grava a ordem. Lança erro (quem chama decide o que mostrar);
  /// como a gravação é uma transação só, um erro não muda a ordem salva.
  Future<bool> _organize(GeoPoint origin, {required bool silent}) async {
    final current = pending;
    if (current.isEmpty) {
      if (!silent) {
        message = 'Não há entregas pendentes.';
      }
      return false;
    }
    final speed = vehicle.avgSpeedKmh;
    // PONTO DE INTEGRAÇÃO do motor de rotas (agente A): trocar esta chamada
    // pelo RouteEngine, passando locksOf(current) como StopConstraint
    // (locked / fixedPosition). Enquanto isso, as travas são aplicadas
    // depois por applyLocks.
    final optimized = _optimizer.optimize(
      origin: origin,
      pending: current,
      speedKmh: speed,
    );
    final ordered = applyLocks(optimized.ordered, current, locksOf(current));
    final end = _endPoint;
    final km = routeDistanceKm(origin, ordered, end: end);
    final duration = estimateTravelTime(km, speedKmh: speed);

    final route = await _deliveries.saveRouteOrder(
      ordered,
      originLat: origin.latitude,
      originLng: origin.longitude,
      estimatedKm: km,
      estimatedMinutes: duration.inMinutes,
    );

    if (!silent) {
      _pushUndo(_ids(current));
      await _recordPlan(route, origin, current, km, duration, end);
    }
    await refresh();

    if (!silent) {
      final skipped = optimized.skippedWithoutCoords.length;
      final unconfirmed = current
          .where((item) => item.hasCoordinates && !item.locationConfirmed)
          .length;
      final kmText = formatKm(km);
      final time = formatDuration(duration);
      var text = skipped == 0
          ? 'Rota organizada: $kmText · $time (estimativa em linha reta).'
          : 'Rota organizada: $kmText · $time. $skipped endereço(s) sem localização ficaram no fim.';
      if (unconfirmed > 0) {
        text += ' $unconfirmed ponto(s) ainda sem confirmação no mapa.';
      }
      if (current.any((item) => item.hasConstraint)) {
        text += ' Travas respeitadas.';
      }
      message = text;
    }
    return true;
  }

  /// Grava em `route_plans` quanto a rota economizou em relação à ordem de
  /// cadastro. Falhar aqui não desfaz a rota.
  Future<void> _recordPlan(
    DeliveryRoute route,
    GeoPoint origin,
    List<Delivery> stops,
    double optimizedKm,
    Duration optimized,
    GeoPoint? end,
  ) async {
    if (route.id == null) {
      return;
    }
    try {
      final baseline = [...stops]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final baselineKm = routeDistanceKm(origin, baseline, end: end);
      await _deliveries.savePlan(
        routeId: route.id!,
        stops: stops.where((item) => item.hasCoordinates).length,
        baselineKm: baselineKm,
        baselineMinutes: estimateTravelTime(
          baselineKm,
          speedKmh: vehicle.avgSpeedKmh,
        ).inMinutes,
        optimizedKm: optimizedKm,
        optimizedMinutes: optimized.inMinutes,
      );
    } catch (error, stack) {
      await _report(error, stack, 'savePlan');
    }
  }

  // ---------------------------------------------------------------------
  // Edição manual da ordem (RF-002)
  // ---------------------------------------------------------------------

  List<int> _ids(List<Delivery> list) => [
        for (final item in list)
          if (item.id != null) item.id!,
      ];

  void _pushUndo(List<int> snapshot) {
    if (_undo.isNotEmpty && listEquals(_undo.last, snapshot)) {
      return;
    }
    _undo.add(snapshot);
    if (_undo.length > maxUndo) {
      _undo.removeAt(0);
    }
  }

  /// Mostra a nova ordem na hora (antes de gravar).
  void _applyLocalOrder(List<int> ids) {
    final position = {for (var i = 0; i < ids.length; i++) ids[i]: i + 1};
    items = [
      for (final item in items)
        position.containsKey(item.id)
            ? item.copyWith(routeOrder: position[item.id])
            : item,
    ];
  }

  /// Grava a ordem que o motorista montou. [ordered] são as paradas abertas
  /// (todas) na nova ordem. A rota passa a ser "editada na mão" e não é mais
  /// reorganizada sozinha. Dá para desfazer com [undoReorder].
  Future<bool> reorderStops(List<Delivery> ordered) {
    return _action(
      'reorderStops',
      () async {
        final before = _ids(pending);
        final ids = _ids(ordered);
        if (listEquals(before, ids)) {
          return true;
        }
        _applyLocalOrder(ids);
        notifyListeners();
        await _deliveries.reorder(ids);
        _pushUndo(before);
        await refresh();
        return true;
      },
      orElse: false,
      failure: 'Não foi possível salvar a nova ordem. A anterior foi mantida.',
    );
  }

  /// Volta para a ordem anterior à última mudança.
  Future<bool> undoReorder() {
    return _action(
      'undoReorder',
      () async {
        if (_undo.isEmpty) {
          return false;
        }
        final open = _ids(pending);
        final snapshot = _undo.last;
        // Paradas que entraram ou saíram depois do snapshot.
        final ids = [
          ...snapshot.where(open.contains),
          ...open.where((id) => !snapshot.contains(id)),
        ];
        _applyLocalOrder(ids);
        notifyListeners();
        await _deliveries.reorder(ids);
        _undo.removeLast();
        await refresh();
        message = 'Ordem anterior restaurada.';
        return true;
      },
      orElse: false,
      failure: 'Não foi possível desfazer.',
    );
  }

  /// Liga/desliga a trava (cadeado): ao recalcular, a parada continua na
  /// posição em que está.
  Future<bool> toggleLock(Delivery delivery) {
    return _action(
      'toggleLock',
      () async {
        await _deliveries.setLock(delivery.id!, !delivery.locked);
        await refresh();
        return true;
      },
      orElse: false,
      failure: 'Não foi possível travar a parada.',
    );
  }

  /// Fixa a parada (alfinete) na posição [position] (0 = primeira). Null
  /// solta.
  Future<bool> setFixedPosition(Delivery delivery, int? position) {
    return _action(
      'setFixedPosition',
      () async {
        await _deliveries.setFixedPosition(delivery.id!, position);
        await refresh();
        return true;
      },
      orElse: false,
      failure: 'Não foi possível fixar a parada.',
    );
  }

  /// Alfinete: fixa na posição atual ou solta se já estiver fixa.
  Future<bool> togglePin(Delivery delivery) {
    if (delivery.fixedPosition != null) {
      return setFixedPosition(delivery, null);
    }
    final index = pending.indexWhere((item) => item.id == delivery.id);
    return setFixedPosition(delivery, index < 0 ? 0 : index);
  }

  // ---------------------------------------------------------------------
  // Histórico de rotas
  // ---------------------------------------------------------------------

  Future<void> loadRoutes() {
    return _action(
      'loadRoutes',
      () async {
        routes = await _deliveries.listRoutes();
      },
      orElse: null,
      failure: 'Não foi possível carregar as rotas.',
      lock: false,
      clearMessage: false,
    );
  }

  Future<List<Delivery>> stopsOfRoute(int routeId) {
    return _action(
      'stopsOfRoute',
      () => _deliveries.stopsOf(routeId),
      orElse: const <Delivery>[],
      failure: 'Não foi possível carregar as paradas.',
      lock: false,
      clearMessage: false,
    );
  }

  Future<List<RoutePlan>> plansOfRoute(int routeId) {
    return _action(
      'plansOfRoute',
      () => _deliveries.plansFor(routeId),
      orElse: const <RoutePlan>[],
      failure: 'Não foi possível carregar a economia da rota.',
      lock: false,
      clearMessage: false,
    );
  }

  /// Reabre uma rota antiga. A ativa atual vai para o histórico.
  Future<bool> openRoute(int routeId) {
    return _action(
      'openRoute',
      () async {
        await _deliveries.openRoute(routeId);
        _undo.clear();
        await refresh();
        routes = await _deliveries.listRoutes();
        message = 'Rota reaberta.';
        return true;
      },
      orElse: false,
      failure: 'Não foi possível reabrir a rota.',
    );
  }

  /// Exclui a rota (paradas e planos). As entregas continuam salvas.
  Future<bool> deleteRoute(int routeId) {
    return _action(
      'deleteRoute',
      () async {
        await _deliveries.deleteRoute(routeId);
        if (activeRoute?.id == routeId) {
          _undo.clear();
        }
        await refresh();
        routes = await _deliveries.listRoutes();
        message = 'Rota excluída. As entregas continuam salvas.';
        return true;
      },
      orElse: false,
      failure: 'Não foi possível excluir a rota.',
    );
  }

  /// Ponto final da rota ativa (null limpa).
  Future<bool> setEndPoint(GeoPoint? point) {
    return _action(
      'setEndPoint',
      () async {
        await _deliveries.setEndPoint(point?.latitude, point?.longitude);
        await refresh();
        return true;
      },
      orElse: false,
      failure: 'Não foi possível salvar o ponto final.',
      lock: false,
    );
  }

  // ---------------------------------------------------------------------
  // Rascunhos de formulário (persistem se o app fechar no meio)
  // ---------------------------------------------------------------------

  Future<void> saveDraft(String key, String json) async {
    try {
      await _settings.set(key, json);
    } catch (error, stack) {
      await _report(error, stack, 'saveDraft');
    }
  }

  /// Null se não houver rascunho.
  Future<String?> loadDraft(String key) async {
    try {
      final value = await _settings.get(key);
      return value == null || value.isEmpty ? null : value;
    } catch (error, stack) {
      await _report(error, stack, 'loadDraft');
      return null;
    }
  }

  /// Apaga o rascunho (grava vazio: o repositório de ajustes não tem
  /// remoção e [loadDraft] trata vazio como "sem rascunho").
  Future<void> clearDraft(String key) => saveDraft(key, '');

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
        var results = const <GeoResult>[];
        try {
          results = await _geocoding.search(saved.fullAddress);
        } on GeocodingException {
          // Sem internet: salva o endereço e localiza depois.
        }
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
    } catch (error, stack) {
      await _report(error, stack, 'saveBaseLocation');
      message = friendlyMessage(
        error,
        fallback: 'Não foi possível salvar o ponto de saída.',
      );
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

  Future<BatchImportResult> importParsed(
    List<ParsedDelivery> parsed, {
    bool locate = false,
  }) async {
    if (busy) {
      return const BatchImportResult(saved: 0, located: 0, failedLocate: 0);
    }
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
    } catch (error, stack) {
      await _report(error, stack, 'importParsed');
      await _safeRefresh();
      message = saved == 0
          ? friendlyMessage(
              error,
              fallback: 'Não foi possível adicionar as entregas.',
            )
          : '$saved entrega(s) adicionada(s) antes de um erro. Confira a lista e tente o resto de novo.';
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

  Future<void> startShift() {
    return _action(
      'startShift',
      () async {
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
      },
      orElse: null,
      failure: 'Não foi possível iniciar o turno.',
    );
  }

  Future<Shift?> endShift({double? odometerEnd}) {
    return _action(
      'endShift',
      () => _endShift(odometerEnd),
      orElse: null,
      failure: 'Não foi possível encerrar o turno. Tente de novo.',
    );
  }

  Future<Shift?> _endShift(double? odometerEnd) async {
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
