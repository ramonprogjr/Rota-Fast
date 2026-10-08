import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:rota_pizza/core/constants/app_constants.dart';
import 'package:rota_pizza/core/theme/app_theme.dart';
import 'package:rota_pizza/core/utils/address_parser.dart';
import 'package:rota_pizza/models/delivery.dart';
import 'package:rota_pizza/models/geo_result.dart';
import 'package:rota_pizza/providers/app_state.dart';
import 'package:rota_pizza/screens/confirm_location_screen.dart';
import 'package:rota_pizza/services/ocr_service.dart';
import 'package:rota_pizza/widgets/big_button.dart';

class ScanTicketsScreen extends StatefulWidget {
  const ScanTicketsScreen({super.key});

  @override
  State<ScanTicketsScreen> createState() => _ScanTicketsScreenState();
}

class _Draft {
  _Draft(this.parsed)
      : name = TextEditingController(text: parsed.customerName ?? ''),
        address = TextEditingController(text: parsed.address),
        order = TextEditingController(text: parsed.orderNumber ?? '');

  final ParsedDelivery parsed;
  final TextEditingController name;
  final TextEditingController address;
  final TextEditingController order;
  bool keep = true;

  void dispose() {
    name.dispose();
    address.dispose();
    order.dispose();
  }
}

class _ScanTicketsScreenState extends State<ScanTicketsScreen> {
  final _picker = ImagePicker();
  final _ocr = OcrService();
  final _photos = <XFile>[];
  final _drafts = <_Draft>[];
  bool _reading = false;
  String? _hint;

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    _ocr.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Fotografar comandas')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'Tire até 5 fotos das comandas. Confira o texto antes de localizar — o leitor pode errar número ou bairro.',
            style: TextStyle(color: AppColors.muted, fontSize: 16),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _photos.length >= AppConstants.maxTicketPhotos || _reading
                ? null
                : _takePhoto,
            icon: const Icon(Icons.photo_camera),
            label: Text(
              'Tirar foto (${_photos.length}/${AppConstants.maxTicketPhotos})',
            ),
          ),
          if (_hint != null) ...[
            const SizedBox(height: 8),
            Text(_hint!, style: const TextStyle(color: AppColors.warning)),
          ],
          const SizedBox(height: 16),
          if (_reading) const LinearProgressIndicator(),
          ..._drafts.asMap().entries.map((entry) {
            final draft = entry.value;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Comanda ${entry.key + 1}'),
                      value: draft.keep,
                      onChanged: (value) => setState(() => draft.keep = value),
                    ),
                    TextField(
                      controller: draft.name,
                      decoration: const InputDecoration(labelText: 'Cliente'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: draft.order,
                      decoration: const InputDecoration(labelText: 'Pedido'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: draft.address,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Endereço'),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          BigButton(
            label: state.busy ? 'Salvando...' : 'Salvar e confirmar no mapa',
            icon: Icons.checklist,
            onPressed: _reading || state.busy || !_drafts.any((item) => item.keep)
                ? null
                : _saveAndConfirm,
          ),
        ],
      ),
    );
  }

  Future<void> _takePhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (file == null) {
      return;
    }
    setState(() {
      _photos.add(file);
      _reading = true;
      _hint = null;
    });
    try {
      final text = await _ocr.readFile(file.path);
      final parsed = AddressParser.parseTicket(text);
      if (parsed.isEmpty) {
        setState(() {
          _hint =
              'Não li um endereço nesta foto. Deixe a comanda reta, com boa luz, ou edite na mão.';
          _drafts.add(_Draft(ParsedDelivery(address: text)));
        });
      } else {
        setState(() {
          _drafts.addAll(parsed.map(_Draft.new));
        });
      }
    } catch (_) {
      setState(() {
        _hint = 'Não consegui ler a foto. Tente de novo ou digite o endereço.';
      });
    } finally {
      if (mounted) {
        setState(() => _reading = false);
      }
    }
  }

  Future<void> _saveAndConfirm() async {
    final state = context.read<AppState>();
    final kept = _drafts.where((item) => item.keep).toList();
    for (final draft in kept) {
      if (draft.address.text.trim().length < 5) {
        continue;
      }
      if (state.isDuplicateAddress(draft.address.text)) {
        continue;
      }
      var delivery = await state.saveDelivery(
        Delivery(
          customerName:
              draft.name.text.trim().isEmpty ? 'Cliente' : draft.name.text.trim(),
          orderNumber:
              draft.order.text.trim().isEmpty ? null : draft.order.text.trim(),
          address: draft.address.text.trim(),
        ),
      );
      if (!mounted) {
        return;
      }
      final results = await state.searchAddress(query: delivery.fullAddress);
      if (!mounted) {
        return;
      }
      if (results.isEmpty) {
        continue;
      }
      final confirmed = await Navigator.of(context).push<GeoResult>(
        MaterialPageRoute<GeoResult>(
          builder: (_) => ConfirmLocationScreen(
            address: delivery.fullAddress,
            candidates: results,
          ),
        ),
      );
      if (confirmed != null) {
        await state.confirmLocation(delivery, confirmed);
      }
    }
    if (!mounted) {
      return;
    }
    await state.organizeRoute(useGps: true);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
