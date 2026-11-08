import 'package:flutter/material.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/core/utils/haversine.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/widgets/one_line_label.dart';

/// Destaque da próxima parada, com as três ações mais usadas na rua.
class NextStopCard extends StatelessWidget {
  const NextStopCard({
    super.key,
    required this.delivery,
    required this.position,
    required this.total,
    this.distanceKm,
    required this.onNavigate,
    required this.onDelivered,
    required this.onFailed,
    this.onTap,
  });

  final Delivery delivery;
  final int position;
  final int total;
  final double? distanceKm;
  final VoidCallback onNavigate;
  final VoidCallback onDelivered;
  final VoidCallback onFailed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final onTheWay = delivery.status == DeliveryStatus.inProgress;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.primary, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    onTheWay ? 'A CAMINHO' : 'PRÓXIMA PARADA',
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
              const SizedBox(height: 8),
              Text(
                delivery.displayName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                delivery.shortAddress,
                style: const TextStyle(fontSize: 16, color: AppColors.text),
              ),
              Text(
                [
                  if (delivery.neighborhood?.isNotEmpty ?? false)
                    delivery.neighborhood!,
                  if (distanceKm != null) formatKm(distanceKm!),
                ].join(' · '),
                style: const TextStyle(color: AppColors.muted),
              ),
              if (delivery.notes?.isNotEmpty ?? false) ...[
                const SizedBox(height: 6),
                Text(
                  delivery.notes!,
                  style: const TextStyle(color: AppColors.warning),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onNavigate,
                icon: const Icon(Icons.navigation),
                label: const Text('Navegar'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: AppColors.background,
                      ),
                      onPressed: onDelivered,
                      icon: const Icon(Icons.check),
                      label: const OneLineLabel('Entregue'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onFailed,
                      icon: const Icon(
                        Icons.report_outlined,
                        color: AppColors.danger,
                      ),
                      label: const OneLineLabel('Não entregue'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
