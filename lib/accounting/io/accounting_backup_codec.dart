import 'dart:convert';
import 'dart:typed_data';

import '../adapters/legacy_movement_adapter.dart';
import '../domain/wallet.dart';
import '../migration/accounting_migrator.dart';
import '../persistence/accounting_document.dart';
import '../support/sha256.dart';
import 'accounting_backup_bundle.dart';

abstract interface class AccountingBackupCodec {
  Map<String, Object?> encodeV3(AccountingBackupBundle bundle);
  DecodedAccountingBackup decodeAny(Map<String, Object?> json);
}

final class DefaultAccountingBackupCodec implements AccountingBackupCodec {
  const DefaultAccountingBackupCodec({
    LegacyMovementAdapter adapter = const LegacyMovementAdapter(),
    AccountingMigrator migrator = const AccountingMigrator(
      LegacyMovementAdapter(),
    ),
  }) : _adapter = adapter,
       _migrator = migrator;

  final LegacyMovementAdapter _adapter;
  final AccountingMigrator _migrator;

  static const Set<String> _v3CanonicalKeys = <String>{
    'schemaVersion',
    'wallets',
    'walletImages',
    'movements',
    'snapshots',
    'currentPrices',
    'settings',
    'appliedMigrationIds',
    'legacyMovementMetadata',
    'legacyMovementMigrationMetadata',
    'legacyMigrationProblems',
    'legacyAccountingPolicy',
    'assignmentAudits',
    'updatedAt',
    'exportedAt',
  };

  @override
  Map<String, Object?> encodeV3(AccountingBackupBundle bundle) {
    final documentJson = bundle.document.toJson();
    final movements = <Map<String, Object?>>[];
    for (final movement in bundle.document.movements) {
      final synchronized = _adapter.toLegacyJson(
        movement,
        preservedFields:
            bundle.document.legacyMovementMetadata[movement.id] ??
            const <String, Object?>{},
      );
      synchronized.addAll(movement.toJson());
      _assertDecimalStrings(synchronized);
      movements.add(synchronized);
    }
    return <String, Object?>{
      ...bundle.preservedTopLevelFields,
      ...documentJson,
      'schemaVersion': accountingSchemaVersion,
      'movements': movements,
      'walletImages': bundle.walletImages
          .map(
            (image) => <String, Object?>{
              'imageRef': image.imageRef.toJson(),
              'entryName': 'wallet_images/${image.imageRef.fileName}',
              'bytesBase64': base64Encode(image.bytes),
            },
          )
          .toList(),
      'snapshots': bundle.snapshots.map((value) => value.toJson()).toList(),
      'currentPrices': bundle.currentPrices,
      'settings': bundle.settings.toJson(),
      'exportedAt': bundle.exportedAt.toIso8601String(),
    };
  }

