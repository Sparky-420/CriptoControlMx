import '../domain/accounting_amount.dart';
import '../domain/accounting_movement.dart';
import '../domain/ledger_validation.dart';

final class WalletAssetKey {
  const WalletAssetKey(this.walletId, this.asset);

  final String walletId;
  final String asset;

  @override
  bool operator ==(Object other) =>
      other is WalletAssetKey &&
      other.walletId == walletId &&
      other.asset == asset;

  @override
  int get hashCode => Object.hash(walletId, asset);
}

final class CustodyPosition {
  const CustodyPosition({
    required this.reconciledQuantity,
    required this.appliedCredits,
    required this.appliedDebits,
    required this.signedAdjustments,
    required this.resolvedAdjustmentQuantity,
    required this.requestedQuantity,
    required this.unappliedQuantity,
    required this.contributingMovementIds,
    required this.issues,
    this.lastObservedBalance,
  });

  final AccountingAmount reconciledQuantity;
  final AccountingAmount appliedCredits;
  final AccountingAmount appliedDebits;
  final AccountingAmount signedAdjustments;
  final AccountingAmount resolvedAdjustmentQuantity;
  final AccountingAmount? lastObservedBalance;
  final AccountingAmount requestedQuantity;
  final AccountingAmount unappliedQuantity;
  final List<String> contributingMovementIds;
  final List<ProjectionIssue> issues;
}

final class CustodyProjection {
  const CustodyProjection(
    this.positions,
    this.adjustmentHistory,
    this.effectsByMovementId,
  );

  final Map<WalletAssetKey, CustodyPosition> positions;
  final List<AccountingMovement> adjustmentHistory;
  final Map<String, List<CustodyMovementEffect>> effectsByMovementId;

  List<CustodyMovementEffect> effectsFor(String movementId) =>
      effectsByMovementId[movementId] ?? const <CustodyMovementEffect>[];
}

final class CustodyMovementEffect {
  const CustodyMovementEffect({
    required this.key,
    required this.before,
    required this.requested,
    required this.applied,
    required this.unapplied,
    required this.after,
  });

  final WalletAssetKey key;
  final AccountingAmount before;
  final AccountingAmount requested;
  final AccountingAmount applied;
  final AccountingAmount unapplied;
  final AccountingAmount after;
}
