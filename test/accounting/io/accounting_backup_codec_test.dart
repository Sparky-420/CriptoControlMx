import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cripto_control_mx/accounting/adapters/legacy_movement_adapter.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_movement.dart';
import 'package:cripto_control_mx/accounting/domain/movement_type.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/io/accounting_backup_bundle.dart';
import 'package:cripto_control_mx/accounting/io/accounting_backup_codec.dart';
import 'package:cripto_control_mx/accounting/io/accounting_backup_restore_service.dart';
import 'package:cripto_control_mx/accounting/io/cloud_image_chunks.dart';
import 'package:cripto_control_mx/accounting/io/shared_preferences_accounting_backup_state_store.dart';
import 'package:cripto_control_mx/accounting/migration/legacy_migration_problem.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_document.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_repository.dart';
import 'package:cripto_control_mx/accounting/persistence/shared_preferences_accounting_repository.dart';
import 'package:cripto_control_mx/accounting/persistence/wallet_image_processor.dart';
import 'package:cripto_control_mx/accounting/persistence/wallet_image_store.dart';
import 'package:cripto_control_mx/accounting/support/sha256.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('backup restores image bytes only after SHA-256 validation', () async {
    final source = completeBackupBundleFixture();
    final codec = DefaultAccountingBackupCodec();
    final targetRepository = _MemoryAccountingRepository();
    final targetImages = _MemoryWalletImageStore();
    final targetStateStore = _MemoryBackupStateStore();
    final restoreService = DefaultAccountingBackupRestoreService(
      targetRepository,
      targetImages,
      targetStateStore,
    );
    final encoded = codec.encodeV3(source);
    final decoded = codec.decodeAny(encoded);
    final restored = await restoreService.restore(decoded);
    expect(restored.document.toJson(), source.document.toJson());
    expect(
      await targetImages.read(source.walletImages.single.imageRef),
      source.walletImages.single.bytes,
    );
    final reopened = await targetStateStore.read();
    expect(
      reopened.snapshots.map((value) => value.toJson()).toList(),
      source.snapshots.map((value) => value.toJson()).toList(),
    );
    expect(reopened.currentPrices, source.currentPrices);
    expect(reopened.settings.toJson(), source.settings.toJson());
  });

  test(
    'restore accepts multiple wallets sharing the same valid image',
    () async {
      final source = completeBackupBundleFixture();
      final sharedImage = source.walletImages.single;
      final secondWallet = Wallet.create(
        id: '55555555-5555-4555-8555-555555555555',
        name: 'Secundaria',
        provider: 'Bitso',
        createdAt: source.exportedAt,
        imageRef: sharedImage.imageRef,
      );
      final document = AccountingDocument(
        schemaVersion: source.document.schemaVersion,
        wallets: <Wallet>[...source.document.wallets, secondWallet],
        movements: source.document.movements,
        appliedMigrationIds: source.document.appliedMigrationIds,
        updatedAt: source.document.updatedAt,
        legacyMovementMetadata: source.document.legacyMovementMetadata,
        legacyMovementMigrationMetadata:
            source.document.legacyMovementMigrationMetadata,
        legacyMigrationProblems: source.document.legacyMigrationProblems,
        assignmentAudits: source.document.assignmentAudits,
        legacyAccountingPolicy: source.document.legacyAccountingPolicy,
      );
      final sharedBundle = AccountingBackupBundle(
        document: document,
        snapshots: source.snapshots,
        currentPrices: source.currentPrices,
        settings: source.settings,
        walletImages: <PortableWalletImage>[sharedImage],
        exportedAt: source.exportedAt,
        preservedTopLevelFields: source.preservedTopLevelFields,
      );
      final repository = _MemoryAccountingRepository();
      final images = _MemoryWalletImageStore();
      final states = _MemoryBackupStateStore();
      final service = DefaultAccountingBackupRestoreService(
        repository,
        images,
        states,
      );

      final restored = await service.restore(
        const DefaultAccountingBackupCodec().decodeAny(
          const DefaultAccountingBackupCodec().encodeV3(sharedBundle),
        ),
      );

      expect(restored.document.wallets, hasLength(2));
      expect(images.values, hasLength(1));
      expect(await images.read(sharedImage.imageRef), sharedImage.bytes);
    },
  );

  test(
    'restore rejects shared image ids with contradictory metadata before staging',
    () async {
      final source = completeBackupBundleFixture();
      final sharedImage = source.walletImages.single;
      final contradictoryImageRef = WalletImageRef.create(
        id: sharedImage.imageRef.id,
        fileName: '${sharedImage.imageRef.sha256}.jpg',
        mimeType: 'image/jpeg',
        sha256: sharedImage.imageRef.sha256,
        width: sharedImage.imageRef.width,
        height: sharedImage.imageRef.height,
        byteLength: sharedImage.imageRef.byteLength,
      );
      final secondWallet = Wallet.create(
        id: '55555555-5555-4555-8555-555555555555',
        name: 'Secundaria',
        provider: 'Bitso',
        createdAt: source.exportedAt,
        imageRef: contradictoryImageRef,
      );
      final document = AccountingDocument(
        schemaVersion: source.document.schemaVersion,
        wallets: <Wallet>[...source.document.wallets, secondWallet],
        movements: source.document.movements,
        appliedMigrationIds: source.document.appliedMigrationIds,
        updatedAt: source.document.updatedAt,
        legacyMovementMetadata: source.document.legacyMovementMetadata,
        legacyMovementMigrationMetadata:
            source.document.legacyMovementMigrationMetadata,
        legacyMigrationProblems: source.document.legacyMigrationProblems,
        assignmentAudits: source.document.assignmentAudits,
        legacyAccountingPolicy: source.document.legacyAccountingPolicy,
      );
      final repository = _MemoryAccountingRepository();
      final images = _MemoryWalletImageStore();
      final states = _MemoryBackupStateStore();
      final service = DefaultAccountingBackupRestoreService(
        repository,
        images,
        states,
      );

      await expectLater(
        service.restore(
          DecodedAccountingBackup(
            bundle: AccountingBackupBundle(
              document: document,
              snapshots: source.snapshots,
              currentPrices: source.currentPrices,
              settings: source.settings,
              walletImages: <PortableWalletImage>[sharedImage],
              exportedAt: source.exportedAt,
              preservedTopLevelFields: source.preservedTopLevelFields,
            ),
            origin: AccountingBackupOrigin.schemaV3,
            warnings: const <String>[],
          ),
        ),
        throwsFormatException,
      );
      expect(images.stageCalls, 0);
    },
  );

  test('v3 codec preserves the complete canonical bundle and extensions', () {
    final source = completeBackupBundleFixture();
    const codec = DefaultAccountingBackupCodec();

    final encoded = codec.encodeV3(source);

    expect(encoded['schemaVersion'], 3);
    expect(
      encoded.keys,
      containsAll(<String>{
        'wallets',
        'walletImages',
        'movements',
        'snapshots',
        'currentPrices',
        'settings',
        'appliedMigrationIds',
        'legacyMovementMetadata',
        'legacyMigrationProblems',
        'legacyAccountingPolicy',
        'assignmentAudits',
        'updatedAt',
        'exportedAt',
      }),
    );
    final image = Map<String, Object?>.from(
      (encoded['walletImages']! as List).single as Map,
    );
    expect(
      image['entryName'],
      'wallet_images/${source.walletImages.single.imageRef.fileName}',
    );
    expect(
      sha256BytesHex(
        Uint8List.fromList(base64Decode(image['bytesBase64']! as String)),
      ),
      source.walletImages.single.imageRef.sha256,
    );
    final movements = (encoded['movements']! as List)
        .map((value) => Map<String, Object?>.from(value as Map))
        .toList();
    for (final movement in movements) {
      for (final key in <String>[
        'quantity',
        'unitPriceFiat',
        'fiatFeeAmount',
        'receivedAmount',
        'cryptoFeeAmount',
        'totalDebitedAmount',
        'feeFiatValue',
        'adjustmentQuantity',
        'observedBalance',
      ]) {
        if (movement[key] != null) {
          expect(movement[key], isA<String>(), reason: key);
        }
      }
    }
    final movement = movements.firstWhere(
      (value) => value['type'] == MovementType.balanceAdjustment.name,
    );
    expect(
      ((movement['reconciliationLinks']! as List).single
          as Map)['quantityResolved'],
      isA<String>(),
    );

    final decoded = codec.decodeAny(encoded);

    expect(decoded.origin, AccountingBackupOrigin.schemaV3);
    expect(decoded.bundle.document.toJson(), source.document.toJson());
    expect(
      decoded.bundle.walletImages.single.imageRef.fileName,
      source.walletImages.single.imageRef.fileName,
    );
    expect(
      decoded.bundle.snapshots.map((value) => value.toJson()).toList(),
      source.snapshots.map((value) => value.toJson()).toList(),
    );
    expect(decoded.bundle.currentPrices, source.currentPrices);
    expect(decoded.bundle.settings.toJson(), source.settings.toJson());
    expect(decoded.bundle.preservedTopLevelFields, <String, Object?>{
      'futureTopLevel': 7,
    });
    expect(jsonEncode(codec.encodeV3(decoded.bundle)), jsonEncode(encoded));
  });

  test(
    'unsafe portable image paths are rejected before store staging',
    () async {
      const codec = DefaultAccountingBackupCodec();
      final source = completeBackupBundleFixture();
      final encoded = codec.encodeV3(source);
      final targetImages = _MemoryWalletImageStore();

      for (final unsafe in <String>[
        'wallet_images/../x.png',
        '/wallet_images/x.png',
        r'C:\wallet_images\x.png',
        'wallet_images/nested/x.png',
      ]) {
        final manipulated = _deepCopy(encoded);
        ((manipulated['walletImages']! as List).single as Map)['entryName'] =
            unsafe;
        expect(() => codec.decodeAny(manipulated), throwsFormatException);
      }

      expect(targetImages.stageCalls, 0);
      expect(targetImages.values, isEmpty);
    },
  );

  test('v2 import migrates movements and records absent snapshots', () {
    const codec = DefaultAccountingBackupCodec();
    final decoded = codec.decodeAny(<String, Object?>{
      'version': 2,
      'exportedAt': '2026-08-11T23:45:00.000Z',
      'movements': <Object?>[
        <String, Object?>{
          'id': 'legacy-id',
          'type': 'buy',
          'coin': 'BTC',
          'date': '2026-08-11T23:45:00.000Z',
          'quantity': 0.5,
          'unitPrice': 100,
          'fee': 1,
        },
      ],
      'currentPrices': <String, Object?>{'BTC': 120.0},
    });

    expect(decoded.origin, AccountingBackupOrigin.legacyV2);
    expect(decoded.bundle.document.movements.single.id, 'legacy-id');
    expect(decoded.bundle.document.legacyMigrationProblems, isEmpty);
    expect(decoded.bundle.snapshots, isEmpty);
    expect(decoded.warnings, contains(contains('sin instantáneas')));
    expect(decoded.bundle.settings.sellFeePercent, 0);
    expect(decoded.bundle.settings.priceModes, isEmpty);
    expect(decoded.bundle.settings.manualPricesUpdatedAtMs, isEmpty);
  });

  test('future canonical schema is rejected instead of migrated as legacy', () {
    const codec = DefaultAccountingBackupCodec();
    final encoded = codec.encodeV3(completeBackupBundleFixture());
    encoded['schemaVersion'] = 4;

    expect(
      () => codec.decodeAny(encoded),
      throwsA(
        isA<UnsupportedAccountingSchemaException>().having(
          (error) => error.version,
          'version',
          4,
        ),
      ),
    );
  });

  test('v3 image-free backup remains image-free after round-trip', () {
    const codec = DefaultAccountingBackupCodec();
    final source = completeBackupBundleFixture();
    final imageFreeDocument = AccountingDocument(
      schemaVersion: 3,
      wallets: source.document.wallets
          .map(
            (wallet) => Wallet(
              id: wallet.id,
              name: wallet.name,
              provider: wallet.provider,
              status: wallet.status,
              createdAt: wallet.createdAt,
              updatedAt: wallet.updatedAt,
            ),
          )
          .toList(),
      movements: source.document.movements,
      appliedMigrationIds: source.document.appliedMigrationIds,
      updatedAt: source.document.updatedAt,
      legacyMovementMetadata: source.document.legacyMovementMetadata,
      legacyMigrationProblems: source.document.legacyMigrationProblems,
    );
    final bundle = AccountingBackupBundle(
      document: imageFreeDocument,
      snapshots: source.snapshots,
      currentPrices: source.currentPrices,
      settings: source.settings,
      walletImages: const <PortableWalletImage>[],
      exportedAt: source.exportedAt,
    );

    final decoded = codec.decodeAny(codec.encodeV3(bundle));

    expect(decoded.bundle.walletImages, isEmpty);
    expect(decoded.bundle.document.toJson(), imageFreeDocument.toJson());
  });

  test('Firebase image chunks are deterministic and validate the manifest', () {
    final bytes = Uint8List.fromList(
      List<int>.generate(1200001, (index) => index % 251),
    );
    final chunks = splitCloudImage('image-1', bytes);
    final manifest = CloudImageManifest(
      imageId: 'image-1',
      sha256: sha256BytesHex(bytes),
      chunkCount: chunks.length,
      byteLength: bytes.length,
    );

    expect(chunks.map((chunk) => chunk.index), <int>[0, 1, 2]);
    expect(chunks, everyElement(isA<CloudImageChunk>()));
    expect(chunks.map((chunk) => chunk.imageId).toSet(), <String>{'image-1'});
    expect(manifest.chunkCount, 3);
    expect(manifest.byteLength, 1200001);
    expect(manifest.sha256, sha256BytesHex(bytes));
    expect(
      joinCloudImage(manifest, <CloudImageChunk>[
        chunks[2],
        chunks[0],
        chunks[1],
      ]),
      bytes,
    );

    expect(
      () => joinCloudImage(manifest, <CloudImageChunk>[
        chunks[0],
        chunks[1],
        CloudImageChunk(imageId: 'wrong', index: 2, bytes: chunks[2].bytes),
      ]),
      throwsFormatException,
    );
    expect(
      () => joinCloudImage(manifest, <CloudImageChunk>[chunks[0], chunks[1]]),
      throwsFormatException,
    );
    expect(
      () => joinCloudImage(manifest, <CloudImageChunk>[
        chunks[0],
        chunks[1],
        chunks[1],
      ]),
      throwsFormatException,
    );
    expect(
      () => joinCloudImage(manifest, <CloudImageChunk>[
        chunks[0],
        chunks[1],
        CloudImageChunk(imageId: 'image-1', index: 3, bytes: chunks[2].bytes),
      ]),
      throwsFormatException,
    );
  });

  test(
    'Firebase upload plan bounds writes and cleans stale chunks last',
    () async {
      final chunks = List<CloudImageChunk>.generate(
        21,
        (index) => CloudImageChunk(
          imageId: 'image-${index ~/ 3}',
          index: index % 3,
          bytes: Uint8List.fromList(<int>[index]),
        ),
      );
      final retainedId = '${chunks.first.imageId}:${chunks.first.index}';
      final priorIds = <String>[
        retainedId,
        ...List<String>.generate(805, (index) => 'stale:$index'),
      ];

      final plan = planCloudImageUpload(chunks, priorIds);
      final events = <String>[];

      await executeCloudImageUploadPlan(
        plan,
        writeChunkBatch: (batch) async => events.add('write:${batch.length}'),
        publishCurrent: () async => events.add('publish'),
        deleteStaleChunkBatch: (batch) async =>
            events.add('delete:${batch.length}'),
      );

      expect(plan.phases, <CloudImageUploadPhase>[
        CloudImageUploadPhase.writeChunks,
        CloudImageUploadPhase.publishCurrent,
        CloudImageUploadPhase.deleteStaleChunks,
      ]);
      expect(plan.chunkWriteBatches.map((batch) => batch.length), <int>[
        10,
        10,
        1,
      ]);
      expect(plan.staleChunkDeleteBatches.map((batch) => batch.length), <int>[
        400,
        400,
        5,
      ]);
      expect(
        plan.staleChunkDeleteBatches.expand((batch) => batch),
        isNot(contains(retainedId)),
      );
      expect(events, <String>[
        'write:10',
        'write:10',
        'write:1',
        'publish',
        'delete:400',
        'delete:400',
        'delete:5',
      ]);
    },
  );

  test('SharedPreferences state store reopens typed backup values', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final source = completeBackupBundleFixture();
    final first = SharedPreferencesAccountingBackupStateStore();
    final state = AccountingBackupApplicationState(
      snapshots: source.snapshots,
      currentPrices: source.currentPrices,
      settings: source.settings,
    );

    await first.write(state);
    final reopened = await SharedPreferencesAccountingBackupStateStore().read();

    expect(
      reopened.snapshots.map((value) => value.toJson()).toList(),
      source.snapshots.map((value) => value.toJson()).toList(),
    );
    expect(reopened.currentPrices, source.currentPrices);
    expect(reopened.settings.toJson(), source.settings.toJson());
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey('portfolio_snapshots_v23_json'), isTrue);
    expect(preferences.containsKey('prices_json'), isTrue);
    expect(preferences.containsKey('sell_fee_percent'), isTrue);
    expect(preferences.containsKey('price_modes_v1_json'), isTrue);
    expect(preferences.containsKey('manual_prices_updated_at_v1_json'), isTrue);
  });

  test(
    'SharedPreferences adapters reopen and restore the same bundle twice',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final root = await Directory.systemTemp.createTemp('backup_reopen_');
      addTearDown(() => root.delete(recursive: true));
      const codec = DefaultAccountingBackupCodec();
      final source = completeBackupBundleFixture();
      final images = PrivateWalletImageStore(
        applicationSupportDirectory: () async => root,
      );
      final firstService = DefaultAccountingBackupRestoreService(
        SharedPreferencesAccountingRepository(),
        images,
        SharedPreferencesAccountingBackupStateStore(),
      );

      await firstService.restore(codec.decodeAny(codec.encodeV3(source)));
      final reopenedRepository = SharedPreferencesAccountingRepository();
      final reopenedStateStore = SharedPreferencesAccountingBackupStateStore();
      final reopenedDocument = (await reopenedRepository.read())!;
      final reopenedState = await reopenedStateStore.read();
      final reopenedImages = <PortableWalletImage>[];
      for (final wallet in reopenedDocument.wallets) {
        final imageRef = wallet.imageRef;
        if (imageRef != null) {
          reopenedImages.add(
            PortableWalletImage(
              imageRef: imageRef,
              bytes: await images.read(imageRef),
            ),
          );
        }
      }
      final reopenedBundle = AccountingBackupBundle(
        document: reopenedDocument,
        snapshots: reopenedState.snapshots,
        currentPrices: reopenedState.currentPrices,
        settings: reopenedState.settings,
        walletImages: reopenedImages,
        exportedAt: source.exportedAt,
        preservedTopLevelFields: source.preservedTopLevelFields,
      );
      final secondService = DefaultAccountingBackupRestoreService(
        reopenedRepository,
        images,
        reopenedStateStore,
      );

      await secondService.restore(
        codec.decodeAny(codec.encodeV3(reopenedBundle)),
      );
      final twiceDocument = (await reopenedRepository.read())!;
      final twiceState = await reopenedStateStore.read();

      expect(twiceDocument.toJson(), source.document.toJson());
      expect(
        twiceDocument.movements,
        hasLength(source.document.movements.length),
      );
      expect(reopenedImages, hasLength(source.walletImages.length));
      expect(
        twiceState.snapshots.map((value) => value.toJson()).toList(),
        source.snapshots.map((value) => value.toJson()).toList(),
      );
      expect(twiceState.currentPrices, source.currentPrices);
      expect(twiceState.settings.toJson(), source.settings.toJson());
    },
  );

  test(
    'private image batch removes only new files after active write failure',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'backup_restore_images_',
      );
      addTearDown(() => root.delete(recursive: true));
      final source = completeBackupBundleFixture();
      final repository = _MemoryAccountingRepository()..failNextWrite = true;
      final images = PrivateWalletImageStore(
        applicationSupportDirectory: () async => root,
      );
      final states = _MemoryBackupStateStore();
      final service = DefaultAccountingBackupRestoreService(
        repository,
        images,
        states,
      );

      await expectLater(
        service.restore(
          const DefaultAccountingBackupCodec().decodeAny(
            const DefaultAccountingBackupCodec().encodeV3(source),
          ),
        ),
        throwsStateError,
      );

      final imageFile = File(
        '${root.path}${Platform.pathSeparator}wallet_images'
        '${Platform.pathSeparator}${source.walletImages.single.imageRef.fileName}',
      );
      expect(imageFile.existsSync(), isFalse);
    },
  );

  test('restore validates the complete bundle before image staging', () async {
    final source = completeBackupBundleFixture();
    final manipulated = DecodedAccountingBackup(
      bundle: AccountingBackupBundle(
        document: source.document,
        snapshots: source.snapshots,
        currentPrices: source.currentPrices,
        settings: source.settings,
        walletImages: <PortableWalletImage>[
          PortableWalletImage(
            imageRef: source.walletImages.single.imageRef,
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
          ),
        ],
        exportedAt: source.exportedAt,
      ),
      origin: AccountingBackupOrigin.schemaV3,
      warnings: const <String>[],
    );
    final repository = _MemoryAccountingRepository();
    final images = _MemoryWalletImageStore();
    final states = _MemoryBackupStateStore();
    final previousState = states.value;
    final service = DefaultAccountingBackupRestoreService(
      repository,
      images,
      states,
    );

    await expectLater(service.restore(manipulated), throwsFormatException);

    expect(images.stageCalls, 0);
    expect(repository.value, isNull);
    expect(states.value, same(previousState));
  });

  test(
    'rollback exception still removes new images after compensation failure',
    () async {
      final source = completeBackupBundleFixture();
      final repository = _MemoryAccountingRepository();
      final images = _MemoryWalletImageStore();
      final states = _MemoryBackupStateStore()..writeFailuresRemaining = 2;
      final service = DefaultAccountingBackupRestoreService(
        repository,
        images,
        states,
      );

      await expectLater(
        service.restore(
          const DefaultAccountingBackupCodec().decodeAny(
            const DefaultAccountingBackupCodec().encodeV3(source),
          ),
        ),
        throwsA(
          isA<AccountingRestoreRollbackException>()
              .having(
                (error) => error.writeCause,
                'writeCause',
                isA<StateError>(),
              )
              .having(
                (error) => error.rollbackCause,
                'rollbackCause',
                isA<StateError>(),
              ),
        ),
      );

      expect(repository.value, isNull);
      expect(images.values, isEmpty);
    },
  );

  test(
    'failed document compensation preserves images referenced by persisted new state',
    () async {
      final source = completeBackupBundleFixture();
      final previous = previousDocumentFixture();
      final repository = _MemoryAccountingRepository()
        ..value = previous
        ..failWriteCalls.add(2);
      final images = _MemoryWalletImageStore();
      final states = _MemoryBackupStateStore()..failNextWrite = true;
      final service = DefaultAccountingBackupRestoreService(
        repository,
        images,
        states,
      );

      await expectLater(
        service.restore(
          const DefaultAccountingBackupCodec().decodeAny(
            const DefaultAccountingBackupCodec().encodeV3(source),
          ),
        ),
        throwsA(isA<AccountingRestoreRollbackException>()),
      );

      expect(repository.value?.toJson(), source.document.toJson());
      expect(
        images.values.keys,
        contains(source.walletImages.single.imageRef.id),
      );
    },
  );

  for (final hasPreviousDocument in <bool>[false, true]) {
    test('restore compensates repository failure with previous document '
        '${hasPreviousDocument ? 'present' : 'absent'}', () async {
      final source = completeBackupBundleFixture();
      final previous = hasPreviousDocument ? previousDocumentFixture() : null;
      final repository = _MemoryAccountingRepository()..value = previous;
      final images = _MemoryWalletImageStore();
      final states = _MemoryBackupStateStore();
      final previousState = states.value;
      repository.failNextWrite = true;
      final service = DefaultAccountingBackupRestoreService(
        repository,
        images,
        states,
      );

      await expectLater(
        service.restore(
          const DefaultAccountingBackupCodec().decodeAny(
            const DefaultAccountingBackupCodec().encodeV3(source),
          ),
        ),
        throwsStateError,
      );

      expect(repository.value?.toJson(), previous?.toJson());
      expect(states.value, same(previousState));
      expect(images.values, isEmpty);
    });

    test('restore compensates application-state failure with previous document '
        '${hasPreviousDocument ? 'present' : 'absent'}', () async {
      final source = completeBackupBundleFixture();
      final previous = hasPreviousDocument ? previousDocumentFixture() : null;
      final repository = _MemoryAccountingRepository()..value = previous;
      final images = _MemoryWalletImageStore();
      final states = _MemoryBackupStateStore();
      final previousState = states.value;
      states.failNextWrite = true;
      final service = DefaultAccountingBackupRestoreService(
        repository,
        images,
        states,
      );

      await expectLater(
        service.restore(
          const DefaultAccountingBackupCodec().decodeAny(
            const DefaultAccountingBackupCodec().encodeV3(source),
          ),
        ),
        throwsStateError,
      );

      expect(repository.value?.toJson(), previous?.toJson());
      expect(states.value, same(previousState));
      expect(images.values, isEmpty);
    });
  }
}

