import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/core/utils/haversine.dart';
import 'package:rota_max/core/utils/phone_utils.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/delivery_event.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:rota_max/screens/add_delivery_screen.dart';
import 'package:rota_max/screens/confirm_location_screen.dart';
import 'package:rota_max/widgets/nav_app_sheet.dart';
import 'package:rota_max/widgets/big_button.dart';
import 'package:rota_max/widgets/failure_sheet.dart';

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
                color: AppColors.primarySoft,
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
                final results = await state.searchAddress(
                  query: current.fullAddress,
                  state: current.state,
                  postalCode: current.postalCode,
                );
                if (!context.mounted) {
                  return;
                }
                if (results.isEmpty) {
                  final manual = await ConfirmLocationScreen.askMarkOnMap(
                    context,
                    message: state.message,
                  );
                  if (!manual || !context.mounted) {
                    return;
                  }
                }
                final confirmed = await Navigator.of(context).push<GeoResult>(
                  MaterialPageRoute(
                    builder: (_) => ConfirmLocationScreen(
                      address: current.fullAddress,
                      candidates: results,
                      center: current.hasCoordinates
                          ? GeoPoint(current.latitude!, current.longitude!)
                          : state.originPoint,
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
          const SizedBox(height: 16),
          _StatusLine(delivery: current),
          const SizedBox(height: 16),
          if (current.isOpen) ...[
            BigButton(
              label: current.status == DeliveryStatus.inProgress
                  ? 'Navegar (a caminho)'
                  : 'Navegar',
              icon: Icons.navigation,
              onPressed: () => navigateToDelivery(context, state, current),
            ),
            const SizedBox(height: 10),
            BigButton(
              label: 'Entregue',
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final input = await askFailureReason(context);
                      if (input == null) {
                        return;
                      }
                      await state.markFailed(
                        current,
                        input.reason,
                        note: input.note,
                      );
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.report_outlined,
                        color: AppColors.danger),
                    label: const Text('Não entregue'),
                  ),
                ),
                const SizedBox(width: 8),
                if (current.status != DeliveryStatus.skipped)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => state.skip(current),
                      icon: const Icon(Icons.skip_next,
                          color: AppColors.warning),
                      label: const Text('Pular'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => state.recalculateFrom(current),
              icon: const Icon(Icons.refresh),
              label: const Text('Recalcular rota a partir daqui'),
            ),
          ] else if (current.isFailed) ...[
            BigButton(
              label: 'Tentar de novo',
              icon: Icons.replay,
              onPressed: () => state.retry(current),
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: () => _confirmReopen(context, state, current),
              icon: const Icon(Icons.undo),
              label: const Text('Reabrir (marquei por engano)'),
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
          const SizedBox(height: 24),
          Text('Histórico', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _EventTimeline(
            // Recarrega quando o status ou a data de atualização mudam.
            key: ValueKey('${current.status}-${current.updatedAt}'),
            future: state.eventsFor(current),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReopen(
    BuildContext context,
    AppState state,
    Delivery delivery,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reabrir entrega?'),
        content: const Text(
          'Ela volta para a rota como pendente. A mudança fica no histórico.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reabrir'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await state.reopen(delivery);
    }
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

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.delivery});

  final Delivery delivery;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forStatus(delivery.status);
    final detail = switch (delivery.status) {
      DeliveryStatus.failed => [
          delivery.failureReason?.label,
          if (delivery.attempts > 1) '${delivery.attempts} tentativas',
        ].whereType<String>().join(' · '),
      DeliveryStatus.delivered when delivery.deliveredAt != null =>
        'às ${DateFormat('HH:mm').format(delivery.deliveredAt!)}',
      _ => '',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 12, color: color),
          const SizedBox(width: 10),
          Text(
            delivery.status.label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                detail,
                style: const TextStyle(color: AppColors.text),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EventTimeline extends StatelessWidget {
  const _EventTimeline({super.key, required this.future});

  final Future<List<DeliveryEvent>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DeliveryEvent>>(
      future: future,
      builder: (context, snapshot) {
        final events = snapshot.data;
        if (events == null) {
          return const SizedBox(height: 24);
        }
        if (events.isEmpty) {
          return const Text(
            'Sem registros.',
            style: TextStyle(color: AppColors.muted),
          );
        }
        final time = DateFormat('dd/MM HH:mm');
        return Column(
          children: [
            for (final event in events.reversed)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.circle,
                  size: 12,
                  color: AppColors.forStatus(event.to),
                ),
                title: Text(
                  event.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  [
                    time.format(event.createdAt),
                    event.reason?.label,
                    event.note,
                  ].whereType<String>().join(' · '),
                ),
              ),
          ],
        );
      },
    );
  }
}
