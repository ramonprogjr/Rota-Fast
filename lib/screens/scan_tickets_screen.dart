import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:rota_max/core/constants/app_constants.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/core/utils/address_parser.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:rota_max/screens/confirm_location_screen.dart';
import 'package:rota_max/services/draft_store.dart';
import 'package:rota_max/services/ocr_service.dart';
import 'package:rota_max/widgets/big_button.dart';

class ScanTicketsScreen extends StatefulWidget {
  const ScanTicketsScreen({super.key, this.drafts});

  /// Padrão: `AppState.drafts`.
  final DraftStore? drafts;

  @override
  State<ScanTicketsScreen> createState() => _ScanTicketsScreenState();
}

/// Uma comanda lida, com os campos editáveis.
class _Draft {
  _Draft(ParsedDelivery parsed)
    : name = TextEditingController(text: parsed.customerName ?? ''),
      order = TextEditingController(text: parsed.orderNumber ?? ''),
      phone = TextEditingController(text: parsed.phone ?? ''),
      address = TextEditingController(text: parsed.address),
      number = TextEditingController(text: parsed.number ?? ''),
      complement = TextEditingController(text: parsed.complement ?? ''),
      neighborhood = TextEditingController(text: parsed.neighborhood ?? ''),
      city = TextEditingController(text: parsed.city),
      state = TextEditingController(text: parsed.state ?? ''),
      cep = TextEditingController(
        text: AddressParser.formatPostalCode(parsed.postalCode),
      ),
      value = parsed.value;

  factory _Draft.fromJson(Map<String, dynamic> json) {
    String? text(String key) {
      final value = json[key];
      return value == null || '$value'.isEmpty ? null : '$value';
    }

    final draft = _Draft(
      ParsedDelivery(
        customerName: text('name'),
        orderNumber: text('order'),
        phone: text('phone'),
        address: text('address') ?? '',
        number: text('number'),
        complement: text('complement'),
        neighborhood: text('neighborhood'),
        city: text('city') ?? AppConstants.defaultCity,
        state: text('state'),
        postalCode: text('cep'),
        value: (json['value'] as num?)?.toDouble(),
      ),
    );
    draft.keep = json['keep'] != false;
    return draft;
  }

  final TextEditingController name;
  final TextEditingController order;
  final TextEditingController phone;
  final TextEditingController address;
  final TextEditingController number;
  final TextEditingController complement;
  final TextEditingController neighborhood;
  final TextEditingController city;
  final TextEditingController state;
  final TextEditingController cep;
  final double? value;
  bool keep = true;

  List<TextEditingController> get controllers => [
    name,
    order,
    phone,
    address,
    number,
    complement,
    neighborhood,
    city,
    state,
    cep,
  ];

  /// Baixa confiança: falta número ou o texto não parece uma rua.
  bool get needsReview =>
      number.text.trim().isEmpty ||
      address.text.trim().length < 5 ||
      !AddressParser.hasStreetWord(address.text);

  String? _clean(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  Delivery toDelivery(String fallbackCity) => Delivery(
    customerName: _clean(name) ?? 'Cliente',
    orderNumber: _clean(order),
    phone: _clean(phone),
    address: address.text.trim(),
    number: _clean(number),
    complement: _clean(complement),
    neighborhood: _clean(neighborhood),
    city: _clean(city) ?? fallbackCity,
    state: _clean(state)?.toUpperCase(),
    postalCode: AddressParser.normalizePostalCode(cep.text),
    value: value,
  );

  Map<String, dynamic> toJson() => {
    'name': name.text,
    'order': order.text,
    'phone': phone.text,
    'address': address.text,
    'number': number.text,
    'complement': complement.text,
    'neighborhood': neighborhood.text,
    'city': city.text,
    'state': state.text,
    'cep': cep.text,
    'value': value,
    'keep': keep,
  };

  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
  }
}

class _ScanTicketsScreenState extends State<ScanTicketsScreen> {
  final _picker = ImagePicker();
  final _ocr = OcrService();
  final _photos = <XFile>[];
  final _drafts = <_Draft>[];
  bool _reading = false;
  bool _saving = false;
  bool _done = false;
  String? _hint;
  Timer? _draftTimer;
  late final DraftStore _store;

  @override
  void initState() {
    super.initState();
    _store = widget.drafts ?? context.read<AppState>().drafts;
    _restore();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    if (!_done) {
      _persist();
    }
    for (final draft in _drafts) {
      draft.dispose();
    }
    _ocr.close();
    super.dispose();
  }

  Future<void> _restore() async {
    final data = await _store.load(DraftStore.scanKey);
    final items = data?['items'];
    if (!mounted || items is! List || items.isEmpty || _drafts.isNotEmpty) {
      return;
    }
    setState(() {
      for (final item in items) {
        if (item is Map<String, dynamic>) {
          _add(_Draft.fromJson(item));
        }
      }
      _hint = 'Comandas recuperadas da última vez. Confira e salve.';
    });
  }

  void _add(_Draft draft) {
    for (final controller in draft.controllers) {
      controller.addListener(_schedulePersist);
    }
    _drafts.add(draft);
  }

