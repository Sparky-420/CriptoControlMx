import 'package:cripto_control_mx/accounting/application/movement_assignment_command.dart';
import 'package:cripto_control_mx/accounting/application/movement_assignment_service.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_movement.dart';
import 'package:cripto_control_mx/accounting/domain/assignment_audit.dart';
import 'package:cripto_control_mx/accounting/domain/movement_normalizer.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/migration/accounting_migrator.dart';
import 'package:cripto_control_mx/accounting/adapters/legacy_movement_adapter.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_document.dart';
import 'package:cripto_control_mx/accounting/projection/accounting_ledger_engine.dart';
import 'package:cripto_control_mx/accounting/projection/custody_projector.dart';
import 'package:cripto_control_mx/accounting/projection/performance_projector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = DefaultMovementAssignmentService();

  test('assignOne replaces the event without duplicating custody', () {
    final before = legacyDocumentFixture();
    final result = service.assignOne(
      before,
      command: const AssignDestinationWallet(
        'old-1',
        '11111111-1111-4111-8111-111111111111',
      ),
      operationId: 'assignment-op-1',
      assignedAt: DateTime.utc(2026, 8, 11),
    );

    expect(result.document.movements, hasLength(before.movements.length));
    expect(result.document.movements.single.id, 'old-1');
    expect(
      result.document.movements.single.quantity,
      before.movements.single.quantity,
    );
    expect(
      result.document.movements.single.destinationWalletId,
      '11111111-1111-4111-8111-111111111111',
    );
    expect(result.document.movements.single.sourceWalletId, isNull);
    expect(
      result.document.movements.single.walletAssignmentStatus,
      WalletAssignmentStatus.assigned,
    );
    expect(result.document.assignmentAudits, hasLength(1));
    expect(result.document.assignmentAudits.single.id, 'assignment-op-1:old-1');
    expect(
      result.document.assignmentAudits.single.before.sourceWalletId,
      isNull,
    );
    expect(
      result.document.assignmentAudits.single.before.destinationWalletId,
      isNull,
    );
    expect(
      result.document.assignmentAudits.single.after.destinationWalletId,
      '11111111-1111-4111-8111-111111111111',
    );
    expect(project(result.document).totalCustody, project(before).totalCustody);
  });

  test('assigning transfer sides ignores legacy platform text', () {
    final before = transferDocumentFixture();
    final sourceOnly = service.assignOne(
      before,
      command: const AssignSourceWallet('transfer-1', walletOneId),
      operationId: 'source-op',
      assignedAt: DateTime.utc(2026, 8, 11),
    );
    expect(
      sourceOnly.document.movements.single.walletAssignmentStatus,
      WalletAssignmentStatus.partiallyAssigned,
    );
    final owned = service.assignOne(
      sourceOnly.document,
      command: const AssignOwnTransferDestination('transfer-1', walletTwoId),
      operationId: 'owned-op',
      assignedAt: DateTime.utc(2026, 8, 12),
    );
    expect(
      owned.document.movements.single.walletAssignmentStatus,
      WalletAssignmentStatus.assigned,
    );
    expect(
      owned.document.movements.single.destinationType,
      DestinationType.ownWallet,
    );
    expect(owned.document.movements.single.destinationWalletId, walletTwoId);
    final external = service.assignOne(
      sourceOnly.document,
      command: const ClassifyExternalTransferDestination('transfer-1'),
      operationId: 'external-op',
      assignedAt: DateTime.utc(2026, 8, 12),
    );
    expect(
      external.document.movements.single.walletAssignmentStatus,
      WalletAssignmentStatus.assigned,
    );
    expect(
      external.document.movements.single.destinationType,
      DestinationType.external,
    );
    expect(external.document.movements.single.destinationWalletId, isNull);
  });

  test('assigns legacy transferIn destination without destination type', () {
    final before = _documentFromLegacy(<Map<String, Object?>>[
      <String, Object?>{
        'id': 'incoming-1',
        'type': 'transfer_in',
        'coin': 'UNI',
        'date': '2026-08-11T12:00:00Z',
        'quantity': '3',
        'unitPrice': '80',
        'fee': '0',
      },
    ]);

    expect(
      () => service.assignOne(
        before,
        command: const AssignSourceWallet('incoming-1', walletOneId),
        operationId: 'incoming-wrong-side-op',
        assignedAt: DateTime.utc(2026, 8, 15),
      ),
      throwsArgumentError,
    );

    final result = service.assignOne(
      before,
      command: const AssignDestinationWallet('incoming-1', walletOneId),
      operationId: 'incoming-destination-op',
      assignedAt: DateTime.utc(2026, 8, 15),
    );

    final movement = result.document.movements.single;
    expect(result.changedIds, <String>['incoming-1']);
    expect(movement.destinationWalletId, walletOneId);
    expect(movement.destinationType, isNull);
    expect(movement.walletAssignmentStatus, WalletAssignmentStatus.assigned);
    expect(
      result.document.assignmentAudits.single.after.destinationType,
      isNull,
    );
  });

  test('assignMany is atomic and records one audit per changed movement', () {
    final before = twoTransferDocumentFixture();
    final beforeJson = before.toJson();
    final result = service.assignMany(
      before,
      commands: const <MovementAssignmentCommand>[
        AssignSourceWallet('transfer-1', walletOneId),
        AssignOwnTransferDestination('transfer-1', walletTwoId),
        AssignSourceWallet('transfer-2', walletTwoId),
        ClassifyExternalTransferDestination('transfer-2'),
      ],
      operationId: 'batch-op',
      assignedAt: DateTime.utc(2026, 8, 13),
    );
    expect(result.changedIds, <String>['transfer-1', 'transfer-2']);
    expect(result.document.movements.map((movement) => movement.id), <String>[
      'transfer-1',
      'transfer-2',
    ]);
    expect(result.document.movements, hasLength(2));
    expect(result.document.assignmentAudits, hasLength(2));
    expect(
      result.document.assignmentAudits.map((audit) => audit.operationId),
      everyElement('batch-op'),
    );

    expect(
      () => service.assignMany(
        before,
        commands: const <MovementAssignmentCommand>[
          AssignSourceWallet('transfer-1', walletOneId),
          AssignOwnTransferDestination('transfer-1', walletOneId),
        ],
        operationId: 'bad-batch',
        assignedAt: DateTime.utc(2026, 8, 13),
      ),
      throwsArgumentError,
    );
    expect(before.toJson(), beforeJson);
  });

  test('identical assignment is idempotent and reassignment is audited', () {
    final first = service.assignOne(
      transferDocumentFixture(),
      command: const AssignSourceWallet('transfer-1', walletOneId),
      operationId: 'first-op',
      assignedAt: DateTime.utc(2026, 8, 11),
    );
    final repeat = service.assignOne(
      first.document,
      command: const AssignSourceWallet('transfer-1', walletOneId),
      operationId: 'repeat-op',
      assignedAt: DateTime.utc(2026, 8, 12),
    );
    expect(repeat.changedIds, isEmpty);
    expect(repeat.document.toJson(), first.document.toJson());

    final owned = service.assignOne(
      first.document,
      command: const AssignOwnTransferDestination('transfer-1', walletTwoId),
      operationId: 'owned-op',
      assignedAt: DateTime.utc(2026, 8, 12),
    );
    final external = service.assignOne(
      owned.document,
      command: const ClassifyExternalTransferDestination('transfer-1'),
      operationId: 'external-op',
      assignedAt: DateTime.utc(2026, 8, 13),
    );
    final audit = external.document.assignmentAudits.last;
    expect(audit.changedTargets, <WalletAssignmentTarget>{
      WalletAssignmentTarget.destination,
    });
    expect(audit.before.destinationWalletId, walletTwoId);
    expect(audit.after.destinationWalletId, isNull);
    expect(audit.after.destinationType, DestinationType.external);
  });

  test(
    'own transfer without its destination wallet stays partially assigned',
    () {
      final base = transferDocumentFixture();
      final malformed = _replaceMovement(
        base,
        base.movements.single.copyWith(
          sourceWalletId: walletOneId,
          destinationWalletId: null,
          destinationType: DestinationType.ownWallet,
          walletAssignmentStatus: WalletAssignmentStatus.partiallyAssigned,
        ),
      );

      final result = service.assignOne(
        malformed,
        command: const AssignSourceWallet('transfer-1', walletOneId),
        operationId: 'confirm-source-op',
        assignedAt: DateTime.utc(2026, 8, 14),
      );

      expect(
        result.document.movements.single.walletAssignmentStatus,
        WalletAssignmentStatus.partiallyAssigned,
      );
    },
  );

  test('identical command preserves a pending draft without an audit', () {
    final base = legacyDocumentFixture();
    final pending = _replaceMovement(
      base,
      base.movements.single.copyWith(
        destinationWalletId: walletOneId,
        walletAssignmentStatus: WalletAssignmentStatus.pending,
      ),
    );

    final result = service.assignOne(
      pending,
      command: const AssignDestinationWallet('old-1', walletOneId),
      operationId: 'pending-repeat-op',
      assignedAt: DateTime.utc(2026, 8, 14),
    );

    expect(result.changedIds, isEmpty);
    expect(result.unchangedIds, <String>['old-1']);
    expect(result.document.toJson(), pending.toJson());
  });

  test('wrong-side command rejects without changing the complete document', () {
    final before = transferDocumentFixture();

    expect(
      () => service.assignOne(
        before,
        command: const AssignDestinationWallet('transfer-1', walletOneId),
        operationId: 'wrong-side-op',
        assignedAt: DateTime.utc(2026, 8, 14),
      ),
      throwsArgumentError,
    );
    expect(before.toJson(), transferDocumentFixture().toJson());
  });

  test('archived and virtual wallets cannot be assigned', () {
    final before = legacyDocumentFixture();
    final archived = Wallet(
      id: walletOneId,
      name: 'Mercado Pago',
      provider: 'Mercado Pago',
      status: WalletStatus.archived,
      createdAt: DateTime.utc(2026, 8, 11),
      updatedAt: DateTime.utc(2026, 8, 11),
    );
    final archivedDocument = _withWallets(before, <Wallet>[archived]);
    final virtualDocument = _withWallets(before, <Wallet>[
      Wallet(
        id: 'virtual:unassigned',
        name: 'Unassigned',
        provider: 'system',
        status: WalletStatus.active,
        createdAt: DateTime.utc(2026, 8, 11),
        updatedAt: DateTime.utc(2026, 8, 11),
      ),
    ]);

    expect(
      () => service.assignOne(
        archivedDocument,
        command: const AssignDestinationWallet('old-1', walletOneId),
        operationId: 'archived-op',
        assignedAt: DateTime.utc(2026, 8, 14),
      ),
      throwsArgumentError,
    );
    expect(
      () => service.assignOne(
        virtualDocument,
        command: const AssignDestinationWallet('old-1', 'virtual:unassigned'),
        operationId: 'virtual-op',
        assignedAt: DateTime.utc(2026, 8, 14),
      ),
      throwsArgumentError,
    );
  });

  test('audit JSON sorts changed targets by enum name', () {
    final audit = AssignmentAudit(
      id: 'op:movement',
      operationId: 'op',
      movementId: 'movement',
      changedTargets: const <WalletAssignmentTarget>{
        WalletAssignmentTarget.source,
        WalletAssignmentTarget.adjustment,
        WalletAssignmentTarget.destination,
      },
      before: const AssignmentStateSnapshot(
        sourceWalletId: null,
        destinationWalletId: null,
        adjustmentWalletId: null,
        destinationType: null,
        status: WalletAssignmentStatus.legacyUnassigned,
      ),
      after: const AssignmentStateSnapshot(
        sourceWalletId: null,
        destinationWalletId: null,
        adjustmentWalletId: null,
        destinationType: null,
        status: WalletAssignmentStatus.legacyUnassigned,
      ),
      assignedAt: DateTime.utc(2026, 8, 14),
    );

    expect(audit.toJson()['changedTargets'], <String>[
      'adjustment',
      'destination',
      'source',
    ]);
  });

  test('document JSON without assignmentAudits defaults to an empty list', () {
    final json = legacyDocumentFixture().toJson()..remove('assignmentAudits');

    expect(AccountingDocument.fromJson(json).assignmentAudits, isEmpty);
  });
}

