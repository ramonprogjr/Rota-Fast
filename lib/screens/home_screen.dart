import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/core/utils/haversine.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:rota_max/screens/add_delivery_screen.dart';
import 'package:rota_max/screens/confirm_location_screen.dart';
import 'package:rota_max/screens/delivery_detail_screen.dart';
import 'package:rota_max/screens/edit_route_screen.dart';
import 'package:rota_max/screens/paste_addresses_screen.dart';
import 'package:rota_max/screens/scan_tickets_screen.dart';
import 'package:rota_max/screens/settings_screen.dart';
import 'package:rota_max/screens/shift_report_screen.dart';
import 'package:rota_max/widgets/day_panel.dart';
import 'package:rota_max/widgets/delivery_card.dart';
import 'package:rota_max/widgets/failure_sheet.dart';
import 'package:rota_max/widgets/next_stop_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pending = state.pending;
    final done = state.doneToday;
    final problems = state.problems;
    final next = state.nextStop;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rota Max'),
        actions: [
          IconButton(
            tooltip: 'Linha do tempo do turno',
            onPressed: () => _openReport(context),
            icon: const Icon(Icons.timeline),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AddDeliveryScreen(),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Adicionar'),
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                DayPanel(state: state),
                if (state.message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    state.message!,
                    style: const TextStyle(color: AppColors.text),
                  ),
                ],
                if (!state.baseLocation.isConfigured) ...[
                  const SizedBox(height: 12),
                  _BaseLocationBanner(state: state),
                ],
                if (state.oilWarning) ...[
                  const SizedBox(height: 12),
                  _OilBanner(state: state),
                ],
                if (next != null) ...[
                  const SizedBox(height: 12),
                  NextStopCard(
                    delivery: next,
                    position: pending.indexOf(next) + 1,
                    total: pending.length,
                    distanceKm: state.distanceFromPrevious(next),
                    onTap: () => _openDetail(context, next),
                    onNavigate: () => _navigate(context, state, next),
                    onDelivered: () => state.markDelivered(next),
                    onFailed: () => _markFailed(context, state, next),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: state.busy
                            ? null
                            : () => state.organizeRoute(useGps: true),
                        icon: const Icon(Icons.route),
                        label: Text(
                          state.busy ? 'Organizando...' : 'Organizar rota',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: state.activeShift == null
                            ? () => state.startShift()
                            : () => _endShift(context, state),
                        icon: Icon(
                          state.activeShift == null
                              ? Icons.play_arrow
                              : Icons.stop,
                        ),
                        label: Text(
                          state.activeShift == null
                              ? 'Iniciar turno'
                              : 'Encerrar turno',
                        ),
                      ),
                    ),
                  ],
                ),
                if (pending.length > 1) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('home-edit-order'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const EditRouteScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.swap_vert),
                      label: const Text('Editar ordem'),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ScanTicketsScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Etiquetas'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PasteAddressesScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.content_paste),
                        label: const Text('Colar lista'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  pending.isEmpty ? 'Nenhuma parada na rota' : 'Na rota',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (pending.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Toque em Adicionar, fotografe as etiquetas ou cole os endereços.',
                      style: TextStyle(color: AppColors.muted, fontSize: 16),
                    ),
                  ),
                ...pending.asMap().entries.map((entry) {
                  final delivery = entry.value;
                  return DeliveryCard(
                    delivery: delivery,
                    index: entry.key + 1,
                    distanceKm: state.distanceFromPrevious(delivery),
                    onTap: () => _openDetail(context, delivery),
                    onConfirmLocation: () =>
                        _confirmLocation(context, state, delivery),
                  );
                }),
                if (problems.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Com problema',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  ...problems.map(
                    (delivery) => DeliveryCard(
                      delivery: delivery,
                      onTap: () => _openDetail(context, delivery),
                    ),
                  ),
                ],
                if (done.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Concluídas hoje',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  ...done.map(
                    (delivery) => DeliveryCard(
                      delivery: delivery,
                      onTap: () => _openDetail(context, delivery),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _TimelineCard(state: state, onTap: () => _openReport(context)),
                const SizedBox(height: 12),
                const Text(
                  'Monte a rota com o veículo parado. No caminho, use os comandos de voz do app de navegação.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ],
            ),
    );
  }

  Future<void> _markFailed(
    BuildContext context,
    AppState state,
    Delivery delivery,
  ) async {
    final input = await askFailureReason(context);
    if (input != null) {
      await state.markFailed(delivery, input.reason, note: input.note);
    }
  }

  void _openReport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ShiftReportScreen(),
      ),
    );
  }

  Future<void> _endShift(BuildContext context, AppState state) async {
    final ended = await state.endShift();
    if (!context.mounted || ended == null) {
      return;
    }
    final report = await state.reportFor(ended);
    if (!context.mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShiftReportScreen(report: report),
      ),
    );
  }

  Future<void> _confirmLocation(
    BuildContext context,
    AppState state,
    Delivery delivery,
  ) async {
    final results = await state.searchAddress(query: delivery.fullAddress);
    if (!context.mounted || results.isEmpty) {
      return;
    }
    final confirmed = await Navigator.of(context).push<GeoResult>(
      MaterialPageRoute(
        builder: (_) => ConfirmLocationScreen(
          address: delivery.fullAddress,
          candidates: results,
        ),
      ),
    );
    if (confirmed != null) {
      await state.confirmLocation(delivery, confirmed);
    }
  }

  Future<void> _navigate(
    BuildContext context,
    AppState state,
    Delivery delivery,
  ) async {
    final ok = await state.navigateTo(delivery);
    if (!context.mounted) {
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir a navegação.')),
      );
    }
  }

  void _openDetail(BuildContext context, Delivery delivery) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeliveryDetailScreen(deliveryId: delivery.id!),
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.state, required this.onTap});

  final AppState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shift = state.lastEndedShift;
    final km = shift == null ? null : formatKm(shift.gpsKm);
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.timeline, color: Colors.white, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Linha do tempo',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      km == null
                          ? 'Toque para ver exatamente onde você foi'
                          : '$km no mapa · toque para ver o caminho',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _BaseLocationBanner extends StatelessWidget {
  const _BaseLocationBanner({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final baseLocation = state.baseLocation;
    final configured = baseLocation.isConfigured;
    return Material(
      color: configured ? AppColors.surface : AppColors.warningSurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.storefront, color: AppColors.text),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      baseLocation.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      configured
                          ? baseLocation.fullAddress
                          : 'Toque para cadastrar o ponto de partida',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _OilBanner extends StatelessWidget {
  const _OilBanner({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final vehicle = state.vehicle;
    return Material(
      color: AppColors.warningSurface,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.oil_barrel_outlined, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${vehicle.name}: faltam ${vehicle.oilRemainingKm.round()} km '
                'para a troca de óleo (a cada '
                '${vehicle.oilIntervalKm.round()} km).',
                style: const TextStyle(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
