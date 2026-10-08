import 'package:flutter/material.dart';
import 'package:rota_pizza/core/theme/app_theme.dart';
import 'package:rota_pizza/core/utils/haversine.dart';
import 'package:rota_pizza/models/delivery.dart';

class DeliveryCard extends StatelessWidget {
  const DeliveryCard({
    super.key,
    required this.delivery,
    this.index,
    this.distanceKm,
    this.onTap,
    this.onNavigate,
    this.onDelivered,
    this.onConfirmLocation,
  });

  final Delivery delivery;
  final int? index;
  final double? distanceKm;
  final VoidCallback? onTap;
  final VoidCallback? onNavigate;
  final VoidCallback? onDelivered;
  final VoidCallback? onConfirmLocation;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _badge(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      delivery.displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.cream,
                      ),
                    ),
                  ),
                  _priorityChip(),
                ],
              ),
              if (delivery.orderNumber != null &&
                  delivery.orderNumber!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Pedido #${delivery.orderNumber}',
                  style: const TextStyle(
                    color: AppColors.accentSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                delivery.shortAddress,
                style: const TextStyle(fontSize: 16, color: AppColors.cream),
              ),
              Text(
                delivery.city,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (distanceKm != null)
                    Text(
                      formatKm(distanceKm!),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (!delivery.hasCoordinates) ...[
                    const SizedBox(width: 8),
                    const Text(
                      'Sem localização',
                      style: TextStyle(color: AppColors.warning),
                    ),
                  ] else if (!delivery.locationConfirmed) ...[
                    const SizedBox(width: 8),
                    const Text(
                      'Conferir ponto',
                      style: TextStyle(color: AppColors.warning),
                    ),
                  ] else ...[
                    const SizedBox(width: 8),
                    const Text(
                      'Local confirmado',
                      style: TextStyle(color: AppColors.success),
                    ),
                  ],
                ],
              ),
              if (delivery.isPending &&
                  (onNavigate != null || onDelivered != null)) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (onNavigate != null)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onNavigate,
                          icon: const Icon(Icons.navigation),
                          label: const Text('Navegar'),
                        ),
                      ),
                    if (onNavigate != null && onDelivered != null)
                      const SizedBox(width: 8),
                    if (onDelivered != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onDelivered,
                          icon: const Icon(Icons.check, color: AppColors.success),
                          label: const Text('Entregue'),
                        ),
                      ),
                  ],
                ),
                if (onConfirmLocation != null &&
                    (!delivery.locationConfirmed || !delivery.hasCoordinates))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: onConfirmLocation,
                      icon: const Icon(Icons.pin_drop),
                      label: const Text('Confirmar no mapa'),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge() {
    final label = index != null ? '$index' : (delivery.isPending ? '•' : '✓');
    return CircleAvatar(
      radius: 18,
      backgroundColor:
          delivery.isPending ? AppColors.accent : AppColors.success,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _priorityChip() {
    if (delivery.priority == DeliveryPriority.normal) {
      return const SizedBox.shrink();
    }
    final urgent = delivery.priority == DeliveryPriority.urgent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: urgent ? AppColors.urgent : AppColors.warning,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        urgent ? 'URGENTE' : 'ALTA',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.black,
        ),
      ),
    );
  }
}
