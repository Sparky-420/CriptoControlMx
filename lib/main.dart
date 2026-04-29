import 'dart:convert';
import 'package:flutter/material.dart';

void main() {
  runApp(const CriptoControlApp());
}

class CriptoControlApp extends StatelessWidget {
  const CriptoControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    var materialApp = MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Control Cripto MX',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
      home: const HomePage(),
    );
    return materialApp;
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;

  final Map<String, double> precios = {
    'BTC': 0,
    'ETH': 0,
    'LINK': 0,
    'LTC': 0,
    'UNI': 0,
  };

  @override
  Widget build(BuildContext context) {
    final pages = [
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Resumen general',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              title: Text('Costo base actual'),
              subtitle: Text('\$0.00 MXN'),
            ),
          ),
          const Card(
            child: ListTile(
              title: Text('Valor actual'),
              subtitle: Text('\$0.00 MXN'),
            ),
          ),
          const Card(
            child: ListTile(
              title: Text('P/L no realizado'),
              subtitle: Text('\$0.00 MXN'),
            ),
          ),
        ],
      ),
      const Center(
        child: Text(
          'Aquí irán tus movimientos BUY, SELL,\nTRANSFER_IN, TRANSFER_OUT y SEND',
          textAlign: TextAlign.center,
        ),
      ),
      ListView(
        padding: const EdgeInsets.all(16),
        children: precios.entries
            .map(
              (e) => Card(
                child: ListTile(
                  title: Text(e.key),
                  subtitle: Text('Precio actual: \$${e.value.toStringAsFixed(2)} MXN'),
                ),
              ),
            )
            .toList(),
      ),
      const Center(
        child: Text(
          'Ajustes\n\nPrimero hagamos que esta base corra bien',
          textAlign: TextAlign.center,
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Control Cripto MX')),
      body: pages[index],
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Luego metemos el formulario de movimientos')),
          );
        },
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) {
          setState(() => index = value);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Resumen'),
          NavigationDestination(icon: Icon(Icons.swap_horiz), label: 'Movimientos'),
          NavigationDestination(icon: Icon(Icons.currency_bitcoin), label: 'Monedas'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Ajustes'),
        ],
      ),
    );
  }
}