const walletOneId = '11111111-1111-4111-8111-111111111111';
const walletTwoId = '22222222-2222-4222-8222-222222222222';

AccountingDocument legacyDocumentFixture() {
  final migrated = const AccountingMigrator(LegacyMovementAdapter())
      .migrateLegacy(
        legacy: <Map<String, Object?>>[
          <String, Object?>{
            'id': 'old-1',
            'type': 'buy',
            'coin': 'BTC',
            'date': '2026-08-11T12:00:00Z',
            'quantity': '0.25',
            'unitPrice': '1000000',
            'fee': '15',
            'platform': 'Mercado Pago',
          },
        ],
      )
      .document;
  return AccountingDocument(
    schemaVersion: accountingSchemaVersion,
    wallets: <Wallet>[
      Wallet.create(
        id: walletOneId,
        name: 'Mercado Pago',
        provider: 'Mercado Pago',
        createdAt: DateTime.utc(2026, 8, 11),
      ),
    ],
    movements: migrated.movements,
    appliedMigrationIds: migrated.appliedMigrationIds,
    updatedAt: migrated.updatedAt,
    legacyMovementMetadata: migrated.legacyMovementMetadata,
    legacyMovementMigrationMetadata: migrated.legacyMovementMigrationMetadata,
    legacyMigrationProblems: migrated.legacyMigrationProblems,
    legacyAccountingPolicy: migrated.legacyAccountingPolicy,
  );
}

