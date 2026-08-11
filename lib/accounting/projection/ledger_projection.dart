import '../domain/accounting_amount.dart';
import '../domain/ledger_validation.dart';
import '../domain/wallet.dart';
import 'custody_projection.dart';
import 'fee_effect.dart';
import 'performance_projection.dart';

const String virtualUnassignedWalletId = 'virtual:unassigned';
const String virtualPendingWalletId = 'virtual:pending';
const String virtualUnknownWalletId = 'virtual:unknown';

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
    required this.availability,
    required this.completeness,
    required this.custodyMarketValue,
    required this.knownPositionMarketValue,
  });

  final WalletAssetKey key;
  final CustodyPosition custody;
  final PerformancePosition performance;
  final PositionAvailability availability;
  final AccountingCompletenessResult completeness;
  final AccountingAmount custodyMarketValue;
  final AccountingAmount knownPositionMarketValue;

  AccountingAmount get reconciliationDifference =>
      availability.reconciliationDifference;

  AccountingAmount get knownAvailable => availability.knownAvailable;

  AccountingAmount get unknownAvailable => availability.unknownAvailable;

  AccountingAmount get custodyDeficit => availability.custodyDeficit;
}

final class PositionAvailability {
  const PositionAvailability({
    required this.reconciliationDifference,
    required this.knownAvailable,
    required this.unknownAvailable,
    required this.custodyDeficit,
  });

  factory PositionAvailability.derive({
    required AccountingAmount custodyQuantity,
    required AccountingAmount knownQuantity,
  }) {
    final knownAvailable = knownQuantity
        .min(custodyQuantity)
        .max(AccountingAmount.zero);
    return PositionAvailability(
      reconciliationDifference: custodyQuantity - knownQuantity,
      knownAvailable: knownAvailable,
      unknownAvailable: (custodyQuantity - knownAvailable).max(
        AccountingAmount.zero,
      ),
      custodyDeficit: (knownQuantity - custodyQuantity).max(
        AccountingAmount.zero,
      ),
    );
  }

  final AccountingAmount reconciliationDifference;
  final AccountingAmount knownAvailable;
  final AccountingAmount unknownAvailable;
  final AccountingAmount custodyDeficit;
}

final class MovementCustodyLegEffect {
  const MovementCustodyLegEffect({
    required this.key,
    required this.kind,
    required this.before,
    required this.requested,
    required this.applied,
    required this.unapplied,
    required this.after,
  });

  final WalletAssetKey key;
  final LedgerLegKind kind;
  final AccountingAmount before;
  final AccountingAmount requested;
  final AccountingAmount applied;
  final AccountingAmount unapplied;
  final AccountingAmount after;
}

final class MovementEffect {
  factory MovementEffect({
    required String movementId,
    required AccountingAmount requestedQuantity,
    required AccountingAmount appliedQuantity,
    required AccountingAmount unappliedQuantity,
    required List<MovementCustodyLegEffect> custodyLegs,
    required Map<String, AccountingAmount> globalDeltasByAsset,
    required FeeEffect feeEffect,
    required List<ProjectionIssue> issues,
    TransferAllocation? transferAllocation,
    SaleResult? sale,
  }) => MovementEffect._(
    movementId: movementId,
    requestedQuantity: requestedQuantity,
    appliedQuantity: appliedQuantity,
    unappliedQuantity: unappliedQuantity,
    custodyLegs: List<MovementCustodyLegEffect>.unmodifiable(
      List<MovementCustodyLegEffect>.of(custodyLegs),
    ),
    globalDeltasByAsset: Map<String, AccountingAmount>.unmodifiable(
      Map<String, AccountingAmount>.of(globalDeltasByAsset),
    ),
    feeEffect: feeEffect,
    issues: List<ProjectionIssue>.unmodifiable(
      List<ProjectionIssue>.of(issues),
    ),
    transferAllocation: transferAllocation,
    sale: sale,
  );

  const MovementEffect._({
    required this.movementId,
    required this.requestedQuantity,
    required this.appliedQuantity,
    required this.unappliedQuantity,
    required this.custodyLegs,
    required this.globalDeltasByAsset,
    required this.feeEffect,
    required this.issues,
    this.transferAllocation,
    this.sale,
  });

  final String movementId;
  final AccountingAmount requestedQuantity;
  final AccountingAmount appliedQuantity;
  final AccountingAmount unappliedQuantity;
  final List<MovementCustodyLegEffect> custodyLegs;
  final Map<String, AccountingAmount> globalDeltasByAsset;
  final FeeEffect feeEffect;
  final TransferAllocation? transferAllocation;
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
    required this.fiatCostEffect,
  });

  final AccountingAmount custodyMarketValue;
  final AccountingAmount knownPositionMarketValue;
  final AccountingAmount knownCostBasis;
  final AccountingAmount realizedPnlKnown;
  final AccountingAmount unrealizedPnlKnown;
  final AccountingAmount fiatCostEffect;
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
