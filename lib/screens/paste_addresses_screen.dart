import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rota_pizza/core/theme/app_theme.dart';
import 'package:rota_pizza/core/utils/address_parser.dart';
import 'package:rota_pizza/providers/app_state.dart';
import 'package:rota_pizza/widgets/big_button.dart';

class PasteAddressesScreen extends StatefulWidget {
  const PasteAddressesScreen({super.key});

  @override
  State<PasteAddressesScreen> createState() => _PasteAddressesScreenState();
}

class _PasteAddressesScreenState extends State<PasteAddressesScreen> {
  final _controller = TextEditingController();
  List<ParsedDelivery> _preview = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
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
            'Exemplo:\nJoão — Rua Marechal Deodoro, 1500, Centro, SBC\nMaria — Av. Kennedy, 456, Rudge Ramos',
            style: TextStyle(color: AppColors.cream, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            minLines: 8,
            maxLines: 16,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Cole os endereços aqui',
            ),
            onChanged: (value) {
              setState(() => _preview = AddressParser.parseBatch(value));
            },
          ),
          const SizedBox(height: 12),
          Text(
            _preview.isEmpty
                ? 'Nenhum endereço reconhecido ainda.'
                : '${_preview.length} endereço(s) reconhecido(s)',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          ..._preview.map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.customerName ?? 'Cliente'),
              subtitle: Text(item.address),
            ),
          ),
          const SizedBox(height: 16),
          BigButton(
            label: state.busy ? 'Importando...' : 'Salvar entregas',
            icon: Icons.playlist_add,
            onPressed: state.busy || _preview.isEmpty
                ? null
                : () async {
                    await state.importParsed(_preview);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
          ),
        ],
      ),
    );
  }
}
