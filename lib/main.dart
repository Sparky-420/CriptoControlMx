import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cripto_control_mx/cripto_control_app.dart' as app;
import 'package:cripto_control_mx/tactical_tool.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _seedFromBundledBackupIfNeeded();
  runApp(const CriptoControlShell());
}

class CriptoControlShell extends StatelessWidget {
  const CriptoControlShell({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (BuildContext shellContext) {
          return Stack(
            children: <Widget>[
              const app.CriptoControlApp(),
              Positioned(
                right: 14,
                bottom: 88,
                child: SafeArea(
                  child: FloatingActionButton.extended(
                    heroTag: 'tactical_tool_fab',
                    onPressed: () {
                      Navigator.of(shellContext).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const TacticalToolScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.psychology_alt_outlined),
                    label: const Text('Táctica'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> _seedFromBundledBackupIfNeeded() async {
  final prefs = await SharedPreferences.getInstance();
  final existingMovementsRaw = prefs.getString('movements_json');

  var hasExistingMovements = false;
  if (existingMovementsRaw != null && existingMovementsRaw.trim().isNotEmpty) {
    try {
      final existingDecoded = jsonDecode(existingMovementsRaw);
      hasExistingMovements =
          existingDecoded is List && existingDecoded.isNotEmpty;
    } catch (_) {
      hasExistingMovements = true;
    }
  }

  if (hasExistingMovements) return;

  try {
    final raw = await rootBundle.loadString('assets/import/backup_v2.json');
    final decoded = jsonDecode(raw);

    if (decoded is! Map<String, dynamic>) return;

    final movements = decoded['movements'];
    final currentPrices = decoded['currentPrices'];
    final settings = decoded['settings'];

    if (movements is! List || movements.isEmpty || currentPrices is! Map) {
      return;
    }

    await prefs.setString('movements_json', jsonEncode(movements));
    await prefs.setString('prices_json', jsonEncode(currentPrices));

    if (settings is Map && settings['sellFeePercent'] is num) {
      await prefs.setDouble(
        'sell_fee_percent',
        (settings['sellFeePercent'] as num).toDouble(),
      );
    }
  } catch (_) {
    // Sin archivo incluido o JSON inválido: la app arranca normal.
  }
}
