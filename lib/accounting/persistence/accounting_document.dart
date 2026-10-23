import '../domain/accounting_movement.dart';
import '../domain/assignment_audit.dart';
import '../domain/wallet.dart';
import '../migration/legacy_migration_problem.dart';

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
    Map<String, Map<String, Object?>> legacyMovementMetadata =
        const <String, Map<String, Object?>>{},
    Map<String, Map<String, Object?>> legacyMovementMigrationMetadata =
        const <String, Map<String, Object?>>{},
    List<LegacyMigrationProblem> legacyMigrationProblems =
        const <LegacyMigrationProblem>[],
    List<AssignmentAudit> assignmentAudits = const <AssignmentAudit>[],
    LegacyAccountingPolicy legacyAccountingPolicy =
        LegacyAccountingPolicy.preservePreviousGlobal,
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
      legacyMovementMetadata: legacyMovementMetadata,
      legacyMovementMigrationMetadata: legacyMovementMigrationMetadata,
      legacyMigrationProblems: legacyMigrationProblems,
      assignmentAudits: assignmentAudits,
      legacyAccountingPolicy: legacyAccountingPolicy,
    );
  }

  const AccountingDocument._({
    required this.schemaVersion,
    required this.wallets,
    required this.movements,
    required this.appliedMigrationIds,
    required this.updatedAt,
    required this.legacyMovementMetadata,
    required this.legacyMovementMigrationMetadata,
    required this.legacyMigrationProblems,
    required this.assignmentAudits,
    required this.legacyAccountingPolicy,
  });

  final int schemaVersion;
  final List<Wallet> wallets;
  final List<AccountingMovement> movements;
  final Set<String> appliedMigrationIds;
  final DateTime updatedAt;
  final Map<String, Map<String, Object?>> legacyMovementMetadata;
  final Map<String, Map<String, Object?>> legacyMovementMigrationMetadata;
  final List<LegacyMigrationProblem> legacyMigrationProblems;
  final List<AssignmentAudit> assignmentAudits;
  final LegacyAccountingPolicy legacyAccountingPolicy;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'wallets': wallets.map((wallet) => wallet.toJson()).toList(),
    'movements': movements.map((movement) => movement.toJson()).toList(),
    'appliedMigrationIds': appliedMigrationIds.toList()..sort(),
    'updatedAt': updatedAt.toIso8601String(),
    'legacyMovementMetadata': legacyMovementMetadata,
    'legacyMovementMigrationMetadata': legacyMovementMigrationMetadata,
    'legacyMigrationProblems': legacyMigrationProblems
        .map((problem) => problem.toJson())
        .toList(),
    'assignmentAudits': assignmentAudits
        .map((audit) => audit.toJson())
        .toList(),
    'legacyAccountingPolicy': legacyAccountingPolicy.name,
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
      legacyMovementMetadata:
          (json['legacyMovementMetadata'] as Map? ?? const <String, Object?>{})
              .map(
                (key, value) => MapEntry(
                  key as String,
                  Map<String, Object?>.from(value as Map),
                ),
              ),
      legacyMovementMigrationMetadata:
          (json['legacyMovementMigrationMetadata'] as Map? ??
                  const <String, Object?>{})
              .map(
                (key, value) => MapEntry(
                  key as String,
                  Map<String, Object?>.from(value as Map),
                ),
              ),
      legacyMigrationProblems:
          (json['legacyMigrationProblems'] as List? ?? const <Object?>[])
              .map(
                (problem) => LegacyMigrationProblem.fromJson(
                  Map<String, Object?>.from(problem as Map),
                ),
              )
              .toList(),
      assignmentAudits: (json['assignmentAudits'] as List? ?? const <Object?>[])
          .map(
            (audit) => AssignmentAudit.fromJson(
              Map<String, Object?>.from(audit as Map),
            ),
          )
          .toList(),
      legacyAccountingPolicy: json['legacyAccountingPolicy'] == null
          ? LegacyAccountingPolicy.preservePreviousGlobal
          : LegacyAccountingPolicy.values.byName(
              json['legacyAccountingPolicy']! as String,
            ),
    );
  }
}
