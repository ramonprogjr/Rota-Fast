import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:rota_max/core/constants/app_constants.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/core/utils/haversine.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/models/vehicle.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:rota_max/services/route_locks.dart';
import 'package:rota_max/services/fuel_station_service.dart';
import 'package:rota_max/widgets/location_status_banner.dart';
import 'package:rota_max/widgets/nav_app_sheet.dart';

/// Mapa da rota: paradas numeradas na ordem, trajeto a partir do ponto de
/// saída, posição do motorista e postos de combustível próximos.
class RouteMapScreen extends StatefulWidget {
  const RouteMapScreen({
    super.key,
    this.fuelService,
    this.showTiles = true,
    this.refreshOnOpen = true,
  });

  /// Serviço de postos (padrão: instância compartilhada com cache).
  final FuelStationService? fuelService;

  /// Desligado nos testes (sem rede).
  final bool showTiles;

  /// Lê o GPS ao abrir a tela.
  final bool refreshOnOpen;

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

const _fuelColor = Color(0xFFFF8A3D);
const _userColor = Color(0xFF2F9BFF);

class _RouteMapScreenState extends State<RouteMapScreen> {
  final _mapController = MapController();
  bool _showStations = false;

  /// Modo "Mudar ordem": o mapa fica parado e os números são arrastados na
  /// hora (funciona com mouse e com o dedo, sem precisar segurar).
  bool _reordering = false;
  bool _loadingStations = false;
  FuelStationResult? _stations;
  GeoPoint? _stationsCenter;

  FuelStationService get _fuel =>
      widget.fuelService ?? FuelStationService.shared;

