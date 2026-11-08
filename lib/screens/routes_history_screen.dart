import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/core/utils/haversine.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/delivery_route.dart';
import 'package:rota_max/providers/app_state.dart';

String routeTitle(DeliveryRoute route) {
  final name = route.name?.trim();
  if (name != null && name.isNotEmpty) {
    return name;
  }
  return 'Rota de ${DateFormat("dd/MM 'às' HH:mm", 'pt_BR').format(route.createdAt)}';
}

String routeLine(RouteSummary item) {
  final parts = <String>[
    '${item.stops} parada(s)',
    '${item.delivered} entregue(s)',
    if (item.failed > 0) '${item.failed} não entregue(s)',
    if (item.estimatedKm != null) formatKm(item.estimatedKm!),
    if (item.savedKm > 0) 'economia ${formatKm(item.savedKm)}',
  ];
  return parts.join(' · ');
}

/// Rotas anteriores (RF-004): ver, reabrir e excluir.
class RoutesHistoryScreen extends StatefulWidget {
  const RoutesHistoryScreen({super.key});

  @override
  State<RoutesHistoryScreen> createState() => _RoutesHistoryScreenState();
}

class _RoutesHistoryScreenState extends State<RoutesHistoryScreen> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AppState>().loadRoutes();
      if (mounted) {
        setState(() => _loaded = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final routes = state.routes;
    return Scaffold(
      appBar: AppBar(title: const Text('Rotas')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : routes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Nenhuma rota ainda. Organize a rota na aba Rota.',
                    style: TextStyle(color: AppColors.muted, fontSize: 16),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: routes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = routes[index];
                    return Material(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        key: Key('route-${item.id}'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                routeTitle(item.route),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (item.route.isActive)
                              const Text(
                                'ATIVA',
                                style: TextStyle(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(routeLine(item)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => RouteDetailScreen(summary: item),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class RouteDetailScreen extends StatefulWidget {
  const RouteDetailScreen({super.key, required this.summary});

  final RouteSummary summary;

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  late Future<List<Delivery>> _stops;

  @override
  void initState() {
    super.initState();
    _stops = context.read<AppState>().stopsOfRoute(widget.summary.id);
  }

  Future<void> _reopen(AppState state) async {
    final ok = await state.openRoute(widget.summary.id);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(state.message ?? 'Rota reaberta.')),
    );
    if (ok) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _delete(AppState state) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir rota?'),
        content: const Text(
          'A rota e a ordem das paradas serão apagadas. As entregas continuam '
          'salvas; as que ainda estão abertas voltam para a lista.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Excluir',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      return;
    }
    final ok = await state.deleteRoute(widget.summary.id);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(state.message ?? 'Rota excluída.')),
    );
    if (ok) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final summary = widget.summary;
    return Scaffold(
      appBar: AppBar(title: Text(routeTitle(summary.route))),
      body: FutureBuilder<List<Delivery>>(
        future: _stops,
        builder: (context, snapshot) {
          final stops = snapshot.data ?? const <Delivery>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                routeLine(summary),
                style: const TextStyle(color: AppColors.muted, fontSize: 15),
              ),
              if (summary.bestPlan != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Ordem de cadastro: ${formatKm(summary.bestPlan!.baselineKm)}'
                  ' · organizada: ${formatKm(summary.bestPlan!.optimizedKm)}',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
              const SizedBox(height: 16),
              if (!snapshot.hasData)
                const Center(child: CircularProgressIndicator())
              else if (stops.isEmpty)
                const Text(
                  'Sem paradas.',
                  style: TextStyle(color: AppColors.muted),
                ),
              for (var i = 0; i < stops.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.forStatus(stops[i].status),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(stops[i].displayName),
                  subtitle: Text(
                    '${stops[i].shortAddress} · ${stops[i].status.label}',
                  ),
                ),
              const SizedBox(height: 16),
              if (!summary.route.isActive)
                FilledButton.icon(
                  onPressed: state.busy ? null : () => _reopen(state),
                  icon: const Icon(Icons.replay),
                  label: const Text('Reabrir esta rota'),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: state.busy ? null : () => _delete(state),
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                label: const Text('Excluir rota'),
              ),
            ],
          );
        },
      ),
    );
  }
}
