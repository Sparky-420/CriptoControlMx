import 'dart:typed_data';

import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_document.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_repository.dart';
import 'package:cripto_control_mx/accounting/persistence/wallet_image_processor.dart';
import 'package:cripto_control_mx/accounting/persistence/wallet_image_store.dart';
import 'package:cripto_control_mx/wallets/application/wallet_edit_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DefaultWalletEditService', () {
    test('creates a wallet in the canonical v3 document', () async {
      final repository = _MemoryAccountingRepository();
      final service = DefaultWalletEditService(repository);
      final current = _document(wallets: const <Wallet>[]);
      final now = DateTime.utc(2026, 8, 24);

      final result = await service.createWallet(
        current,
        id: '11111111-1111-4111-8111-111111111111',
        name: '  Mercado Pago  ',
        provider: '  Mercado Pago  ',
        now: now,
      );

      expect(result.wallet.name, 'Mercado Pago');
      expect(result.wallet.provider, 'Mercado Pago');
      expect(result.document.wallets, <Wallet>[result.wallet]);
      expect(repository.written, same(result.document));
    });

    test(
      'updates only wallet identity fields without touching movements',
      () async {
        final repository = _MemoryAccountingRepository();
        final service = DefaultWalletEditService(repository);
        final createdAt = DateTime.utc(2026, 8, 23);
        final updatedAt = DateTime.utc(2026, 8, 24);
        final existing = Wallet.create(
          id: '11111111-1111-4111-8111-111111111111',
          name: 'Bitso',
          provider: 'Bitso',
          createdAt: createdAt,
        );
        final current = _document(wallets: <Wallet>[existing]);

        final result = await service.updateWallet(
          current,
          walletId: existing.id,
          name: '  Bitso Principal  ',
          provider: '  Bitso México  ',
          now: updatedAt,
        );

        expect(result.wallet.id, existing.id);
        expect(result.wallet.name, 'Bitso Principal');
        expect(result.wallet.provider, 'Bitso México');
        expect(result.wallet.status, existing.status);
        expect(result.wallet.createdAt, createdAt);
        expect(result.wallet.updatedAt, updatedAt);
        expect(result.document.movements, isEmpty);
        expect(repository.written, same(result.document));
      },
    );

    test(
      'updates wallet text without clearing an existing image ref',
      () async {
        final repository = _MemoryAccountingRepository();
        final service = DefaultWalletEditService(repository);
        final existing = Wallet.create(
          id: '11111111-1111-4111-8111-111111111111',
          name: 'Bitso',
          provider: 'Bitso',
          imageRef: _imageRef,
          createdAt: DateTime.utc(2026, 8, 23),
        );

        final result = await service.updateWallet(
          _document(wallets: <Wallet>[existing]),
          walletId: existing.id,
          name: 'Bitso Principal',
          provider: 'Bitso México',
          now: DateTime.utc(2026, 8, 24),
        );

        expect(result.wallet.imageRef, same(_imageRef));
        expect(repository.written!.wallets.single.imageRef, same(_imageRef));
      },
    );

    test('updates wallet image through processor and private store', () async {
      final repository = _MemoryAccountingRepository();
      final processor = _FakeWalletImageProcessor();
      final store = _FakeWalletImageStore();
      final service = DefaultWalletEditService(
        repository,
        imageProcessor: processor,
        imageStore: store,
      );
      final existing = Wallet.create(
        id: '11111111-1111-4111-8111-111111111111',
        name: 'Bitso',
        provider: 'Bitso',
        createdAt: DateTime.utc(2026, 8, 23),
      );

      final result = await service.updateWallet(
        _document(wallets: <Wallet>[existing]),
        walletId: existing.id,
        name: 'Bitso',
        provider: 'Bitso',
        imageBytes: Uint8List.fromList(<int>[1, 2, 3]),
        now: DateTime.utc(2026, 8, 24),
      );

      expect(processor.sources, <List<int>>[
        <int>[1, 2, 3],
      ]);
      expect(store.staged, <ProcessedWalletImage>[processor.image]);
      expect(store.batch.committed, isTrue);
      expect(store.batch.rolledBack, isFalse);
      expect(result.wallet.imageRef, processor.image.imageRef);
      expect(
        repository.written!.wallets.single.imageRef,
        processor.image.imageRef,
      );
    });

    test('rolls back staged image when canonical write fails', () async {
      final repository = _MemoryAccountingRepository(failWrite: true);
      final processor = _FakeWalletImageProcessor();
      final store = _FakeWalletImageStore();
      final service = DefaultWalletEditService(
        repository,
        imageProcessor: processor,
        imageStore: store,
      );
      final existing = Wallet.create(
        id: '11111111-1111-4111-8111-111111111111',
        name: 'Bitso',
        provider: 'Bitso',
        createdAt: DateTime.utc(2026, 8, 23),
      );

      await expectLater(
        service.updateWallet(
          _document(wallets: <Wallet>[existing]),
          walletId: existing.id,
          name: 'Bitso',
          provider: 'Bitso',
          imageBytes: Uint8List.fromList(<int>[1]),
          now: DateTime.utc(2026, 8, 24),
        ),
        throwsStateError,
      );

      expect(store.batch.committed, isTrue);
      expect(store.batch.rolledBack, isTrue);
      expect(repository.written, isNull);
    });

    test(
      'image processing failure preserves the previous wallet image',
      () async {
        final repository = _MemoryAccountingRepository();
        final processor = _FakeWalletImageProcessor(fail: true);
        final store = _FakeWalletImageStore();
        final service = DefaultWalletEditService(
          repository,
          imageProcessor: processor,
          imageStore: store,
        );
        final existing = Wallet.create(
          id: '11111111-1111-4111-8111-111111111111',
          name: 'Bitso',
          provider: 'Bitso',
          imageRef: _imageRef,
          createdAt: DateTime.utc(2026, 8, 23),
        );
        final current = _document(wallets: <Wallet>[existing]);
        repository.written = current;

        await expectLater(
          service.updateWallet(
            current,
            walletId: existing.id,
            name: 'Bitso',
            provider: 'Bitso',
            imageBytes: Uint8List.fromList(<int>[1]),
            now: DateTime.utc(2026, 8, 24),
          ),
          throwsStateError,
        );

        expect(repository.written, same(current));
        expect(repository.written!.wallets.single.imageRef, same(_imageRef));
        expect(store.staged, isEmpty);
      },
    );
  });
}

