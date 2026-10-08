import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rota_pizza/core/theme/app_theme.dart';
import 'package:rota_pizza/core/utils/haversine.dart';
import 'package:rota_pizza/core/utils/phone_utils.dart';
import 'package:rota_pizza/models/delivery.dart';
import 'package:rota_pizza/models/geo_result.dart';
import 'package:rota_pizza/providers/app_state.dart';
import 'package:rota_pizza/screens/add_delivery_screen.dart';
import 'package:rota_pizza/screens/confirm_location_screen.dart';
import 'package:rota_pizza/widgets/big_button.dart';

class DeliveryDetailScreen extends StatelessWidget {
  const DeliveryDetailScreen({super.key, required this.deliveryId});

  final int deliveryId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    Delivery? match;
    for (final item in state.items) {
      if (item.id == deliveryId) {
        match = item;
        break;
      }
    }
    if (match == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Entrega')),
        body: const Center(child: Text('Entrega não encontrada.')),
      );
    }

    final current = match;
    final distance = state.distanceFromPrevious(current);
    final canCall = PhoneUtils.telUrl(current.phone) != null;
    final canWhats = PhoneUtils.whatsAppUrl(current.phone) != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(current.displayName),
        actions: [
          IconButton(
            tooltip: 'Editar',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AddDeliveryScreen(existing: current),
                ),
              );
            },
            icon: const Icon(Icons.edit),
          ),
          IconButton(
            tooltip: 'Excluir',
            onPressed: () => _confirmDelete(context, state, current),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (current.orderNumber != null)
            Text(
              'Pedido #${current.orderNumber}',
              style: const TextStyle(
                color: AppColors.accentSoft,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(height: 8),
          Text(current.fullAddress, style: const TextStyle(fontSize: 18)),
          if (current.phone != null) ...[
            const SizedBox(height: 8),
            Text(
              current.phone!,
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 12),
          if (distance != null)
            Text('Trecho estimado: ${formatKm(distance)} (linha reta)'),
          if (current.value != null)
            Text('Valor: ${state.money.format(current.value)}'),
          Text(
            current.locationConfirmed
                ? 'Local confirmado no mapa'
                : (current.hasCoordinates
                    ? 'Ponto ainda não confirmado — confira antes de sair'
                    : 'Ainda sem coordenadas — localize na edição.'),
            style: TextStyle(
              color: current.locationConfirmed
                  ? AppColors.success
                  : AppColors.warning,
            ),
          ),
          if (!current.locationConfirmed) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final results =
                    await state.searchAddress(query: current.fullAddress);
                if (!context.mounted || results.isEmpty) {
                  return;
                }
                final confirmed = await Navigator.of(context).push<GeoResult>(
                  MaterialPageRoute(
                    builder: (_) => ConfirmLocationScreen(
                      address: current.fullAddress,
                      candidates: results,
                    ),
                  ),
                );
                if (confirmed != null) {
                  await state.confirmLocation(current, confirmed);
                }
              },
              icon: const Icon(Icons.pin_drop),
              label: const Text('Confirmar no mapa'),
            ),
          ],
          const SizedBox(height: 24),
          if (current.isPending) ...[
            BigButton(
              label: 'Navegar',
              icon: Icons.navigation,
              onPressed: () async {
                final ok = await state.maps.navigate(
                  address: current.fullAddress,
                );
                if (!context.mounted) {
                  return;
                }
                if (!ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Não foi possível abrir o Google Maps.'),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 10),
            BigButton(
              label: 'Marcar como entregue',
              icon: Icons.check_circle,
              color: AppColors.success,
              onPressed: () async {
                await state.markDelivered(current);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => state.recalculateFrom(current),
              icon: const Icon(Icons.refresh),
              label: const Text('Recalcular rota a partir daqui'),
            ),
          ] else ...[
            const Text(
              'Entrega concluída',
              style: TextStyle(
                color: AppColors.success,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => state.reopen(current),
              child: const Text('Reabrir como pendente'),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canWhats
                      ? () => state.maps.openWhatsApp(current.phone)
                      : null,
                  icon: const Icon(Icons.chat),
                  label: const Text('WhatsApp'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      canCall ? () => state.maps.call(current.phone) : null,
                  icon: const Icon(Icons.phone),
                  label: const Text('Ligar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppState state,
    Delivery delivery,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir entrega?'),
        content: Text('Remover ${delivery.displayName} da lista.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true && delivery.id != null) {
      await state.deleteDelivery(delivery.id!);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}
