import 'dart:typed_data';

import '../../accounting/domain/wallet.dart';
import '../../accounting/persistence/accounting_document.dart';
import '../../accounting/persistence/accounting_repository.dart';
import '../../accounting/persistence/wallet_image_processor.dart';
import '../../accounting/persistence/wallet_image_store.dart';

final class WalletEditResult {
  const WalletEditResult({required this.document, required this.wallet});

  final AccountingDocument document;
  final Wallet wallet;
}

final class DefaultWalletEditService {
  const DefaultWalletEditService(
    this.repository, {
    this.imageProcessor,
    this.imageStore,
  });

  final AccountingRepository repository;
  final WalletImageProcessor? imageProcessor;
  final WalletImageStore? imageStore;

  Future<WalletEditResult> createWallet(
    AccountingDocument current, {
    required String id,
    required String name,
    required String provider,
    Uint8List? imageBytes,
    required DateTime now,
  }) async {
    final image = await _processImage(imageBytes);
    final wallet = Wallet.create(
      id: id,
      name: name,
      provider: provider,
      imageRef: image?.imageRef,
      createdAt: now,
    );
    final document = _copyDocument(
      current,
      wallets: <Wallet>[...current.wallets, wallet],
      updatedAt: now,
    );
    await _writeDocument(
      document,
      image: image,
      rollbackReferencedImageIds: _imageIds(current),
    );
    return WalletEditResult(document: document, wallet: wallet);
  }

  Future<WalletEditResult> updateWallet(
    AccountingDocument current, {
    required String walletId,
    required String name,
    required String provider,
    Uint8List? imageBytes,
    required DateTime now,
  }) async {
    final index = current.wallets.indexWhere((wallet) => wallet.id == walletId);
    if (index < 0) {
      throw StateError('Wallet not found: $walletId');
    }
    final existing = current.wallets[index];
    final image = await _processImage(imageBytes);
    final normalized = Wallet.create(
      id: existing.id,
      name: name,
      provider: provider,
      imageRef: image?.imageRef ?? existing.imageRef,
      createdAt: existing.createdAt,
    );
    final wallet = Wallet(
      id: existing.id,
      name: normalized.name,
      provider: normalized.provider,
      status: existing.status,
      createdAt: existing.createdAt,
      updatedAt: now,
      imageRef: normalized.imageRef,
      colorArgb: existing.colorArgb,
      note: existing.note,
      schemaVersion: existing.schemaVersion,
    );
    final wallets = <Wallet>[...current.wallets];
    wallets[index] = wallet;
    final document = _copyDocument(current, wallets: wallets, updatedAt: now);
    await _writeDocument(
      document,
      image: image,
      rollbackReferencedImageIds: _imageIds(current),
    );
    return WalletEditResult(document: document, wallet: wallet);
  }

  Future<ProcessedWalletImage?> _processImage(Uint8List? imageBytes) async {
    if (imageBytes == null) return null;
    final processor = imageProcessor;
    if (processor == null) {
      throw StateError('WalletImageProcessor is required to process images.');
    }
    return processor.process(imageBytes, preserveAlpha: true);
  }

  Future<void> _writeDocument(
    AccountingDocument document, {
    ProcessedWalletImage? image,
    Set<String> rollbackReferencedImageIds = const <String>{},
  }) async {
    if (image == null) {
      await repository.write(document);
      return;
    }
    final store = imageStore;
    if (store == null) {
      throw StateError('WalletImageStore is required to persist images.');
    }
    final batch = await store.stageAll(<ProcessedWalletImage>[image]);
    try {
      await batch.commit();
      await repository.write(document);
    } catch (_) {
      await batch.rollback(referencedImageIds: rollbackReferencedImageIds);
      rethrow;
    }
  }
}

Set<String> _imageIds(AccountingDocument document) => document.wallets
    .map((wallet) => wallet.imageRef?.id)
    .whereType<String>()
    .toSet();

AccountingDocument _copyDocument(
  AccountingDocument current, {
  required List<Wallet> wallets,
  required DateTime updatedAt,
}) => AccountingDocument(
  schemaVersion: current.schemaVersion,
  wallets: wallets,
  movements: current.movements,
  appliedMigrationIds: current.appliedMigrationIds,
  updatedAt: updatedAt,
  legacyMovementMetadata: current.legacyMovementMetadata,
  legacyMovementMigrationMetadata: current.legacyMovementMigrationMetadata,
  legacyMigrationProblems: current.legacyMigrationProblems,
  assignmentAudits: current.assignmentAudits,
  legacyAccountingPolicy: current.legacyAccountingPolicy,
);
