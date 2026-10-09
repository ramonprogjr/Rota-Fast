import 'package:flutter/material.dart';
import 'package:rota_pizza/core/theme/app_theme.dart';
import 'package:rota_pizza/core/utils/haversine.dart';
import 'package:rota_pizza/models/shift_summary.dart';

class ShiftStatsBar extends StatelessWidget {
  const ShiftStatsBar({super.key, required this.summary, this.earningsLabel});

  final ShiftSummary summary;
  final String? earningsLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 12,
        children: [
          _stat('Entregas', '${summary.pendingCount} pend.'),
          _stat('Estimativa', formatKm(summary.estimatedKm)),
          _stat('Tempo', formatDuration(summary.estimatedDuration)),
          _stat('Hoje', '${summary.doneCount} feitas'),
          if (summary.doneCount > 0)
            _stat('Média', 'R\$ ${summary.avgDeliveryValue.toStringAsFixed(0)}'),
          if (summary.estimatedKm > 0)
            _stat('R\$/km', 'R\$ ${summary.earningsPerKm.toStringAsFixed(1)}'),
          if (earningsLabel != null) _stat('Ganhos', earningsLabel!),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
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
            color: AppColors.cream,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
