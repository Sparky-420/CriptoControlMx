import '../domain/wallet.dart';
import '../domain/accounting_movement.dart';
import '../persistence/accounting_document.dart';

enum WalletDeleteBlockReason { movementHistory, reconciliationLink }

enum WalletDeletionDecision { delete, archive, blocked }

final class WalletImageCleanupIntent {
  const WalletImageCleanupIntent({
    required this.id,
    required this.sourceWalletId,
    required this.imageRef,
    required this.createdAt,
  });

  final String id;
  final String sourceWalletId;
  final WalletImageRef imageRef;
  final DateTime createdAt;
}

final class PreparedWalletDeletion {
  const PreparedWalletDeletion({
    required this.document,
    required this.decision,
    required this.cleanupIntents,
    required this.blockReasons,
  });

  final AccountingDocument document;
  final WalletDeletionDecision decision;
  final List<WalletImageCleanupIntent> cleanupIntents;
  final Set<WalletDeleteBlockReason> blockReasons;
}

abstract interface class WalletLifecycleService {
  PreparedWalletDeletion prepareArchive(
    AccountingDocument document,
    String walletId,
    DateTime updatedAt,
  );

  AccountingDocument restore(
    AccountingDocument document,
    String walletId,
    DateTime updatedAt,
  );

  PreparedWalletDeletion prepareDelete(
    AccountingDocument document,
    String walletId,
    DateTime preparedAt,
  );

  PreparedWalletDeletion prepareReassignAndDelete(
    AccountingDocument document, {
    required String sourceWalletId,
    required String targetWalletId,
    required DateTime updatedAt,
  });
}

final class DefaultWalletLifecycleService implements WalletLifecycleService {
  const DefaultWalletLifecycleService();

  @override
  PreparedWalletDeletion prepareArchive(
    AccountingDocument document,
    String walletId,
    DateTime updatedAt,
  ) {
    final wallet = _wallet(document, walletId);
    return PreparedWalletDeletion(
      document: _replaceWallet(
        document,
        _copyWallet(
          wallet,
          status: WalletStatus.archived,
          updatedAt: updatedAt,
        ),
        updatedAt,
      ),
      decision: WalletDeletionDecision.archive,
      cleanupIntents: const <WalletImageCleanupIntent>[],
      blockReasons: const <WalletDeleteBlockReason>{},
    );
  }

  @override
  AccountingDocument restore(
    AccountingDocument document,
    String walletId,
    DateTime updatedAt,
  ) {
    final wallet = _wallet(document, walletId);
    return _replaceWallet(
      document,
      _copyWallet(wallet, status: WalletStatus.active, updatedAt: updatedAt),
      updatedAt,
    );
  }

  @override
  PreparedWalletDeletion prepareDelete(
    AccountingDocument document,
    String walletId,
    DateTime preparedAt,
  ) {
    final wallet = _wallet(document, walletId);
    final referencedMovementIds = document.movements
        .where(
          (movement) =>
              movement.sourceWalletId == walletId ||
              movement.destinationWalletId == walletId ||
              movement.adjustmentWalletId == walletId,
        )
        .map((movement) => movement.id)
        .toSet();
    final reasons = <WalletDeleteBlockReason>{};
    if (referencedMovementIds.isNotEmpty) {
      reasons.add(WalletDeleteBlockReason.movementHistory);
    }
    if (document.movements.any(
      (movement) =>
          (referencedMovementIds.contains(movement.id) &&
              movement.reconciliationLinks.isNotEmpty) ||
          movement.reconciliationLinks.any(
            (link) => referencedMovementIds.contains(link.adjustmentMovementId),
          ),
    )) {
      reasons.add(WalletDeleteBlockReason.reconciliationLink);
    }
    if (reasons.isNotEmpty) {
      return PreparedWalletDeletion(
        document: document,
        decision: WalletDeletionDecision.blocked,
        cleanupIntents: const <WalletImageCleanupIntent>[],
        blockReasons: reasons,
      );
    }
    final imageRef = wallet.imageRef;
    return PreparedWalletDeletion(
      document: _withoutWallet(document, walletId, preparedAt),
      decision: WalletDeletionDecision.delete,
      cleanupIntents: imageRef == null
          ? const <WalletImageCleanupIntent>[]
          : <WalletImageCleanupIntent>[
              WalletImageCleanupIntent(
                id: 'delete:$walletId:${imageRef.id}',
                sourceWalletId: walletId,
                imageRef: imageRef,
                createdAt: preparedAt,
              ),
            ],
      blockReasons: const <WalletDeleteBlockReason>{},
    );
  }

