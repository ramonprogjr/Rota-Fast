import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rota_pizza/core/constants/app_constants.dart';
import 'package:rota_pizza/core/theme/app_theme.dart';
import 'package:rota_pizza/models/pizzeria.dart';
import 'package:rota_pizza/providers/app_state.dart';
import 'package:rota_pizza/widgets/big_button.dart';

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
    final pizzeria = context.read<AppState>().pizzeria;
    _name = TextEditingController(text: pizzeria.name);
    _address = TextEditingController(text: pizzeria.address);
    _city = TextEditingController(text: pizzeria.city);
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
    final pizzeria = state.pizzeria;

    return Scaffold(
      appBar: AppBar(title: const Text('Estabelecimento e ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'Cadastre o ponto de partida uma vez. A rota começa daqui — pizzaria, restaurante ou dark kitchen.',
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
              labelText: 'Endereço do estabelecimento',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _city,
            decoration: const InputDecoration(labelText: 'Cidade'),
          ),
          const SizedBox(height: 8),
          if (pizzeria.hasCoordinates)
            Text(
              'Localizada: ${pizzeria.latitude!.toStringAsFixed(5)}, ${pizzeria.longitude!.toStringAsFixed(5)}',
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
            label: state.busy ? 'Salvando...' : 'Salvar estabelecimento',
            icon: Icons.storefront,
            onPressed: state.busy
                ? null
                : () {
                    state.savePizzeria(
                      Pizzeria(
                        name: _name.text.trim().isEmpty
                            ? 'Estabelecimento'
                            : _name.text.trim(),
                        address: _address.text.trim(),
                        city: _city.text.trim().isEmpty
                            ? AppConstants.defaultCity
                            : _city.text.trim(),
                        latitude: pizzeria.latitude,
                        longitude: pizzeria.longitude,
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
