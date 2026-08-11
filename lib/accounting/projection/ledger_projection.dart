import '../domain/accounting_amount.dart';
import '../domain/ledger_validation.dart';
import '../domain/wallet.dart';
import 'custody_projection.dart';
import 'performance_projection.dart';

const String virtualUnassignedWalletId = 'virtual:unassigned';
const String virtualPendingWalletId = 'virtual:pending';

final class AccountingCompletenessResult {
  const AccountingCompletenessResult({
    required this.state,
    required this.totalQuantity,
    required this.knownQuantity,
    required this.unknownQuantity,
    required this.cause,
    required this.causingMovementIds,
  });

  final AccountingCompleteness state;
  final AccountingAmount totalQuantity;
  final AccountingAmount knownQuantity;
  final AccountingAmount unknownQuantity;
  final ProjectionIssueCode? cause;
  final List<String> causingMovementIds;
}

final class WalletAssetProjection {
  const WalletAssetProjection({
    required this.key,
    required this.custody,
    required this.performance,
    required this.completeness,
    required this.custodyMarketValue,
    required this.knownPositionMarketValue,
  });

  final WalletAssetKey key;
  final CustodyPosition custody;
  final PerformancePosition performance;
  final AccountingCompletenessResult completeness;
  final AccountingAmount custodyMarketValue;
  final AccountingAmount knownPositionMarketValue;

  AccountingAmount get reconciliationDifference =>
      custody.reconciledQuantity - performance.knownQuantity;

  AccountingAmount get knownAvailable => performance.knownQuantity
      .min(custody.reconciledQuantity)
      .max(AccountingAmount.zero);

  AccountingAmount get unknownAvailable =>
      (custody.reconciledQuantity - knownAvailable).max(AccountingAmount.zero);

  AccountingAmount get custodyDeficit =>
      (performance.knownQuantity - custody.reconciledQuantity).max(
        AccountingAmount.zero,
      );
}

final class MovementEffect {
  const MovementEffect({
    required this.movementId,
    required this.requestedQuantity,
    required this.appliedQuantity,
    required this.unappliedQuantity,
    required this.issues,
    this.sale,
  });

  final String movementId;
  final AccountingAmount requestedQuantity;
  final AccountingAmount appliedQuantity;
  final AccountingAmount unappliedQuantity;
  final List<ProjectionIssue> issues;
  final SaleResult? sale;
}

final class LedgerTotals {
  const LedgerTotals({
    required this.custodyMarketValue,
    required this.knownPositionMarketValue,
    required this.knownCostBasis,
    required this.realizedPnlKnown,
    required this.unrealizedPnlKnown,
  });

  final AccountingAmount custodyMarketValue;
  final AccountingAmount knownPositionMarketValue;
  final AccountingAmount knownCostBasis;
  final AccountingAmount realizedPnlKnown;
  final AccountingAmount unrealizedPnlKnown;
}

final class MigrationProgress {
  const MigrationProgress({required this.assigned, required this.total});

  final int assigned;
  final int total;
}

final class LedgerProjection {
  const LedgerProjection({
    required this.positions,
    required this.sales,
    required this.effects,
    required this.totals,
    required this.issues,
    required this.migrationProgress,
  });

  final Map<WalletAssetKey, WalletAssetProjection> positions;
  final List<SaleResult> sales;
  final Map<String, MovementEffect> effects;
  final LedgerTotals totals;
  final List<ProjectionIssue> issues;
  final MigrationProgress migrationProgress;
}
