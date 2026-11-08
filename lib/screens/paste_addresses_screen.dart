import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/core/utils/address_parser.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:rota_max/widgets/big_button.dart';

class PasteAddressesScreen extends StatefulWidget {
  const PasteAddressesScreen({super.key});

  @override
  State<PasteAddressesScreen> createState() => _PasteAddressesScreenState();
}

class _PasteAddressesScreenState extends State<PasteAddressesScreen> {
  final _controller = TextEditingController();
  List<ParsedDelivery> _preview = [];

  /// Para cada linha, a entrega que ela provavelmente repete (ou null).
  List<Delivery?> _duplicates = [];

  /// Linhas repetidas que o usuário marcou para salvar mesmo assim.
  final Set<int> _includeDuplicate = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parse(String value) {
    final state = context.read<AppState>();
    final parsed = AddressParser.parseBatch(value);
    setState(() {
      _preview = parsed;
      _duplicates = state.duplicatesFor(parsed);
      _includeDuplicate.clear();
    });
  }

  List<ParsedDelivery> get _selected => [
    for (var i = 0; i < _preview.length; i++)
      if (_duplicates[i] == null || _includeDuplicate.contains(i)) _preview[i],
  ];

  Future<void> _import({required bool locate}) async {
    final state = context.read<AppState>();
    await state.importParsed(
      _selected,
      locate: locate,
      includeDuplicates: true,
    );
    if (!mounted) {
      return;
    }
    final text = state.message;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    if (text != null) {
      messenger.showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final duplicateCount = _duplicates.where((item) => item != null).length;
    final selectedCount = _selected.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Colar endereços')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'Cole uma entrega por linha. Dá para copiar do WhatsApp.',
            style: TextStyle(color: AppColors.muted, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Exemplo:\nJoão — Rua Marechal Deodoro, 1500, Centro\nMaria — Av. Kennedy, 456, Rudge Ramos, 09750-000',
            style: TextStyle(color: AppColors.text, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('paste-field'),
            controller: _controller,
            minLines: 8,
            maxLines: 16,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Cole os endereços aqui',
            ),
            onChanged: _parse,
          ),
          const SizedBox(height: 12),
          Text(
            _preview.isEmpty
                ? 'Nenhum endereço reconhecido ainda.'
                : '${_preview.length} endereço(s) reconhecido(s)',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (duplicateCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              '$duplicateCount provável(is) repetida(s). Marque as que devem ser salvas mesmo assim.',
              style: const TextStyle(color: AppColors.warning),
            ),
          ],
          for (var i = 0; i < _preview.length; i++) _row(i),
          const SizedBox(height: 16),
          BigButton(
            key: const Key('paste-locate-all'),
            label: state.busy ? 'Localizando...' : 'Localizar todos agora',
            icon: Icons.travel_explore,
            onPressed: state.busy || selectedCount == 0
                ? null
                : () => _import(locate: true),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('paste-save'),
            onPressed: state.busy || selectedCount == 0
                ? null
                : () => _import(locate: false),
            icon: const Icon(Icons.playlist_add),
            label: Text(
              state.busy
                  ? 'Importando...'
                  : 'Só salvar ($selectedCount) e localizar depois',
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(int index) {
    final item = _preview[index];
    final duplicate = _duplicates[index];
    final details = [
      item.address,
      if ((item.number ?? '').isNotEmpty) item.number!,
      if ((item.neighborhood ?? '').isNotEmpty) item.neighborhood!,
      if ((item.postalCode ?? '').isNotEmpty)
        AddressParser.formatPostalCode(item.postalCode),
    ].join(', ');
    final subtitle = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(details),
        if (item.isLowConfidence)
          const Text(
            'Conferir: falta número ou rua',
            style: TextStyle(color: AppColors.warning),
          ),
        if (duplicate != null)
          Text(
            'Repetida? Já existe: ${duplicate.displayName} — ${duplicate.shortAddress}',
            style: const TextStyle(color: AppColors.warning),
          ),
      ],
    );
    if (duplicate == null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(item.customerName ?? 'Cliente'),
        subtitle: subtitle,
      );
    }
    return CheckboxListTile(
      key: Key('paste-duplicate-$index'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: _includeDuplicate.contains(index),
      onChanged: (value) {
        setState(() {
          if (value == true) {
            _includeDuplicate.add(index);
          } else {
            _includeDuplicate.remove(index);
          }
        });
      },
      title: Text(item.customerName ?? 'Cliente'),
      subtitle: subtitle,
    );
  }
}