  @override
  PreparedWalletDeletion prepareReassignAndDelete(
    AccountingDocument document, {
    required String sourceWalletId,
    required String targetWalletId,
    required DateTime updatedAt,
  }) {
    final source = _wallet(document, sourceWalletId);
    final target = _wallet(document, targetWalletId);
    if (sourceWalletId == targetWalletId) {
      throw ArgumentError('Las carteras origen y destino deben ser distintas.');
    }
    if (target.status != WalletStatus.active) {
      throw ArgumentError.value(
        targetWalletId,
        'targetWalletId',
        'La cartera destino debe estar activa.',
      );
    }
    final replacements = <AccountingMovement>[];
    for (final movement in document.movements) {
      final reassigned = movement.copyWith(
        sourceWalletId: movement.sourceWalletId == sourceWalletId
            ? targetWalletId
            : movement.sourceWalletId,
        destinationWalletId: movement.destinationWalletId == sourceWalletId
            ? targetWalletId
            : movement.destinationWalletId,
        adjustmentWalletId: movement.adjustmentWalletId == sourceWalletId
            ? targetWalletId
            : movement.adjustmentWalletId,
        updatedAt:
            movement.sourceWalletId == sourceWalletId ||
                movement.destinationWalletId == sourceWalletId ||
                movement.adjustmentWalletId == sourceWalletId
            ? updatedAt
            : movement.updatedAt,
      );
      if (reassigned.destinationType == DestinationType.ownWallet &&
          reassigned.sourceWalletId != null &&
          reassigned.sourceWalletId == reassigned.destinationWalletId) {
        throw ArgumentError(
          'Una transferencia interna requiere carteras distintas.',
        );
      }
      replacements.add(reassigned);
    }
    final reassignedDocument = AccountingDocument(
      schemaVersion: document.schemaVersion,
      wallets: <Wallet>[
        for (final wallet in document.wallets)
          if (wallet.id != sourceWalletId) wallet,
      ],
      movements: replacements,
      appliedMigrationIds: document.appliedMigrationIds,
      updatedAt: updatedAt,
      legacyMovementMetadata: document.legacyMovementMetadata,
      legacyMovementMigrationMetadata: document.legacyMovementMigrationMetadata,
      legacyMigrationProblems: document.legacyMigrationProblems,
      assignmentAudits: document.assignmentAudits,
      legacyAccountingPolicy: document.legacyAccountingPolicy,
    );
    final imageRef = source.imageRef;
    return PreparedWalletDeletion(
      document: reassignedDocument,
      decision: WalletDeletionDecision.delete,
      cleanupIntents: imageRef == null
          ? const <WalletImageCleanupIntent>[]
          : <WalletImageCleanupIntent>[
              WalletImageCleanupIntent(
                id: 'delete:$sourceWalletId:${imageRef.id}',
                sourceWalletId: sourceWalletId,
                imageRef: imageRef,
                createdAt: updatedAt,
              ),
            ],
      blockReasons: const <WalletDeleteBlockReason>{},
    );
  }
}

Wallet _wallet(AccountingDocument document, String walletId) {
  if (walletId.startsWith('virtual:')) {
    throw ArgumentError.value(
      walletId,
      'walletId',
      'Debe ser una cartera real.',
    );
  }
  for (final wallet in document.wallets) {
    if (wallet.id == walletId) return wallet;
  }
  throw ArgumentError.value(walletId, 'walletId', 'Cartera inexistente.');
}

Wallet _copyWallet(
  Wallet wallet, {
  required WalletStatus status,
  required DateTime updatedAt,
}) => Wallet(
  id: wallet.id,
  name: wallet.name,
  provider: wallet.provider,
  status: status,
  createdAt: wallet.createdAt,
  updatedAt: updatedAt,
  imageRef: wallet.imageRef,
  colorArgb: wallet.colorArgb,
  note: wallet.note,
  schemaVersion: wallet.schemaVersion,
);

AccountingDocument _replaceWallet(
  AccountingDocument document,
  Wallet replacement,
  DateTime updatedAt,
) => AccountingDocument(
  schemaVersion: document.schemaVersion,
  wallets: <Wallet>[
    for (final wallet in document.wallets)
      if (wallet.id == replacement.id) replacement else wallet,
  ],
  movements: document.movements,
  appliedMigrationIds: document.appliedMigrationIds,
  updatedAt: updatedAt,
  legacyMovementMetadata: document.legacyMovementMetadata,
  legacyMovementMigrationMetadata: document.legacyMovementMigrationMetadata,
  legacyMigrationProblems: document.legacyMigrationProblems,
  assignmentAudits: document.assignmentAudits,
  legacyAccountingPolicy: document.legacyAccountingPolicy,
);

AccountingDocument _withoutWallet(
  AccountingDocument document,
  String walletId,
  DateTime updatedAt,
) => AccountingDocument(
  schemaVersion: document.schemaVersion,
  wallets: <Wallet>[
    for (final wallet in document.wallets)
      if (wallet.id != walletId) wallet,
  ],
  movements: document.movements,
  appliedMigrationIds: document.appliedMigrationIds,
  updatedAt: updatedAt,
  legacyMovementMetadata: document.legacyMovementMetadata,
  legacyMovementMigrationMetadata: document.legacyMovementMigrationMetadata,
  legacyMigrationProblems: document.legacyMigrationProblems,
  assignmentAudits: document.assignmentAudits,
  legacyAccountingPolicy: document.legacyAccountingPolicy,
);
