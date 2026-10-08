import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:rota_pizza/core/constants/app_constants.dart';
import 'package:rota_pizza/core/theme/app_theme.dart';
import 'package:rota_pizza/core/utils/haversine.dart';
import 'package:rota_pizza/core/utils/shift_timeline.dart';
import 'package:rota_pizza/models/shift.dart';
import 'package:rota_pizza/providers/app_state.dart';
import 'package:rota_pizza/widgets/big_button.dart';

class ShiftReportScreen extends StatelessWidget {
  const ShiftReportScreen({super.key, this.report});

  final DayReport? report;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DayReport?>(
      future: report != null
          ? Future.value(report)
          : context.read<AppState>().latestReport(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final state = context.watch<AppState>();
        return Scaffold(
          appBar: AppBar(title: const Text('Linha do tempo')),
          body: data == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nenhum turno registrado ainda. Toque em Iniciar turno na tela inicial.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _ReportBody(report: data, state: state),
        );
      },
    );
  }
}

class _ReportBody extends StatefulWidget {
  const _ReportBody({required this.report, required this.state});

  final DayReport report;
  final AppState state;

  @override
  State<_ReportBody> createState() => _ReportBodyState();
}

class _ReportBodyState extends State<_ReportBody> {
  final _mapController = MapController();
  int _selected = 0;
  bool _mapReady = false;

  DayReport get report => widget.report;
  AppState get state => widget.state;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final origin = state.originPoint == null
        ? null
        : LatLng(state.originPoint!.latitude, state.originPoint!.longitude);
    final points = report.points
        .map((item) => LatLng(item.latitude, item.longitude))
        .toList();
    final events = ShiftTimeline.build(
      shift: report.shift,
      points: report.points,
      completed: report.completed,
      originName: state.pizzeria.name,
      origin: origin,
    );
    final selectedEvent =
        events.isEmpty ? null : events[_selected.clamp(0, events.length - 1)];
    final highlight = selectedEvent == null
        ? const <LatLng>[]
        : ShiftTimeline.pathInRange(
            report.points,
            _rangeStart(events, _selected),
            selectedEvent.time,
          );

