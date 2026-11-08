import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/providers/app_state.dart';

/// Edição manual da ordem das paradas abertas (RF-002). Cada mudança já é
/// gravada no aparelho; concluídas não aparecem aqui.
class EditRouteScreen extends StatelessWidget {
  const EditRouteScreen({super.key});

  Future<void> _move(AppState state, List<Delivery> list, int from, int to) {
    final next = [...list];
    final item = next.removeAt(from);
    next.insert(to, item);
    return state.reorderStops(next);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final stops = state.pending;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar ordem'),
        actions: [
          IconButton(
            key: const Key('edit-route-undo'),
            tooltip: 'Desfazer',
            onPressed:
                state.canUndo && !state.busy ? () => state.undoReorder() : null,
            icon: const Icon(Icons.undo),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              stops.isEmpty
                  ? 'Nenhuma parada aberta para ordenar.'
                  : 'Arraste pela alça ou use as setas. Cadeado: a parada '
                      'fica onde está ao recalcular. Alfinete: posição fixa.',
              style: const TextStyle(color: AppColors.muted, fontSize: 14),
            ),
          ),
          if (state.message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                state.message!,
                style: const TextStyle(color: AppColors.text),
              ),
            ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              buildDefaultDragHandles: false,
              itemCount: stops.length,
              // onReorderItem já entrega o índice final ajustado.
              onReorderItem: (from, to) {
                if (from != to) {
                  _move(state, stops, from, to);
                }
              },
              itemBuilder: (context, index) {
                final item = stops[index];
                return _StopTile(
                  key: ValueKey('stop-${item.id}'),
                  delivery: item,
                  index: index,
                  isFirst: index == 0,
                  isLast: index == stops.length - 1,
                  enabled: !state.busy,
                  onUp: () => _move(state, stops, index, index - 1),
                  onDown: () => _move(state, stops, index, index + 1),
                  onLock: () => state.toggleLock(item),
                  onPin: () => state.togglePin(item),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state.busy || stops.isEmpty
                          ? null
                          : () => state.organizeRoute(),
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text(
                        'Recalcular respeitando travas',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        // Cada mudança já foi gravada; aqui só confirma.
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ordem salva.')),
                        );
                        Navigator.of(context).maybePop();
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Salvar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({
    super.key,
    required this.delivery,
    required this.index,
    required this.isFirst,
    required this.isLast,
    required this.enabled,
    required this.onUp,
    required this.onDown,
    required this.onLock,
    required this.onPin,
  });

  final Delivery delivery;
  final int index;
  final bool isFirst;
  final bool isLast;
  final bool enabled;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onLock;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) {
    final id = delivery.id;
    final pinned = delivery.fixedPosition != null;
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    '${index + 1}',
                    key: Key('stop-number-$id'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        delivery.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        delivery.shortAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      if (delivery.status != DeliveryStatus.pending)
                        Text(
                          delivery.status.label,
                          style: const TextStyle(
                            color: AppColors.warning,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                ReorderableDragStartListener(
                  index: index,
                  enabled: enabled,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      Icons.drag_handle,
                      key: Key('stop-drag-$id'),
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  key: Key('stop-up-$id'),
                  tooltip: 'Subir',
                  onPressed: enabled && !isFirst ? onUp : null,
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  key: Key('stop-down-$id'),
                  tooltip: 'Descer',
                  onPressed: enabled && !isLast ? onDown : null,
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  key: Key('stop-lock-$id'),
                  tooltip: delivery.locked ? 'Destravar' : 'Travar no lugar',
                  onPressed: enabled ? onLock : null,
                  color: delivery.locked ? AppColors.warning : null,
                  icon: Icon(delivery.locked ? Icons.lock : Icons.lock_open),
                ),
                IconButton(
                  key: Key('stop-pin-$id'),
                  tooltip: pinned
                      ? 'Soltar da posição ${delivery.fixedPosition! + 1}'
                      : 'Fixar nesta posição',
                  onPressed: enabled ? onPin : null,
                  color: pinned ? AppColors.primarySoft : null,
                  icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
