import '../domain/accounting_amount.dart';
import '../domain/accounting_movement.dart';
import '../domain/ledger_validation.dart';
import '../domain/movement_type.dart';
import '../domain/wallet.dart';
import 'custody_projection.dart';
import 'performance_projection.dart';

abstract interface class PerformanceProjector {
  PerformanceProjection project(
    NormalizedLedger ledger,
    CustodyProjection custody,
    Map<String, AccountingAmount> currentPrices, {
    required SaleCostConsumptionPolicy salePolicy,
    required TransferCostAllocationPolicy transferPolicy,
  });
}

final class DefaultPerformanceProjector implements PerformanceProjector {
  const DefaultPerformanceProjector();

  @override
  PerformanceProjection project(
    NormalizedLedger ledger,
    CustodyProjection custody,
    Map<String, AccountingAmount> currentPrices, {
    required SaleCostConsumptionPolicy salePolicy,
    required TransferCostAllocationPolicy transferPolicy,
  }) {
    final states = <WalletAssetKey, _PerformanceState>{};
    final sales = <SaleResult>[];

    for (final movement in ledger.movements) {
      switch (movement.type) {
        case MovementType.buy:
          _applyBuy(movement, states);
        case MovementType.sell:
          final result = _applySale(movement, states, custody, salePolicy);
          if (result != null) sales.add(result);
        case MovementType.transferIn:
        case MovementType.transferOut:
        case MovementType.balanceAdjustment:
          break;
      }
    }

    final positions = <WalletAssetKey, PerformancePosition>{
      for (final entry in states.entries)
        entry.key: entry.value.toPosition(
          currentPrices[entry.key.asset] ?? AccountingAmount.zero,
        ),
    };
    return PerformanceProjection(
      Map<WalletAssetKey, PerformancePosition>.unmodifiable(positions),
      List<SaleResult>.unmodifiable(sales),
    );
  }

  void _applyBuy(
    AccountingMovement movement,
    Map<WalletAssetKey, _PerformanceState> states,
  ) {
    final walletId = movement.destinationWalletId;
    final quantity = movement.quantity;
    final unitPrice = movement.unitPriceFiat;
    if (walletId == null || quantity == null) return;

    final state = states.putIfAbsent(
      WalletAssetKey(walletId, movement.asset),
      _PerformanceState.new,
    );
    if (unitPrice == null) {
      state.block(movement.id);
      return;
    }
    final cost = (quantity * unitPrice) + movement.fiatFeeAmount;
    state.knownQuantity = state.knownQuantity + quantity;
    state.knownCostBasis = state.knownCostBasis + cost;
    state.investedCapital = state.investedCapital + cost;
  }

  SaleResult? _applySale(
    AccountingMovement movement,
    Map<WalletAssetKey, _PerformanceState> states,
    CustodyProjection custody,
    SaleCostConsumptionPolicy salePolicy,
  ) {
    final walletId = movement.sourceWalletId;
    final requestedQuantity = movement.quantity;
    final unitPrice = movement.unitPriceFiat;
    if (walletId == null || requestedQuantity == null || unitPrice == null) {
      return null;
    }

    final key = WalletAssetKey(walletId, movement.asset);
    final state = states.putIfAbsent(key, _PerformanceState.new);
    final effect = custody
        .effectsFor(movement.id)
        .where((value) => value.key == key)
        .firstOrNull;
    final appliedQuantity = effect == null
        ? AccountingAmount.zero
        : AccountingAmount.zero - effect.applied;
    final insufficientCustody =
        effect == null || effect.unapplied != AccountingAmount.zero;
    if (insufficientCustody) {
      state.block(movement.id);
      state.addIssues(custody.positions[key]?.issues);
      return SaleResult(
        movementId: movement.id,
        status: SaleAccountingStatus.insufficientCustody,
        totalQuantity: requestedQuantity,
        knownQuantity: AccountingAmount.zero,
        demonstratedCostBasis: AccountingAmount.zero,
        knownProceeds: AccountingAmount.zero,
        allocatedKnownFiatFee: AccountingAmount.zero,
        realizedPnlKnown: AccountingAmount.zero,
        pendingCostQuantity: AccountingAmount.zero,
      );
    }
    final knownQuantity = switch (salePolicy) {
      SaleCostConsumptionPolicy.knownFirst => appliedQuantity.min(
        state.knownQuantity,
      ),
    };
    final average = state.averageCost;
    final demonstratedCost = average * knownQuantity;
    final knownProceeds = unitPrice * knownQuantity;
    final allocatedFee = requestedQuantity == AccountingAmount.zero
        ? AccountingAmount.zero
        : (movement.fiatFeeAmount * knownQuantity).divide(requestedQuantity);
    final realizedPnl = knownProceeds - allocatedFee - demonstratedCost;
    final pendingQuantity = appliedQuantity - knownQuantity;
    final status = pendingQuantity == AccountingAmount.zero
        ? SaleAccountingStatus.complete
        : SaleAccountingStatus.partiallyKnown;

    state.knownQuantity = state.knownQuantity - knownQuantity;
    state.knownCostBasis = state.knownCostBasis - demonstratedCost;
    state.realizedPnlKnown = state.realizedPnlKnown + realizedPnl;
    if (pendingQuantity != AccountingAmount.zero) {
      state.pendingPnlQuantity = state.pendingPnlQuantity + pendingQuantity;
    }
    if (status != SaleAccountingStatus.complete) {
      state.block(movement.id);
      state.addIssues(custody.positions[key]?.issues);
    }

    return SaleResult(
      movementId: movement.id,
      status: status,
      totalQuantity: requestedQuantity,
      knownQuantity: knownQuantity,
      demonstratedCostBasis: demonstratedCost,
      knownProceeds: knownProceeds,
      allocatedKnownFiatFee: allocatedFee,
      realizedPnlKnown: realizedPnl,
      pendingCostQuantity: pendingQuantity,
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

final class _PerformanceState {
  AccountingAmount knownQuantity = AccountingAmount.zero;
  AccountingAmount knownCostBasis = AccountingAmount.zero;
  AccountingAmount investedCapital = AccountingAmount.zero;
  AccountingAmount realizedPnlKnown = AccountingAmount.zero;
  AccountingAmount pendingPnlQuantity = AccountingAmount.zero;
  final blockingMovementIds = <String>[];
  final issues = <ProjectionIssue>[];

  AccountingAmount get averageCost => knownQuantity == AccountingAmount.zero
      ? AccountingAmount.zero
      : knownCostBasis.divide(knownQuantity);

  void block(String movementId) {
    if (!blockingMovementIds.contains(movementId)) {
      blockingMovementIds.add(movementId);
    }
  }

  void addIssues(List<ProjectionIssue>? values) {
    if (values == null) return;
    for (final value in values) {
      if (!issues.any(
        (existing) =>
            existing.code == value.code &&
            existing.movementId == value.movementId,
      )) {
        issues.add(value);
      }
    }
  }

  PerformancePosition toPosition(AccountingAmount currentPrice) {
    final average = averageCost;
    return PerformancePosition(
      knownQuantity: knownQuantity,
      knownCostBasis: knownCostBasis,
      averageCost: average,
      investedCapital: investedCapital,
      realizedPnlKnown: realizedPnlKnown,
      unrealizedPnlKnown: (knownQuantity * currentPrice) - knownCostBasis,
      pendingPnlQuantity: pendingPnlQuantity,
      blockingMovementIds: List<String>.unmodifiable(blockingMovementIds),
      issues: List<ProjectionIssue>.unmodifiable(issues),
    );
  }
}