Map<String, Object?> _deepCopy(Map<String, Object?> value) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);

AccountingDocument previousDocumentFixture() => AccountingDocument(
  schemaVersion: 3,
  wallets: const <Wallet>[],
  movements: const <AccountingMovement>[],
  appliedMigrationIds: const <String>{},
  updatedAt: DateTime.utc(2026, 8, 10),
);

AccountingBackupBundle completeBackupBundleFixture() {
  final at = DateTime.utc(2026, 8, 11, 23, 45);
  final bytes = Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10]);
  final hash = sha256BytesHex(bytes);
  final imageRef = WalletImageRef.create(
    id: hash,
    fileName: '$hash.png',
    mimeType: 'image/png',
    sha256: hash,
    width: 1,
    height: 1,
    byteLength: bytes.length,
  );
  final wallet = Wallet.create(
    id: '11111111-1111-4111-8111-111111111111',
    name: 'Principal',
    provider: 'Bitso',
    createdAt: at,
    imageRef: imageRef,
  );
  final adjustment = AccountingMovement(
    id: '22222222-2222-4222-8222-222222222222',
    type: MovementType.balanceAdjustment,
    asset: 'BTC',
    occurredAt: at,
    fiatFeeAmount: AccountingAmount.parse('0'),
    walletAssignmentStatus: WalletAssignmentStatus.assigned,
    cryptoFeeAmount: AccountingAmount.parse('0'),
    fiatFeeTreatment: FiatFeeTreatment.none,
    reconciliationLinks: <ReconciliationLink>[
      ReconciliationLink(
        adjustmentMovementId: '33333333-3333-4333-8333-333333333333',
        quantityResolved: AccountingAmount.parse('0.01'),
      ),
    ],
    adjustmentWalletId: wallet.id,
    adjustmentQuantity: AccountingAmount.parse('-0.125'),
    observedBalance: AccountingAmount.parse('1.875'),
    adjustmentReason: 'Conciliación manual',
    note: 'Saldo observado en exchange',
    createdAt: at,
    updatedAt: at,
  );
  final transfer = AccountingMovement(
    id: '44444444-4444-4444-8444-444444444444',
    type: MovementType.transferOut,
    asset: 'BTC',
    occurredAt: at.add(const Duration(minutes: 1)),
    quantity: AccountingAmount.parse('0.5'),
    unitPriceFiat: AccountingAmount.parse('64.25'),
    fiatFeeAmount: AccountingAmount.parse('1.25'),
    sourceWalletId: wallet.id,
    destinationType: DestinationType.external,
    externalRecipientName: 'Cold storage',
    externalDestinationPlatform: 'Ledger',
    walletAssignmentStatus: WalletAssignmentStatus.assigned,
    receivedAmount: AccountingAmount.parse('0.49'),
    cryptoFeeAmount: AccountingAmount.parse('0.01'),
    cryptoFeeAsset: 'BTC',
    totalDebitedAmount: AccountingAmount.parse('0.5'),
    feeFiatValue: AccountingAmount.parse('0.6425'),
    fiatFeeTreatment: FiatFeeTreatment.combined,
    network: 'Bitcoin',
    note: 'Retiro propio',
    reconciliationLinks: const <ReconciliationLink>[],
    createdAt: at,
    updatedAt: at.add(const Duration(minutes: 1)),
  );
  final unconvertible = LegacyMigrationProblem.create(
    kind: LegacyMigrationProblemKind.unconvertible,
    sourceIndex: 4,
    primaryPayload: <String, Object?>{'type': '???', 'coin': 'BTC'},
    conversionIssues: const <LegacyConversionIssue>[
      LegacyConversionIssue(
        code: LegacyConversionIssueCode.unknownMovementType,
        message: 'tipo desconocido',
        rawValue: '???',
      ),
    ],
  );
  final conflicting = LegacyMigrationProblem.create(
    kind: LegacyMigrationProblemKind.conflictingId,
    sourceIndex: 7,
    primaryPayload: <String, Object?>{'id': adjustment.id, 'quantity': 1},
    conflictingPayload: <String, Object?>{'id': adjustment.id, 'quantity': 2},
  );
  return AccountingBackupBundle(
    document: AccountingDocument(
      schemaVersion: 3,
      wallets: <Wallet>[wallet],
      movements: <AccountingMovement>[adjustment, transfer],
      appliedMigrationIds: const <String>{'legacy-v1'},
      updatedAt: at,
      legacyMovementMetadata: <String, Map<String, Object?>>{
        adjustment.id: <String, Object?>{'legacyCustom': 'preserve'},
      },
      legacyMigrationProblems: <LegacyMigrationProblem>[
        unconvertible,
        conflicting,
      ],
    ),
    snapshots: <BackupPortfolioSnapshot>[
      BackupPortfolioSnapshot(
        id: 'snapshot-1',
        createdAt: at,
        totalCostBase: 100.25,
        totalCurrentValue: 120.5,
        totalUnrealizedPL: 20.25,
        totalRealizedPL: 3.75,
        movementCount: 2,
        coins: const <BackupCoinSnapshot>[
          BackupCoinSnapshot(
            coin: 'BTC',
            quantity: 1.875,
            costBase: 100.25,
            avgPrice: 53.46666666666667,
            currentValue: 120.5,
            unrealizedPL: 20.25,
            realizedPL: 3.75,
          ),
        ],
      ),
    ],
    currentPrices: const <String, double>{'BTC': 64.26666666666667},
    settings: const AccountingBackupSettings(
      sellFeePercent: 0.65,
      priceModes: <String, String>{'BTC': 'manual'},
      manualPricesUpdatedAtMs: <String, int>{'BTC': 1786491900000},
      preservedFields: <String, Object?>{'futureSetting': true},
    ),
    walletImages: <PortableWalletImage>[
      PortableWalletImage(imageRef: imageRef, bytes: bytes),
    ],
    exportedAt: at.add(const Duration(minutes: 2)),
    preservedTopLevelFields: const <String, Object?>{'futureTopLevel': 7},
  );
}

