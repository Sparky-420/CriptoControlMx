import 'package:flutter/material.dart';

class AppTabSpec {
  final String label;
  final IconData icon;

  const AppTabSpec({required this.label, required this.icon});
}

class AppTabRegistry {
  static const List<AppTabSpec> tabs = <AppTabSpec>[
    AppTabSpec(label: 'Resumen', icon: Icons.dashboard_outlined),
    AppTabSpec(label: 'Movimientos', icon: Icons.swap_horiz),
    AppTabSpec(label: 'Simular', icon: Icons.tune),
    AppTabSpec(label: 'Monedas', icon: Icons.currency_bitcoin),
    AppTabSpec(label: 'Ajustes', icon: Icons.settings_outlined),
  ];

  static List<NavigationDestination> destinations() {
    return tabs
        .map(
          (AppTabSpec tab) => NavigationDestination(
            icon: Icon(tab.icon),
            label: tab.label,
          ),
        )
        .toList(growable: false);
  }
}
