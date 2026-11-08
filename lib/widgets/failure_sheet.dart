import 'package:flutter/material.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/models/delivery.dart';

class FailureInput {
  const FailureInput(this.reason, this.note);

  final FailureReason reason;
  final String? note;
}

/// Pergunta o motivo de não ter entregado (obrigatório) e uma observação.
/// Retorna null se o motorista cancelar.
Future<FailureInput?> askFailureReason(BuildContext context) {
  return showModalBottomSheet<FailureInput>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _FailureSheet(),
  );
}

class _FailureSheet extends StatefulWidget {
  const _FailureSheet();

  @override
  State<_FailureSheet> createState() => _FailureSheetState();
}

class _FailureSheetState extends State<_FailureSheet> {
  FailureReason? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needsNote = _reason == FailureReason.other;
    final canSave =
        _reason != null && (!needsNote || _note.text.trim().isNotEmpty);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Por que não entregou?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final reason in FailureReason.values)
                ChoiceChip(
                  label: Text(reason.label),
                  selected: _reason == reason,
                  selectedColor: AppColors.danger.withValues(alpha: 0.3),
                  onSelected: (_) => setState(() => _reason = reason),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            onChanged: (_) => setState(() {}),
            maxLines: 2,
            decoration: InputDecoration(
              labelText: needsNote
                  ? 'Descreva o motivo (obrigatório)'
                  : 'Observação (opcional)',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: canSave
                ? () => Navigator.of(context).pop(
                      FailureInput(
                        _reason!,
                        _note.text.trim().isEmpty ? null : _note.text.trim(),
                      ),
                    )
                : null,
            icon: const Icon(Icons.report_outlined),
            label: const Text('Registrar não entrega'),
          ),
        ],
      ),
    );
  }
}
