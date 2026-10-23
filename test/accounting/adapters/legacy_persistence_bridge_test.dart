import 'package:cripto_control_mx/accounting/adapters/legacy_movement_adapter.dart';
import 'package:cripto_control_mx/accounting/adapters/legacy_persistence_bridge.dart';
import 'package:cripto_control_mx/accounting/application/wallet_lifecycle_coordinator.dart';
import 'package:cripto_control_mx/accounting/application/wallet_lifecycle_service.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_movement.dart';
import 'package:cripto_control_mx/accounting/domain/assignment_audit.dart';
import 'package:cripto_control_mx/accounting/domain/movement_type.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/migration/accounting_migrator.dart';
import 'package:cripto_control_mx/accounting/migration/legacy_migration_problem.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_document.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_repository.dart';
import 'package:cripto_control_mx/accounting/persistence/shared_preferences_accounting_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const adapter = LegacyMovementAdapter();

  test(
    'load migrates legacy source once and persists only the v3 document',
    () async {
      const legacyEncoded =
          '[{"id":"old-1","type":"buy","coin":"BTC","date":"2026-08-11T12:00:00Z","quantity":"0.25","unitPrice":"1000000","fee":"15","platform":"Mercado Pago","note":"historial"}]';
      SharedPreferences.setMockInitialValues(<String, Object>{
        'movements_json': legacyEncoded,
      });
      final repository = SharedPreferencesAccountingRepository();
      final bridge = LegacyPersistenceBridge(
        repository,
        AccountingMigrator(adapter),
        adapter,
        RecordingLifecycleCoordinator(),
      );

      final loaded = await bridge.load(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'old-1',
          'type': 'buy',
          'coin': 'BTC',
          'date': '2026-08-11T12:00:00Z',
          'quantity': '0.25',
          'unitPrice': '1000000',
          'fee': '15',
          'platform': 'Mercado Pago',
          'note': 'historial',
        },
      ]);

      expect(loaded.migrationReport!.imported, 1);
      expect((await repository.read())!.toJson(), loaded.document.toJson());
      expect(loaded.legacyView.single['platform'], 'Mercado Pago');
      expect(loaded.legacyView.single['note'], 'historial');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('movements_json'), legacyEncoded);
      expect(preferences.containsKey(accountingDocumentKey), isTrue);
    },
  );

  test(
    'legacy-view save preserves v3 wallet fields without dual persistence',
    () async {
      const legacyEncoded = '[{"legacy":"unchanged"}]';
      SharedPreferences.setMockInitialValues(<String, Object>{
        'movements_json': legacyEncoded,
      });
      final current = assignedDocumentFixture();
      final repository = SharedPreferencesAccountingRepository();
      final bridge = LegacyPersistenceBridge(
        repository,
        const AccountingMigrator(adapter),
        adapter,
        RecordingLifecycleCoordinator(),
      );
      final legacy =
          adapter.toLegacyJson(
              current.movements.single,
              preservedFields: current.legacyMovementMetadata['old-1']!,
            )
            ..['note'] = 'nota editada'
            ..['date'] = '2026-08-15T16:30:00Z'
            ..['quantity'] = '0.75'
            ..['fee'] = '21';

      final saved = await bridge.saveLegacyView(current, <Map<String, Object?>>[
        legacy,
      ]);

      final movement = saved.movements.single;
      expect(movement.note, 'nota editada');
      expect(movement.occurredAt, DateTime.utc(2026, 8, 15, 16, 30));
      expect(movement.quantity, AccountingAmount.parse('0.75'));
      expect(movement.fiatFeeAmount, AccountingAmount.fromInt(21));
      expect(
        movement.destinationWalletId,
        '11111111-1111-4111-8111-111111111111',
      );
      expect(movement.destinationType, DestinationType.ownWallet);
      expect(
        movement.adjustmentWalletId,
        '11111111-1111-4111-8111-111111111111',
      );
      expect(
        movement.reconciliationLinks.single.adjustmentMovementId,
        'adjust-1',
      );
      expect(
        saved.wallets.map((wallet) => wallet.toJson()).toList(),
        current.wallets.map((wallet) => wallet.toJson()).toList(),
      );
      expect(saved.legacyMovementMetadata, current.legacyMovementMetadata);
      expect(
        saved.legacyMovementMigrationMetadata,
        current.legacyMovementMigrationMetadata,
      );
      expect(
        saved.legacyMigrationProblems.map((problem) => problem.toJson()),
        current.legacyMigrationProblems.map((problem) => problem.toJson()),
      );
      expect(
        saved.assignmentAudits.map((audit) => audit.toJson()),
        current.assignmentAudits.map((audit) => audit.toJson()),
      );
      expect((await repository.read())!.toJson(), saved.toJson());
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('movements_json'), legacyEncoded);
    },
  );

  test(
    'new legacy rows remain explicitly unassigned despite wallet fields',
    () async {
      final current = assignedDocumentFixture();
      final repository = SharedPreferencesAccountingRepository();
      final bridge = LegacyPersistenceBridge(
        repository,
        const AccountingMigrator(adapter),
        adapter,
        RecordingLifecycleCoordinator(),
      );
      const raw = <String, Object?>{
        'id': 'new-1',
        'type': 'buy',
        'coin': 'ETH',
        'date': '2026-08-13T12:00:00Z',
        'quantity': '2',
        'unitPrice': '50000',
        'fee': '10',
        'sourceWalletId': '11111111-1111-4111-8111-111111111111',
        'destinationWalletId': '11111111-1111-4111-8111-111111111111',
        'destinationType': 'ownWallet',
        'adjustmentWalletId': '11111111-1111-4111-8111-111111111111',
        'walletAssignmentStatus': 'assigned',
        'platform': 'untrusted legacy platform',
      };

      final saved = await bridge.saveLegacyView(current, <Map<String, Object?>>[
        raw,
      ]);

      final added = saved.movements.singleWhere(
        (movement) => movement.id == 'new-1',
      );
      expect(
        added.walletAssignmentStatus,
        WalletAssignmentStatus.legacyUnassigned,
      );
      expect(added.sourceWalletId, isNull);
      expect(added.destinationWalletId, isNull);
      expect(added.destinationType, isNull);
      expect(added.adjustmentWalletId, isNull);
      expect(saved.legacyMovementMetadata['new-1'], raw);
      expect(
        saved.legacyMovementMigrationMetadata['new-1']!['projectionWalletId'],
        'virtual:unassigned',
      );
    },
  );

  test(
    'deleted ids win over same-id legacy rows and remove only their metadata',
    () async {
      final original = assignedDocumentFixture();
      final retained = original.movements.single.copyWith(id: 'keep-1');
      final current = AccountingDocument(
        schemaVersion: accountingSchemaVersion,
        wallets: original.wallets,
        movements: <AccountingMovement>[original.movements.single, retained],
        appliedMigrationIds: original.appliedMigrationIds,
        updatedAt: original.updatedAt,
        legacyMovementMetadata: <String, Map<String, Object?>>{
          ...original.legacyMovementMetadata,
          'keep-1': <String, Object?>{'id': 'keep-1', 'type': 'buy'},
        },
        legacyMovementMigrationMetadata: <String, Map<String, Object?>>{
          ...original.legacyMovementMigrationMetadata,
          'keep-1': <String, Object?>{
            'projectionWalletId': 'virtual:unassigned',
          },
        },
        legacyMigrationProblems: original.legacyMigrationProblems,
        legacyAccountingPolicy: original.legacyAccountingPolicy,
      );
      final repository = SharedPreferencesAccountingRepository();
      final bridge = LegacyPersistenceBridge(
        repository,
        const AccountingMigrator(adapter),
        adapter,
        RecordingLifecycleCoordinator(),
      );
      final repeated = adapter.toLegacyJson(
        current.movements.first,
        preservedFields: current.legacyMovementMetadata['old-1']!,
      );

      final saved = await bridge.saveLegacyView(
        current,
        <Map<String, Object?>>[repeated],
        deletedIds: const <String>{'old-1'},
      );

      expect(saved.movements.map((movement) => movement.id), <String>[
        'keep-1',
      ]);
      expect(saved.legacyMovementMetadata.containsKey('old-1'), isFalse);
      expect(
        saved.legacyMovementMigrationMetadata.containsKey('old-1'),
        isFalse,
      );
      expect(
        saved.legacyMovementMetadata['keep-1'],
        current.legacyMovementMetadata['keep-1'],
      );
      expect(
        saved.legacyMovementMigrationMetadata['keep-1'],
        current.legacyMovementMigrationMetadata['keep-1'],
      );
    },
  );

  test(
    'deleteLegacyIds persists removal without requiring the deleted legacy row',
    () async {
      final current = assignedDocumentFixture();
      final repository = SharedPreferencesAccountingRepository();
      final bridge = LegacyPersistenceBridge(
        repository,
        const AccountingMigrator(adapter),
        adapter,
        RecordingLifecycleCoordinator(),
      );

      final saved = await bridge.deleteLegacyIds(current, const <String>{
        'old-1',
      });

      expect(saved.movements, isEmpty);
      expect(saved.legacyMovementMetadata.containsKey('old-1'), isFalse);
      expect(
        saved.legacyMovementMigrationMetadata.containsKey('old-1'),
        isFalse,
      );
      expect((await repository.read())!.toJson(), saved.toJson());
    },
  );

  test('clearCanonicalDocument removes authoritative v3 state', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final current = assignedDocumentFixture();
    final repository = SharedPreferencesAccountingRepository();
    await repository.write(current);
    final bridge = LegacyPersistenceBridge(
      repository,
      const AccountingMigrator(adapter),
      adapter,
      RecordingLifecycleCoordinator(),
    );

    await bridge.clearCanonicalDocument();

    expect(await repository.read(), isNull);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey(accountingDocumentKey), isFalse);
  });

  test(
    'load keeps persisted v3 authoritative over conflicting legacy source',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final current = assignedDocumentFixture();
      final repository = SharedPreferencesAccountingRepository();
      await repository.write(current);
      final bridge = LegacyPersistenceBridge(
        repository,
        const AccountingMigrator(adapter),
        adapter,
        RecordingLifecycleCoordinator(),
      );

      final loaded = await bridge.load(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'old-1',
          'type': 'sell',
          'coin': 'ETH',
          'date': '2026-08-13T12:00:00Z',
          'quantity': '99',
          'unitPrice': '1',
          'fee': '0',
          'note': 'conflicting legacy source',
        },
      ]);

      expect(loaded.migrationReport, isNull);
      expect(loaded.document.toJson(), current.toJson());
      expect(loaded.legacyView.single['coin'], 'BTC');
      expect(
        loaded.legacyView.single['note'],
        isNot('conflicting legacy source'),
      );
    },
  );

  test(
    'load keeps unconvertible legacy rows in durable migration quarantine',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final repository = SharedPreferencesAccountingRepository();
      final bridge = LegacyPersistenceBridge(
        repository,
        const AccountingMigrator(adapter),
        adapter,
        RecordingLifecycleCoordinator(),
      );
      const broken = <String, Object?>{'id': 'broken', 'coin': 'BTC'};

      final loaded = await bridge.load(<Map<String, Object?>>[broken]);

      expect(loaded.document.movements, isEmpty);
      expect(loaded.migrationReport!.problems.single.primaryPayload, broken);
      expect(
        (await repository.read())!
            .legacyMigrationProblems
            .single
            .primaryPayload,
        broken,
      );
    },
  );

  test('load quarantines conflicting duplicate legacy IDs', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = SharedPreferencesAccountingRepository();
    final bridge = LegacyPersistenceBridge(
      repository,
      const AccountingMigrator(adapter),
      adapter,
      RecordingLifecycleCoordinator(),
    );
    const first = <String, Object?>{
      'id': 'same-id',
      'type': 'buy',
      'coin': 'BTC',
      'date': '2026-08-13T12:00:00Z',
      'quantity': '1',
      'unitPrice': '1',
      'fee': '0',
    };

    final loaded = await bridge.load(<Map<String, Object?>>[
      first,
      <String, Object?>{...first, 'quantity': '2'},
    ]);

    expect(loaded.document.movements, isEmpty);
    expect(
      loaded.migrationReport!.problems.single.kind,
      LegacyMigrationProblemKind.conflictingId,
    );
    expect(
      loaded.migrationReport!.problems.single.primaryPayload['quantity'],
      '2',
    );
  });

  test(
    'load recovers pending cleanup after persisted v3 is authoritative',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final repository = SharedPreferencesAccountingRepository();
      final current = assignedDocumentFixture();
      await repository.write(current);
      final lifecycle = RecordingLifecycleCoordinator();
      final bridge = LegacyPersistenceBridge(
        repository,
        const AccountingMigrator(adapter),
        adapter,
        lifecycle,
      );

      final loaded = await bridge.load(const <Map<String, Object?>>[]);

      expect(loaded.document.toJson(), current.toJson());
      expect(lifecycle.recoverCalls, 1);
    },
  );

  test(
    'load recovers pending cleanup after migrated v3 is persisted',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final repository = SharedPreferencesAccountingRepository();
      final lifecycle = RecordingLifecycleCoordinator();
      final bridge = LegacyPersistenceBridge(
        repository,
        const AccountingMigrator(adapter),
        adapter,
        lifecycle,
      );

      final loaded = await bridge.load(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'old-1',
          'type': 'buy',
          'coin': 'BTC',
          'date': '2026-08-11T12:00:00Z',
          'quantity': '1',
          'unitPrice': '1',
          'fee': '0',
        },
      ]);

      expect(loaded.migrationReport, isNotNull);
      expect((await repository.read())!.schemaVersion, accountingSchemaVersion);
      expect(lifecycle.recoverCalls, 1);
    },
  );
}

