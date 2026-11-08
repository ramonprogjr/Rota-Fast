import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/models/vehicle.dart';
import 'package:rota_max/providers/app_state.dart';

IconData vehicleIcon(VehicleType type) {
  switch (type) {
    case VehicleType.motorcycle:
      return Icons.two_wheeler;
    case VehicleType.car:
      return Icons.directions_car;
    case VehicleType.utility:
      return Icons.airport_shuttle;
    case VehicleType.van:
      return Icons.local_shipping_outlined;
    case VehicleType.truck:
      return Icons.local_shipping;
  }
}

String _km(double value) =>
    NumberFormat.decimalPattern('pt_BR').format(value.round());

/// Aba Veículos: cadastro, veículo ativo e troca de óleo.
class VehiclesScreen extends StatelessWidget {
  const VehiclesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Veículos')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-vehicle',
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Veículo'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          const Text(
            'O veículo ativo define consumo, velocidade média da rota e para '
            'onde vão os km do turno.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          for (final vehicle in state.vehicles)
            _VehicleCard(
              vehicle: vehicle,
              shiftOpen: state.activeShift != null,
            ),
        ],
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicle, required this.shiftOpen});

  final Vehicle vehicle;
  final bool shiftOpen;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final oilColor = vehicle.oilWarning ? AppColors.warning : AppColors.success;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: vehicle.isActive
            ? const BorderSide(color: AppColors.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openForm(context, vehicle),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    vehicleIcon(vehicle.type),
                    color: AppColors.primarySoft,
                    size: 30,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vehicle.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            vehicle.type.label,
                            if (vehicle.plate?.isNotEmpty ?? false)
                              vehicle.plate!,
                            vehicle.fuelType.label,
                          ].join(' · '),
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  if (vehicle.isActive)
                    const Chip(
                      label: Text('ATIVO'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Odômetro ${_km(vehicle.odometerKm)} km · '
                '${vehicle.kmPerLiter.toStringAsFixed(1).replaceAll('.', ',')} km/l · '
                '${vehicle.avgSpeedKmh.round()} km/h na cidade',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Óleo: faltam ${_km(vehicle.oilRemainingKm)} km '
                      '(troca a cada ${_km(vehicle.oilIntervalKm)} km)',
                      style: TextStyle(
                        color: oilColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: vehicle.oilProgress,
                  minHeight: 8,
                  backgroundColor: AppColors.surfaceHigh,
                  color: oilColor,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _registerOil(context, state, vehicle),
                      icon: const Icon(Icons.oil_barrel_outlined),
                      label: const Text('Troquei o óleo'),
                    ),
                  ),
                  if (!vehicle.isActive) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          await state.activateVehicle(vehicle);
                          if (shiftOpen && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Os km do turno aberto continuam no veículo '
                                  'com que ele começou.',
                                ),
                              ),
                            );
                          }
                        },
                        child: const Text('Usar este'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _registerOil(
  BuildContext context,
  AppState state,
  Vehicle vehicle,
) async {
  final controller = TextEditingController(
    text: vehicle.odometerKm.round().toString(),
  );
  final value = await showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Troca de óleo'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Odômetro na troca (km)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            double.tryParse(controller.text.trim().replaceAll(',', '.')),
          ),
          child: const Text('Registrar'),
        ),
      ],
    ),
  );
  if (value != null) {
    await state.registerOilChange(vehicle, value);
  }
}

void _openForm(BuildContext context, [Vehicle? vehicle]) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => VehicleFormScreen(vehicle: vehicle),
    ),
  );
}

class VehicleFormScreen extends StatefulWidget {
  const VehicleFormScreen({super.key, this.vehicle});

  final Vehicle? vehicle;

  @override
  State<VehicleFormScreen> createState() => _VehicleFormScreenState();
}

class _VehicleFormScreenState extends State<VehicleFormScreen> {
  late VehicleType _type;
  late FuelType _fuel;
  late final TextEditingController _name;
  late final TextEditingController _plate;
  late final TextEditingController _kmL;
  late final TextEditingController _price;
  late final TextEditingController _speed;
  late final TextEditingController _odo;
  late final TextEditingController _oilInterval;
  late final TextEditingController _lastOil;

