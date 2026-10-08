import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rota_pizza/core/constants/app_constants.dart';
import 'package:rota_pizza/core/theme/app_theme.dart';
import 'package:rota_pizza/models/delivery.dart';
import 'package:rota_pizza/models/geo_result.dart';
import 'package:rota_pizza/providers/app_state.dart';
import 'package:rota_pizza/screens/confirm_location_screen.dart';
import 'package:rota_pizza/screens/scan_tickets_screen.dart';
import 'package:rota_pizza/widgets/big_button.dart';

class AddDeliveryScreen extends StatefulWidget {
  const AddDeliveryScreen({super.key, this.existing});

  final Delivery? existing;

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
  late final TextEditingController _value;
  DeliveryPriority _priority = DeliveryPriority.normal;
  double? _lat;
  double? _lng;
  String? _geoHint;

  bool _confirmed = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final current = widget.existing;
    _name = TextEditingController(text: current?.customerName ?? '');
    _order = TextEditingController(text: current?.orderNumber ?? '');
    _phone = TextEditingController(text: current?.phone ?? '');
    _address = TextEditingController(text: current?.address ?? '');
    _number = TextEditingController(text: current?.number ?? '');
    _complement = TextEditingController(text: current?.complement ?? '');
    _neighborhood = TextEditingController(text: current?.neighborhood ?? '');
    _city = TextEditingController(
      text: current?.city ?? AppConstants.defaultCity,
    );
    _value = TextEditingController(
      text: current?.value == null
          ? ''
          : current!.value!.toStringAsFixed(2).replaceAll('.', ','),
    );
    _priority = current?.priority ?? DeliveryPriority.normal;
    _lat = current?.latitude;
    _lng = current?.longitude;
    _confirmed = current?.locationConfirmed ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _order.dispose();
    _phone.dispose();
    _address.dispose();
    _number.dispose();
    _complement.dispose();
    _neighborhood.dispose();
    _city.dispose();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Editar entrega' : 'Nova entrega'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            TextFormField(
              key: const Key('field-customer'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Cliente'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _order,
              decoration: const InputDecoration(labelText: 'Pedido (ex: 1024)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(
                labelText: 'Telefone / WhatsApp',
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('field-address'),
              controller: _address,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Endereço',
                hintText: 'Rua Marechal Deodoro, 1500',
              ),
              minLines: 2,
              maxLines: 4,
              validator: (value) {
                if (value == null || value.trim().length < 5) {
                  return 'Informe um endereço';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _number,
                    decoration: const InputDecoration(labelText: 'Número'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _complement,
                    decoration: const InputDecoration(labelText: 'Complemento'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _neighborhood,
              decoration: const InputDecoration(labelText: 'Bairro'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _city,
              decoration: const InputDecoration(labelText: 'Cidade'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _value,
              decoration: const InputDecoration(
                labelText: 'Valor da entrega (R\$)',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            const Text('Prioridade', style: TextStyle(color: AppColors.muted)),
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
              },
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: state.busy ? null : _locate,
              icon: const Icon(Icons.my_location),
              label: const Text('Localizar e confirmar no mapa'),
            ),
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
              label: const Text('Fotografar comandas'),
            ),
            if (_geoHint != null) ...[
              const SizedBox(height: 8),
              Text(_geoHint!, style: const TextStyle(color: AppColors.cream)),
            ],
            if (_lat != null)
              Text(
                'Coordenadas: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                style: const TextStyle(color: AppColors.success),
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

  String get _query {
    final parts = [
      _address.text.trim(),
      _number.text.trim(),
      _neighborhood.text.trim(),
      _city.text.trim(),
    ].where((part) => part.isNotEmpty);
    return parts.join(', ');
  }

  Future<void> _locate() async {
    if (_address.text.trim().length < 5) {
      setState(() => _geoHint = 'Preencha o endereço primeiro.');
      return;
    }
    final state = context.read<AppState>();
    final results = await state.searchAddress(
      query: _query,
      street: _address.text,
      number: _number.text,
      neighborhood: _neighborhood.text,
      city: _city.text,
    );
    if (!mounted) {
      return;
    }
    if (results.isEmpty) {
      setState(() => _geoHint = state.message ?? 'Endereço não encontrado.');
      return;
    }
    final confirmed = await Navigator.of(context).push<GeoResult>(
      MaterialPageRoute(
        builder: (_) => ConfirmLocationScreen(
          address: _query,
          candidates: results,
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
      _geoHint = 'Ponto confirmado no mapa.';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final valueText = _value.text.trim().replaceAll('.', '').replaceAll(',', '.');
    final delivery = (widget.existing ??
            Delivery(
              customerName: _name.text.trim(),
              address: _address.text.trim(),
            ))
        .copyWith(
          customerName:
              _name.text.trim().isEmpty ? 'Cliente' : _name.text.trim(),
          orderNumber: _order.text.trim().isEmpty ? null : _order.text.trim(),
          phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          address: _address.text.trim(),
          number: _number.text.trim().isEmpty ? null : _number.text.trim(),
          complement:
              _complement.text.trim().isEmpty ? null : _complement.text.trim(),
          neighborhood: _neighborhood.text.trim().isEmpty
              ? null
              : _neighborhood.text.trim(),
          city: _city.text.trim().isEmpty
              ? AppConstants.defaultCity
              : _city.text.trim(),
          value: double.tryParse(valueText),
          priority: _priority,
          latitude: _lat,
          longitude: _lng,
          locationConfirmed: _confirmed,
        );
    final state = context.read<AppState>();
    if (state.isDuplicateAddress(
          delivery.fullAddress,
          ignoreId: delivery.id,
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esse endereço já está nas pendentes.')),
      );
      return;
    }
    await state.saveDelivery(delivery, locate: false);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }
}
