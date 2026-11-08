import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rota_max/core/theme/app_theme.dart';
import 'package:rota_max/providers/app_state.dart';

/// Aba Veículos provisória: mostra o veículo atual até a tela completa
/// (vários veículos, troca de óleo) entrar na Etapa 6.
class VehiclesPlaceholderScreen extends StatelessWidget {
  const VehiclesPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final vehicle = state.vehicle;
    return Scaffold(
      appBar: AppBar(title: const Text('Veículos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.two_wheeler, color: AppColors.primarySoft),
              title: const Text('Veículo atual'),
              subtitle: Text(
                'Odômetro ${vehicle.odometerKm.toStringAsFixed(0)} km · '
                '${vehicle.kmPerLiter.toStringAsFixed(1)} km/l',
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Em breve: cadastro de moto, carro, utilitário, van e caminhão, '
            'com troca de óleo por veículo.',
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