AccountingDocument _document({required List<Wallet> wallets}) =>
    AccountingDocument(
      schemaVersion: accountingSchemaVersion,
      wallets: wallets,
      movements: const <Never>[],
      appliedMigrationIds: const <String>{},
      updatedAt: DateTime.utc(2026, 8, 23),
    );

final class _MemoryAccountingRepository implements AccountingRepository {
  _MemoryAccountingRepository({this.failWrite = false});

  final bool failWrite;
  AccountingDocument? written;

  @override
  Future<void> clear() async {}

  @override
  Future<AccountingDocument?> read() async => written;

  @override
  Future<void> write(AccountingDocument document) async {
    if (failWrite) throw StateError('write failed');
    written = document;
  }
}

final class _FakeWalletImageProcessor implements WalletImageProcessor {
  _FakeWalletImageProcessor({this.fail = false});

  final bool fail;
  final sources = <List<int>>[];
  final image = ProcessedWalletImage(
    Uint8List.fromList(<int>[9, 8, 7]),
    WalletImageRef.create(
      id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      fileName:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png',
      mimeType: 'image/png',
      sha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      width: 24,
      height: 24,
      byteLength: 3,
    ),
  );

  @override
  Future<ProcessedWalletImage> process(
    Uint8List source, {
    required bool preserveAlpha,
    int maxLongEdge = 1024,
    int jpegQuality = 82,
  }) async {
    if (fail) throw StateError('processing failed');
    sources.add(source.toList());
    return image;
  }
}

final _imageRef = WalletImageRef.create(
  id: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  fileName:
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.png',
  mimeType: 'image/png',
  sha256: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  width: 24,
  height: 24,
  byteLength: 3,
);

final class _FakeWalletImageStore implements WalletImageStore {
  final staged = <ProcessedWalletImage>[];
  final batch = _FakeWalletImageWriteBatch();

  @override
  Future<void> deleteIfUnreferenced(
    WalletImageRef imageRef,
    Set<String> referencedImageIds,
  ) async {}

  @override
  Future<Uint8List> read(WalletImageRef imageRef) async => Uint8List(0);

  @override
  Future<WalletImageWriteBatch> stageAll(
    List<ProcessedWalletImage> images,
  ) async {
    staged.addAll(images);
    return batch;
  }

  @override
  Future<void> write(ProcessedWalletImage image) async {}
}

final class _FakeWalletImageWriteBatch implements WalletImageWriteBatch {
  bool committed = false;
  bool rolledBack = false;

  @override
  Future<void> commit() async {
    committed = true;
  }

  @override
  Future<void> rollback({
    Set<String> referencedImageIds = const <String>{},
  }) async {
    rolledBack = true;
  }
}
