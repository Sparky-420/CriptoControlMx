import '../migration/accounting_migrator.dart';
import '../migration/migration_report.dart';
import '../application/wallet_lifecycle_coordinator.dart';
import '../domain/accounting_movement.dart';
import '../domain/wallet.dart';
import '../persistence/accounting_document.dart';
import '../persistence/accounting_repository.dart';
import '../projection/ledger_projection.dart';
import 'legacy_movement_adapter.dart';

final class AccountingLoadResult {
  const AccountingLoadResult({
    required this.document,
    required this.legacyView,
    required this.migrationReport,
  });

  final AccountingDocument document;
  final List<Map<String, Object?>> legacyView;
  final MigrationReport? migrationReport;
}

final class LegacyPersistenceBridge {
  const LegacyPersistenceBridge(
    this.repository,
    this.migrator,
    this.adapter,
    this.lifecycleCoordinator,
  );

  final AccountingRepository repository;
  final AccountingMigrator migrator;
  final LegacyMovementAdapter adapter;
  final WalletLifecycleCoordinator lifecycleCoordinator;

  Future<AccountingLoadResult> load(
    List<Map<String, Object?>> legacySource,
  ) async {
    final persisted = await repository.read();
    if (persisted != null) {
      await lifecycleCoordinator.recoverPendingCleanup();
      return AccountingLoadResult(
        document: persisted,
        legacyView: _legacyView(persisted),
        migrationReport: null,
      );
    }

    final report = migrator.migrateLegacy(legacy: legacySource);
    await repository.write(report.document);
    await lifecycleCoordinator.recoverPendingCleanup();
    return AccountingLoadResult(
      document: report.document,
      legacyView: _legacyView(report.document),
      migrationReport: report,
    );
  }

  Future<AccountingDocument> saveLegacyView(
    AccountingDocument current,
    List<Map<String, Object?>> legacyView, {
    Set<String> deletedIds = const <String>{},
  }) async {
    final currentById = <String, AccountingMovement>{
      for (final movement in current.movements) movement.id: movement,
    };
    final updatedById = <String, AccountingMovement>{};
    final metadata = <String, Map<String, Object?>>{
      ...current.legacyMovementMetadata,
    };
    final migrationMetadata = <String, Map<String, Object?>>{
      ...current.legacyMovementMigrationMetadata,
    };

    for (final raw in legacyView) {
      final conversion = adapter.fromLegacyJson(raw);
      final legacyMovement = conversion.movementOrNull;
      if (legacyMovement == null) {
        throw FormatException('Legacy movement cannot be converted.');
      }
      if (deletedIds.contains(legacyMovement.id)) continue;
      if (updatedById.containsKey(legacyMovement.id)) {
        throw StateError('Duplicate legacy movement id: ${legacyMovement.id}');
      }
      final existing = currentById[legacyMovement.id];
      if (existing == null) {
        updatedById[legacyMovement.id] = legacyMovement.copyWith(
          sourceWalletId: null,
          destinationWalletId: null,
          destinationType: null,
          adjustmentWalletId: null,
          walletAssignmentStatus: WalletAssignmentStatus.legacyUnassigned,
        );
        metadata[legacyMovement.id] = <String, Object?>{
          ...conversion.preservedFields,
        };
        migrationMetadata[legacyMovement.id] = <String, Object?>{
          'projectionWalletId': virtualUnassignedWalletId,
          'accountingPolicy':
              LegacyAccountingPolicy.preservePreviousGlobal.name,
        };
      } else {
        updatedById[legacyMovement.id] = _mergeLegacyFields(
          existing,
          legacyMovement,
        );
      }
    }

    final movements = <AccountingMovement>[
      for (final movement in current.movements)
        if (!deletedIds.contains(movement.id))
          updatedById.remove(movement.id) ?? movement,
      ...updatedById.values,
    ];
    for (final id in deletedIds) {
      metadata.remove(id);
      migrationMetadata.remove(id);
    }
    final document = AccountingDocument(
      schemaVersion: current.schemaVersion,
      wallets: current.wallets,
      movements: movements,
      appliedMigrationIds: current.appliedMigrationIds,
      updatedAt: _updatedAt(current.updatedAt, movements),
      legacyMovementMetadata: metadata,
      legacyMovementMigrationMetadata: migrationMetadata,
      legacyMigrationProblems: current.legacyMigrationProblems,
      assignmentAudits: current.assignmentAudits,
      legacyAccountingPolicy: current.legacyAccountingPolicy,
    );
    await repository.write(document);
    return document;
  }

  Future<AccountingDocument> deleteLegacyIds(
    AccountingDocument current,
    Set<String> deletedIds,
  ) => saveLegacyView(current, _legacyView(current), deletedIds: deletedIds);

  Future<void> clearCanonicalDocument() => repository.clear();

  List<Map<String, Object?>> _legacyView(AccountingDocument document) =>
      document.movements
          .map(
            (movement) => adapter.toLegacyJson(
              movement,
              preservedFields:
                  document.legacyMovementMetadata[movement.id] ??
                  const <String, Object?>{},
            ),
          )
          .toList(growable: false);
}

AccountingMovement _mergeLegacyFields(
  AccountingMovement current,
  AccountingMovement legacy,
) => current.copyWith(
  type: legacy.type,
  asset: legacy.asset,
  occurredAt: legacy.occurredAt,
  quantity: legacy.quantity,
  unitPriceFiat: legacy.unitPriceFiat,
  fiatFeeAmount: legacy.fiatFeeAmount,
  receivedAmount: legacy.receivedAmount,
  cryptoFeeAmount: legacy.cryptoFeeAmount,
  cryptoFeeAsset: legacy.cryptoFeeAsset,
  totalDebitedAmount: legacy.totalDebitedAmount,
  feeFiatValue: legacy.feeFiatValue,
  fiatFeeTreatment: legacy.fiatFeeTreatment,
  network: legacy.network,
  note: legacy.note,
  createdAt: legacy.createdAt,
  updatedAt: legacy.updatedAt,
);

DateTime _updatedAt(DateTime current, List<AccountingMovement> movements) {
  var latest = current;
  for (final movement in movements) {
    if (movement.updatedAt.isAfter(latest)) latest = movement.updatedAt;
  }
  return latest;
}