  @override
  void initState() {
    super.initState();
    if (widget.refreshOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<AppState>().refreshLocation();
        }
      });
    }
  }

  Future<void> _recalculate(AppState state) async {
    await state.organizeRoute(useGps: true);
    if (!mounted) {
      return;
    }
    final text = state.message ?? 'Rota recalculada.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pending = state.pending;
    final next = state.nextStop;
    final origin = state.originPoint;
    final reading = state.location;
    final user = reading?.point;
    final closed = [
      ...state.doneToday,
      ...state.problems,
    ].where((item) => item.hasCoordinates).toList();

    final routeLine = <LatLng>[
      if (origin != null) LatLng(origin.latitude, origin.longitude),
      for (final item in pending)
        if (item.hasCoordinates) LatLng(item.latitude!, item.longitude!),
    ];
    final allPoints = <LatLng>[
      ...routeLine,
      for (final item in closed) LatLng(item.latitude!, item.longitude!),
      if (user != null) LatLng(user.latitude, user.longitude),
    ];
    final withoutCoords = pending.where((item) => !item.hasCoordinates).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa da rota'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: FilterChip(
              key: const Key('toggle-fuel'),
              avatar: const Icon(Icons.local_gas_station, size: 18),
              label: const Text('Postos'),
              selected: _showStations,
              onSelected: (value) => _toggleStations(state, value),
            ),
          ),
          if (_showStations && (_stations?.stations.isNotEmpty ?? false))
            IconButton(
              tooltip: 'Lista de postos',
              onPressed: () => _openStationList(state),
              icon: const Icon(Icons.list),
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: allPoints.isEmpty
                  ? const LatLng(
                      AppConstants.fallbackLat,
                      AppConstants.fallbackLng,
                    )
                  : allPoints.first,
              initialZoom: 15,
              interactionOptions: InteractionOptions(
                flags: _reordering ? InteractiveFlag.none : InteractiveFlag.all,
              ),
              initialCameraFit: allPoints.length >= 2
                  ? CameraFit.coordinates(
                      coordinates: allPoints,
                      padding: const EdgeInsets.fromLTRB(40, 90, 40, 220),
                      maxZoom: 17,
                    )
                  : null,
            ),
            children: [
              if (widget.showTiles)
                TileLayer(
                  urlTemplate: AppConstants.osmTileUrl,
                  userAgentPackageName: AppConstants.osmUserAgentPackage,
                ),
              if (routeLine.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: routeLine,
                      strokeWidth: 4,
                      color: AppColors.primary.withValues(alpha: 0.8),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final item in closed)
                    Marker(
                      point: LatLng(item.latitude!, item.longitude!),
                      width: 26,
                      height: 26,
                      child: _ClosedStopMarker(delivery: item),
                    ),
                  if (origin != null)
                    Marker(
                      point: LatLng(origin.latitude, origin.longitude),
                      width: 34,
                      height: 34,
                      child: const _OriginMarker(),
                    ),
                  for (var i = 0; i < pending.length; i++)
                    if (pending[i].hasCoordinates)
                      Marker(
                        key: Key('stop-marker-${pending[i].id}'),
                        point: LatLng(
                          pending[i].latitude!,
                          pending[i].longitude!,
                        ),
                        width: pending[i].id == next?.id ? 44 : 34,
                        height: pending[i].id == next?.id ? 44 : 34,
                        child: _StopMarker(
                          number: i + 1,
                          delivery: pending[i],
                          highlighted: pending[i].id == next?.id,
                          onTap: () => _showStop(state, pending[i], i + 1),
                          reordering: _reordering,
                          onDropped: (draggedId) =>
                              _moveStop(state, draggedId, i),
                        ),
                      ),
                  if (_showStations)
                    for (final station in _stations?.stations ?? const [])
                      Marker(
                        point: LatLng(station.latitude, station.longitude),
                        width: 32,
                        height: 32,
                        child: _FuelMarker(
                          station: station,
                          highlightDiesel:
                              state.vehicle.fuelType == FuelType.diesel,
                          onTap: () => _confirmStation(state, station),
                        ),
                      ),
                  if (user != null)
                    Marker(
                      key: const Key('user-marker'),
                      point: LatLng(user.latitude, user.longitude),
                      width: 110,
                      height: 52,
                      child: _UserMarker(
                        stale: reading!.stale || !reading.isOk,
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LocationStatusBanner(
                  reading: reading,
                  busy: state.locating,
                  onRetry: () => state.refreshLocation(retry: true),
                  onOpenLocationSettings: state.openLocationSettings,
                  onOpenAppSettings: state.openAppSettings,
                ),
                if (withoutCoords > 0) ...[
                  const SizedBox(height: 6),
                  _Pill(
                    text:
                        '$withoutCoords parada(s) sem localização '
                        'não aparecem no mapa.',
                  ),
                ],
                if (pending.length >= 2) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _Pill(
                          text: _reordering
                              ? 'Arraste um número e solte sobre outro.'
                              : 'Toque em "Mudar ordem" para arrastar '
                                    'os números.',
                        ),
                      ),
                      const SizedBox(width: 6),
                      FilledButton.icon(
                        key: const Key('map-reorder-mode'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _reordering
                              ? AppColors.success
                              : AppColors.surfaceHigh,
                          foregroundColor: _reordering
                              ? AppColors.background
                              : AppColors.text,
                          visualDensity: VisualDensity.compact,
                          // O tema estica os botões na largura toda.
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: () =>
                            setState(() => _reordering = !_reordering),
                        icon: Icon(
                          _reordering ? Icons.check : Icons.swap_vert,
                          size: 18,
                        ),
                        label: Text(_reordering ? 'Concluir' : 'Mudar ordem'),
                      ),
                    ],
                  ),
                ],
                if (_showStations && _loadingStations) ...[
                  const SizedBox(height: 6),
                  const _Pill(text: 'Buscando postos próximos...'),
                ],
                if (_showStations && _stations?.error != null) ...[
                  const SizedBox(height: 6),
                  _Pill(text: _stations!.error!, warning: true),
                ],
              ],
            ),
          ),
          Positioned(
            right: 12,
            bottom: next == null ? 24 : 200,
            child: Column(
              children: [
                FloatingActionButton.small(
                  key: const Key('map-recalculate'),
                  heroTag: 'map-recalculate',
                  tooltip: 'Recalcular rota inteligente',
                  backgroundColor: AppColors.success,
                  foregroundColor: AppColors.background,
                  onPressed: state.busy || pending.isEmpty
                      ? null
                      : () => _recalculate(state),
                  child: state.busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'map-fit',
                  tooltip: 'Ver a rota inteira',
                  onPressed: () => _fit(allPoints),
                  child: const Icon(Icons.fit_screen),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'map-me',
                  tooltip: 'Minha posição',
                  onPressed: () => _centerOnUser(state),
                  child: state.locating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
          if (next != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: _NextStopPanel(
                state: state,
                delivery: next,
                position: pending.indexOf(next) + 1,
                total: pending.length,
              ),
            ),
        ],
      ),
    );
  }

  void _fit(List<LatLng> points) {
    if (points.isEmpty) {
      return;
    }
    if (points.length == 1) {
      _mapController.move(points.first, 16);
      return;
    }
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.fromLTRB(40, 90, 40, 220),
        maxZoom: 17,
      ),
    );
  }

  Future<void> _centerOnUser(AppState state) async {
    await state.refreshLocation();
    final point = state.location?.point;
    if (!mounted || point == null) {
      return;
    }
    _mapController.move(LatLng(point.latitude, point.longitude), 16);
  }

  /// Centro da busca de postos: motorista, senão próxima parada, senão
  /// ponto de saída, senão o centro do mapa.
  GeoPoint _searchCenter(AppState state) {
    final user = state.location?.point;
    if (user != null) {
      return user;
    }
    final next = state.nextStop;
    if (next != null && next.hasCoordinates) {
      return GeoPoint(next.latitude!, next.longitude!);
    }
    final origin = state.originPoint;
    if (origin != null) {
      return origin;
    }
    final center = _mapController.camera.center;
    return GeoPoint(center.latitude, center.longitude);
  }

  Future<void> _toggleStations(AppState state, bool value) async {
    setState(() => _showStations = value);
    if (!value) {
      return;
    }
    final center = _searchCenter(state);
    setState(() {
      _loadingStations = true;
      _stationsCenter = center;
    });
    final result = await _fuel.nearby(center.latitude, center.longitude);
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingStations = false;
      _stations = result;
    });
    if (result.ok && result.stations.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum posto encontrado por perto.')),
      );
    }
  }

  List<FuelStation> _sortedStations() {
    final center = _stationsCenter;
    final list = [...?_stations?.stations];
    if (center != null) {
      list.sort(
        (a, b) => a
            .distanceKmFrom(center.latitude, center.longitude)
            .compareTo(b.distanceKmFrom(center.latitude, center.longitude)),
      );
    }
    return list;
  }

  Future<void> _openStationList(AppState state) async {
    final stations = _sortedStations();
    final center = _stationsCenter;
    final diesel = state.vehicle.fuelType == FuelType.diesel;
    final chosen = await showModalBottomSheet<FuelStation>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              'Postos próximos',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              diesel
                  ? 'Preços não disponíveis. Postos com diesel em destaque.'
                  : 'Preços não disponíveis.',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            for (final station in stations)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.local_gas_station,
                  color: diesel && station.hasDiesel
                      ? AppColors.success
                      : _fuelColor,
                ),
                title: Text(station.label),
                subtitle: Text(
                  [
                    if (center != null)
                      formatKm(
                        station.distanceKmFrom(
                          center.latitude,
                          center.longitude,
                        ),
                      ),
                    if (station.hasDiesel) 'Diesel',
                  ].join(' · '),
                  style: TextStyle(
                    color: diesel && station.hasDiesel
                        ? AppColors.success
                        : AppColors.muted,
                    fontWeight: diesel && station.hasDiesel
                        ? FontWeight.w700
                        : FontWeight.normal,
                  ),
                ),
                trailing: const Icon(Icons.navigation),
                onTap: () => Navigator.of(sheetContext).pop(station),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) {
      await navigateToPoint(
        context,
        state,
        chosen.latitude,
        chosen.longitude,
        label: chosen.label,
      );
    }
  }

  Future<void> _confirmStation(AppState state, FuelStation station) async {
    final center = _stationsCenter;
    final go = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                station.label,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              Text(
                [
                  if (center != null)
                    formatKm(
                      station.distanceKmFrom(center.latitude, center.longitude),
                    ),
                  if (station.hasDiesel) 'Diesel',
                  'Preços não disponíveis',
                ].join(' · '),
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                icon: const Icon(Icons.navigation),
                label: const Text('Navegar até o posto'),
              ),
            ],
          ),
        ),
      ),
    );
    if (go == true && mounted) {
      await navigateToPoint(
        context,
        state,
        station.latitude,
        station.longitude,
        label: station.label,
      );
    }
  }

  /// Arrastar no mapa: a parada [draggedId] passa a ocupar a posição
  /// [targetIndex] (a do número onde foi solta). Mesma regra da tela
  /// "Editar ordem": tira de onde estava e insere no lugar novo.
  Future<void> _moveStop(AppState state, int draggedId, int targetIndex) async {
    final ordered = moveStopTo(state.pending, draggedId, targetIndex);
    if (ordered == null) {
      return;
    }
    final saved = await state.reorderStops(ordered);
    if (!mounted) {
      return;
    }
    final moved = ordered[targetIndex];
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? '${moved.displayName} agora é a parada ${targetIndex + 1}.'
                : state.message ?? 'Não foi possível mudar a ordem.',
          ),
          action: saved
              ? SnackBarAction(
                  label: 'Desfazer',
                  onPressed: () => state.undoReorder(),
                )
              : null,
        ),
      );
  }

  void _showStop(AppState state, Delivery delivery, int number) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$number. ${delivery.displayName} — '
            '${delivery.shortAddress}',
          ),
          action: delivery.isOpen
              ? SnackBarAction(
                  label: 'Navegar',
                  onPressed: () => navigateToDelivery(context, state, delivery),
                )
              : null,
        ),
      );
  }
}