final class _MemoryAccountingRepository implements AccountingRepository {
  AccountingDocument? value;
  bool failNextWrite = false;
  final Set<int> failWriteCalls = <int>{};
  int writeCalls = 0;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<AccountingDocument?> read() async => value;

  @override
  Future<void> write(AccountingDocument document) async {
    writeCalls++;
    if (failNextWrite || failWriteCalls.contains(writeCalls)) {
      failNextWrite = false;
      throw StateError('injected repository failure');
    }
    value = document;
  }
}

final class _MemoryWalletImageStore implements WalletImageStore {
  final Map<String, Uint8List> values = <String, Uint8List>{};
  int stageCalls = 0;

  @override
  Future<void> deleteIfUnreferenced(
    WalletImageRef imageRef,
    Set<String> referencedImageIds,
  ) async {
    if (!referencedImageIds.contains(imageRef.id)) values.remove(imageRef.id);
  }

  @override
  Future<Uint8List> read(WalletImageRef imageRef) async => values[imageRef.id]!;

  @override
  Future<WalletImageWriteBatch> stageAll(
    List<ProcessedWalletImage> images,
  ) async {
    stageCalls++;
    return _MemoryWalletImageWriteBatch(values, images);
  }

  @override
  Future<void> write(ProcessedWalletImage image) async {
    values[image.imageRef.id] = image.bytes;
  }
}

