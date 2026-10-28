import '../adapters/legacy_movement_adapter.dart';
import '../domain/accounting_movement.dart';
import '../domain/wallet.dart';
import '../persistence/accounting_document.dart';
import '../projection/ledger_projection.dart';
import '../support/sha256.dart';
import 'legacy_migration_problem.dart';
import 'migration_report.dart';

const String legacyV1ToV3MigrationId = 'legacy-movements-v1-to-accounting-v3';

final class AccountingMigrator {
  const AccountingMigrator(this.adapter);

  final LegacyMovementAdapter adapter;

  MigrationReport migrateLegacy({
    required List<Map<String, Object?>> legacy,
    AccountingDocument? existing,
  }) {
    final movements = <AccountingMovement>[...?existing?.movements];
    final metadata = <String, Map<String, Object?>>{
      ...?existing?.legacyMovementMetadata,
    };
    final migrationMetadata = <String, Map<String, Object?>>{
      ...?existing?.legacyMovementMigrationMetadata,
    };
    final problems = <LegacyMigrationProblem>[
      ...?existing?.legacyMigrationProblems,
    ];
    final problemIds = problems.map((problem) => problem.id).toSet();
    final movementById = <String, AccountingMovement>{
      for (final movement in movements) movement.id: movement,
    };
    final importedIds = <String>{};
    final conflictedNewIds = <String>{};
    final competingPayloads = <String, Map<String, Object?>>{};
    var imported = 0;
    var skippedDuplicates = 0;

    void addProblem(LegacyMigrationProblem problem) {
      if (problemIds.add(problem.id)) problems.add(problem);
    }

    for (var sourceIndex = 0; sourceIndex < legacy.length; sourceIndex++) {
      final payload = Map<String, Object?>.from(legacy[sourceIndex]);
      final conversion = adapter.fromLegacyJson(payload);
      if (conversion.movementOrNull == null) {
        addProblem(
          LegacyMigrationProblem.create(
            kind: LegacyMigrationProblemKind.unconvertible,
            sourceIndex: sourceIndex,
            primaryPayload: payload,
            conversionIssues: conversion.issues,
          ),
        );
        continue;
      }
      final converted = conversion.movement.copyWith(
        id: payload['id']?.toString().trim().isNotEmpty == true
            ? payload['id']!.toString().trim()
            : deterministicUuidFromSha256(canonicalJson(payload)),
        sourceWalletId: null,
        destinationWalletId: null,
        destinationType: null,
        adjustmentWalletId: null,
        walletAssignmentStatus: WalletAssignmentStatus.legacyUnassigned,
      );
      final storedPayload = metadata[converted.id];
      final prior = movementById[converted.id];
      if (prior == null) {
        if (conflictedNewIds.contains(converted.id)) {
          addProblem(
            LegacyMigrationProblem.create(
              kind: LegacyMigrationProblemKind.conflictingId,
              sourceIndex: sourceIndex,
              primaryPayload: payload,
              conflictingPayload: competingPayloads[converted.id]!,
            ),
          );
          continue;
        }
        movementById[converted.id] = converted;
        movements.add(converted);
        metadata[converted.id] = <String, Object?>{
          ...conversion.preservedFields,
        };
        migrationMetadata[converted.id] = <String, Object?>{
          'projectionWalletId': virtualUnassignedWalletId,
          'accountingPolicy':
              LegacyAccountingPolicy.preservePreviousGlobal.name,
        };
        importedIds.add(converted.id);
        imported++;
        continue;
      }
      if (storedPayload != null &&
          canonicalJson(storedPayload) == canonicalJson(payload)) {
        skippedDuplicates++;
        continue;
      }
      addProblem(
        LegacyMigrationProblem.create(
          kind: LegacyMigrationProblemKind.conflictingId,
          sourceIndex: sourceIndex,
          primaryPayload: payload,
          conflictingPayload: storedPayload ?? prior.toJson(),
        ),
      );
      if (importedIds.remove(converted.id)) {
        imported--;
        movements.removeWhere((movement) => movement.id == converted.id);
        movementById.remove(converted.id);
        metadata.remove(converted.id);
        migrationMetadata.remove(converted.id);
        conflictedNewIds.add(converted.id);
        competingPayloads[converted.id] = storedPayload!;
      }
    }
    final updatedAt = existing?.updatedAt ?? _updatedAt(movements);
    final document = AccountingDocument(
      schemaVersion: accountingSchemaVersion,
      wallets: existing?.wallets ?? const <Wallet>[],
      movements: movements,
      appliedMigrationIds: <String>{
        ...?existing?.appliedMigrationIds,
        legacyV1ToV3MigrationId,
      },
      updatedAt: updatedAt,
      legacyMovementMetadata: metadata,
      legacyMovementMigrationMetadata: migrationMetadata,
      legacyMigrationProblems: problems,
      legacyAccountingPolicy: LegacyAccountingPolicy.preservePreviousGlobal,
    );
    return MigrationReport(
      document: document,
      imported: imported,
      skippedDuplicates: skippedDuplicates,
      unassignedMovementIds: movements
          .where(
            (movement) =>
                movement.walletAssignmentStatus ==
                WalletAssignmentStatus.legacyUnassigned,
          )
          .map((movement) => movement.id)
          .toList(),
      problems: problems,
    );
  }
}

DateTime _updatedAt(List<AccountingMovement> movements) {
  if (movements.isEmpty) {
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
  return movements
      .map((movement) => movement.updatedAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);
}
