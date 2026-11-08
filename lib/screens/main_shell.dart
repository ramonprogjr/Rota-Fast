import 'package:flutter/material.dart';
import 'package:rota_max/screens/history_screen.dart';
import 'package:rota_max/screens/home_screen.dart';
import 'package:rota_max/screens/settings_screen.dart';
import 'package:rota_max/screens/vehicles_placeholder_screen.dart';

/// Estrutura principal: barra inferior com Rota, Relatórios, Veículos e
/// Ajustes. As abas ficam vivas (IndexedStack) para não perder rolagem.
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _tab = widget.initialTab;

  static const _pages = <Widget>[
    HomeScreen(),
    HistoryScreen(),
    VehiclesPlaceholderScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Rota',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Relatórios',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'Veículos',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }
}