  @override
  DecodedAccountingBackup decodeAny(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != null) {
      if (schemaVersion is! int) {
        throw const FormatException('schemaVersion debe ser un entero.');
      }
      if (schemaVersion == accountingSchemaVersion) return _decodeV3(json);
      throw UnsupportedAccountingSchemaException(schemaVersion);
    }
    final legacyVersion = json['version'];
    if (legacyVersion != null && legacyVersion != 1 && legacyVersion != 2) {
      throw FormatException(
        'Versión de respaldo legacy no soportada: $legacyVersion',
      );
    }
    return _decodeLegacy(json);
  }

  DecodedAccountingBackup _decodeV3(Map<String, Object?> json) {
    for (final key in _v3CanonicalKeys) {
      if (!json.containsKey(key)) {
        throw FormatException('La copia v3 no contiene $key.');
      }
    }
    if (json['wallets'] is! List ||
        json['walletImages'] is! List ||
        json['movements'] is! List ||
        json['snapshots'] is! List ||
        json['currentPrices'] is! Map ||
        json['settings'] is! Map ||
        json['appliedMigrationIds'] is! List ||
        json['legacyMovementMetadata'] is! Map ||
        json['legacyMovementMigrationMetadata'] is! Map ||
        json['legacyMigrationProblems'] is! List ||
        json['assignmentAudits'] is! List) {
      throw const FormatException('La copia v3 contiene tipos inválidos.');
    }
    final movementRows = (json['movements']! as List)
        .map((value) => Map<String, Object?>.from(value as Map))
        .toList();
    for (final row in movementRows) {
      _validateDecimalStrings(row);
    }
    final document = AccountingDocument.fromJson(<String, Object?>{
      for (final entry in json.entries)
        if (const <String>{
          'schemaVersion',
          'wallets',
          'movements',
          'appliedMigrationIds',
          'legacyMovementMetadata',
          'legacyMovementMigrationMetadata',
          'legacyMigrationProblems',
          'legacyAccountingPolicy',
          'assignmentAudits',
          'updatedAt',
        }.contains(entry.key))
          entry.key: entry.value,
    });
    _validateDocument(document);
    final walletImages = (json['walletImages']! as List)
        .map((value) => _decodeImage(Map<String, Object?>.from(value as Map)))
        .toList();
    final imageRefs = <String, WalletImageRef>{
      for (final wallet in document.wallets)
        if (wallet.imageRef != null) wallet.imageRef!.id: wallet.imageRef!,
    };
    if (walletImages.length != imageRefs.length ||
        walletImages.any(
          (image) =>
              imageRefs[image.imageRef.id]?.toJson().toString() !=
              image.imageRef.toJson().toString(),
        )) {
      throw const FormatException(
        'Las imágenes no corresponden con las referencias de cartera.',
      );
    }
    final snapshots = (json['snapshots']! as List)
        .map(
          (value) => BackupPortfolioSnapshot.fromJson(
            Map<String, Object?>.from(value as Map),
          ),
        )
        .toList();
    final currentPrices = _finiteDoubleMap(json['currentPrices']! as Map);
    final settings = AccountingBackupSettings.fromJson(
      Map<String, Object?>.from(json['settings']! as Map),
    );
    final exportedAt = DateTime.parse(json['exportedAt']! as String);
    final preserved = <String, Object?>{
      for (final entry in json.entries)
        if (!_v3CanonicalKeys.contains(entry.key)) entry.key: entry.value,
    };
    return DecodedAccountingBackup(
      bundle: AccountingBackupBundle(
        document: document,
        snapshots: snapshots,
        currentPrices: currentPrices,
        settings: settings,
        walletImages: walletImages,
        exportedAt: exportedAt,
        preservedTopLevelFields: preserved,
      ),
      origin: AccountingBackupOrigin.schemaV3,
      warnings: const <String>[],
    );
  }

  DecodedAccountingBackup _decodeLegacy(Map<String, Object?> json) {
    final movements = json['movements'];
    final prices = json['currentPrices'];
    if (movements is! List || prices is! Map) {
      throw const FormatException('La copia legacy está incompleta.');
    }
    final report = _migrator.migrateLegacy(
      legacy: movements
          .map((value) => Map<String, Object?>.from(value as Map))
          .toList(),
    );
    final hasSnapshots = json.containsKey('snapshots');
    final snapshotsRaw = json['snapshots'];
    if (hasSnapshots && snapshotsRaw is! List) {
      throw const FormatException('Las instantáneas legacy no son válidas.');
    }
    final settingsJson = json['settings'] is Map
        ? Map<String, Object?>.from(json['settings']! as Map)
        : <String, Object?>{};
    final settings = AccountingBackupSettings(
      sellFeePercent: settingsJson['sellFeePercent'] == null
          ? 0
          : _finiteDouble(settingsJson['sellFeePercent'], 'sellFeePercent'),
      priceModes: settingsJson['priceModes'] is Map
          ? Map<String, String>.from(settingsJson['priceModes']! as Map)
          : const <String, String>{},
      manualPricesUpdatedAtMs: settingsJson['manualPricesUpdatedAtMs'] is Map
          ? (settingsJson['manualPricesUpdatedAtMs']! as Map).map(
              (key, value) => MapEntry(key as String, (value as num).toInt()),
            )
          : const <String, int>{},
      preservedFields: <String, Object?>{
        for (final entry in settingsJson.entries)
          if (!const <String>{
            'sellFeePercent',
            'priceModes',
            'manualPricesUpdatedAtMs',
          }.contains(entry.key))
            entry.key: entry.value,
      },
    );
    return DecodedAccountingBackup(
      bundle: AccountingBackupBundle(
        document: report.document,
        snapshots: hasSnapshots
            ? (snapshotsRaw as List)
                  .map(
                    (value) => BackupPortfolioSnapshot.fromJson(
                      Map<String, Object?>.from(value as Map),
                    ),
                  )
                  .toList()
            : const <BackupPortfolioSnapshot>[],
        currentPrices: _finiteDoubleMap(prices),
        settings: settings,
        walletImages: const <PortableWalletImage>[],
        exportedAt: json['exportedAt'] == null
            ? report.document.updatedAt
            : DateTime.parse(json['exportedAt']! as String),
        preservedTopLevelFields: <String, Object?>{
          for (final entry in json.entries)
            if (!const <String>{
              'version',
              'schemaVersion',
              'movements',
              'snapshots',
              'currentPrices',
              'settings',
              'exportedAt',
            }.contains(entry.key))
              entry.key: entry.value,
        },
      ),
      origin: json['version'] == 2
          ? AccountingBackupOrigin.legacyV2
          : AccountingBackupOrigin.legacyV1,
      warnings: <String>[
        if (!hasSnapshots) 'Copia legacy sin instantáneas; se usaron vacías.',
      ],
    );
  }
}

