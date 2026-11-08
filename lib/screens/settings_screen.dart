import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rota_max/core/constants/app_constants.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/models/base_location.dart';
import 'package:rota_max/providers/app_state.dart';
import 'package:rota_max/widgets/big_button.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _gas;
  late final TextEditingController _kmL;
  late final TextEditingController _odo;
  late final TextEditingController _oil;

  @override
  void initState() {
    super.initState();
    final baseLocation = context.read<AppState>().baseLocation;
    _name = TextEditingController(text: baseLocation.name);
    _address = TextEditingController(text: baseLocation.address);
    _city = TextEditingController(text: baseLocation.city);
    final vehicle = context.read<AppState>().vehicle;
    _gas = TextEditingController(
      text: vehicle.gasPriceLiter.toStringAsFixed(2).replaceAll('.', ','),
    );
    _kmL = TextEditingController(
      text: vehicle.kmPerLiter.toStringAsFixed(1).replaceAll('.', ','),
    );
    _odo = TextEditingController(
      text: vehicle.odometerKm.toStringAsFixed(0),
    );
    _oil = TextEditingController(
      text: vehicle.lastOilChangeKm.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _city.dispose();
    _gas.dispose();
    _kmL.dispose();
    _odo.dispose();
    _oil.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final baseLocation = state.baseLocation;

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'Cadastre o ponto de partida uma vez. A rota começa daqui: loja, restaurante, centro de distribuição ou sua casa.',
            style: TextStyle(color: AppColors.muted, fontSize: 16),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nome'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Endereço do ponto de saída',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _city,
            decoration: const InputDecoration(labelText: 'Cidade'),
          ),
          const SizedBox(height: 8),
          if (baseLocation.hasCoordinates)
            Text(
              'Localizada: ${baseLocation.latitude!.toStringAsFixed(5)}, ${baseLocation.longitude!.toStringAsFixed(5)}',
              style: const TextStyle(color: AppColors.success),
            )
          else
            const Text(
              'Ainda sem coordenadas.',
              style: TextStyle(color: AppColors.warning),
            ),
          if (state.message != null) ...[
            const SizedBox(height: 8),
            Text(state.message!),
          ],
          const SizedBox(height: 16),
          BigButton(
            label: state.busy ? 'Salvando...' : 'Salvar ponto de saída',
            icon: Icons.storefront,
            onPressed: state.busy
                ? null
                : () {
                    state.saveBaseLocation(
                      BaseLocation(
                        name: _name.text.trim().isEmpty
                            ? 'Ponto de saída'
                            : _name.text.trim(),
                        address: _address.text.trim(),
                        city: _city.text.trim().isEmpty
                            ? AppConstants.defaultCity
                            : _city.text.trim(),
                        latitude: baseLocation.latitude,
                        longitude: baseLocation.longitude,
                      ),
                    );
                  },
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Modo moto'),
            subtitle: const Text(
              'Abre o Google Maps em modo direção. No Maps, escolha a opção de motocicleta se aparecer.',
            ),
            value: state.motorcycleMode,
            onChanged: state.setMotorcycleMode,
          ),
          const SizedBox(height: 16),
          const Text(
            'Moto: gasolina e óleo',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _gas,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Preço do litro (R\$)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _kmL,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Km por litro'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _odo,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Hodômetro atual (km)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _oil,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Hodômetro da última troca de óleo',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              double parse(String raw) =>
                  double.tryParse(raw.trim().replaceAll(',', '.')) ?? 0;
              state.saveVehicle(
                state.vehicle.copyWith(
                  gasPriceLiter: parse(_gas.text),
                  kmPerLiter: parse(_kmL.text),
                  odometerKm: parse(_odo.text),
                  lastOilChangeKm: parse(_oil.text),
                ),
              );
            },
            child: const Text('Salvar dados da moto'),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Segurança: organize a rota com o celular parado. Use suporte no guidão e a voz do Google Maps. Não mexa no app em movimento.',
              style: TextStyle(height: 1.4, fontSize: 15),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sem anúncios, sem conta e sem assinatura. Dados ficam só neste celular.',
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
