import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/core/utils/haversine.dart';
import 'package:rota_max/providers/app_state.dart';

/// Painel pessoal do dia: só números calculados a partir dos dados do aparelho.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final summary = state.summary;
    final total = summary.totalCount;
    final progress = total == 0 ? 0.0 : summary.doneCount / total;
    final today = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(DateTime.now());

    final metrics = <(String, String)>[
      ('Pedidos hoje', '$total'),
      ('Concluídos', '${summary.doneCount}'),
      ('Pendentes', '${summary.pendingCount}'),
      ('Distância restante', formatKm(summary.estimatedKm)),
      ('Tempo restante', formatDuration(summary.estimatedDuration)),
      ('Recebido hoje', state.money.format(summary.earnings)),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Painel do dia')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(_greeting(), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(today, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 16),
          _ProgressCard(progress: progress, done: summary.doneCount, total: total),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.7,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final (label, value) in metrics)
                _MetricCard(label: label, value: value),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Distância e tempo são estimativas a partir das paradas pendentes.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Bom dia';
    }
    if (hour < 18) {
      return 'Boa tarde';
    }
    return 'Boa noite';
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.progress,
    required this.done,
    required this.total,
  });

  final double progress;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Progresso: ${(progress * 100).round()}%',
            style: const TextStyle(
              color: AppColors.cream,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: AppColors.surfaceHigh,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$done de $total entregas',
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

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
        ],
      ),
    );
  }
}