final class _MemoryWalletImageWriteBatch implements WalletImageWriteBatch {
  _MemoryWalletImageWriteBatch(this.values, this.images)
    : preExistingIds = values.keys.toSet();

  final Map<String, Uint8List> values;
  final List<ProcessedWalletImage> images;
  final Set<String> preExistingIds;

  @override
  Future<void> commit() async {
    for (final image in images) {
      values[image.imageRef.id] = image.bytes;
    }
  }

  @override
  Future<void> rollback({
    Set<String> referencedImageIds = const <String>{},
  }) async {
    for (final image in images) {
      if (!preExistingIds.contains(image.imageRef.id) &&
          !referencedImageIds.contains(image.imageRef.id)) {
        values.remove(image.imageRef.id);
      }
    }
  }
}

final class _MemoryBackupStateStore implements AccountingBackupStateStore {
  AccountingBackupApplicationState value =
      const AccountingBackupApplicationState(
        snapshots: <BackupPortfolioSnapshot>[],
        currentPrices: <String, double>{},
        settings: AccountingBackupSettings(
          sellFeePercent: 0,
          priceModes: <String, String>{},
          manualPricesUpdatedAtMs: <String, int>{},
        ),
      );
  bool failNextWrite = false;
  int writeFailuresRemaining = 0;

  @override
  Future<AccountingBackupApplicationState> read() async => value;

  @override
  Future<void> write(AccountingBackupApplicationState state) async {
    if (failNextWrite || writeFailuresRemaining > 0) {
      failNextWrite = false;
      if (writeFailuresRemaining > 0) writeFailuresRemaining--;
      throw StateError('injected state failure');
    }
    value = state;
  }
}
