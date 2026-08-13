import '../domain/accounting_movement.dart';
import '../domain/wallet.dart';

const int accountingSchemaVersion = 3;

final class UnsupportedAccountingSchemaException implements Exception {
  const UnsupportedAccountingSchemaException(this.version);

  final int version;

  @override
  String toString() => 'Unsupported accounting schema version: $version';
}

final class AccountingDocument {
  factory AccountingDocument({
    required int schemaVersion,
    required List<Wallet> wallets,
    required List<AccountingMovement> movements,
    required Set<String> appliedMigrationIds,
    required DateTime updatedAt,
  }) {
    if (schemaVersion != accountingSchemaVersion) {
      throw UnsupportedAccountingSchemaException(schemaVersion);
    }
    return AccountingDocument._(
      schemaVersion: schemaVersion,
      wallets: wallets,
      movements: movements,
      appliedMigrationIds: appliedMigrationIds,
      updatedAt: updatedAt,
    );
  }

  const AccountingDocument._({
    required this.schemaVersion,
    required this.wallets,
    required this.movements,
    required this.appliedMigrationIds,
    required this.updatedAt,
  });

  final int schemaVersion;
  final List<Wallet> wallets;
  final List<AccountingMovement> movements;
  final Set<String> appliedMigrationIds;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'wallets': wallets.map((wallet) => wallet.toJson()).toList(),
    'movements': movements.map((movement) => movement.toJson()).toList(),
    'appliedMigrationIds': appliedMigrationIds.toList()..sort(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory AccountingDocument.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion']! as int;
    if (schemaVersion != accountingSchemaVersion) {
      throw UnsupportedAccountingSchemaException(schemaVersion);
    }
    return AccountingDocument(
      schemaVersion: schemaVersion,
      wallets: (json['wallets']! as List)
          .map(
            (wallet) =>
                Wallet.fromJson(Map<String, Object?>.from(wallet as Map)),
          )
          .toList(),
      movements: (json['movements']! as List)
          .map(
            (movement) => AccountingMovement.fromJson(
              Map<String, Object?>.from(movement as Map),
            ),
          )
          .toList(),
      appliedMigrationIds: (json['appliedMigrationIds']! as List)
          .cast<String>()
          .toSet(),
      updatedAt: DateTime.parse(json['updatedAt']! as String),
    );
  }
}