class _NextStopPanel extends StatelessWidget {
  const _NextStopPanel({
    required this.state,
    required this.delivery,
    required this.position,
    required this.total,
  });

  final AppState state;
  final Delivery delivery;
  final int position;
  final int total;

  /// Distância em linha reta: da posição atual (se recente) ou da parada
  /// anterior na rota.
  double? _distanceKm() {
    final reading = state.location;
    final user = reading?.point;
    if (user != null &&
        reading!.isOk &&
        !reading.stale &&
        delivery.hasCoordinates) {
      return haversineKm(
        user.latitude,
        user.longitude,
        delivery.latitude!,
        delivery.longitude!,
      );
    }
    return state.distanceFromPrevious(delivery);
  }

  @override
  Widget build(BuildContext context) {
    final km = _distanceKm();
    final eta = km == null
        ? null
        : estimateTravelTime(km, speedKmh: state.vehicle.avgSpeedKmh);
    return Material(
      key: const Key('map-next-stop'),
      color: AppColors.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  delivery.status == DeliveryStatus.inProgress
                      ? 'A CAMINHO'
                      : 'PRÓXIMA PARADA',
                  style: const TextStyle(
                    color: AppColors.primarySoft,
                    fontSize: 12,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  '$position de $total',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              delivery.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            Text(
              delivery.shortAddress,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.text),
            ),
            Text(
              km == null
                  ? (delivery.hasCoordinates
                        ? 'Distância indisponível'
                        : 'Sem localização no mapa')
                  : '${formatKm(km)} · ${formatDuration(eta!)} '
                        '(linha reta)',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => navigateToDelivery(context, state, delivery),
                icon: const Icon(Icons.navigation),
                label: const Text('Navegar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopMarker extends StatelessWidget {
  const _StopMarker({
    required this.number,
    required this.delivery,
    required this.highlighted,
    required this.onTap,
    required this.onDropped,
    this.reordering = false,
  });

  final int number;
  final Delivery delivery;
  final bool highlighted;
  final VoidCallback onTap;

  /// No modo "Mudar ordem" o arraste começa na hora; fora dele, só
  /// segurando (para não brigar com o arrastar do mapa).
  final bool reordering;

  /// Outra parada (id) foi solta em cima desta.
  final ValueChanged<int> onDropped;

  @override
  Widget build(BuildContext context) {
    final id = delivery.id;
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != id,
      onAcceptWithDetails: (details) => onDropped(details.data),
      builder: (context, candidates, rejected) {
        final hovering = candidates.isNotEmpty;
        final circle = _StopCircle(
          number: number,
          delivery: delivery,
          highlighted: highlighted,
          hovering: hovering,
        );
        if (id == null) {
          return GestureDetector(onTap: onTap, child: circle);
        }
        final feedback = SizedBox(
          width: 52,
          height: 52,
          child: _StopCircle(
            number: number,
            delivery: delivery,
            highlighted: true,
            hovering: false,
          ),
        );
        if (reordering) {
          return MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: Draggable<int>(
              data: id,
              feedback: feedback,
              childWhenDragging: Opacity(opacity: 0.3, child: circle),
              child: circle,
            ),
          );
        }
        // Segurar e arrastar: o toque curto continua mostrando a parada e
        // arrastar sem segurar continua movendo o mapa.
        return LongPressDraggable<int>(
          data: id,
          delay: const Duration(milliseconds: 300),
          hapticFeedbackOnStart: true,
          feedback: SizedBox(
            width: 52,
            height: 52,
            child: _StopCircle(
              number: number,
              delivery: delivery,
              highlighted: true,
              hovering: false,
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: circle),
          child: GestureDetector(onTap: onTap, child: circle),
        );
      },
    );
  }
}

class _StopCircle extends StatelessWidget {
  const _StopCircle({
    required this.number,
    required this.delivery,
    required this.highlighted,
    required this.hovering,
  });

  final int number;
  final Delivery delivery;
  final bool highlighted;
  final bool hovering;

  @override
  Widget build(BuildContext context) {
    final color = highlighted
        ? AppColors.primary
        : AppColors.forStatus(delivery.status);
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: hovering
              ? AppColors.success
              : highlighted
              ? Colors.white
              : AppColors.background,
          width: hovering ? 4 : (highlighted ? 3 : 2),
        ),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
      ),
      child: Text(
        '$number',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: highlighted ? 18 : 14,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

class _ClosedStopMarker extends StatelessWidget {
  const _ClosedStopMarker({required this.delivery});

  final Delivery delivery;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.45,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.forStatus(delivery.status),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.background, width: 2),
        ),
        child: Icon(
          delivery.isDelivered ? Icons.check : Icons.close,
          size: 14,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _OriginMarker extends StatelessWidget {
  const _OriginMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primarySoft, width: 2),
      ),
      child: const Icon(Icons.storefront, size: 20, color: AppColors.text),
    );
  }
}

class _UserMarker extends StatelessWidget {
  const _UserMarker({required this.stale});

  final bool stale;

  @override
  Widget build(BuildContext context) {
    final color = stale ? AppColors.muted : _userColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 8,
                spreadRadius: 4,
              ),
            ],
          ),
        ),
        if (stale) ...[
          const SizedBox(height: 4),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'desatualizada',
                  maxLines: 1,
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FuelMarker extends StatelessWidget {
  const _FuelMarker({
    required this.station,
    required this.highlightDiesel,
    required this.onTap,
  });

  final FuelStation station;
  final bool highlightDiesel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strong = highlightDiesel && station.hasDiesel;
    final faded = highlightDiesel && !station.hasDiesel;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: faded ? 0.55 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: strong ? AppColors.success : _fuelColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const Icon(
            Icons.local_gas_station,
            size: 18,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: warning ? AppColors.warningSurface : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          text,
          style: TextStyle(
            color: warning ? AppColors.warning : AppColors.text,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
