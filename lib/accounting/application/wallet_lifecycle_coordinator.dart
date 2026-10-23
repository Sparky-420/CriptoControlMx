import '../persistence/accounting_document.dart';
import '../persistence/accounting_repository.dart';
import '../persistence/wallet_image_store.dart';
import 'wallet_image_cleanup_journal.dart';
import 'wallet_lifecycle_service.dart';

enum WalletDeleteCommitStatus {
  blocked,
  archived,
  committed,
  committedWithPendingCleanup,
}

final class WalletImageCleanupResult {
  const WalletImageCleanupResult({
    required this.deletedImageIds,
    required this.stillReferencedImageIds,
    required this.pendingRetryImageIds,
  });

  final Set<String> deletedImageIds;
  final Set<String> stillReferencedImageIds;
  final Set<String> pendingRetryImageIds;
}

final class WalletDeleteCommitResult {
  const WalletDeleteCommitResult({
    required this.document,
    required this.status,
    required this.cleanup,
  });

  final AccountingDocument document;
  final WalletDeleteCommitStatus status;
  final WalletImageCleanupResult cleanup;
}

abstract interface class WalletLifecycleCoordinator {
  Future<WalletDeleteCommitResult> commitDelete(
    PreparedWalletDeletion prepared,
  );

  Future<WalletImageCleanupResult> recoverPendingCleanup();
}

final class DefaultWalletLifecycleCoordinator
    implements WalletLifecycleCoordinator {
  const DefaultWalletLifecycleCoordinator(
    this.repository,
    this.images,
    this.cleanupJournal,
  );

  final AccountingRepository repository;
  final WalletImageStore images;
  final WalletImageCleanupJournal cleanupJournal;

  @override
  Future<WalletDeleteCommitResult> commitDelete(
    PreparedWalletDeletion prepared,
  ) async {
    switch (prepared.decision) {
      case WalletDeletionDecision.blocked:
        return WalletDeleteCommitResult(
          document: prepared.document,
          status: WalletDeleteCommitStatus.blocked,
          cleanup: _emptyCleanup,
        );
      case WalletDeletionDecision.archive:
        await repository.write(prepared.document);
        return WalletDeleteCommitResult(
          document: prepared.document,
          status: WalletDeleteCommitStatus.archived,
          cleanup: _emptyCleanup,
        );
      case WalletDeletionDecision.delete:
        final existing = await cleanupJournal.readAll();
        final pending = _deduplicate(<WalletImageCleanupIntent>[
          ...existing,
          ...prepared.cleanupIntents,
        ]);
        await cleanupJournal.replaceAll(pending);
        await repository.write(prepared.document);
        final authoritative = await repository.read();
        if (authoritative == null) {
          throw StateError('Committed accounting document could not be read.');
        }
        final cleanup = await _process(authoritative, pending);
        return WalletDeleteCommitResult(
          document: authoritative,
          status: cleanup.pendingRetryImageIds.isEmpty
              ? WalletDeleteCommitStatus.committed
              : WalletDeleteCommitStatus.committedWithPendingCleanup,
          cleanup: cleanup,
        );
    }
  }

  @override
  Future<WalletImageCleanupResult> recoverPendingCleanup() async {
    final pending = _deduplicate(await cleanupJournal.readAll());
    if (pending.isEmpty) return _emptyCleanup;
    final authoritative = await repository.read();
    if (authoritative == null) {
      throw StateError('Accounting document is unavailable for recovery.');
    }
    return _process(authoritative, pending);
  }

  Future<WalletImageCleanupResult> _process(
    AccountingDocument authoritative,
    List<WalletImageCleanupIntent> intents,
  ) async {
    final referencedImageIds = authoritative.wallets
        .map((wallet) => wallet.imageRef?.id)
        .whereType<String>()
        .toSet();
    final deleted = <String>{};
    final stillReferenced = <String>{};
    final pendingRetry = <String>{};
    final retained = <WalletImageCleanupIntent>[];
    for (final intent in intents) {
      if (referencedImageIds.contains(intent.imageRef.id)) {
        stillReferenced.add(intent.imageRef.id);
        continue;
      }
      try {
        await images.deleteIfUnreferenced(intent.imageRef, referencedImageIds);
        deleted.add(intent.imageRef.id);
      } catch (_) {
        pendingRetry.add(intent.imageRef.id);
        retained.add(intent);
      }
    }
    await cleanupJournal.replaceAll(retained);
    return WalletImageCleanupResult(
      deletedImageIds: deleted,
      stillReferencedImageIds: stillReferenced,
      pendingRetryImageIds: pendingRetry,
    );
  }
}

const WalletImageCleanupResult _emptyCleanup = WalletImageCleanupResult(
  deletedImageIds: <String>{},
  stillReferencedImageIds: <String>{},
  pendingRetryImageIds: <String>{},
);

List<WalletImageCleanupIntent> _deduplicate(
  List<WalletImageCleanupIntent> intents,
) {
  final byId = <String, WalletImageCleanupIntent>{};
  for (final intent in intents) {
    byId[intent.id] = intent;
  }
  final ids = byId.keys.toList()..sort();
  return <WalletImageCleanupIntent>[for (final id in ids) byId[id]!];
}