AccountingDocument transferDocumentFixture() =>
    _documentFromLegacy(<Map<String, Object?>>[
      <String, Object?>{
        'id': 'transfer-1',
        'type': 'transfer_out',
        'coin': 'BTC',
        'date': '2026-08-11T12:00:00Z',
        'quantity': '1',
        'fee': '0',
        'sourcePlatform': 'Mercado Pago',
        'destinationPlatform': 'Bitso',
      },
    ]);

AccountingDocument twoTransferDocumentFixture() =>
    _documentFromLegacy(<Map<String, Object?>>[
      <String, Object?>{
        'id': 'transfer-1',
        'type': 'transfer_out',
        'coin': 'BTC',
        'date': '2026-08-11T12:00:00Z',
        'quantity': '1',
        'fee': '0',
      },
      <String, Object?>{
        'id': 'transfer-2',
        'type': 'transfer_out',
        'coin': 'ETH',
        'date': '2026-08-12T12:00:00Z',
        'quantity': '2',
        'fee': '0',
      },
    ]);

AccountingDocument _documentFromLegacy(List<Map<String, Object?>> source) {
  final migrated = const AccountingMigrator(
    LegacyMovementAdapter(),
  ).migrateLegacy(legacy: source).document;
  return AccountingDocument(
    schemaVersion: accountingSchemaVersion,
    wallets: <Wallet>[
      Wallet.create(
        id: walletOneId,
        name: 'Mercado Pago',
        provider: 'Mercado Pago',
        createdAt: DateTime.utc(2026, 8, 11),
      ),
      Wallet.create(
        id: walletTwoId,
        name: 'Bitso',
        provider: 'Bitso',
        createdAt: DateTime.utc(2026, 8, 11),
      ),
    ],
    movements: migrated.movements,
    appliedMigrationIds: migrated.appliedMigrationIds,
    updatedAt: migrated.updatedAt,
    legacyMovementMetadata: migrated.legacyMovementMetadata,
    legacyMovementMigrationMetadata: migrated.legacyMovementMigrationMetadata,
    legacyMigrationProblems: migrated.legacyMigrationProblems,
    legacyAccountingPolicy: migrated.legacyAccountingPolicy,
  );
}

