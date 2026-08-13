import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'accounting_backup_bundle.dart';
import 'accounting_backup_restore_service.dart';

const String accountingBackupSnapshotsKey = 'portfolio_snapshots_v23_json';
const String accountingBackupPricesKey = 'prices_json';
const String accountingBackupSellFeePercentKey = 'sell_fee_percent';
const String accountingBackupPriceModesKey = 'price_modes_v1_json';
const String accountingBackupManualPricesUpdatedAtKey =
    'manual_prices_updated_at_v1_json';

const String _preservedSettingsKey = '__accountingBackupPreservedFields';

final class SharedPreferencesAccountingBackupStateStore
    implements AccountingBackupStateStore {
  SharedPreferencesAccountingBackupStateStore({
    Future<SharedPreferences>? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _preferences;

  @override
  Future<AccountingBackupApplicationState> read() async {
    final preferences = await _preferences;
    final snapshotsJson = preferences.getString(accountingBackupSnapshotsKey);
    final pricesJson = preferences.getString(accountingBackupPricesKey);
    final priceModesJson = preferences.getString(accountingBackupPriceModesKey);
    final manualJson = preferences.getString(
      accountingBackupManualPricesUpdatedAtKey,
    );
    final rawModes = priceModesJson == null
        ? <String, Object?>{}
        : Map<String, Object?>.from(jsonDecode(priceModesJson) as Map);
    final preservedEncoded = rawModes.remove(_preservedSettingsKey);
    return AccountingBackupApplicationState(
      snapshots: snapshotsJson == null
          ? const <BackupPortfolioSnapshot>[]
          : (jsonDecode(snapshotsJson) as List)
                .map(
                  (value) => BackupPortfolioSnapshot.fromJson(
                    Map<String, Object?>.from(value as Map),
                  ),
                )
                .toList(),
      currentPrices: pricesJson == null
          ? const <String, double>{}
          : (jsonDecode(pricesJson) as Map).map(
              (key, value) =>
                  MapEntry(key as String, (value as num).toDouble()),
            ),
      settings: AccountingBackupSettings(
        sellFeePercent:
            preferences.getDouble(accountingBackupSellFeePercentKey) ?? 0,
        priceModes: rawModes.map(
          (key, value) => MapEntry(key, value as String),
        ),
        manualPricesUpdatedAtMs: manualJson == null
            ? const <String, int>{}
            : (jsonDecode(manualJson) as Map).map(
                (key, value) => MapEntry(key as String, (value as num).toInt()),
              ),
        preservedFields: preservedEncoded is String
            ? Map<String, Object?>.from(jsonDecode(preservedEncoded) as Map)
            : const <String, Object?>{},
      ),
    );
  }

  @override
  Future<void> write(AccountingBackupApplicationState state) async {
    final preferences = await _preferences;
    final writes = <Future<bool>>[
      preferences.setString(
        accountingBackupSnapshotsKey,
        jsonEncode(state.snapshots.map((value) => value.toJson()).toList()),
      ),
      preferences.setString(
        accountingBackupPricesKey,
        jsonEncode(state.currentPrices),
      ),
      preferences.setDouble(
        accountingBackupSellFeePercentKey,
        state.settings.sellFeePercent,
      ),
      preferences.setString(
        accountingBackupPriceModesKey,
        jsonEncode(<String, Object?>{
          ...state.settings.priceModes,
          if (state.settings.preservedFields.isNotEmpty)
            _preservedSettingsKey: jsonEncode(state.settings.preservedFields),
        }),
      ),
      preferences.setString(
        accountingBackupManualPricesUpdatedAtKey,
        jsonEncode(state.settings.manualPricesUpdatedAtMs),
      ),
    ];
    final results = await Future.wait(writes);
    if (results.any((wrote) => !wrote)) {
      throw StateError('SharedPreferences rechazó el estado del respaldo.');
    }
  }
}
