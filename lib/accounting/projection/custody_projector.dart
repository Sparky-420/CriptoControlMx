import '../domain/accounting_amount.dart';
import '../domain/accounting_movement.dart';
import '../domain/ledger_validation.dart';
import '../domain/movement_normalizer.dart';
import '../domain/movement_type.dart';
import '../domain/wallet.dart';
import 'custody_projection.dart';
import 'fee_effect.dart';

abstract interface class CustodyProjector {
  CustodyProjection project(NormalizedLedger ledger);
}

final class DefaultCustodyProjector implements CustodyProjector {
  const DefaultCustodyProjector();

  @override
  CustodyProjection project(NormalizedLedger ledger) =>
      _project(ledger, resolveLinks: true);

  CustodyProjection _project(
    NormalizedLedger ledger, {
    required bool resolveLinks,
  }) {
    final states = <WalletAssetKey, _CustodyState>{};
    final effects = <String, List<CustodyMovementEffect>>{};
    final legMovementIds = ledger.legs.map((leg) => leg.movementId).toSet();
    final movementsById = <String, AccountingMovement>{};
    for (final movement in ledger.movements) {
      if (legMovementIds.contains(movement.id) &&
          !movementsById.containsKey(movement.id)) {
        movementsById[movement.id] = movement;
      }
    }
    final resolutions = resolveLinks
        ? _resolveLinks(
            ledger,
            movementsById,
            _project(ledger, resolveLinks: false),
          )
        : _LinkResolution.empty;

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
      final applied = state.apply(
        requested,
        leg,
        movement,
        maximumCredit: _transferCreditLimit(
          leg,
          movement,
          effects,
          resolutions,
        ),
      );
      if (leg.kind == LedgerLegKind.adjustment) {
        state.resolvedAdjustments = state.resolvedAdjustments + resolved;
      }
      (effects[leg.movementId] ??= <CustodyMovementEffect>[]).add(
        CustodyMovementEffect(
          key: key,
          before: before,
          requested: requested,
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
    CustodyProjection baseCustody,
  ) {
    final adjustmentById = <String, AccountingMovement>{
      for (final movement in movementsById.values)
        if (movement.type == MovementType.balanceAdjustment)
          movement.id: movement,
    };
    final legsByMovementId = <String, List<LedgerLeg>>{};
    for (final leg in ledger.legs) {
      (legsByMovementId[leg.movementId] ??= <LedgerLeg>[]).add(leg);
    }
    final byAdjustmentId = <String, AccountingAmount>{};
    final byLegKey = <String, AccountingAmount>{};
    final issuesByMovementId = <String, List<ProjectionIssue>>{};

    void issue(ProjectionIssueCode code, String movementId, String message) =>
        (issuesByMovementId[movementId] ??= <ProjectionIssue>[]).add(
          ProjectionIssue(code, movementId, message),
        );

    for (final movement in movementsById.values) {
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
        if (adjustmentQuantity == null || matchingLeg == null) {
          issue(
            ProjectionIssueCode.invalidReconciliationLink,
            movement.id,
            'El vínculo de conciliación no coincide con el ajuste.',
          );
          continue;
        }
        final legKey = _linkResolutionKey(matchingLeg);
        final currentForLeg = byLegKey[legKey] ?? AccountingAmount.zero;
        final linkCapacity = _linkCapacity(baseCustody, movement, matchingLeg);
        final isInvalid =
            link.quantityResolved.compareTo(AccountingAmount.zero) <= 0 ||
            link.quantityResolved.compareTo(_absolute(matchingLeg.quantity)) >
                0 ||
            (currentForLeg + link.quantityResolved).compareTo(linkCapacity) >
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
        byLegKey[legKey] =
            (byLegKey[legKey] ?? AccountingAmount.zero) + link.quantityResolved;
      }
    }
    return _LinkResolution(byAdjustmentId, byLegKey, issuesByMovementId);
  }
}

AccountingAmount? _transferCreditLimit(
  LedgerLeg leg,
  AccountingMovement? movement,
  Map<String, List<CustodyMovementEffect>> effects,
  _LinkResolution resolutions,
) {
  if (leg.kind != LedgerLegKind.custodyCredit ||
      movement?.type != MovementType.transferOut ||
      movement?.destinationType != DestinationType.ownWallet ||
      movement?.receivedAmount == null ||
      movement?.totalDebitedAmount == null) {
    return null;
  }
  final sourceEffect = effects[movement!.id]
      ?.where(
        (effect) =>
            effect.key.walletId == movement.sourceWalletId &&
            effect.key.asset == movement.asset &&
            effect.requested.compareTo(AccountingAmount.zero) < 0,
      )
      .firstOrNull;
  if (sourceEffect == null) return AccountingAmount.zero;
  final received = movement.receivedAmount!;
  final totalDebited = movement.totalDebitedAmount!;
  final appliedDebit = _absolute(sourceEffect.applied);
  final sourceBacked = appliedDebit == AccountingAmount.zero
      ? AccountingAmount.zero
      : appliedDebit == totalDebited
      ? received
      : received == totalDebited
      ? appliedDebit
      : (received * appliedDebit).divide(totalDebited);
  final linkedCredit =
      resolutions.byLegKey[_linkResolutionKey(leg)] ?? AccountingAmount.zero;
  return (sourceBacked + linkedCredit).min(received);
}

String _linkResolutionKey(LedgerLeg leg) =>
    '${leg.movementId}|${leg.walletId}|${leg.asset}|${leg.kind.name}|${_signedLegQuantity(leg).compareTo(AccountingAmount.zero)}';

AccountingAmount _linkCapacity(
  CustodyProjection baseCustody,
  AccountingMovement movement,
  LedgerLeg leg,
) {
  if (leg.kind != LedgerLegKind.custodyCredit ||
      movement.type != MovementType.transferOut ||
      movement.destinationType != DestinationType.ownWallet) {
    return _absolute(leg.quantity);
  }
  final baseEffect = baseCustody
      .effectsFor(movement.id)
      .where(
        (effect) =>
            effect.key.walletId == leg.walletId &&
            effect.key.asset == leg.asset &&
            effect.requested == leg.quantity,
      )
      .firstOrNull;
  return (_absolute(leg.quantity) -
          (baseEffect?.applied ?? AccountingAmount.zero).max(
            AccountingAmount.zero,
          ))
      .max(AccountingAmount.zero);
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
  const _LinkResolution(
    this.byAdjustmentId,
    this.byLegKey,
    this.issuesByMovementId,
  );

  final Map<String, AccountingAmount> byAdjustmentId;
  final Map<String, AccountingAmount> byLegKey;
  final Map<String, List<ProjectionIssue>> issuesByMovementId;

  static const _LinkResolution empty = _LinkResolution(
    <String, AccountingAmount>{},
    <String, AccountingAmount>{},
    <String, List<ProjectionIssue>>{},
  );
}

/// Validates a prospective transfer against a completed custody projection.
/// Historical replay deliberately does not use this validator: it preserves an
/// insufficient event as an applied and unapplied custody effect instead.
final class TransferCustodyValidator {
  const TransferCustodyValidator();

