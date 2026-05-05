import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main_v2_step2.dart' as v2;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _seedFromBundledBackupIfNeeded();
  v2.main();
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

    if (movements is! List || movements.isEmpty || currentPrices is! Map)
      return;

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