final class RecordingLifecycleCoordinator
    implements WalletLifecycleCoordinator {
  int recoverCalls = 0;

  @override
  Future<WalletDeleteCommitResult> commitDelete(
    PreparedWalletDeletion prepared,
  ) => throw UnimplementedError();

  @override
  Future<WalletImageCleanupResult> recoverPendingCleanup() async {
    recoverCalls += 1;
    return const WalletImageCleanupResult(
      deletedImageIds: <String>{},
      stillReferencedImageIds: <String>{},
      pendingRetryImageIds: <String>{},
    );
  }
}

AccountingDocument assignedDocumentFixture() {
  final updatedAt = DateTime.utc(2026, 8, 12);
  const walletId = '11111111-1111-4111-8111-111111111111';
  final wallet = Wallet.create(
    id: walletId,
    name: 'Bitso',
    provider: 'Bitso',
    createdAt: updatedAt,
    imageRef: WalletImageRef.create(
      id: 'a' * 64,
      fileName: 'bitso.png',
      mimeType: 'image/png',
      sha256: 'a' * 64,
      width: 40,
      height: 40,
      byteLength: 123,
    ),
  );
  return AccountingDocument(
    schemaVersion: accountingSchemaVersion,
    wallets: <Wallet>[wallet],
    movements: <AccountingMovement>[
      AccountingMovement(
        id: 'old-1',
        type: MovementType.buy,
        asset: 'BTC',
        occurredAt: DateTime.utc(2026, 8, 11, 12),
        quantity: AccountingAmount.parse('0.25'),
        unitPriceFiat: AccountingAmount.fromInt(1000000),
        fiatFeeAmount: AccountingAmount.fromInt(15),
        sourceWalletId: walletId,
        destinationWalletId: walletId,
        destinationType: DestinationType.ownWallet,
        walletAssignmentStatus: WalletAssignmentStatus.assigned,
        cryptoFeeAmount: AccountingAmount.zero,
        fiatFeeTreatment: FiatFeeTreatment.paidSeparately,
        adjustmentWalletId: walletId,
        adjustmentQuantity: AccountingAmount.parse('0.01'),
        reconciliationLinks: <ReconciliationLink>[
          ReconciliationLink(
            adjustmentMovementId: 'adjust-1',
            quantityResolved: AccountingAmount.parse('0.01'),
          ),
        ],
        createdAt: updatedAt,
        updatedAt: updatedAt,
      ),
    ],
    appliedMigrationIds: const <String>{legacyV1ToV3MigrationId},
    updatedAt: updatedAt,
    legacyMovementMetadata: <String, Map<String, Object?>>{
      'old-1': <String, Object?>{
        'id': 'old-1',
        'type': 'buy',
        'coin': 'BTC',
        'date': '2026-08-11T12:00:00Z',
        'quantity': '0.25',
        'unitPrice': '1000000',
        'fee': '15',
        'platform': 'Mercado Pago',
      },
    },
    legacyMovementMigrationMetadata: <String, Map<String, Object?>>{
      'old-1': <String, Object?>{'projectionWalletId': 'virtual:unassigned'},
    },
    legacyMigrationProblems: <LegacyMigrationProblem>[
      LegacyMigrationProblem.create(
        kind: LegacyMigrationProblemKind.unconvertible,
        sourceIndex: 1,
        primaryPayload: const <String, Object?>{'id': 'broken'},
      ),
    ],
    assignmentAudits: <AssignmentAudit>[
      AssignmentAudit(
        id: 'assignment-op:old-1',
        operationId: 'assignment-op',
        movementId: 'old-1',
        changedTargets: const <WalletAssignmentTarget>{
          WalletAssignmentTarget.destination,
        },
        before: const AssignmentStateSnapshot(
          sourceWalletId: null,
          destinationWalletId: null,
          adjustmentWalletId: null,
          destinationType: null,
          status: WalletAssignmentStatus.legacyUnassigned,
        ),
        after: AssignmentStateSnapshot(
          sourceWalletId: null,
          destinationWalletId: walletId,
          adjustmentWalletId: null,
          destinationType: DestinationType.ownWallet,
          status: WalletAssignmentStatus.assigned,
        ),
        assignedAt: updatedAt,
      ),
    ],
  );
}
