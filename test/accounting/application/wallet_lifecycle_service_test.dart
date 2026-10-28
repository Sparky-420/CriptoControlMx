import 'dart:convert';
import 'dart:typed_data';

import 'package:cripto_control_mx/accounting/application/wallet_lifecycle_coordinator.dart';
import 'package:cripto_control_mx/accounting/application/wallet_lifecycle_service.dart';
import 'package:cripto_control_mx/accounting/application/wallet_image_cleanup_journal.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_movement.dart';
import 'package:cripto_control_mx/accounting/domain/movement_type.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_document.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_repository.dart';
import 'package:cripto_control_mx/accounting/persistence/wallet_image_processor.dart';
import 'package:cripto_control_mx/accounting/persistence/wallet_image_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const service = DefaultWalletLifecycleService();
  final clock = DateTime.utc(2026, 8, 13, 12);

  test('wallet with movement history is archived, never deleted', () {
    final document = documentWithWalletHistory();
    const walletId = '11111111-1111-4111-8111-111111111111';

    final deletion = service.prepareDelete(document, walletId, clock);

    expect(deletion.decision, WalletDeletionDecision.blocked);
    expect(
      deletion.blockReasons,
      contains(WalletDeleteBlockReason.movementHistory),
    );
    expect(deletion.document.toJson(), document.toJson());
    final archived = service.prepareArchive(document, walletId, clock);
    expect(archived.decision, WalletDeletionDecision.archive);
    expect(archived.document.wallets.single.status, WalletStatus.archived);
    expect(archived.document.wallets.single.updatedAt, clock);
    expect(
      archived.document.wallets.single.imageRef?.toJson(),
      imageRef.toJson(),
    );
    expect(
      archived.document.movements.map((movement) => movement.toJson()),
      document.movements.map((movement) => movement.toJson()),
    );
    expect(archived.cleanupIntents, isEmpty);
    expect(
      archived.document.wallets.where(
        (wallet) => wallet.status == WalletStatus.active,
      ),
      isEmpty,
    );

    final restored = service.restore(
      archived.document,
      walletId,
      clock.add(const Duration(hours: 1)),
    );

    expect(restored.wallets.single.status, WalletStatus.active);
    expect(restored.wallets.single.id, document.wallets.single.id);
    expect(restored.wallets.single.imageRef?.toJson(), imageRef.toJson());
    expect(
      restored.movements.map((movement) => movement.toJson()),
      document.movements.map((movement) => movement.toJson()),
    );
  });

  test(
    'all canonical wallet references and reconciliation links block delete',
    () {
      const walletId = '11111111-1111-4111-8111-111111111111';
      final document = documentWithAllReferenceKinds();
      final before = jsonEncode(document.toJson());

      final deletion = service.prepareDelete(document, walletId, clock);

      expect(deletion.decision, WalletDeletionDecision.blocked);
      expect(deletion.cleanupIntents, isEmpty);
      expect(deletion.blockReasons, <WalletDeleteBlockReason>{
        WalletDeleteBlockReason.movementHistory,
        WalletDeleteBlockReason.reconciliationLink,
      });
      expect(jsonEncode(deletion.document.toJson()), before);
    },
  );

  test(
    'a referenced movement carrying reconciliation reports both blockers',
    () {
      const walletId = '11111111-1111-4111-8111-111111111111';
      final base = documentWithWalletHistory();
      final linked = base.movements.single.copyWith(
        reconciliationLinks: <ReconciliationLink>[
          ReconciliationLink(
            adjustmentMovementId: 'external-adjustment',
            quantityResolved: AccountingAmount.parse('0.01'),
          ),
        ],
      );
      final document = AccountingDocument(
        schemaVersion: base.schemaVersion,
        wallets: base.wallets,
        movements: <AccountingMovement>[linked],
        appliedMigrationIds: base.appliedMigrationIds,
        updatedAt: base.updatedAt,
      );

      final deletion = service.prepareDelete(document, walletId, clock);

      expect(deletion.blockReasons, <WalletDeleteBlockReason>{
        WalletDeleteBlockReason.movementHistory,
        WalletDeleteBlockReason.reconciliationLink,
      });
    },
  );

  test(
    'empty wallet deletion is pure and carries its exact image reference',
    () {
      const sourceId = '11111111-1111-4111-8111-111111111111';
      const retainedId = '22222222-2222-4222-8222-222222222222';
      final createdAt = DateTime.utc(2026, 8, 11);
      final retained = Wallet.create(
        id: retainedId,
        name: 'Retained',
        provider: 'Provider B',
        createdAt: createdAt,
      );
      final document = AccountingDocument(
        schemaVersion: accountingSchemaVersion,
        wallets: <Wallet>[
          Wallet.create(
            id: sourceId,
            name: 'Empty',
            provider: 'Provider A',
            createdAt: createdAt,
            imageRef: imageRef,
          ),
          retained,
        ],
        movements: const <AccountingMovement>[],
        appliedMigrationIds: const <String>{'migration-kept'},
        updatedAt: createdAt,
        legacyMovementMetadata: const <String, Map<String, Object?>>{
          'legacy': <String, Object?>{'preserved': true},
        },
      );

      final deletion = service.prepareDelete(document, sourceId, clock);

      expect(deletion.decision, WalletDeletionDecision.delete);
      expect(deletion.blockReasons, isEmpty);
      expect(deletion.document.wallets.map((wallet) => wallet.id), <String>[
        retainedId,
      ]);
      expect(deletion.document.wallets.single.toJson(), retained.toJson());
      expect(deletion.document.movements, same(document.movements));
      expect(
        deletion.document.appliedMigrationIds,
        document.appliedMigrationIds,
      );
      expect(
        deletion.document.legacyMovementMetadata,
        document.legacyMovementMetadata,
      );
      expect(deletion.document.updatedAt, clock);
      expect(deletion.cleanupIntents, hasLength(1));
      final intent = deletion.cleanupIntents.single;
      expect(intent.id, 'delete:$sourceId:${imageRef.id}');
      expect(intent.sourceWalletId, sourceId);
      expect(intent.imageRef, same(imageRef));
      expect(intent.createdAt, clock);
    },
  );

  test('empty wallet without an image produces no cleanup intent', () {
    const walletId = '11111111-1111-4111-8111-111111111111';
    final createdAt = DateTime.utc(2026, 8, 11);
    final document = AccountingDocument(
      schemaVersion: accountingSchemaVersion,
      wallets: <Wallet>[
        Wallet.create(
          id: walletId,
          name: 'Empty',
          provider: 'Provider',
          createdAt: createdAt,
        ),
      ],
      movements: const <AccountingMovement>[],
      appliedMigrationIds: const <String>{},
      updatedAt: createdAt,
    );

    final deletion = service.prepareDelete(document, walletId, clock);

    expect(deletion.decision, WalletDeletionDecision.delete);
    expect(deletion.document.wallets, isEmpty);
    expect(deletion.cleanupIntents, isEmpty);
  });

  test('virtual and unknown wallet ids are rejected', () {
    final document = documentWithWalletHistory();

    expect(
      () => service.prepareArchive(document, 'virtual:unassigned', clock),
      throwsArgumentError,
    );
    expect(
      () => service.restore(
        document,
        '22222222-2222-4222-8222-222222222222',
        clock,
      ),
      throwsArgumentError,
    );
    expect(
      () => service.prepareDelete(document, 'virtual:unknown', clock),
      throwsArgumentError,
    );
  });

  test('reassign and delete replaces every wallet side before removal', () {
    const sourceId = '11111111-1111-4111-8111-111111111111';
    const targetId = '22222222-2222-4222-8222-222222222222';
    final document = reassignableDocument();

    final prepared = service.prepareReassignAndDelete(
      document,
      sourceWalletId: sourceId,
      targetWalletId: targetId,
      updatedAt: clock,
    );

    expect(prepared.decision, WalletDeletionDecision.delete);
    expect(prepared.blockReasons, isEmpty);
    expect(prepared.document.wallets.map((wallet) => wallet.id), <String>[
      targetId,
    ]);
    expect(prepared.document.movements.map((movement) => movement.id), <String>[
      'source-1',
      'destination-1',
      'adjustment-1',
    ]);
    for (final movement in prepared.document.movements) {
      expect(movement.sourceWalletId, isNot(sourceId));
      expect(movement.destinationWalletId, isNot(sourceId));
      expect(movement.adjustmentWalletId, isNot(sourceId));
      expect(movement.updatedAt, clock);
    }
    expect(prepared.document.movements[0].sourceWalletId, targetId);
    expect(prepared.document.movements[1].destinationWalletId, targetId);
    expect(prepared.document.movements[2].adjustmentWalletId, targetId);
    expect(prepared.document.updatedAt, clock);
    expect(
      prepared.document.legacyMovementMetadata,
      document.legacyMovementMetadata,
    );
    expect(prepared.cleanupIntents.single.imageRef, same(imageRef));
    expect(
      prepared.cleanupIntents.single.id,
      'delete:$sourceId:${imageRef.id}',
    );
  });

  test(
    'reassign rejects an internal transfer that would become same-wallet',
    () {
      const sourceId = '11111111-1111-4111-8111-111111111111';
      const targetId = '22222222-2222-4222-8222-222222222222';
      final document = reassignableDocument(
        movements: <AccountingMovement>[
          movementFixture(
            id: 'transfer-1',
            type: MovementType.transferOut,
            sourceWalletId: sourceId,
            destinationWalletId: targetId,
          ),
        ],
      );

      expect(
        () => service.prepareReassignAndDelete(
          document,
          sourceWalletId: sourceId,
          targetWalletId: targetId,
          updatedAt: clock,
        ),
        throwsArgumentError,
      );
    },
  );

  test('reassign rejects an archived target wallet', () {
    const sourceId = '11111111-1111-4111-8111-111111111111';
    const targetId = '22222222-2222-4222-8222-222222222222';
    final document = documentWithArchivedTarget();

    expect(
      () => service.prepareReassignAndDelete(
        document,
        sourceWalletId: sourceId,
        targetWalletId: targetId,
        updatedAt: clock,
      ),
      throwsArgumentError,
    );
  });

  test(
    'cleanup journal deduplicates ids and repeated replace is byte-equivalent',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final journal = SharedPreferencesWalletImageCleanupJournal(preferences);
      final intent = WalletImageCleanupIntent(
        id: 'delete:wallet:${imageRef.id}',
        sourceWalletId: '11111111-1111-4111-8111-111111111111',
        imageRef: imageRef,
        createdAt: clock,
      );

      await journal.replaceAll(<WalletImageCleanupIntent>[intent, intent]);
      final firstBytes = preferences.getString(walletImageCleanupJournalKey);
      final recovered = await journal.readAll();
      await journal.replaceAll(recovered);

      expect(recovered, hasLength(1));
      expect(recovered.single.id, intent.id);
      expect(recovered.single.imageRef.toJson(), imageRef.toJson());
      expect(preferences.getString(walletImageCleanupJournalKey), firstBytes);
      expect(preferences.containsKey(accountingDocumentKey), isFalse);
    },
  );

  test(
    'cleanup journal rejects an image path instead of a safe basename',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        walletImageCleanupJournalKey: jsonEncode(<Object?>[
          <String, Object?>{
            'id': 'delete:wallet:${imageRef.id}',
            'sourceWalletId': '11111111-1111-4111-8111-111111111111',
            'imageRef': <String, Object?>{
              ...imageRef.toJson(),
              'fileName': '../private/${imageRef.fileName}',
            },
            'createdAt': clock.toIso8601String(),
          },
        ]),
      });
      final preferences = await SharedPreferences.getInstance();
      final journal = SharedPreferencesWalletImageCleanupJournal(preferences);

      expect(journal.readAll(), throwsArgumentError);
    },
  );

  group('ordered deletion commit and recovery', () {
    test('blocked preparation performs no writes or image calls', () async {
      final events = <String>[];
      final document = documentWithWalletHistory();
      final repository = FakeRepository(document, events);
      final journal = FakeJournal(events);
      final images = FakeImageStore(events);
      final coordinator = DefaultWalletLifecycleCoordinator(
        repository,
        images,
        journal,
      );
      final prepared = service.prepareDelete(
        document,
        '11111111-1111-4111-8111-111111111111',
        clock,
      );

      final result = await coordinator.commitDelete(prepared);

      expect(result.status, WalletDeleteCommitStatus.blocked);
      expect(result.document.toJson(), document.toJson());
      expect(events, isEmpty);
    });

    test('archive writes only the archive document', () async {
      final events = <String>[];
      final document = documentWithWalletHistory();
      final repository = FakeRepository(document, events);
      final journal = FakeJournal(events);
      final images = FakeImageStore(events);
      final coordinator = DefaultWalletLifecycleCoordinator(
        repository,
        images,
        journal,
      );
      final prepared = service.prepareArchive(
        document,
        '11111111-1111-4111-8111-111111111111',
        clock,
      );

      final result = await coordinator.commitDelete(prepared);

      expect(result.status, WalletDeleteCommitStatus.archived);
      expect(repository.document!.wallets.single.status, WalletStatus.archived);
      expect(events, <String>['repository.write']);
    });

    test(
      'delete commits journal then v3 document then re-reads before deleting',
      () async {
        final events = <String>[];
        final document = emptyWalletDocument();
        final repository = FakeRepository(document, events);
        final journal = FakeJournal(events);
        final images = FakeImageStore(events);
        final coordinator = DefaultWalletLifecycleCoordinator(
          repository,
          images,
          journal,
        );
        final prepared = service.prepareDelete(
          document,
          '11111111-1111-4111-8111-111111111111',
          clock,
        );

        final result = await coordinator.commitDelete(prepared);

        expect(result.status, WalletDeleteCommitStatus.committed);
        expect(result.cleanup.deletedImageIds, <String>{imageRef.id});
        expect(journal.intents, isEmpty);
        expect(images.lastReferencedImageIds, isEmpty);
        expect(events, <String>[
          'journal.read',
          'journal.replace',
          'repository.write',
          'repository.read',
          'image.delete',
          'journal.replace',
        ]);
      },
    );

    test(
      'journal failure prevents document commit and image deletion',
      () async {
        final events = <String>[];
        final document = emptyWalletDocument();
        final repository = FakeRepository(document, events);
        final journal = FakeJournal(events)..failNextReplace = true;
        final images = FakeImageStore(events);
        final coordinator = DefaultWalletLifecycleCoordinator(
          repository,
          images,
          journal,
        );
        final prepared = service.prepareDelete(
          document,
          '11111111-1111-4111-8111-111111111111',
          clock,
        );

        await expectLater(coordinator.commitDelete(prepared), throwsStateError);

        expect(repository.document!.wallets, isNotEmpty);
        expect(images.deleteCalls, 0);
        expect(events, <String>['journal.read', 'journal.replace']);
      },
    );

    test(
      'repository failure retains journal intent and performs zero deletes',
      () async {
        final events = <String>[];
        final document = emptyWalletDocument();
        final repository = FakeRepository(document, events)..failWrite = true;
        final journal = FakeJournal(events);
        final images = FakeImageStore(events);
        final coordinator = DefaultWalletLifecycleCoordinator(
          repository,
          images,
          journal,
        );
        final prepared = service.prepareDelete(
          document,
          '11111111-1111-4111-8111-111111111111',
          clock,
        );

        await expectLater(coordinator.commitDelete(prepared), throwsStateError);

        expect(journal.intents, hasLength(1));
        expect(images.deleteCalls, 0);
        expect(events, <String>[
          'journal.read',
          'journal.replace',
          'repository.write',
        ]);
      },
    );

    test(
      'physical failure stays pending and a recovery retry clears it',
      () async {
        final events = <String>[];
        final document = emptyWalletDocument();
        final repository = FakeRepository(document, events);
        final journal = FakeJournal(events);
        final images = FakeImageStore(events)..failDelete = true;
        final coordinator = DefaultWalletLifecycleCoordinator(
          repository,
          images,
          journal,
        );
        final prepared = service.prepareDelete(
          document,
          '11111111-1111-4111-8111-111111111111',
          clock,
        );

        final failed = await coordinator.commitDelete(prepared);
        images.failDelete = false;
        final retried = await coordinator.recoverPendingCleanup();
        final repeated = await coordinator.recoverPendingCleanup();

        expect(
          failed.status,
          WalletDeleteCommitStatus.committedWithPendingCleanup,
        );
        expect(failed.cleanup.pendingRetryImageIds, <String>{imageRef.id});
        expect(retried.deletedImageIds, <String>{imageRef.id});
        expect(retried.pendingRetryImageIds, isEmpty);
        expect(repeated.deletedImageIds, isEmpty);
        expect(images.deleteCalls, 2);
        expect(journal.intents, isEmpty);
      },
    );

    test(
      'recovery before document commit sees reference and never deletes image',
      () async {
        final events = <String>[];
        final document = emptyWalletDocument();
        final prepared = service.prepareDelete(
          document,
          '11111111-1111-4111-8111-111111111111',
          clock,
        );
        final repository = FakeRepository(document, events);
        final journal = FakeJournal(events)
          ..intents = <WalletImageCleanupIntent>[...prepared.cleanupIntents];
        final images = FakeImageStore(events);
        final coordinator = DefaultWalletLifecycleCoordinator(
          repository,
          images,
          journal,
        );

        final result = await coordinator.recoverPendingCleanup();

        expect(result.stillReferencedImageIds, <String>{imageRef.id});
        expect(images.deleteCalls, 0);
        expect(journal.intents, isEmpty);
      },
    );

    test(
      'recovery after document commit deletes an unreferenced image',
      () async {
        final events = <String>[];
        final document = emptyWalletDocument();
        final prepared = service.prepareDelete(
          document,
          '11111111-1111-4111-8111-111111111111',
          clock,
        );
        final repository = FakeRepository(prepared.document, events);
        final journal = FakeJournal(events)
          ..intents = <WalletImageCleanupIntent>[...prepared.cleanupIntents];
        final images = FakeImageStore(events);
        final coordinator = DefaultWalletLifecycleCoordinator(
          repository,
          images,
          journal,
        );

        final result = await coordinator.recoverPendingCleanup();

        expect(result.deletedImageIds, <String>{imageRef.id});
        expect(images.deleteCalls, 1);
        expect(journal.intents, isEmpty);
      },
    );

    test(
      'shared image remains physical and its stale intent is removed',
      () async {
        final events = <String>[];
        final document = emptyWalletDocument(sharedImage: true);
        final repository = FakeRepository(document, events);
        final journal = FakeJournal(events);
        final images = FakeImageStore(events);
        final coordinator = DefaultWalletLifecycleCoordinator(
          repository,
          images,
          journal,
        );
        final prepared = service.prepareDelete(
          document,
          '11111111-1111-4111-8111-111111111111',
          clock,
        );

        final result = await coordinator.commitDelete(prepared);

        expect(result.status, WalletDeleteCommitStatus.committed);
        expect(result.cleanup.stillReferencedImageIds, <String>{imageRef.id});
        expect(images.deleteCalls, 0);
        expect(journal.intents, isEmpty);
      },
    );
  });
}

