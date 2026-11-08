import 'package:flutter/material.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/core/utils/haversine.dart';
import 'package:rota_max/providers/app_state.dart';

/// Topo da aba Rota: progresso do dia e números principais (PRD §3.1).
class DayPanel extends StatelessWidget {
  const DayPanel({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final summary = state.summary;
    final problems = state.problems.length;
    final done = summary.doneCount;
    final total = done + summary.pendingCount + problems;
    final progress = total == 0 ? 0.0 : done / total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  total == 0
                      ? 'Nenhuma entrega hoje'
                      : '$done de $total entregas',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                  color: AppColors.primarySoft,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.surfaceHigh,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Metric(label: 'Na rota', value: '${summary.pendingCount}'),
              _Metric(
                label: 'Problemas',
                value: '$problems',
                color: problems > 0 ? AppColors.danger : null,
              ),
              _Metric(label: 'Restam', value: formatKm(summary.estimatedKm)),
              _Metric(
                label: 'Tempo',
                value: formatDuration(summary.estimatedDuration),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color ?? AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
