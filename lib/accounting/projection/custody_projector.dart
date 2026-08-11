import '../domain/accounting_amount.dart';
import '../domain/accounting_movement.dart';
import '../domain/ledger_validation.dart';
import '../domain/movement_normalizer.dart';
import '../domain/movement_type.dart';
import 'custody_projection.dart';

abstract interface class CustodyProjector {
  CustodyProjection project(NormalizedLedger ledger);
}

final class DefaultCustodyProjector implements CustodyProjector {
  const DefaultCustodyProjector();

  @override
  CustodyProjection project(NormalizedLedger ledger) {
    final states = <WalletAssetKey, _CustodyState>{};
    final effects = <String, List<CustodyMovementEffect>>{};
    final movementsById = <String, AccountingMovement>{
      for (final movement in ledger.movements) movement.id: movement,
    };
    final resolutions = _resolveLinks(ledger, movementsById);

    for (final leg in ledger.legs) {
      final key = WalletAssetKey(leg.walletId, leg.asset);
      final state = states.putIfAbsent(key, _CustodyState.new);
      final rawRequested = switch (leg.kind) {
        LedgerLegKind.custodyCredit => leg.quantity,
        LedgerLegKind.custodyDebit => AccountingAmount.zero - leg.quantity,
        LedgerLegKind.adjustment => leg.quantity,
        LedgerLegKind.performanceEvent => AccountingAmount.zero,
      };
      final resolved = leg.kind == LedgerLegKind.adjustment
          ? resolutions.byAdjustmentId[leg.movementId] ?? AccountingAmount.zero
          : AccountingAmount.zero;
      final requested = leg.kind == LedgerLegKind.adjustment
          ? _withAdjustmentRemainder(rawRequested, resolved)
          : rawRequested;
      final before = state.quantity;
      final movement = movementsById[leg.movementId];
      if (leg.kind == LedgerLegKind.adjustment &&
          movement?.observedBalance != null &&
          before + rawRequested != movement!.observedBalance) {
        state.issues.add(
          ProjectionIssue(
            ProjectionIssueCode.observedBalanceMismatch,
            leg.movementId,
            'El saldo observado no coincide con la custodia anterior y el ajuste.',
          ),
        );
      }
      state.addIssues(resolutions.issuesByMovementId[leg.movementId]);
      final applied = state.apply(requested, leg, movement);
      if (leg.kind == LedgerLegKind.adjustment) {
        state.resolvedAdjustments = state.resolvedAdjustments + resolved;
      }
      (effects[leg.movementId] ??= <CustodyMovementEffect>[]).add(
        CustodyMovementEffect(
          key: key,
          before: before,
          requested: rawRequested,
          applied: applied,
          unapplied: requested - applied,
          after: state.quantity,
        ),
      );
    }

    return CustodyProjection(
      Map<WalletAssetKey, CustodyPosition>.unmodifiable({
        for (final entry in states.entries) entry.key: entry.value.toPosition(),
      }),
      List<AccountingMovement>.unmodifiable(
        ledger.movements.where(
          (movement) => movement.type == MovementType.balanceAdjustment,
        ),
      ),
      Map<String, List<CustodyMovementEffect>>.unmodifiable({
        for (final entry in effects.entries)
          entry.key: List<CustodyMovementEffect>.unmodifiable(entry.value),
      }),
    );
  }

