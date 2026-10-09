import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rota_pizza/core/theme/app_theme.dart';
import 'package:rota_pizza/models/dashboard.dart';
import 'package:rota_pizza/providers/app_state.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final summary = DashboardSummary(
      companyId: 'local-company',
      date: '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
      deliveries: state.summary.totalCount,
      earnings: state.summary.earnings,
      km: state.summary.estimatedKm,
      activeDrivers: state.activeShift == null ? 0 : 1,
      pendingRoutes: state.pending.length,
      completedShifts: state.lastEndedShift == null ? 0 : 1,
    );

    final metrics = summary.metrics();

    return Scaffold(
      appBar: AppBar(title: const Text('Painel da operação')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            'Rota Max · visão de operação',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.45,
            physics: const NeverScrollableScrollPhysics(),
            children: metrics
                .map(
                  (metric) => _MetricCard(
                    label: metric.label,
                    value: metric.value,
                    trend: metric.trend,
                    helper: metric.helper,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
          const Text(
            'Indicadores da operação',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          _InfoLine(
            label: 'Entregas pendentes',
            value: '${summary.pendingRoutes}',
          ),
          _InfoLine(
            label: 'Média por entrega',
            value: 'R\$ ${summary.avgEarningsPerDelivery.toStringAsFixed(1)}',
          ),
          _InfoLine(
            label: 'Km por entrega',
            value: '${summary.avgDeliveriesPerDriver.toStringAsFixed(1)}',
          ),
          _InfoLine(
            label: 'Turnos concluídos',
            value: '${summary.completedShifts}',
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Próxima etapa',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Autenticação, usuários por empresa, turnos por entregador e painel administrativo.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    this.trend,
    this.helper,
  });

  final String label;
  final String value;
  final String? trend;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
          Text(
            value,
            style: const TextStyle(
              color: AppColors.cream,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (trend != null)
            Text(
              trend!,
              style: const TextStyle(
                color: AppColors.accentSoft,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (helper != null)
            Text(
              helper!,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted)),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.cream,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