    final date =
        DateFormat("EEEE, dd/MM", 'pt_BR').format(report.shift.startedAt);
    final start = DateFormat('HH:mm').format(report.shift.startedAt);
    final end = report.shift.endedAt == null
        ? 'agora'
        : DateFormat('HH:mm').format(report.shift.endedAt!);
    final oilTotal = AppConstants.oilIntervalKm;
    final oilUsed = report.oilKmSinceChange.clamp(0, oilTotal).toDouble();
    final oilProgress = (oilUsed / oilTotal).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(date, style: Theme.of(context).textTheme.titleLarge),
        Text(
          '$start – $end · São Bernardo do Campo',
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _metric('Km GPS', formatKm(report.gpsKm))),
            const SizedBox(width: 10),
            Expanded(
              child: _metric('Entregas', '${report.deliveries} pizzas'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _metric('Ganhos', state.money.format(report.earnings)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metric('Gasolina', state.money.format(report.gasCost)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 340,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: points.isEmpty
                    ? (origin ?? const LatLng(-23.6944, -46.5654))
                    : points[points.length ~/ 2],
                initialZoom: 13,
                onMapReady: () => _mapReady = true,
                initialCameraFit: points.length >= 2
                    ? CameraFit.coordinates(
                        coordinates: points,
                        padding: const EdgeInsets.all(40),
                        maxZoom: 14.2,
                      )
                    : null,
              ),
              children: [
                TileLayer(
                  urlTemplate: AppConstants.osmTileUrl,
                  userAgentPackageName: AppConstants.osmUserAgentPackage,
                ),
                if (points.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: points,
                        color: AppColors.accentSoft.withValues(alpha: 0.55),
                        strokeWidth: 5,
                        borderStrokeWidth: 2,
                        borderColor: AppColors.background.withValues(alpha: 0.7),
                      ),
                      if (highlight.length >= 2)
                        Polyline(
                          points: highlight,
                          color: AppColors.cream,
                          strokeWidth: 6,
                        ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    for (var i = 0; i < events.length; i++)
                      if (events[i].point != null)
                        Marker(
                          point: events[i].point!,
                          width: i == _selected ? 40 : 32,
                          height: i == _selected ? 40 : 32,
                          child: GestureDetector(
                            onTap: () => _select(i, events[i]),
                            child: _MapPin(
                              event: events[i],
                              selected: i == _selected,
                            ),
                          ),
                        ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Toque num ponto da linha do tempo para ver exatamente onde você foi.',
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 20),
        const Text(
          'Linha do tempo',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...List.generate(events.length, (index) {
          return _TimelineTile(
            event: events[index],
            selected: index == _selected,
            isLast: index == events.length - 1,
            money: state.money,
            onTap: () => _select(index, events[index]),
          );
        }),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ÓLEO',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Faltam ${report.oilKmRemaining.toStringAsFixed(0)} km para a troca',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: oilProgress,
                  minHeight: 10,
                  backgroundColor: AppColors.surfaceHigh,
                  color: report.oilKmRemaining <= 100
                      ? AppColors.urgent
                      : AppColors.warning,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${oilUsed.toStringAsFixed(0)} de ${oilTotal.toStringAsFixed(0)} km neste ciclo',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        BigButton(
          label: 'Enviar no WhatsApp',
          icon: Icons.chat,
          onPressed: () {
            state.maps.openWhatsApp(
              null,
              text: state.whatsAppReportText(report),
            );
          },
        ),
      ],
    );
  }

  DateTime _rangeStart(List<ShiftTimelineEvent> events, int index) {
    if (index <= 0) {
      return events.first.time;
    }
    return events[index - 1].time;
  }

  void _select(int index, ShiftTimelineEvent event) {
    setState(() => _selected = index);
    final point = event.point;
    if (!_mapReady || point == null) {
      return;
    }
    _mapController.move(point, event.kind == TimelineKind.stop ? 15.2 : 14.2);
  }

  Widget _metric(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.cream,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.event, required this.selected});

  final ShiftTimelineEvent event;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppColors.cream : AppColors.accent;
    final fg = selected ? AppColors.background : Colors.white;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.background, width: 2),
      ),
      child: event.kind == TimelineKind.stop
          ? Text(
              '${event.stopNumber}',
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            )
          : Icon(
              event.kind == TimelineKind.start
                  ? Icons.storefront
                  : Icons.flag,
              size: 16,
              color: fg,
            ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.event,
    required this.selected,
    required this.isLast,
    required this.money,
    required this.onTap,
  });

  final ShiftTimelineEvent event;
  final bool selected;
  final bool isLast;
  final NumberFormat money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hour = DateFormat('HH:mm').format(event.time);
    final travel = <String>[
      if (event.kmFromPrevious != null && event.kmFromPrevious! > 0.05)
        formatKm(event.kmFromPrevious!),
      if (event.minutesFromPrevious != null && event.minutesFromPrevious! > 0)
        '${event.minutesFromPrevious} min',
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              child: Text(
                hour,
                style: TextStyle(
                  color: selected ? AppColors.cream : AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.cream : AppColors.surfaceHigh,
                      shape: BoxShape.circle,
                    ),
                    child: event.kind == TimelineKind.stop
                        ? Text(
                            '${event.stopNumber}',
                            style: TextStyle(
                              color: selected
                                  ? AppColors.background
                                  : AppColors.cream,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : Icon(
                            event.kind == TimelineKind.start
                                ? Icons.storefront
                                : Icons.flag,
                            size: 12,
                            color: selected
                                ? AppColors.background
                                : AppColors.cream,
                          ),
                  ),
                  if (!isLast)
                    Container(
                      width: 2,
                      height: 46,
                      color: AppColors.surfaceHigh,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected ? AppColors.cream : AppColors.cream,
                      ),
                    ),
                    Text(
                      event.subtitle,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                    if (travel.isNotEmpty)
                      Text(
                        travel,
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (event.delivery?.value != null)
              Text(
                money.format(event.delivery!.value!),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ),
    );
  }
}
