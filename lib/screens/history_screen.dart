import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rota_pizza/core/theme/app_theme.dart';
import 'package:rota_pizza/models/delivery.dart';
import 'package:rota_pizza/providers/app_state.dart';
import 'package:rota_pizza/screens/delivery_detail_screen.dart';
import 'package:rota_pizza/widgets/delivery_card.dart';
import 'package:rota_pizza/widgets/shift_stats_bar.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final week = state.weekStats();
    final grouped = state.historyByDay();
    final dayFormat = DateFormat("EEE dd/MM", 'pt_BR');
    final headerFormat = DateFormat("EEEE, dd/MM", 'pt_BR');

    return Scaffold(
      appBar: AppBar(title: const Text('Histórico')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          ShiftStatsBar(
            summary: state.summary,
            earningsLabel: state.money.format(state.summary.earnings),
          ),
          const SizedBox(height: 16),
          const Text(
            'Esta semana',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...week.map((day) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(dayFormat.format(day.day)),
              trailing: Text(
                '${day.deliveries} · ${state.money.format(day.earnings)}',
                style: const TextStyle(color: AppColors.cream),
              ),
            );
          }),
          const SizedBox(height: 16),
          if (grouped.isEmpty)
            const Text(
              'Nenhuma entrega concluída ainda.',
              style: TextStyle(color: AppColors.muted),
            ),
          ...grouped.entries.expand((entry) {
            final date = DateTime.parse(entry.key);
            return [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  headerFormat.format(date),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              ...entry.value.map(
                (Delivery delivery) => DeliveryCard(
                  delivery: delivery,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            DeliveryDetailScreen(deliveryId: delivery.id!),
                      ),
                    );
                  },
                ),
              ),
            ];
          }),
        ],
      ),
    );
  }
}