final WalletImageRef imageRef = WalletImageRef.create(
  id: 'a' * 64,
  fileName: '${'a' * 64}.png',
  mimeType: 'image/png',
  sha256: 'a' * 64,
  width: 40,
  height: 40,
  byteLength: 123,
);

AccountingDocument documentWithWalletHistory() {
  final createdAt = DateTime.utc(2026, 8, 11);
  const walletId = '11111111-1111-4111-8111-111111111111';
  return AccountingDocument(
    schemaVersion: accountingSchemaVersion,
    wallets: <Wallet>[
      Wallet.create(
        id: walletId,
        name: 'Bitso',
        provider: 'Bitso',
        createdAt: createdAt,
        imageRef: imageRef,
      ),
    ],
    movements: <AccountingMovement>[
      AccountingMovement(
        id: 'buy-1',
        type: MovementType.buy,
        asset: 'BTC',
        occurredAt: createdAt,
        quantity: AccountingAmount.parse('0.25'),
        unitPriceFiat: AccountingAmount.fromInt(1000000),
        fiatFeeAmount: AccountingAmount.zero,
        destinationWalletId: walletId,
        destinationType: DestinationType.ownWallet,
        walletAssignmentStatus: WalletAssignmentStatus.assigned,
        cryptoFeeAmount: AccountingAmount.zero,
        fiatFeeTreatment: FiatFeeTreatment.none,
        reconciliationLinks: const <ReconciliationLink>[],
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    ],
    appliedMigrationIds: const <String>{},
    updatedAt: createdAt,
  );
}

AccountingDocument documentWithAllReferenceKinds() {
  final base = documentWithWalletHistory();
  const walletId = '11111111-1111-4111-8111-111111111111';
  final createdAt = DateTime.utc(2026, 8, 11);
  AccountingMovement movement({
    required String id,
    required MovementType type,
    String? sourceWalletId,
    String? destinationWalletId,
    String? adjustmentWalletId,
    List<ReconciliationLink> links = const <ReconciliationLink>[],
  }) => AccountingMovement(
    id: id,
    type: type,
    asset: 'BTC',
    occurredAt: createdAt,
    quantity: AccountingAmount.fromInt(1),
    fiatFeeAmount: AccountingAmount.zero,
    sourceWalletId: sourceWalletId,
    destinationWalletId: destinationWalletId,
    destinationType: destinationWalletId == null
        ? null
        : DestinationType.ownWallet,
    walletAssignmentStatus: WalletAssignmentStatus.assigned,
    cryptoFeeAmount: AccountingAmount.zero,
    fiatFeeTreatment: FiatFeeTreatment.none,
    adjustmentWalletId: adjustmentWalletId,
    adjustmentQuantity: adjustmentWalletId == null
        ? null
        : AccountingAmount.fromInt(1),
    reconciliationLinks: links,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
  return AccountingDocument(
    schemaVersion: base.schemaVersion,
    wallets: base.wallets,
    movements: <AccountingMovement>[
      movement(
        id: 'source-1',
        type: MovementType.sell,
        sourceWalletId: walletId,
      ),
      movement(
        id: 'destination-1',
        type: MovementType.buy,
        destinationWalletId: walletId,
      ),
      movement(
        id: 'adjustment-1',
        type: MovementType.balanceAdjustment,
        adjustmentWalletId: walletId,
      ),
      movement(
        id: 'linked-1',
        type: MovementType.buy,
        links: <ReconciliationLink>[
          ReconciliationLink(
            adjustmentMovementId: 'adjustment-1',
            quantityResolved: AccountingAmount.fromInt(1),
          ),
        ],
      ),
    ],
    appliedMigrationIds: base.appliedMigrationIds,
    updatedAt: base.updatedAt,
  );
}

AccountingDocument emptyWalletDocument({bool sharedImage = false}) {
  final createdAt = DateTime.utc(2026, 8, 11);
  return AccountingDocument(
    schemaVersion: accountingSchemaVersion,
    wallets: <Wallet>[
      Wallet.create(
        id: '11111111-1111-4111-8111-111111111111',
        name: 'Delete me',
        provider: 'Provider A',
        createdAt: createdAt,
        imageRef: imageRef,
      ),
      if (sharedImage)
        Wallet.create(
          id: '22222222-2222-4222-8222-222222222222',
          name: 'Keep me',
          provider: 'Provider B',
          createdAt: createdAt,
          imageRef: imageRef,
        ),
    ],
    movements: const <AccountingMovement>[],
    appliedMigrationIds: const <String>{},
    updatedAt: createdAt,
  );
}

AccountingDocument reassignableDocument({List<AccountingMovement>? movements}) {
  final createdAt = DateTime.utc(2026, 8, 11);
  const sourceId = '11111111-1111-4111-8111-111111111111';
  return AccountingDocument(
    schemaVersion: accountingSchemaVersion,
    wallets: <Wallet>[
      Wallet.create(
        id: sourceId,
        name: 'Source',
        provider: 'Provider A',
        createdAt: createdAt,
        imageRef: imageRef,
      ),
      Wallet.create(
        id: '22222222-2222-4222-8222-222222222222',
        name: 'Target',
        provider: 'Provider B',
        createdAt: createdAt,
      ),
    ],
    movements:
        movements ??
        <AccountingMovement>[
          movementFixture(
            id: 'source-1',
            type: MovementType.sell,
            sourceWalletId: sourceId,
          ),
          movementFixture(
            id: 'destination-1',
            type: MovementType.buy,
            destinationWalletId: sourceId,
          ),
          movementFixture(
            id: 'adjustment-1',
            type: MovementType.balanceAdjustment,
            adjustmentWalletId: sourceId,
          ),
        ],
    appliedMigrationIds: const <String>{'kept'},
    updatedAt: createdAt,
    legacyMovementMetadata: const <String, Map<String, Object?>>{
      'source-1': <String, Object?>{'platform': 'preserved'},
    },
  );
}

AccountingDocument documentWithArchivedTarget() {
  final document = reassignableDocument();
  final archivedTarget = Wallet(
    id: '22222222-2222-4222-8222-222222222222',
    name: 'Target',
    provider: 'Provider B',
    status: WalletStatus.archived,
    createdAt: DateTime.utc(2026, 8, 11),
    updatedAt: DateTime.utc(2026, 8, 12),
  );
  return AccountingDocument(
    schemaVersion: document.schemaVersion,
    wallets: <Wallet>[document.wallets.first, archivedTarget],
    movements: document.movements,
    appliedMigrationIds: document.appliedMigrationIds,
    updatedAt: document.updatedAt,
    legacyMovementMetadata: document.legacyMovementMetadata,
    legacyMovementMigrationMetadata: document.legacyMovementMigrationMetadata,
    legacyMigrationProblems: document.legacyMigrationProblems,
    assignmentAudits: document.assignmentAudits,
    legacyAccountingPolicy: document.legacyAccountingPolicy,
  );
}

AccountingMovement movementFixture({
  required String id,
  required MovementType type,
  String? sourceWalletId,
  String? destinationWalletId,
  String? adjustmentWalletId,
}) {
  final createdAt = DateTime.utc(2026, 8, 11);
  return AccountingMovement(
    id: id,
    type: type,
    asset: 'BTC',
    occurredAt: createdAt,
    quantity: AccountingAmount.fromInt(1),
    fiatFeeAmount: AccountingAmount.zero,
    sourceWalletId: sourceWalletId,
    destinationWalletId: destinationWalletId,
    destinationType: destinationWalletId == null
        ? null
        : DestinationType.ownWallet,
    walletAssignmentStatus: WalletAssignmentStatus.assigned,
    cryptoFeeAmount: AccountingAmount.zero,
    fiatFeeTreatment: FiatFeeTreatment.none,
    adjustmentWalletId: adjustmentWalletId,
    adjustmentQuantity: adjustmentWalletId == null
        ? null
        : AccountingAmount.fromInt(1),
    reconciliationLinks: const <ReconciliationLink>[],
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

final class FakeRepository implements AccountingRepository {
  FakeRepository(this.document, this.events);

  AccountingDocument? document;
  final List<String> events;
  bool failWrite = false;

  @override
  Future<AccountingDocument?> read() async {
    events.add('repository.read');
    return document;
  }

  @override
  Future<void> write(AccountingDocument document) async {
    events.add('repository.write');
    if (failWrite) throw StateError('repository write failed');
    this.document = document;
  }

  @override
  Future<void> clear() async => document = null;
}

final class FakeJournal implements WalletImageCleanupJournal {
  FakeJournal(this.events);

  final List<String> events;
  List<WalletImageCleanupIntent> intents = <WalletImageCleanupIntent>[];
  bool failNextReplace = false;

  @override
  Future<List<WalletImageCleanupIntent>> readAll() async {
    events.add('journal.read');
    return <WalletImageCleanupIntent>[...intents];
  }

  @override
  Future<void> replaceAll(List<WalletImageCleanupIntent> intents) async {
    events.add('journal.replace');
    if (failNextReplace) {
      failNextReplace = false;
      throw StateError('journal write failed');
    }
    this.intents = <WalletImageCleanupIntent>[...intents];
  }
}

final class FakeImageStore implements WalletImageStore {
  FakeImageStore(this.events);

  final List<String> events;
  bool failDelete = false;
  int deleteCalls = 0;
  Set<String>? lastReferencedImageIds;

  @override
  Future<void> deleteIfUnreferenced(
    WalletImageRef imageRef,
    Set<String> referencedImageIds,
  ) async {
    events.add('image.delete');
    deleteCalls += 1;
    lastReferencedImageIds = <String>{...referencedImageIds};
    if (failDelete) throw StateError('image delete failed');
  }

  @override
  Future<Uint8List> read(WalletImageRef imageRef) => throw UnimplementedError();

  @override
  Future<WalletImageWriteBatch> stageAll(List<ProcessedWalletImage> images) =>
      throw UnimplementedError();

  @override
  Future<void> write(ProcessedWalletImage image) => throw UnimplementedError();
}
