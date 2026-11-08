import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:rota_max/core/constants/app_constants.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/core/utils/address_parser.dart';
import 'package:rota_max/models/delivery.dart';
import 'package:rota_max/models/geo_result.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:rota_max/screens/confirm_location_screen.dart';
import 'package:rota_max/screens/scan_tickets_screen.dart';
import 'package:rota_max/services/address_autocomplete_service.dart';
import 'package:rota_max/services/draft_store.dart';
import 'package:rota_max/widgets/address_autocomplete_field.dart';
import 'package:rota_max/widgets/big_button.dart';

class AddDeliveryScreen extends StatefulWidget {
  const AddDeliveryScreen({
    super.key,
    this.existing,
    this.autocomplete,
    this.drafts,
  });

  final Delivery? existing;

  /// Padrão: [AddressAutocompleteService.shared].
  final AddressAutocompleteService? autocomplete;

  /// Padrão: `AppState.drafts`.
  final DraftStore? drafts;

  @override
  State<AddDeliveryScreen> createState() => _AddDeliveryScreenState();
}

class _AddDeliveryScreenState extends State<AddDeliveryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _order;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _number;
  late final TextEditingController _complement;
  late final TextEditingController _neighborhood;
  late final TextEditingController _city;
  late final TextEditingController _uf;
  late final TextEditingController _cep;
  late final TextEditingController _reference;
  late final TextEditingController _value;
  DeliveryPriority _priority = DeliveryPriority.normal;
  double? _lat;
  double? _lng;
  String? _geoHint;
  bool _confirmed = false;

  /// O ponto foi confirmado no mapa nesta tela (vai para o cache ao salvar).
  bool _confirmedHere = false;

  /// Assinatura do endereço quando o pino foi definido. Se o endereço mudar,
  /// o pino deixa de valer.
  String? _pinSignature;

  /// Preenchendo campos por código (sugestão, rascunho): não apaga o pino.
  bool _filling = false;
  bool _saved = false;
  bool _draftRestored = false;
  Timer? _draftTimer;
  late final DraftStore _drafts;

  bool get _editing => widget.existing != null;

  List<TextEditingController> get _all => [
    _name,
    _order,
    _phone,
    _address,
    _number,
    _complement,
    _neighborhood,
    _city,
    _uf,
    _cep,
    _reference,
    _value,
  ];

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _drafts = widget.drafts ?? state.drafts;
    final current = widget.existing;
    _name = TextEditingController(text: current?.customerName ?? '');
    _order = TextEditingController(text: current?.orderNumber ?? '');
    _phone = TextEditingController(text: current?.phone ?? '');
    _address = TextEditingController(text: current?.address ?? '');
    _number = TextEditingController(text: current?.number ?? '');
    _complement = TextEditingController(text: current?.complement ?? '');
    _neighborhood = TextEditingController(text: current?.neighborhood ?? '');
    _city = TextEditingController(text: current?.city ?? state.cityHint());
    _uf = TextEditingController(
      text: current == null ? AppConstants.defaultState : (current.state ?? ''),
    );
    _cep = TextEditingController(
      text: AddressParser.formatPostalCode(current?.postalCode),
    );
    _reference = TextEditingController(text: current?.notes ?? '');
    _value = TextEditingController(
      text: current?.value == null
          ? ''
          : current!.value!.toStringAsFixed(2).replaceAll('.', ','),
    );
    _priority = current?.priority ?? DeliveryPriority.normal;
    _lat = current?.latitude;
    _lng = current?.longitude;
    _confirmed = current?.locationConfirmed ?? false;
    _pinSignature = _lat == null ? null : _signature();

    for (final controller in [_address, _number, _neighborhood, _city, _cep]) {
      controller.addListener(_onAddressChanged);
    }
    if (!_editing) {
      for (final controller in _all) {
        controller.addListener(_scheduleDraft);
      }
      _restoreDraft();
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    if (!_editing && !_saved) {
      // Sai da tela sem salvar: guarda o que foi digitado.
      _writeDraft();
    }
    for (final controller in _all) {
      controller.dispose();
    }
    super.dispose();
  }

  String _signature() => AddressParser.locationSignature(
    street: _address.text,
    number: _number.text,
    neighborhood: _neighborhood.text,
    city: _city.text,
    postalCode: _cep.text,
  );

  void _onAddressChanged() {
    if (_filling) {
      return;
    }
    final changed = _pinSignature != null && _signature() != _pinSignature;
    setState(() {
      if (changed && _lat != null) {
        _lat = null;
        _lng = null;
        _confirmed = false;
        _confirmedHere = false;
        _pinSignature = null;
        _geoHint = 'Endereço alterado: localize de novo no mapa.';
      }
    });
  }

  bool get _incomplete =>
      _address.text.trim().isNotEmpty &&
      (_number.text.trim().isEmpty || _neighborhood.text.trim().isEmpty);

  // ---------------------------------------------------------------- rascunho

  Map<String, dynamic> _draftData() => {
    'name': _name.text,
    'order': _order.text,
    'phone': _phone.text,
    'address': _address.text,
    'number': _number.text,
    'complement': _complement.text,
    'neighborhood': _neighborhood.text,
    'city': _city.text,
    'state': _uf.text,
    'cep': _cep.text,
    'reference': _reference.text,
    'value': _value.text,
    'priority': _priority.name,
    if (_lat != null) 'lat': _lat,
    if (_lng != null) 'lng': _lng,
    'confirmed': _confirmed,
  };

  bool get _hasTypedSomething => [
    _name,
    _order,
    _phone,
    _address,
    _number,
    _complement,
    _neighborhood,
    _cep,
    _reference,
    _value,
  ].any((controller) => controller.text.trim().isNotEmpty);

  void _scheduleDraft() {
    if (_filling) {
      return;
    }
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), _writeDraft);
  }

  void _writeDraft() {
    if (_hasTypedSomething) {
      _drafts.save(DraftStore.addDeliveryKey, _draftData());
    } else {
      _drafts.clear(DraftStore.addDeliveryKey);
    }
  }

  Future<void> _restoreDraft() async {
    final data = await _drafts.load(DraftStore.addDeliveryKey);
    if (!mounted || data == null || _hasTypedSomething) {
      return;
    }
    String text(String key) => '${data[key] ?? ''}';
    _filling = true;
    try {
      _name.text = text('name');
      _order.text = text('order');
      _phone.text = text('phone');
      _address.text = text('address');
      _number.text = text('number');
      _complement.text = text('complement');
      _neighborhood.text = text('neighborhood');
      if (text('city').isNotEmpty) {
        _city.text = text('city');
      }
      _uf.text = text('state');
      _cep.text = text('cep');
      _reference.text = text('reference');
      _value.text = text('value');
    } finally {
      _filling = false;
    }
    if (!_hasTypedSomething) {
      return;
    }
    setState(() {
      _priority = DeliveryPriority.values.firstWhere(
        (item) => item.name == data['priority'],
        orElse: () => DeliveryPriority.normal,
      );
      _lat = (data['lat'] as num?)?.toDouble();
      _lng = (data['lng'] as num?)?.toDouble();
      _confirmed = data['confirmed'] == true && _lat != null;
      _pinSignature = _lat == null ? null : _signature();
      _draftRestored = true;
    });
  }

  void _discardDraft() {
    _draftTimer?.cancel();
    _filling = true;
    try {
      for (final controller in _all) {
        controller.clear();
      }
      _city.text = context.read<AppState>().cityHint();
      _uf.text = AppConstants.defaultState;
    } finally {
      _filling = false;
    }
    _drafts.clear(DraftStore.addDeliveryKey);
    setState(() {
      _draftRestored = false;
      _lat = null;
      _lng = null;
      _confirmed = false;
      _pinSignature = null;
      _geoHint = null;
      _priority = DeliveryPriority.normal;
    });
  }

  // ------------------------------------------------------------ autocomplete

  void _applySuggestion(AddressSuggestion suggestion) {
    _filling = true;
    try {
      _address.text = suggestion.street ?? suggestion.label;
      if ((suggestion.number ?? '').isNotEmpty) {
        _number.text = suggestion.number!;
      }
      if ((suggestion.neighborhood ?? '').isNotEmpty) {
        _neighborhood.text = suggestion.neighborhood!;
      }
      if ((suggestion.city ?? '').isNotEmpty) {
        _city.text = suggestion.city!;
      }
      if ((suggestion.state ?? '').isNotEmpty) {
        _uf.text = suggestion.state!;
      }
      if ((suggestion.postalCode ?? '').isNotEmpty) {
        _cep.text = AddressParser.formatPostalCode(suggestion.postalCode);
      }
    } finally {
      _filling = false;
    }
    setState(() {
      _lat = suggestion.lat;
      _lng = suggestion.lng;
      _confirmed = false;
      _confirmedHere = false;
      _pinSignature = _signature();
      _geoHint = 'Endereço sugerido. Confira o ponto no mapa antes de sair.';
    });
    _scheduleDraft();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar entrega' : 'Nova entrega')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_draftRestored)
                Card(
                  color: AppColors.surfaceHigh,
                  child: ListTile(
                    leading: const Icon(Icons.restore),
                    title: const Text('Rascunho recuperado'),
                    trailing: TextButton(
                      onPressed: _discardDraft,
                      child: const Text('Descartar'),
                    ),
                  ),
                ),
              TextFormField(
                key: const Key('field-customer'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Cliente'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _order,
                      decoration: const InputDecoration(labelText: 'Pedido'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _phone,
                      decoration: const InputDecoration(
                        labelText: 'Telefone / WhatsApp',
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AddressAutocompleteField(
                fieldKey: const Key('field-address'),
                controller: _address,
                service: widget.autocomplete,
                focus: state.originPoint,
                onSelected: _applySuggestion,
                decoration: const InputDecoration(
                  labelText: 'Rua / Avenida',
                  hintText: 'Rua Marechal Deodoro',
                ),
                validator: (value) {
                  if (value == null || value.trim().length < 5) {
                    return 'Informe a rua';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('field-number'),
                      controller: _number,
                      decoration: const InputDecoration(labelText: 'Número'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _complement,
                      decoration: const InputDecoration(
                        labelText: 'Complemento',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('field-neighborhood'),
                controller: _neighborhood,
                decoration: const InputDecoration(labelText: 'Bairro'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      key: const Key('field-city'),
                      controller: _city,
                      decoration: const InputDecoration(labelText: 'Cidade'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: const Key('field-uf'),
                      controller: _uf,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')),
                        LengthLimitingTextInputFormatter(2),
                        const _UpperCaseFormatter(),
                      ],
                      decoration: const InputDecoration(labelText: 'UF'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('field-cep'),
                controller: _cep,
                keyboardType: TextInputType.number,
                inputFormatters: const [CepInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'CEP',
                  hintText: '00000-000',
                ),
                validator: (value) {
                  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                  if (digits.isNotEmpty && digits.length != 8) {
                    return 'CEP tem 8 números';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('field-reference'),
                controller: _reference,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Ponto de referência',
                  hintText: 'Ex.: portão azul, ao lado da padaria',
                ),
              ),
              if (_incomplete) ...[
                const SizedBox(height: 10),
                const _IncompleteBadge(),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _value,
                decoration: const InputDecoration(
                  labelText: 'Valor da entrega (R\$)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Prioridade',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              SegmentedButton<DeliveryPriority>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: DeliveryPriority.normal,
                    label: Text('Normal'),
                  ),
                  ButtonSegment(
                    value: DeliveryPriority.high,
                    label: Text('Alta'),
                  ),
                  ButtonSegment(
                    value: DeliveryPriority.urgent,
                    label: Text('Urgente'),
                  ),
                ],
                selected: {_priority},
                onSelectionChanged: (value) {
                  setState(() => _priority = value.first);
                  _scheduleDraft();
                },
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('locate-delivery'),
                onPressed: state.busy ? null : _locate,
                icon: const Icon(Icons.my_location),
                label: const Text('Localizar e confirmar no mapa'),
              ),
              if (!_editing) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ScanTicketsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Fotografar etiquetas'),
                ),
              ],
              if (_geoHint != null) ...[
                const SizedBox(height: 8),
                Text(_geoHint!, style: const TextStyle(color: AppColors.text)),
              ],
              if (_lat != null && _lng != null)
                Text(
                  '${_confirmed ? 'Ponto confirmado' : 'Ponto aproximado'}: '
                  '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                  style: TextStyle(
                    color: _confirmed ? AppColors.success : AppColors.warning,
                  ),
                ),
              const SizedBox(height: 20),
              BigButton(
                key: const Key('save-delivery'),
                label: state.busy ? 'Salvando...' : 'Salvar entrega',
                icon: Icons.save,
                onPressed: state.busy ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _clean(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  /// Entrega com o que está na tela. Campos apagados viram null de verdade
  /// (copyWith não consegue limpar campos).
  Delivery _buildDelivery() {
    final state = context.read<AppState>();
    final current = widget.existing;
    final valueText = _value.text
        .trim()
        .replaceAll('.', '')
        .replaceAll(',', '.');
    final uf = _clean(_uf)?.toUpperCase();
    return Delivery(
      id: current?.id,
      orderNumber: _clean(_order),
      packageId: current?.packageId,
      customerName: _clean(_name) ?? 'Cliente',
      phone: _clean(_phone),
      address: _address.text.trim(),
      number: _clean(_number),
      complement: _clean(_complement),
      neighborhood: _clean(_neighborhood),
      postalCode: AddressParser.normalizePostalCode(_cep.text),
      city: _clean(_city) ?? state.cityHint(),
      state: uf,
      latitude: _lat,
      longitude: _lng,
      value: double.tryParse(valueText),
      notes: _clean(_reference),
      priority: _priority,
      status: current?.status ?? DeliveryStatus.pending,
      failureReason: current?.failureReason,
      attempts: current?.attempts ?? 0,
      routeOrder: current?.routeOrder,
      locationConfirmed: _lat != null && _confirmed,
      createdAt: current?.createdAt,
      updatedAt: current == null ? null : DateTime.now(),
      deliveredAt: current?.deliveredAt,
    );
  }

  Future<void> _locate() async {
    if (_address.text.trim().length < 3) {
      setState(() => _geoHint = 'Preencha a rua primeiro.');
      return;
    }
    final state = context.read<AppState>();
    final draft = _buildDelivery();
    final results = await state.searchAddress(
      query: draft.fullAddress,
      street: draft.address,
      number: draft.number,
      neighborhood: draft.neighborhood,
      city: draft.city,
      state: draft.state,
      postalCode: draft.postalCode,
    );
    if (!mounted) {
      return;
    }
    if (results.isEmpty) {
      final reason = state.message ?? 'Endereço não encontrado.';
      setState(() => _geoHint = reason);
      final manual = await ConfirmLocationScreen.askMarkOnMap(
        context,
        message: reason,
      );
      if (!manual || !mounted) {
        return;
      }
    }
    final center = _lat != null && _lng != null
        ? GeoPoint(_lat!, _lng!)
        : state.originPoint;
    final confirmed = await Navigator.of(context).push<GeoResult>(
      MaterialPageRoute(
        builder: (_) => ConfirmLocationScreen(
          address: draft.fullAddress,
          candidates: results,
          center: center,
        ),
      ),
    );
    if (!mounted || confirmed == null) {
      return;
    }
    setState(() {
      _lat = confirmed.latitude;
      _lng = confirmed.longitude;
      _confirmed = true;
      _confirmedHere = true;
      _pinSignature = _signature();
      _geoHint = 'Ponto confirmado no mapa.';
    });
    _scheduleDraft();
  }

  Future<bool> _askDuplicate(Delivery existing) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Endereço repetido'),
        content: Text(
          'Já existe uma entrega neste endereço:\n\n'
          '${existing.displayName}\n${existing.fullAddress}\n'
          '(${existing.status.label})\n\nQuer salvar outra mesmo assim?',
        ),
        actions: [
          TextButton(
            key: const Key('duplicate-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('duplicate-save-anyway'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Salvar mesmo assim'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final state = context.read<AppState>();
    final delivery = _buildDelivery();
    var allowDuplicate = false;
    final duplicate = state.findDuplicate(delivery, ignoreId: delivery.id);
    if (duplicate != null) {
      allowDuplicate = await _askDuplicate(duplicate);
      if (!allowDuplicate || !mounted) {
        return;
      }
    }
    Delivery saved;
    try {
      saved = await state.saveDelivery(
        delivery,
        allowDuplicate: allowDuplicate,
      );
    } on DuplicateAddressException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
      return;
    }
    if (_confirmedHere && saved.hasCoordinates) {
      // Guarda o ponto confirmado no cache para a próxima vez.
      await state.confirmLocation(
        saved,
        GeoResult(
          latitude: saved.latitude!,
          longitude: saved.longitude!,
          displayName: saved.fullAddress,
          confirmed: true,
        ),
      );
    }
    _saved = true;
    _draftTimer?.cancel();
    if (!_editing) {
      await _drafts.clear(DraftStore.addDeliveryKey);
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }
}

class _IncompleteBadge extends StatelessWidget {
  const _IncompleteBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('incomplete-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warningSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.warning),
          SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Endereço incompleto',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: '\nFalta número ou bairro. Dá para salvar, mas confira.',
                    style: TextStyle(color: AppColors.text),
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

/// Máscara de CEP: 00000-000 (no banco vão só os dígitos).
class CepInputFormatter extends TextInputFormatter {
  const CepInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 8) {
      digits = digits.substring(0, 8);
    }
    final text = AddressParser.formatPostalCode(digits);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  const _UpperCaseFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
