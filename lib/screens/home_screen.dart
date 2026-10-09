import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rota_pizza/core/theme/app_theme.dart';
import 'package:rota_pizza/core/utils/haversine.dart';
import 'package:rota_pizza/models/delivery.dart';
import 'package:rota_pizza/models/geo_result.dart';
import 'package:rota_pizza/providers/app_state.dart';
import 'package:rota_pizza/screens/add_delivery_screen.dart';
import 'package:rota_pizza/screens/confirm_location_screen.dart';
import 'package:rota_pizza/screens/dashboard_screen.dart';
import 'package:rota_pizza/screens/delivery_detail_screen.dart';
import 'package:rota_pizza/screens/history_screen.dart';
import 'package:rota_pizza/screens/paste_addresses_screen.dart';
import 'package:rota_pizza/screens/scan_tickets_screen.dart';
import 'package:rota_pizza/screens/settings_screen.dart';
import 'package:rota_pizza/screens/shift_report_screen.dart';
import 'package:rota_pizza/widgets/delivery_card.dart';
import 'package:rota_pizza/widgets/shift_stats_bar.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pending = state.pending;
    final done = state.doneToday;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rota Food'),
        actions: [
          IconButton(
            tooltip: 'Linha do tempo',
            onPressed: () => _openReport(context),
            icon: const Icon(Icons.timeline),
          ),
          IconButton(
            tooltip: 'Painel da operação',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DashboardScreen()),
              );
            },
            icon: const Icon(Icons.insights_outlined),
          ),
          IconButton(
            tooltip: 'Histórico',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
              );
            },
            icon: const Icon(Icons.bar_chart),
          ),
          IconButton(
            tooltip: 'Estabelecimento e ajustes',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              );
            },
            icon: const Icon(Icons.storefront_outlined),
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
                _TimelineCard(state: state, onTap: () => _openReport(context)),
                const SizedBox(height: 12),
                _PizzeriaBanner(state: state),
                const SizedBox(height: 12),
                if (state.oilWarning)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Óleo: faltam menos de 100 km para a troca (a cada 1000 km).',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ShiftStatsBar(
                  summary: state.summary,
                  earningsLabel: state.summary.earnings > 0
                      ? state.money.format(state.summary.earnings)
                      : null,
                ),
                if (state.message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    state.message!,
                    style: const TextStyle(color: AppColors.cream),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: state.activeShift == null
                      ? () => state.startShift()
                      : () => _endShift(context, state),
                  icon: Icon(
                    state.activeShift == null ? Icons.play_arrow : Icons.stop,
                  ),
                  label: Text(
                    state.activeShift == null
                        ? 'Iniciar turno'
                        : 'Encerrar turno',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _openReport(context),
                  icon: const Icon(Icons.timeline),
                  label: const Text('Linha do tempo'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: state.busy
                      ? null
                      : () => state.organizeRoute(useGps: true),
                  icon: const Icon(Icons.route),
                  label: Text(
                    state.busy ? 'Organizando...' : 'Organizar rota',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ScanTicketsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Fotografar comandas'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PasteAddressesScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Colar vários endereços'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Configure a rota parado. No caminho, use o Google Maps. O turno precisa ficar ativo para registrar o km.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Text(
                  pending.isEmpty ? 'Nenhuma entrega pendente' : 'Entregas',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (pending.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Toque em Adicionar, fotografe as comandas ou cole os endereços.',
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
                    onNavigate: () => _navigate(context, state, delivery),
                    onDelivered: () => state.markDelivered(delivery),
                    onConfirmLocation: () =>
                        _confirmLocation(context, state, delivery),
                  );
                }),
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
              ],
            ),
    );
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
    final ok = await state.maps.navigate(address: delivery.fullAddress);
    if (!context.mounted) {
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o Google Maps.')),
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
      color: AppColors.accent,
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

class _PizzeriaBanner extends StatelessWidget {
  const _PizzeriaBanner({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final pizzeria = state.pizzeria;
    final configured = pizzeria.isConfigured;
    return Material(
      color: configured ? AppColors.surface : const Color(0xFF3A2218),
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
              const Icon(Icons.storefront, color: AppColors.cream),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pizzeria.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      configured
                          ? pizzeria.fullAddress
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