PortableWalletImage _decodeImage(Map<String, Object?> json) {
  final imageRef = WalletImageRef.fromJson(
    Map<String, Object?>.from(json['imageRef']! as Map),
  );
  final entryName = json['entryName'];
  if (entryName != 'wallet_images/${imageRef.fileName}') {
    throw const FormatException('La ruta portable de imagen no es segura.');
  }
  final bytes = Uint8List.fromList(
    base64Decode(json['bytesBase64']! as String),
  );
  if (bytes.length != imageRef.byteLength ||
      sha256BytesHex(bytes) != imageRef.sha256) {
    throw const FormatException('La imagen portable no coincide con su hash.');
  }
  return PortableWalletImage(imageRef: imageRef, bytes: bytes);
}

Map<String, double> _finiteDoubleMap(Map values) => values.map((key, value) {
  if (key is! String) throw const FormatException('Clave numérica inválida.');
  return MapEntry(key, _finiteDouble(value, key));
});

double _finiteDouble(Object? value, String field) {
  if (value is! num || !value.isFinite) {
    throw FormatException('$field debe ser un número finito.');
  }
  return value.toDouble();
}

void _validateDocument(AccountingDocument document) {
  final walletIds = <String>{};
  for (final wallet in document.wallets) {
    if (wallet.id.trim().isEmpty || !walletIds.add(wallet.id)) {
      throw const FormatException('ID de cartera inválido o duplicado.');
    }
  }
  final movementIds = <String>{};
  for (final movement in document.movements) {
    if (movement.id.trim().isEmpty || !movementIds.add(movement.id)) {
      throw const FormatException('ID de movimiento inválido o duplicado.');
    }
    for (final id in <String?>[
      movement.sourceWalletId,
      movement.destinationWalletId,
      movement.adjustmentWalletId,
    ]) {
      if (id != null && !walletIds.contains(id)) {
        throw const FormatException('Referencia de cartera inexistente.');
      }
    }
  }
}

const List<String> _amountFields = <String>[
  'quantity',
  'unitPriceFiat',
  'fiatFeeAmount',
  'receivedAmount',
  'cryptoFeeAmount',
  'totalDebitedAmount',
  'feeFiatValue',
  'adjustmentQuantity',
  'observedBalance',
];

void _assertDecimalStrings(Map<String, Object?> row) {
  assert(() {
    _validateDecimalStrings(row);
    return true;
  }());
}

void _validateDecimalStrings(Map<String, Object?> row) {
  for (final field in _amountFields) {
    final value = row[field];
    if (value != null && value is! String) {
      throw FormatException('$field debe usar un decimal String.');
    }
  }
  final links = row['reconciliationLinks'];
  if (links is List) {
    for (final link in links) {
      final quantity = (link as Map)['quantityResolved'];
      if (quantity != null && quantity is! String) {
        throw const FormatException(
          'quantityResolved debe usar un decimal String.',
        );
      }
    }
  }
}