  _LinkResolution _resolveLinks(
    NormalizedLedger ledger,
    Map<String, AccountingMovement> movementsById,
  ) {
    final adjustmentById = <String, AccountingMovement>{
      for (final movement in ledger.movements)
        if (movement.type == MovementType.balanceAdjustment)
          movement.id: movement,
    };
    final legsByMovementId = <String, List<LedgerLeg>>{};
    for (final leg in ledger.legs) {
      (legsByMovementId[leg.movementId] ??= <LedgerLeg>[]).add(leg);
    }
    final byAdjustmentId = <String, AccountingAmount>{};
    final issuesByMovementId = <String, List<ProjectionIssue>>{};

    void issue(ProjectionIssueCode code, String movementId, String message) =>
        (issuesByMovementId[movementId] ??= <ProjectionIssue>[]).add(
          ProjectionIssue(code, movementId, message),
        );

    for (final movement in ledger.movements) {
      if (movement.type == MovementType.balanceAdjustment) continue;
      for (final link in movement.reconciliationLinks) {
        final adjustment = adjustmentById[link.adjustmentMovementId];
        if (adjustment == null) {
          issue(
            ProjectionIssueCode.linkedAdjustmentDeletion,
            movement.id,
            'El ajuste enlazado ya no existe.',
          );
          continue;
        }
        final adjustmentQuantity = adjustment.adjustmentQuantity;
        final matchingLeg = adjustmentQuantity == null
            ? null
            : (legsByMovementId[movement.id] ?? const <LedgerLeg>[])
                  .where(
                    (leg) =>
                        leg.walletId == adjustment.adjustmentWalletId &&
                        leg.asset == adjustment.asset &&
                        _sameSign(_signedLegQuantity(leg), adjustmentQuantity),
                  )
                  .firstOrNull;
        final current = byAdjustmentId[adjustment.id] ?? AccountingAmount.zero;
        final isInvalid =
            adjustmentQuantity == null ||
            link.quantityResolved.compareTo(AccountingAmount.zero) <= 0 ||
            matchingLeg == null ||
            link.quantityResolved.compareTo(_absolute(matchingLeg.quantity)) >
                0 ||
            (current + link.quantityResolved).compareTo(
                  _absolute(adjustmentQuantity),
                ) >
                0;
        if (isInvalid) {
          issue(
            ProjectionIssueCode.invalidReconciliationLink,
            movement.id,
            'El vínculo de conciliación no coincide con el ajuste.',
          );
          continue;
        }
        byAdjustmentId[adjustment.id] = current + link.quantityResolved;
      }
    }
    return _LinkResolution(byAdjustmentId, issuesByMovementId);
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

AccountingAmount _signedLegQuantity(LedgerLeg leg) =>
    leg.kind == LedgerLegKind.custodyDebit
    ? AccountingAmount.zero - leg.quantity
    : leg.quantity;

AccountingAmount _withAdjustmentRemainder(
  AccountingAmount adjustment,
  AccountingAmount resolved,
) => _sameSign(adjustment, AccountingAmount.fromInt(1))
    ? _absolute(adjustment) - resolved
    : AccountingAmount.zero - (_absolute(adjustment) - resolved);

final class _LinkResolution {
  const _LinkResolution(this.byAdjustmentId, this.issuesByMovementId);

  final Map<String, AccountingAmount> byAdjustmentId;
  final Map<String, List<ProjectionIssue>> issuesByMovementId;
}

final class LedgerRebuilder {
  const LedgerRebuilder({
    this.normalizer = const DefaultMovementNormalizer(),
    this.projector = const DefaultCustodyProjector(),
  });

  final MovementNormalizer normalizer;
  final CustodyProjector projector;

  CustodyProjection rebuild(List<AccountingMovement> movements) =>
      projector.project(normalizer.normalize(movements));
}

final class DifferenceReconciliationService {
  const DifferenceReconciliationService();

  AccountingMovement link(
    AccountingMovement accountingMovement, {
    required AccountingMovement adjustment,
    required AccountingAmount justifiedQuantity,
  }) {
    final adjustmentQuantity = adjustment.adjustmentQuantity;
    if (adjustment.type != MovementType.balanceAdjustment ||
        adjustmentQuantity == null ||
        adjustment.adjustmentWalletId == null ||
        justifiedQuantity.compareTo(AccountingAmount.zero) <= 0 ||
        justifiedQuantity.compareTo(_absolute(adjustmentQuantity)) > 0) {
      throw ArgumentError('El vínculo de conciliación no es válido.');
    }
    final direction = _directionFor(accountingMovement);
    if (accountingMovement.asset != adjustment.asset ||
        direction == null ||
        direction.walletId != adjustment.adjustmentWalletId ||
        _sameSign(direction.quantity, adjustmentQuantity) == false ||
        justifiedQuantity.compareTo(_absolute(direction.quantity)) > 0) {
      throw ArgumentError(
        'El vínculo debe coincidir en cartera, activo y signo.',
      );
    }
    return accountingMovement.copyWith(
      reconciliationLinks: <ReconciliationLink>[
        ...accountingMovement.reconciliationLinks,
        ReconciliationLink(
          adjustmentMovementId: adjustment.id,
          quantityResolved: justifiedQuantity,
        ),
      ],
    );
  }

  _CustodyDirection? _directionFor(AccountingMovement movement) {
    switch (movement.type) {
      case MovementType.buy:
      case MovementType.transferIn:
        return movement.destinationWalletId == null || movement.quantity == null
            ? null
            : _CustodyDirection(
                movement.destinationWalletId!,
                movement.quantity!,
              );
      case MovementType.sell:
        return movement.sourceWalletId == null || movement.quantity == null
            ? null
            : _CustodyDirection(
                movement.sourceWalletId!,
                AccountingAmount.zero - movement.quantity!,
              );
      case MovementType.transferOut:
        return movement.sourceWalletId == null ||
                movement.totalDebitedAmount == null
            ? null
            : _CustodyDirection(
                movement.sourceWalletId!,
                AccountingAmount.zero - movement.totalDebitedAmount!,
              );
      case MovementType.balanceAdjustment:
        return null;
    }
  }
}

final class _CustodyDirection {
  const _CustodyDirection(this.walletId, this.quantity);

  final String walletId;
  final AccountingAmount quantity;
}

AccountingAmount _absolute(AccountingAmount value) =>
    value.compareTo(AccountingAmount.zero) < 0
    ? AccountingAmount.zero - value
    : value;

bool _sameSign(AccountingAmount left, AccountingAmount right) =>
    (left.compareTo(AccountingAmount.zero) < 0) ==
    (right.compareTo(AccountingAmount.zero) < 0);

final class _CustodyState {
  AccountingAmount quantity = AccountingAmount.zero;
  AccountingAmount credits = AccountingAmount.zero;
  AccountingAmount debits = AccountingAmount.zero;
  AccountingAmount adjustments = AccountingAmount.zero;
  AccountingAmount resolvedAdjustments = AccountingAmount.zero;
  AccountingAmount requested = AccountingAmount.zero;
  AccountingAmount unapplied = AccountingAmount.zero;
  AccountingAmount? observedBalance;
  final contributors = <String>[];
  final issues = <ProjectionIssue>[];

  AccountingAmount apply(
    AccountingAmount signedQuantity,
    LedgerLeg leg,
    AccountingMovement? movement,
  ) {
    final applied = signedQuantity.compareTo(AccountingAmount.zero) < 0
        ? _negativeApplied(signedQuantity, leg.movementId)
        : signedQuantity;
    quantity = quantity + applied;
    requested = requested + signedQuantity;
    unapplied = unapplied + (signedQuantity - applied);
    if (!contributors.contains(leg.movementId)) {
      contributors.add(leg.movementId);
    }
    switch (leg.kind) {
      case LedgerLegKind.custodyCredit:
        credits = credits + applied;
      case LedgerLegKind.custodyDebit:
        debits = debits + _absolute(applied);
      case LedgerLegKind.adjustment:
        adjustments = adjustments + applied;
        observedBalance = movement?.observedBalance;
      case LedgerLegKind.performanceEvent:
        break;
    }
    return applied;
  }

  AccountingAmount _negativeApplied(
    AccountingAmount requestedDebit,
    String movementId,
  ) {
    final available = quantity.max(AccountingAmount.zero);
    final appliedMagnitude = _absolute(requestedDebit).min(available);
    final applied = AccountingAmount.zero - appliedMagnitude;
    if (applied != requestedDebit) {
      issues.add(
        ProjectionIssue(
          ProjectionIssueCode.insufficientCustody,
          movementId,
          'La custodia disponible no cubre el débito solicitado.',
        ),
      );
    }
    return applied;
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

  CustodyPosition toPosition() => CustodyPosition(
    reconciledQuantity: quantity,
    appliedCredits: credits,
    appliedDebits: debits,
    signedAdjustments: adjustments,
    resolvedAdjustmentQuantity: resolvedAdjustments,
    lastObservedBalance: observedBalance,
    requestedQuantity: requested,
    unappliedQuantity: unapplied,
    contributingMovementIds: List<String>.unmodifiable(contributors),
    issues: List<ProjectionIssue>.unmodifiable(issues),
  );
}
