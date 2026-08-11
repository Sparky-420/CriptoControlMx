import '../domain/accounting_amount.dart';
import '../domain/accounting_movement.dart';
import '../domain/ledger_validation.dart';
import '../domain/movement_type.dart';
import '../domain/wallet.dart';
import 'custody_projection.dart';
import 'fee_effect.dart';
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
    final transferAllocations = <String, TransferAllocation>{};
    final appliedMovementIds = <String>{};

    for (final movement in ledger.movements) {
      if (!ledger.acceptedMovementIds.contains(movement.id)) continue;
      if (!appliedMovementIds.add(movement.id)) continue;
      switch (movement.type) {
        case MovementType.buy:
          _applyBuy(movement, states);
        case MovementType.sell:
          final result = _applySale(movement, states, custody, salePolicy);
          if (result != null) sales.add(result);
        case MovementType.transferIn:
          _applyBuy(movement, states);
        case MovementType.transferOut:
          final allocation = _applyTransfer(
            movement,
            states,
            custody,
            transferPolicy,
          );
          if (allocation != null) {
            transferAllocations[movement.id] = allocation;
          }
          break;
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
      transferAllocations: Map<String, TransferAllocation>.unmodifiable(
        transferAllocations,
      ),
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
    final knownQuantity = switch (salePolicy) {
      SaleCostConsumptionPolicy.knownFirst => appliedQuantity.min(
        state.knownQuantity,
      ),
    };
    final knownQuantityBefore = state.knownQuantity;
    final knownCostBasisBefore = state.knownCostBasis;
    final consumesAllKnown =
        knownQuantity.compareTo(AccountingAmount.zero) > 0 &&
        knownQuantity == knownQuantityBefore;
    final average = state.averageCost;
    final demonstratedCost = consumesAllKnown
        ? knownCostBasisBefore
        : average * knownQuantity;
    final knownProceeds = unitPrice * knownQuantity;
    final allocatedFee = requestedQuantity == AccountingAmount.zero
        ? AccountingAmount.zero
        : (movement.fiatFeeAmount * knownQuantity).divide(requestedQuantity);
    final realizedPnl = knownProceeds - allocatedFee - demonstratedCost;
    final pendingQuantity = appliedQuantity - knownQuantity;
    final status = insufficientCustody
        ? SaleAccountingStatus.insufficientCustody
        : pendingQuantity == AccountingAmount.zero
        ? SaleAccountingStatus.complete
        : SaleAccountingStatus.partiallyKnown;

    state.knownQuantity = knownQuantityBefore - knownQuantity;
    state.knownCostBasis = consumesAllKnown
        ? AccountingAmount.zero
        : knownCostBasisBefore - demonstratedCost;
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

  TransferAllocation? _applyTransfer(
    AccountingMovement movement,
    Map<WalletAssetKey, _PerformanceState> states,
    CustodyProjection custody,
    TransferCostAllocationPolicy policy,
  ) {
    final sourceWalletId = movement.sourceWalletId;
    if (sourceWalletId == null) return null;
    final sourceKey = WalletAssetKey(sourceWalletId, movement.asset);
    final sourceEffect = custody
        .effectsFor(movement.id)
        .where(
          (effect) =>
              effect.key == sourceKey &&
              effect.requested.compareTo(AccountingAmount.zero) < 0,
        )
        .firstOrNull;
    if (sourceEffect == null) return null;

    final sourceState = states.putIfAbsent(sourceKey, _PerformanceState.new);
    final removal = _removeProportionally(
      state: sourceState,
      custodyBefore: sourceEffect.before.max(AccountingAmount.zero),
      appliedDebit: _absolute(sourceEffect.applied),
      policy: policy,
    );

    if (movement.destinationType == DestinationType.ownWallet &&
        movement.destinationWalletId != null) {
      final destinationKey = WalletAssetKey(
        movement.destinationWalletId!,
        movement.asset,
      );
      final creditEffect = custody
          .effectsFor(movement.id)
          .where(
            (effect) =>
                effect.key == destinationKey &&
                effect.requested.compareTo(AccountingAmount.zero) > 0,
          )
          .firstOrNull;
      if (creditEffect != null) {
        final principal = allocateTransferProportionally(
          custodyBefore: sourceEffect.before.max(AccountingAmount.zero),
          knownAvailable: removal.knownAvailableBefore,
          knownCostBasis: removal.knownCostBasisBefore,
          totalDebited: creditEffect.applied,
        );
        final destinationState = states.putIfAbsent(
          destinationKey,
          _PerformanceState.new,
        );
        destinationState.knownQuantity =
            destinationState.knownQuantity + principal.knownQuantity;
        destinationState.knownCostBasis =
            destinationState.knownCostBasis + principal.transferredCostBasis;
      }
    }

    for (final fee in resolveFeeEffect(
      movement,
    ).otherAssetCustodyDebit.entries) {
      final feeKey = WalletAssetKey(sourceWalletId, fee.key);
      final feeCustodyEffect = custody
          .effectsFor(movement.id)
          .where(
            (effect) =>
                effect.key == feeKey &&
                effect.requested.compareTo(AccountingAmount.zero) < 0,
          )
          .firstOrNull;
      if (feeCustodyEffect == null) continue;
      final feeState = states.putIfAbsent(feeKey, _PerformanceState.new);
      _removeProportionally(
        state: feeState,
        custodyBefore: feeCustodyEffect.before.max(AccountingAmount.zero),
        appliedDebit: _absolute(feeCustodyEffect.applied),
        policy: policy,
      );
    }

    return removal;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

TransferAllocation allocateTransferProportionally({
  required AccountingAmount custodyBefore,
  required AccountingAmount knownAvailable,
  required AccountingAmount knownCostBasis,
  required AccountingAmount totalDebited,
}) {
  if (custodyBefore == AccountingAmount.zero ||
      totalDebited == AccountingAmount.zero) {
    return TransferAllocation(
      totalDebited: AccountingAmount.zero,
      knownQuantity: AccountingAmount.zero,
      unknownQuantity: AccountingAmount.zero,
      transferredCostBasis: AccountingAmount.zero,
    );
  }
  final availableKnown = knownAvailable
      .max(AccountingAmount.zero)
      .min(custodyBefore);
  final knownQuantity = availableKnown == AccountingAmount.zero
      ? AccountingAmount.zero
      : availableKnown == custodyBefore || totalDebited == custodyBefore
      ? availableKnown.min(totalDebited)
      : (totalDebited * availableKnown).divide(custodyBefore);
  final unknownQuantity = totalDebited - knownQuantity;
  final transferredCostBasis = knownQuantity == AccountingAmount.zero
      ? AccountingAmount.zero
      : knownQuantity == availableKnown
      ? knownCostBasis
      : (knownCostBasis * totalDebited).divide(custodyBefore);
  return TransferAllocation(
    totalDebited: totalDebited,
    knownQuantity: knownQuantity,
    unknownQuantity: unknownQuantity,
    transferredCostBasis: transferredCostBasis,
  );
}

final class _TransferRemoval extends TransferAllocation {
  const _TransferRemoval({
    required super.totalDebited,
    required super.knownQuantity,
    required super.unknownQuantity,
    required super.transferredCostBasis,
    required this.knownAvailableBefore,
    required this.knownCostBasisBefore,
  });

  final AccountingAmount knownAvailableBefore;
  final AccountingAmount knownCostBasisBefore;
}

_TransferRemoval _removeProportionally({
  required _PerformanceState state,
  required AccountingAmount custodyBefore,
  required AccountingAmount appliedDebit,
  required TransferCostAllocationPolicy policy,
}) {
  final knownAvailable = state.knownQuantity.min(custodyBefore);
  final knownCostBasis = state.knownQuantity == AccountingAmount.zero
      ? AccountingAmount.zero
      : (state.knownCostBasis * knownAvailable).divide(state.knownQuantity);
  final allocation = switch (policy) {
    TransferCostAllocationPolicy.proportional => allocateTransferProportionally(
      custodyBefore: custodyBefore,
      knownAvailable: knownAvailable,
      knownCostBasis: knownCostBasis,
      totalDebited: appliedDebit,
    ),
  };
  state.knownQuantity = state.knownQuantity - allocation.knownQuantity;
  state.knownCostBasis = state.knownCostBasis - allocation.transferredCostBasis;
  return _TransferRemoval(
    totalDebited: allocation.totalDebited,
    knownQuantity: allocation.knownQuantity,
    unknownQuantity: allocation.unknownQuantity,
    transferredCostBasis: allocation.transferredCostBasis,
    knownAvailableBefore: knownAvailable,
    knownCostBasisBefore: knownCostBasis,
  );
}

AccountingAmount _absolute(AccountingAmount value) =>
    value.compareTo(AccountingAmount.zero) < 0
    ? AccountingAmount.zero - value
    : value;

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