AccountingDocument _replaceMovement(
  AccountingDocument document,
  AccountingMovement replacement,
) => AccountingDocument(
  schemaVersion: document.schemaVersion,
  wallets: document.wallets,
  movements: [replacement],
  appliedMigrationIds: document.appliedMigrationIds,
  updatedAt: document.updatedAt,
  legacyMovementMetadata: document.legacyMovementMetadata,
  legacyMovementMigrationMetadata: document.legacyMovementMigrationMetadata,
  legacyMigrationProblems: document.legacyMigrationProblems,
  assignmentAudits: document.assignmentAudits,
  legacyAccountingPolicy: document.legacyAccountingPolicy,
);

AccountingDocument _withWallets(
  AccountingDocument document,
  List<Wallet> wallets,
) => AccountingDocument(
  schemaVersion: document.schemaVersion,
  wallets: wallets,
  movements: document.movements,
  appliedMigrationIds: document.appliedMigrationIds,
  updatedAt: document.updatedAt,
  legacyMovementMetadata: document.legacyMovementMetadata,
  legacyMovementMigrationMetadata: document.legacyMovementMigrationMetadata,
  legacyMigrationProblems: document.legacyMigrationProblems,
  assignmentAudits: document.assignmentAudits,
  legacyAccountingPolicy: document.legacyAccountingPolicy,
);

ProjectionSummary project(AccountingDocument document) {
  final projection =
      const AccountingLedgerEngine(
        DefaultMovementNormalizer(),
        DefaultCustodyProjector(),
        DefaultPerformanceProjector(),
      ).project(
        LedgerInput(
          wallets: document.wallets,
          movements: document.movements,
          currentPrices: const <String, AccountingAmount>{},
          saleCostConsumptionPolicy: SaleCostConsumptionPolicy.knownFirst,
          transferCostAllocationPolicy:
              TransferCostAllocationPolicy.proportional,
          legacyAccountingPolicy: document.legacyAccountingPolicy,
        ),
      );
  return ProjectionSummary(
    projection.effects.values.fold(
      AccountingAmount.zero,
      (total, effect) =>
          total + (effect.globalDeltasByAsset['BTC'] ?? AccountingAmount.zero),
    ),
  );
}

final class ProjectionSummary {
  const ProjectionSummary(this.totalCustody);

  final AccountingAmount totalCustody;
}