  String _num(double value, [int digits = 0]) =>
      value.toStringAsFixed(digits).replaceAll('.', ',');

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle ?? Vehicle(name: '', type: VehicleType.motorcycle);
    _type = v.type;
    _fuel = v.fuelType;
    _name = TextEditingController(text: v.name);
    _plate = TextEditingController(text: v.plate ?? '');
    _kmL = TextEditingController(text: _num(v.kmPerLiter, 1));
    _price = TextEditingController(text: _num(v.fuelPrice, 2));
    _speed = TextEditingController(text: _num(v.avgSpeedKmh));
    _odo = TextEditingController(text: _num(v.odometerKm));
    _oilInterval = TextEditingController(text: _num(v.oilIntervalKm));
    _lastOil = TextEditingController(text: _num(v.lastOilChangeKm));
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _plate,
      _kmL,
      _price,
      _speed,
      _odo,
      _oilInterval,
      _lastOil,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Ao trocar o tipo num cadastro novo, sugere os valores daquele tipo.
  void _applyDefaults(VehicleType type) {
    setState(() {
      _type = type;
      if (widget.vehicle == null) {
        _kmL.text = _num(type.kmPerLiter, 1);
        _speed.text = _num(type.avgSpeedKmh);
        _oilInterval.text = _num(type.oilIntervalKm);
        _fuel = type == VehicleType.van || type == VehicleType.truck
            ? FuelType.diesel
            : FuelType.gasoline;
      }
    });
  }

  double _parse(TextEditingController c, double fallback) =>
      double.tryParse(c.text.trim().replaceAll('.', '').replaceAll(',', '.')) ??
      fallback;

  double _parseDecimal(TextEditingController c, double fallback) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? fallback;

  Future<void> _save() async {
    final state = context.read<AppState>();
    final base = widget.vehicle ?? Vehicle(name: '', type: _type);
    final name = _name.text.trim().isEmpty ? _type.label : _name.text.trim();
    await state.saveVehicle(
      base.copyWith(
        name: name,
        type: _type,
        plate: _plate.text.trim().toUpperCase(),
        fuelType: _fuel,
        kmPerLiter: _parseDecimal(_kmL, _type.kmPerLiter),
        fuelPrice: _parseDecimal(_price, 6),
        avgSpeedKmh: _parseDecimal(_speed, _type.avgSpeedKmh),
        odometerKm: _parse(_odo, 0),
        oilIntervalKm: _parse(_oilInterval, _type.oilIntervalKm),
        lastOilChangeKm: _parse(_lastOil, 0),
      ),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _delete() async {
    final state = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir veículo?'),
        content: const Text('O histórico de trocas de óleo dele também sai.'),
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
    if (ok == true) {
      await state.deleteVehicle(widget.vehicle!);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool decimal = false,
    String? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(labelText: label, suffixText: suffix),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.vehicle != null;
    final canDelete = editing && context.watch<AppState>().vehicles.length > 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Editar veículo' : 'Novo veículo'),
        actions: [
          if (canDelete)
            IconButton(
              tooltip: 'Excluir',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text('Tipo', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in VehicleType.values)
                ChoiceChip(
                  avatar: Icon(vehicleIcon(type), size: 18),
                  label: Text(type.label),
                  selected: _type == type,
                  onSelected: (_) => _applyDefaults(type),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Nome (ex.: Fiorino branca)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _plate,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Placa (opcional)'),
          ),
          const SizedBox(height: 16),
          const Text('Combustível', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final fuel in FuelType.values)
                ChoiceChip(
                  label: Text(fuel.label),
                  selected: _fuel == fuel,
                  onSelected: (_) => setState(() => _fuel = fuel),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _field(_kmL, 'Consumo', decimal: true, suffix: 'km/l'),
          _field(_price, 'Preço do litro', decimal: true, suffix: 'R\$'),
          _field(_speed, 'Velocidade média na cidade', suffix: 'km/h'),
          const Text(
            'Usada para estimar o tempo da rota. Em trânsito pesado, diminua.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          _field(_odo, 'Odômetro atual', suffix: 'km'),
          _field(_oilInterval, 'Trocar o óleo a cada', suffix: 'km'),
          _field(_lastOil, 'Odômetro da última troca', suffix: 'km'),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Salvar'),
          ),
          if (editing) ...[
            const SizedBox(height: 24),
            Text(
              'Trocas de óleo',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            FutureBuilder<List<OilChange>>(
              future: context.read<AppState>().oilChanges(widget.vehicle!),
              builder: (context, snapshot) {
                final items = snapshot.data ?? const [];
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Nenhuma troca registrada ainda.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  );
                }
                final date = DateFormat('dd/MM/yyyy');
                return Column(
                  children: [
                    for (final item in items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.oil_barrel_outlined),
                        title: Text('${_km(item.odometerKm)} km'),
                        subtitle: Text(date.format(item.changedAt)),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