  void _schedulePersist() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), _persist);
  }

  void _persist() {
    if (_drafts.isEmpty) {
      _store.clear(DraftStore.scanKey);
      return;
    }
    _store.save(DraftStore.scanKey, {
      'items': [for (final draft in _drafts) draft.toJson()],
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final busy = _reading || _saving || state.busy;
    return Scaffold(
      appBar: AppBar(title: const Text('Fotografar etiquetas')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'Tire até 5 fotos das etiquetas ou comandas. Confira o texto antes de localizar — o leitor pode errar número ou bairro.',
            style: TextStyle(color: AppColors.muted, fontSize: 16),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _photos.length >= AppConstants.maxTicketPhotos || busy
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
          for (var i = 0; i < _drafts.length; i++) _card(i, _drafts[i]),
          const SizedBox(height: 16),
          BigButton(
            label: _saving ? 'Salvando...' : 'Salvar e confirmar no mapa',
            icon: Icons.checklist,
            onPressed: busy || !_drafts.any((item) => item.keep)
                ? null
                : _saveAndConfirm,
          ),
        ],
      ),
    );
  }

  Widget _card(int index, _Draft draft) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Text('Comanda ${index + 1}'),
                  if (draft.needsReview) ...[
                    const SizedBox(width: 8),
                    const _Badge('Conferir'),
                  ],
                ],
              ),
              value: draft.keep,
              onChanged: (value) {
                setState(() => draft.keep = value);
                _schedulePersist();
              },
            ),
            _field(draft.name, 'Cliente'),
            Row(
              children: [
                Expanded(child: _field(draft.order, 'Pedido')),
                const SizedBox(width: 8),
                Expanded(
                  child: _field(
                    draft.phone,
                    'Telefone',
                    keyboard: TextInputType.phone,
                  ),
                ),
              ],
            ),
            _field(draft.address, 'Rua / Avenida'),
            Row(
              children: [
                Expanded(child: _field(draft.number, 'Número')),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _field(draft.complement, 'Complemento'),
                ),
              ],
            ),
            _field(draft.neighborhood, 'Bairro'),
            Row(
              children: [
                Expanded(flex: 3, child: _field(draft.city, 'Cidade')),
                const SizedBox(width: 8),
                Expanded(child: _field(draft.state, 'UF')),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _field(
                    draft.cep,
                    'CEP',
                    keyboard: TextInputType.number,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label),
        // Atualiza o selo "Conferir".
        onChanged: (_) => setState(() {}),
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
          _hint = 'Não li um endereço nesta foto. Deixe a etiqueta reta, com boa luz, ou edite na mão.';
          _add(_Draft(ParsedDelivery(address: text)));
        });
      } else {
        setState(() {
          for (final item in parsed) {
            _add(_Draft(item));
          }
        });
      }
      _schedulePersist();
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

  Future<bool> _askDuplicate(Delivery candidate, Delivery existing) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Endereço repetido'),
        content: Text(
          '${candidate.shortAddress} já está na lista '
          '(${existing.displayName}, ${existing.status.label}).\n\nSalvar outra entrega mesmo assim?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Pular'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Salvar mesmo assim'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  Future<void> _saveAndConfirm() async {
    final state = context.read<AppState>();
    final kept = _drafts.where((item) => item.keep).toList();
    final withoutLocation = <Delivery>[];
    var saved = 0;
    var skipped = 0;
    setState(() => _saving = true);
    try {
      for (final draft in kept) {
        if (draft.address.text.trim().length < 5) {
          skipped++;
          continue;
        }
        final candidate = draft.toDelivery(state.cityHint());
        final duplicate = state.findDuplicate(candidate);
        if (duplicate != null) {
          final allow = await _askDuplicate(candidate, duplicate);
          if (!mounted) {
            return;
          }
          if (!allow) {
            skipped++;
            continue;
          }
        }
        final delivery = await state.saveDelivery(
          candidate,
          allowDuplicate: duplicate != null,
        );
        saved++;
        if (!mounted) {
          return;
        }
        final results = await state.searchAddress(
          query: delivery.fullAddress,
          state: delivery.state,
          postalCode: delivery.postalCode,
        );
        if (!mounted) {
          return;
        }
        if (results.isEmpty) {
          // Fica salva sem coordenadas ("Sem localização" na lista).
          withoutLocation.add(delivery);
          continue;
        }
        final confirmed = await Navigator.of(context).push<GeoResult>(
          MaterialPageRoute<GeoResult>(
            builder: (_) => ConfirmLocationScreen(
              address: delivery.fullAddress,
              candidates: results,
              center: state.originPoint,
            ),
          ),
        );
        if (confirmed != null) {
          await state.confirmLocation(delivery, confirmed);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
    if (!mounted) {
      return;
    }
    _done = true;
    _draftTimer?.cancel();
    await _store.clear(DraftStore.scanKey);
    if (!mounted) {
      return;
    }
    if (withoutLocation.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sem localização'),
          content: Text(
            '$saved entrega(s) salva(s)${skipped > 0 ? ', $skipped pulada(s)' : ''}.\n\n'
            'Não achei no mapa:\n'
            '${withoutLocation.map((item) => '• ${item.shortAddress}').join('\n')}\n\n'
            'Elas ficam na lista como "Sem localização". Abra cada uma e use "Confirmar no mapa" para marcar o ponto.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
      if (!mounted) {
        return;
      }
    }
    await state.organizeRoute(useGps: true);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.warningSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.warning,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
