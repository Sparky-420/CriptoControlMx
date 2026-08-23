import '../../accounting/domain/wallet.dart';
import '../../accounting/persistence/accounting_document.dart';
import '../../accounting/persistence/accounting_repository.dart';

final class WalletEditResult {
  const WalletEditResult({required this.document, required this.wallet});

  final AccountingDocument document;
  final Wallet wallet;
}

final class DefaultWalletEditService {
  const DefaultWalletEditService(this.repository);

  final AccountingRepository repository;

  Future<WalletEditResult> createWallet(
    AccountingDocument current, {
    required String id,
    required String name,
    required String provider,
    required DateTime now,
  }) async {
    final wallet = Wallet.create(
      id: id,
      name: name,
      provider: provider,
      createdAt: now,
    );
    final document = _copyDocument(
      current,
      wallets: <Wallet>[...current.wallets, wallet],
      updatedAt: now,
    );
    await repository.write(document);
    return WalletEditResult(document: document, wallet: wallet);
  }

  Future<WalletEditResult> updateWallet(
    AccountingDocument current, {
    required String walletId,
    required String name,
    required String provider,
    required DateTime now,
  }) async {
    final index = current.wallets.indexWhere((wallet) => wallet.id == walletId);
    if (index < 0) {
      throw StateError('Wallet not found: $walletId');
    }
    final existing = current.wallets[index];
    final normalized = Wallet.create(
      id: existing.id,
      name: name,
      provider: provider,
      createdAt: existing.createdAt,
    );
    final wallet = Wallet(
      id: existing.id,
      name: normalized.name,
      provider: normalized.provider,
      status: existing.status,
      createdAt: existing.createdAt,
      updatedAt: now,
      imageRef: existing.imageRef,
      colorArgb: existing.colorArgb,
      note: existing.note,
      schemaVersion: existing.schemaVersion,
    );
    final wallets = <Wallet>[...current.wallets];
    wallets[index] = wallet;
    final document = _copyDocument(current, wallets: wallets, updatedAt: now);
    await repository.write(document);
    return WalletEditResult(document: document, wallet: wallet);
  }
}

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