  void validateNew(AccountingMovement movement, CustodyProjection custody) {
    final normalized = const DefaultMovementNormalizer().normalize(
      <AccountingMovement>[movement],
    );
    if (movement.type != MovementType.transferOut || !normalized.isValid) {
      throw ArgumentError('La transferencia nueva no cumple el contrato.');
    }
    final sourceWalletId = movement.sourceWalletId!;
    final available =
        custody
            .positions[WalletAssetKey(sourceWalletId, movement.asset)]
            ?.reconciledQuantity ??
        AccountingAmount.zero;
    if (available.compareTo(movement.totalDebitedAmount!) < 0) {
      throw ArgumentError('La custodia de origen es insuficiente.');
    }
    for (final fee in resolveFeeEffect(
      movement,
    ).otherAssetCustodyDebit.entries) {
      final feeAvailable =
          custody
              .positions[WalletAssetKey(sourceWalletId, fee.key)]
              ?.reconciledQuantity ??
          AccountingAmount.zero;
      if (feeAvailable.compareTo(fee.value) < 0) {
        throw ArgumentError('La custodia de comisión es insuficiente.');
      }
    }
  }
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
    final normalized = const DefaultMovementNormalizer().normalize(
      <AccountingMovement>[accountingMovement],
    );
    final compatibleLegs = normalized.legs
        .where(
          (leg) =>
              leg.walletId == adjustment.adjustmentWalletId &&
              leg.asset == adjustment.asset &&
              _sameSign(_signedLegQuantity(leg), adjustmentQuantity),
        )
        .toList(growable: false);
    if (accountingMovement.type == MovementType.balanceAdjustment ||
        compatibleLegs.length != 1 ||
        justifiedQuantity.compareTo(_absolute(compatibleLegs.single.quantity)) >
            0) {
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
    AccountingMovement? movement, {
    AccountingAmount? maximumCredit,
  }) {
    final applied = signedQuantity.compareTo(AccountingAmount.zero) < 0
        ? _negativeApplied(signedQuantity, leg.movementId)
        : maximumCredit?.min(signedQuantity) ?? signedQuantity;
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
