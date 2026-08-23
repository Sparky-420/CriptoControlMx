import '../../accounting/domain/accounting_amount.dart';
import '../../accounting/domain/accounting_movement.dart';
import '../../accounting/domain/movement_normalizer.dart';
import '../../accounting/domain/movement_type.dart';
import '../../accounting/domain/wallet.dart';
import '../../accounting/persistence/accounting_document.dart';
import '../../accounting/projection/accounting_ledger_engine.dart';
import '../../accounting/projection/custody_projector.dart';
import '../../accounting/projection/performance_projector.dart';

final class WalletAssetSummary {
  const WalletAssetSummary({
    required this.asset,
    required this.reconciledQuantity,
    required this.knownQuantity,
    required this.knownCostBasis,
    required this.completeness,
  });

  final String asset;
  final AccountingAmount reconciledQuantity;
  final AccountingAmount knownQuantity;
  final AccountingAmount knownCostBasis;
  final AccountingCompleteness completeness;
}

final class WalletPortfolioSummary {
  const WalletPortfolioSummary({
    required this.wallet,
    required this.assignedMovementCount,
    required this.positions,
  });

  final Wallet wallet;
  final int assignedMovementCount;
  final List<WalletAssetSummary> positions;

  List<String> get assets =>
      positions.map((position) => position.asset).toList(growable: false);

  bool get hasAssignedMovements => assignedMovementCount > 0;

  bool get hasIncompleteData => positions.any(
    (position) => position.completeness != AccountingCompleteness.complete,
  );

  Set<AccountingCompleteness> get completenessStates =>
      positions.map((position) => position.completeness).toSet();

  AccountingAmount get knownCostBasis => positions.fold(
    AccountingAmount.zero,
    (total, position) => total + position.knownCostBasis,
  );
}

final class DefaultWalletPortfolioSummaryService {
  const DefaultWalletPortfolioSummaryService({
    this.ledgerEngine = const AccountingLedgerEngine(
      DefaultMovementNormalizer(),
      DefaultCustodyProjector(),
      DefaultPerformanceProjector(),
    ),
  });

  final AccountingLedgerEngine ledgerEngine;

  List<WalletPortfolioSummary> summarize(AccountingDocument document) {
    final projection = ledgerEngine.project(
      LedgerInput(
        wallets: document.wallets,
        movements: document.movements,
        currentPrices: const <String, AccountingAmount>{},
        saleCostConsumptionPolicy: SaleCostConsumptionPolicy.knownFirst,
        transferCostAllocationPolicy: TransferCostAllocationPolicy.proportional,
        legacyAccountingPolicy: document.legacyAccountingPolicy,
      ),
    );
    return <WalletPortfolioSummary>[
      for (final wallet in document.wallets)
        WalletPortfolioSummary(
          wallet: wallet,
          assignedMovementCount: document.movements
              .where((movement) => _referencesWallet(movement, wallet.id))
              .length,
          positions:
              projection.positions.entries
                  .where((entry) => entry.key.walletId == wallet.id)
                  .map(
                    (entry) => WalletAssetSummary(
                      asset: entry.key.asset,
                      reconciledQuantity:
                          entry.value.custody.reconciledQuantity,
                      knownQuantity: entry.value.performance.knownQuantity,
                      knownCostBasis: entry.value.performance.knownCostBasis,
                      completeness: entry.value.completeness.state,
                    ),
                  )
                  .toList(growable: false)
                ..sort((a, b) => a.asset.compareTo(b.asset)),
        ),
    ];
  }
}

bool _referencesWallet(AccountingMovement movement, String walletId) =>
    switch (movement.type) {
      MovementType.buy ||
      MovementType.transferIn => movement.destinationWalletId == walletId,
      MovementType.sell => movement.sourceWalletId == walletId,
      MovementType.transferOut =>
        movement.sourceWalletId == walletId ||
            movement.destinationWalletId == walletId,
      MovementType.balanceAdjustment => movement.adjustmentWalletId == walletId,
    };
