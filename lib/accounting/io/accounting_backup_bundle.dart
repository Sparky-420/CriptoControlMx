import 'dart:typed_data';

import '../domain/wallet.dart';
import '../persistence/accounting_document.dart';
import '../persistence/wallet_image_processor.dart';

enum AccountingBackupOrigin { legacyV1, legacyV2, schemaV3 }

final class BackupCoinSnapshot {
  const BackupCoinSnapshot({
    required this.coin,
    required this.quantity,
    required this.costBase,
    required this.avgPrice,
    required this.currentValue,
    required this.unrealizedPL,
    required this.realizedPL,
  });

  final String coin;
  final double quantity;
  final double costBase;
  final double avgPrice;
  final double currentValue;
  final double unrealizedPL;
  final double realizedPL;

  Map<String, Object?> toJson() => <String, Object?>{
    'coin': coin,
    'quantity': quantity,
    'costBase': costBase,
    'avgPrice': avgPrice,
    'currentValue': currentValue,
    'unrealizedPL': unrealizedPL,
    'realizedPL': realizedPL,
  };

  factory BackupCoinSnapshot.fromJson(Map<String, Object?> json) =>
      BackupCoinSnapshot(
        coin: json['coin']! as String,
        quantity: _finiteDouble(json['quantity'], 'quantity'),
        costBase: _finiteDouble(json['costBase'], 'costBase'),
        avgPrice: _finiteDouble(json['avgPrice'], 'avgPrice'),
        currentValue: _finiteDouble(json['currentValue'], 'currentValue'),
        unrealizedPL: _finiteDouble(json['unrealizedPL'], 'unrealizedPL'),
        realizedPL: _finiteDouble(json['realizedPL'], 'realizedPL'),
      );
}

final class BackupPortfolioSnapshot {
  const BackupPortfolioSnapshot({
    required this.id,
    required this.createdAt,
    required this.totalCostBase,
    required this.totalCurrentValue,
    required this.totalUnrealizedPL,
    required this.totalRealizedPL,
    required this.movementCount,
    required this.coins,
  });

  final String id;
  final DateTime createdAt;
  final double totalCostBase;
  final double totalCurrentValue;
  final double totalUnrealizedPL;
  final double totalRealizedPL;
  final int movementCount;
  final List<BackupCoinSnapshot> coins;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'totalCostBase': totalCostBase,
    'totalCurrentValue': totalCurrentValue,
    'totalUnrealizedPL': totalUnrealizedPL,
    'totalRealizedPL': totalRealizedPL,
    'movementCount': movementCount,
    'coins': coins.map((coin) => coin.toJson()).toList(),
  };

  factory BackupPortfolioSnapshot.fromJson(
    Map<String, Object?> json,
  ) => BackupPortfolioSnapshot(
    id: json['id']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
    totalCostBase: _finiteDouble(json['totalCostBase'], 'totalCostBase'),
    totalCurrentValue: _finiteDouble(
      json['totalCurrentValue'],
      'totalCurrentValue',
    ),
    totalUnrealizedPL: _finiteDouble(
      json['totalUnrealizedPL'],
      'totalUnrealizedPL',
    ),
    totalRealizedPL: _finiteDouble(json['totalRealizedPL'], 'totalRealizedPL'),
    movementCount: json['movementCount']! as int,
    coins: (json['coins']! as List)
        .map(
          (coin) => BackupCoinSnapshot.fromJson(
            Map<String, Object?>.from(coin as Map),
          ),
        )
        .toList(),
  );
}

final class AccountingBackupSettings {
  const AccountingBackupSettings({
    required this.sellFeePercent,
    required this.priceModes,
    required this.manualPricesUpdatedAtMs,
    this.preservedFields = const <String, Object?>{},
  });

  final double sellFeePercent;
  final Map<String, String> priceModes;
  final Map<String, int> manualPricesUpdatedAtMs;
  final Map<String, Object?> preservedFields;

  Map<String, Object?> toJson() => <String, Object?>{
    ...preservedFields,
    'sellFeePercent': sellFeePercent,
    'priceModes': priceModes,
    'manualPricesUpdatedAtMs': manualPricesUpdatedAtMs,
  };

  factory AccountingBackupSettings.fromJson(Map<String, Object?> json) {
    const canonicalKeys = <String>{
      'sellFeePercent',
      'priceModes',
      'manualPricesUpdatedAtMs',
    };
    return AccountingBackupSettings(
      sellFeePercent: _finiteDouble(json['sellFeePercent'], 'sellFeePercent'),
      priceModes: Map<String, String>.from(json['priceModes']! as Map),
      manualPricesUpdatedAtMs: (json['manualPricesUpdatedAtMs']! as Map).map(
        (key, value) => MapEntry(key as String, value as int),
      ),
      preservedFields: <String, Object?>{
        for (final entry in json.entries)
          if (!canonicalKeys.contains(entry.key)) entry.key: entry.value,
      },
    );
  }
}

final class PortableWalletImage {
  const PortableWalletImage({required this.imageRef, required this.bytes});

  final WalletImageRef imageRef;
  final Uint8List bytes;

  ProcessedWalletImage toProcessed() => ProcessedWalletImage(bytes, imageRef);
}

final class AccountingBackupBundle {
  const AccountingBackupBundle({
    required this.document,
    required this.snapshots,
    required this.currentPrices,
    required this.settings,
    required this.walletImages,
    required this.exportedAt,
    this.preservedTopLevelFields = const <String, Object?>{},
  });

  final AccountingDocument document;
  final List<BackupPortfolioSnapshot> snapshots;
  final Map<String, double> currentPrices;
  final AccountingBackupSettings settings;
  final List<PortableWalletImage> walletImages;
  final DateTime exportedAt;
  final Map<String, Object?> preservedTopLevelFields;
}

final class DecodedAccountingBackup {
  const DecodedAccountingBackup({
    required this.bundle,
    required this.origin,
    required this.warnings,
  });

  final AccountingBackupBundle bundle;
  final AccountingBackupOrigin origin;
  final List<String> warnings;
}

double _finiteDouble(Object? value, String field) {
  if (value is! num || !value.isFinite) {
    throw FormatException('$field debe ser un número finito.');
  }
  return value.toDouble();
}
