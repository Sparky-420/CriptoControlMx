import '../domain/accounting_amount.dart';
import '../domain/accounting_movement.dart';
import '../domain/ledger_validation.dart';
import '../domain/movement_normalizer.dart';
import '../domain/movement_type.dart';
import '../domain/wallet.dart';
import 'custody_projection.dart';
import 'custody_projector.dart';
import 'fee_effect.dart';
import 'ledger_projection.dart';
import 'performance_projection.dart';
import 'performance_projector.dart';

export 'ledger_projection.dart';

final class LedgerInput {
  const LedgerInput({
    required this.wallets,
    required this.movements,
    required this.currentPrices,
    required this.saleCostConsumptionPolicy,
    required this.transferCostAllocationPolicy,
    required this.legacyAccountingPolicy,
  });

  final List<Wallet> wallets;
  final List<AccountingMovement> movements;
  final Map<String, AccountingAmount> currentPrices;
  final SaleCostConsumptionPolicy saleCostConsumptionPolicy;
  final TransferCostAllocationPolicy transferCostAllocationPolicy;
  final LegacyAccountingPolicy legacyAccountingPolicy;
}

final class AccountingLedgerEngine {
  const AccountingLedgerEngine(this.normalizer, this.custody, this.performance);

  final MovementNormalizer normalizer;
  final CustodyProjector custody;
  final PerformanceProjector performance;

  LedgerProjection project(LedgerInput input) {
    final walletReferenceIssues = <ProjectionIssue>[];
    final walletIds = input.wallets
        .map((wallet) => wallet.id)
        .where((walletId) => !walletId.startsWith('virtual:'))
        .toSet();
    final routedMovements = input.movements
        .map(
          (movement) => _routeAssignment(
            _routeUnknownWalletReferences(
              movement,
              walletIds,
              walletReferenceIssues,
            ),
          ),
        )
        .toList();
    final normalized = _preserveVirtualGlobalTransfers(
      normalizer.normalize(routedMovements),
      input.legacyAccountingPolicy,
    );
    final custodyProjection = custody.project(normalized);
    final performanceProjection = performance.project(
      normalized,
      custodyProjection,
      input.currentPrices,
      salePolicy: input.saleCostConsumptionPolicy,
      transferPolicy: input.transferCostAllocationPolicy,
    );
    final movementById = <String, AccountingMovement>{};
    for (final movement in normalized.movements) {
      movementById.putIfAbsent(movement.id, () => movement);
    }
    final keysByMovementId = _keysByMovement(normalized.movements);
    final assignmentIssues = <ProjectionIssue>[
      ..._assignmentIssues(normalized.movements),
      ...walletReferenceIssues,
    ];
    final allIssues = _collectIssues(
      normalized,
      custodyProjection,
      performanceProjection,
      assignmentIssues,
    );
    final positions = _combinePositions(
      custodyProjection,
      performanceProjection,
      input.currentPrices,
      movementById,
      keysByMovementId,
      walletReferenceIssues.map((issue) => issue.movementId).toSet(),
    );
    _addUniqueIssues(allIssues, _completenessIssues(positions.values));
    final effects = _movementEffects(
      normalized,
      custodyProjection,
      performanceProjection,
      allIssues,
    );
    final uniqueMovements = movementById.values.toList(growable: false);

    return LedgerProjection(
      positions: Map<WalletAssetKey, WalletAssetProjection>.unmodifiable(
        positions,
      ),
      sales: performanceProjection.sales,
      effects: Map<String, MovementEffect>.unmodifiable(effects),
      totals: _totals(positions.values, effects.values),
      issues: List<ProjectionIssue>.unmodifiable(allIssues),
      migrationProgress: MigrationProgress(
        assigned: uniqueMovements
            .where(
              (movement) =>
                  movement.walletAssignmentStatus ==
                      WalletAssignmentStatus.assigned &&
                  !walletReferenceIssues.any(
                    (issue) => issue.movementId == movement.id,
                  ),
            )
            .length,
        total: uniqueMovements.length,
      ),
    );
  }
}

AccountingMovement _routeUnknownWalletReferences(
  AccountingMovement movement,
  Set<String> walletIds,
  List<ProjectionIssue> issues,
) {
  String? route(String? walletId, String role) {
    if (walletId == null || walletIds.contains(walletId)) {
      return walletId;
    }
    issues.add(
      ProjectionIssue(
        ProjectionIssueCode.unknownWallet,
        movement.id,
        'La cartera $walletId referenciada como $role no existe.',
      ),
    );
    return virtualUnknownWalletId;
  }

  return switch (movement.type) {
    MovementType.buy || MovementType.transferIn => movement.copyWith(
      destinationWalletId: route(movement.destinationWalletId, 'destino'),
    ),
    MovementType.sell => movement.copyWith(
      sourceWalletId: route(movement.sourceWalletId, 'origen'),
    ),
    MovementType.transferOut => movement.copyWith(
      sourceWalletId: route(movement.sourceWalletId, 'origen'),
      destinationWalletId: movement.destinationType == DestinationType.ownWallet
          ? route(movement.destinationWalletId, 'destino')
          : movement.destinationWalletId,
    ),
    MovementType.balanceAdjustment => movement.copyWith(
      adjustmentWalletId: route(movement.adjustmentWalletId, 'ajuste'),
    ),
  };
}

AccountingMovement _routeAssignment(AccountingMovement movement) {
  final status = movement.walletAssignmentStatus;
  if (status == WalletAssignmentStatus.assigned) return movement;
  final virtualWalletId = status == WalletAssignmentStatus.legacyUnassigned
      ? virtualUnassignedWalletId
      : virtualPendingWalletId;
  return switch (movement.type) {
    MovementType.buy || MovementType.transferIn => movement.copyWith(
      destinationWalletId: movement.destinationWalletId ?? virtualWalletId,
    ),
    MovementType.sell => movement.copyWith(
      sourceWalletId: movement.sourceWalletId ?? virtualWalletId,
    ),
    MovementType.transferOut => movement.copyWith(
      sourceWalletId: movement.sourceWalletId ?? virtualWalletId,
      destinationWalletId: movement.destinationType == DestinationType.ownWallet
          ? movement.destinationWalletId ?? virtualWalletId
          : movement.destinationWalletId,
    ),
    MovementType.balanceAdjustment => movement.copyWith(
      adjustmentWalletId: movement.adjustmentWalletId ?? virtualWalletId,
    ),
  };
}

NormalizedLedger _preserveVirtualGlobalTransfers(
  NormalizedLedger ledger,
  LegacyAccountingPolicy policy,
) {
  switch (policy) {
    case LegacyAccountingPolicy.preservePreviousGlobal:
      break;
  }
  final specialIds = <String>{};
  final missingClassificationIds = <String>{};
  final specialLegs = <String, List<LedgerLeg>>{};
  final projectedMovements = <AccountingMovement>[];
  for (final originalMovement in ledger.movements) {
    var movement = originalMovement;
    final walletId = movement.sourceWalletId;
    final isVirtualSource = walletId?.startsWith('virtual:') ?? false;
    final isVirtualSelf =
        movement.destinationType == DestinationType.ownWallet &&
        walletId != null &&
        walletId == movement.destinationWalletId &&
        isVirtualSource;
    final isLegacyVirtual =
        movement.walletAssignmentStatus ==
            WalletAssignmentStatus.legacyUnassigned &&
        isVirtualSource;
    final isLegacyUnclassified =
        isLegacyVirtual &&
        movement.destinationType == null &&
        movement.destinationWalletId == null;
    if (movement.type != MovementType.transferOut ||
        (!isVirtualSelf && !isLegacyUnclassified) ||
        !specialIds.add(movement.id)) {
      projectedMovements.add(movement);
      continue;
    }
    if (isLegacyVirtual) missingClassificationIds.add(movement.id);
    final legs = <LedgerLeg>[];
    if (isVirtualSelf) {
      final received =
          movement.receivedAmount ?? movement.quantity ?? AccountingAmount.zero;
      final isSameAssetFee =
          movement.cryptoFeeAsset == null ||
          movement.cryptoFeeAsset == movement.asset;
      final totalDebited =
          movement.totalDebitedAmount ??
          received +
              (isSameAssetFee
                  ? movement.cryptoFeeAmount
                  : AccountingAmount.zero);
      movement = movement.copyWith(
        destinationType: DestinationType.ownWallet,
        destinationWalletId: walletId,
        receivedAmount: received,
        totalDebitedAmount: totalDebited,
      );
      if (totalDebited.compareTo(AccountingAmount.zero) > 0) {
        legs.add(
          LedgerLeg(
            movementId: movement.id,
            walletId: walletId,
            asset: movement.asset,
            kind: LedgerLegKind.custodyDebit,
            quantity: totalDebited,
            occurredAt: movement.occurredAt.toUtc(),
          ),
        );
      }
      if (received.compareTo(AccountingAmount.zero) > 0) {
        legs.add(
          LedgerLeg(
            movementId: movement.id,
            walletId: walletId,
            asset: movement.asset,
            kind: LedgerLegKind.custodyCredit,
            quantity: received,
            occurredAt: movement.occurredAt.toUtc(),
          ),
        );
      }
      if (!isSameAssetFee &&
          movement.cryptoFeeAsset != null &&
          movement.cryptoFeeAmount.compareTo(AccountingAmount.zero) > 0) {
        legs.add(
          LedgerLeg(
            movementId: movement.id,
            walletId: walletId,
            asset: movement.cryptoFeeAsset!,
            kind: LedgerLegKind.custodyDebit,
            quantity: movement.cryptoFeeAmount,
            occurredAt: movement.occurredAt.toUtc(),
          ),
        );
      }
    } else if ((movement.quantity?.compareTo(AccountingAmount.zero) ?? 0) > 0) {
      legs.add(
        LedgerLeg(
          movementId: movement.id,
          walletId: walletId!,
          asset: movement.asset,
          kind: LedgerLegKind.custodyDebit,
          quantity: movement.quantity!,
          occurredAt: movement.occurredAt.toUtc(),
        ),
      );
    } else if (movement.cryptoFeeAsset != null &&
        movement.cryptoFeeAmount.compareTo(AccountingAmount.zero) > 0) {
      legs.add(
        LedgerLeg(
          movementId: movement.id,
          walletId: walletId!,
          asset: movement.cryptoFeeAsset!,
          kind: LedgerLegKind.custodyDebit,
          quantity: movement.cryptoFeeAmount,
          occurredAt: movement.occurredAt.toUtc(),
        ),
      );
    }
    specialLegs[movement.id] = legs;
    projectedMovements.add(movement);
  }
  if (specialIds.isEmpty) return ledger;

  final existingLegs = <String, List<LedgerLeg>>{};
  for (final leg in ledger.legs) {
    (existingLegs[leg.movementId] ??= <LedgerLeg>[]).add(leg);
  }
  final orderedLegs = <LedgerLeg>[];
  final emittedIds = <String>{};
  for (final movement in projectedMovements) {
    if (!emittedIds.add(movement.id)) continue;
    orderedLegs.addAll(
      specialLegs[movement.id] ??
          existingLegs[movement.id] ??
          const <LedgerLeg>[],
    );
  }
  return NormalizedLedger(
    movements: List<AccountingMovement>.unmodifiable(projectedMovements),
    legs: List<LedgerLeg>.unmodifiable(orderedLegs),
    issues: List<ProjectionIssue>.unmodifiable(<ProjectionIssue>[
      ...ledger.issues.where((issue) {
        if (!specialIds.contains(issue.movementId)) return true;
        if (issue.code == ProjectionIssueCode.sameWalletTransfer) {
          return false;
        }
        return true;
      }),
      for (final movementId in missingClassificationIds)
        ProjectionIssue(
          ProjectionIssueCode.missingDestinationClassification,
          movementId,
          'La transferencia legacy conserva el efecto global con destino pendiente de clasificar.',
        ),
    ]),
    acceptedMovementIds: Set<String>.unmodifiable(<String>{
      ...ledger.acceptedMovementIds,
      ...specialIds,
    }),
  );
}

Map<String, Set<WalletAssetKey>> _keysByMovement(
  List<AccountingMovement> movements,
) {
  final result = <String, Set<WalletAssetKey>>{};
  final seen = <String>{};
  for (final movement in movements) {
    if (!seen.add(movement.id)) continue;
    final keys = result.putIfAbsent(movement.id, () => <WalletAssetKey>{});
    void add(String? walletId, String asset) {
      if (walletId != null) keys.add(WalletAssetKey(walletId, asset));
    }

    switch (movement.type) {
      case MovementType.buy:
      case MovementType.transferIn:
        add(movement.destinationWalletId, movement.asset);
      case MovementType.sell:
        add(movement.sourceWalletId, movement.asset);
      case MovementType.transferOut:
        add(movement.sourceWalletId, movement.asset);
        if (movement.destinationType == DestinationType.ownWallet &&
            movement.destinationWalletId != movement.sourceWalletId) {
          add(movement.destinationWalletId, movement.asset);
        }
        if (movement.cryptoFeeAsset != null &&
            movement.cryptoFeeAsset != movement.asset) {
          add(movement.sourceWalletId, movement.cryptoFeeAsset!);
        }
      case MovementType.balanceAdjustment:
        add(movement.adjustmentWalletId, movement.asset);
    }
  }
  return result;
}

List<ProjectionIssue> _assignmentIssues(List<AccountingMovement> movements) {
  final issues = <ProjectionIssue>[];
  final seen = <String>{};
  for (final movement in movements) {
    if (!seen.add(movement.id)) continue;
    switch (movement.walletAssignmentStatus) {
      case WalletAssignmentStatus.assigned:
        break;
      case WalletAssignmentStatus.partiallyAssigned:
      case WalletAssignmentStatus.pending:
        issues.add(
          ProjectionIssue(
            ProjectionIssueCode.missingWalletAssignment,
            movement.id,
            'El movimiento conserva una asignación de cartera pendiente.',
          ),
        );
      case WalletAssignmentStatus.legacyUnassigned:
        issues.add(
          ProjectionIssue(
            ProjectionIssueCode.legacyAccountingSemantics,
            movement.id,
            'El movimiento legacy conserva su efecto global sin atribuirse a una cartera real.',
          ),
        );
    }
  }
  return issues;
}

Map<WalletAssetKey, WalletAssetProjection> _combinePositions(
  CustodyProjection custody,
  PerformanceProjection performance,
  Map<String, AccountingAmount> prices,
  Map<String, AccountingMovement> movementById,
  Map<String, Set<WalletAssetKey>> keysByMovementId,
  Set<String> unknownWalletMovementIds,
) {
  final keys = <WalletAssetKey>{
    ...custody.positions.keys,
    ...performance.positions.keys,
  };
  final result = <WalletAssetKey, WalletAssetProjection>{};
  for (final key in keys) {
    final custodyPosition = custody.positions[key] ?? _emptyCustodyPosition();
    final performancePosition =
        performance.positions[key] ?? _emptyPerformancePosition();
    final availability = PositionAvailability.derive(
      custodyQuantity: custodyPosition.reconciledQuantity,
      knownQuantity: performancePosition.knownQuantity,
    );
    final related = <AccountingMovement>[
      for (final entry in keysByMovementId.entries)
        if (entry.value.contains(key) && movementById[entry.key] != null)
          movementById[entry.key]!,
    ];
    final legacyIds = _idsWithStatus(related, const <WalletAssignmentStatus>{
      WalletAssignmentStatus.legacyUnassigned,
    });
    final pendingIds = _idsWithStatus(related, const <WalletAssignmentStatus>{
      WalletAssignmentStatus.pending,
      WalletAssignmentStatus.partiallyAssigned,
    });
    final unknownWalletIds = related
        .where((movement) => unknownWalletMovementIds.contains(movement.id))
        .map((movement) => movement.id)
        .toSet()
        .toList(growable: false);
    final unknownIds = <String>{
      ...custodyPosition.contributingMovementIds.where((id) {
        final movement = movementById[id];
        return movement?.type == MovementType.balanceAdjustment ||
            movement?.type == MovementType.transferOut ||
            (movement?.type == MovementType.buy &&
                movement?.unitPriceFiat == null) ||
            (movement?.type == MovementType.transferIn &&
                movement?.unitPriceFiat == null);
      }),
      ...performancePosition.blockingMovementIds,
    }.toList(growable: false);
    final AccountingCompleteness state;
    final ProjectionIssueCode? cause;
    final List<String> causingIds;
    if (key.walletId == virtualUnknownWalletId) {
      state = AccountingCompleteness.pendingAssignment;
      cause = ProjectionIssueCode.unknownWallet;
      causingIds = unknownWalletIds;
    } else if (legacyIds.isNotEmpty ||
        key.walletId == virtualUnassignedWalletId) {
      state = AccountingCompleteness.unassignedLegacy;
      cause = ProjectionIssueCode.legacyAccountingSemantics;
      causingIds = legacyIds;
    } else if (pendingIds.isNotEmpty ||
        key.walletId == virtualPendingWalletId) {
      state = AccountingCompleteness.pendingAssignment;
      cause = ProjectionIssueCode.missingWalletAssignment;
      causingIds = pendingIds;
    } else if (availability.unknownAvailable != AccountingAmount.zero ||
        availability.custodyDeficit != AccountingAmount.zero ||
        performancePosition.pendingPnlQuantity != AccountingAmount.zero) {
      state = AccountingCompleteness.partiallyKnown;
      cause = ProjectionIssueCode.unknownCostBasis;
      causingIds = unknownIds;
    } else {
      state = AccountingCompleteness.complete;
      cause = null;
      causingIds = const <String>[];
    }
    final price = prices[key.asset] ?? AccountingAmount.zero;
    final completeness = AccountingCompletenessResult(
      state: state,
      totalQuantity: custodyPosition.reconciledQuantity,
      knownQuantity: availability.knownAvailable,
      unknownQuantity: availability.unknownAvailable,
      cause: cause,
      causingMovementIds: List<String>.unmodifiable(causingIds),
    );
    result[key] = WalletAssetProjection(
      key: key,
      custody: custodyPosition,
      performance: performancePosition,
      availability: availability,
      completeness: completeness,
      custodyMarketValue: custodyPosition.reconciledQuantity * price,
      knownPositionMarketValue: performancePosition.knownQuantity * price,
    );
  }
  return result;
}

List<String> _idsWithStatus(
  List<AccountingMovement> movements,
  Set<WalletAssignmentStatus> statuses,
) => <String>[
  for (final movement in movements)
    if (statuses.contains(movement.walletAssignmentStatus)) movement.id,
];

List<ProjectionIssue> _collectIssues(
  NormalizedLedger ledger,
  CustodyProjection custody,
  PerformanceProjection performance,
  List<ProjectionIssue> assignmentIssues,
) {
  final result = <ProjectionIssue>[];
  final seen = <String>{};
  void add(ProjectionIssue issue) {
    final identity = '${issue.code.name}|${issue.movementId}|${issue.message}';
    if (seen.add(identity)) result.add(issue);
  }

  ledger.issues.forEach(add);
  for (final position in custody.positions.values) {
    position.issues.forEach(add);
  }
  for (final position in performance.positions.values) {
    position.issues.forEach(add);
  }
  assignmentIssues.forEach(add);
  return result;
}

Iterable<ProjectionIssue> _completenessIssues(
  Iterable<WalletAssetProjection> positions,
) sync* {
  for (final position in positions) {
    if (position.completeness.cause != ProjectionIssueCode.unknownCostBasis) {
      continue;
    }
    for (final movementId in position.completeness.causingMovementIds) {
      yield ProjectionIssue(
        ProjectionIssueCode.unknownCostBasis,
        movementId,
        'La custodia y la posición conocida difieren por costo pendiente.',
      );
    }
  }
}

void _addUniqueIssues(
  List<ProjectionIssue> target,
  Iterable<ProjectionIssue> additions,
) {
  final identities = target
      .map((issue) => '${issue.code.name}|${issue.movementId}|${issue.message}')
      .toSet();
  for (final issue in additions) {
    final identity = '${issue.code.name}|${issue.movementId}|${issue.message}';
    if (identities.add(identity)) target.add(issue);
  }
}

Map<String, MovementEffect> _movementEffects(
  NormalizedLedger ledger,
  CustodyProjection custody,
  PerformanceProjection performance,
  List<ProjectionIssue> issues,
) {
  final sales = <String, SaleResult>{
    for (final sale in performance.sales) sale.movementId: sale,
  };
  final result = <String, MovementEffect>{};
  for (final movement in ledger.movements) {
    if (result.containsKey(movement.id)) continue;
    final custodyEffects = custody.effectsFor(movement.id);
    final primary = _primaryEffect(movement, custodyEffects);
    final custodyLegs = <MovementCustodyLegEffect>[
      for (final effect in custodyEffects)
        MovementCustodyLegEffect(
          key: effect.key,
          kind: _custodyLegKind(movement, effect),
          before: effect.before,
          requested: effect.requested,
          applied: effect.applied,
          unapplied: effect.unapplied,
          after: effect.after,
        ),
    ];
    final globalDeltas = <String, AccountingAmount>{};
    for (final effect in custodyEffects) {
      globalDeltas[effect.key.asset] =
          (globalDeltas[effect.key.asset] ?? AccountingAmount.zero) +
          effect.applied;
    }
    result[movement.id] = MovementEffect(
      movementId: movement.id,
      requestedQuantity: _absolute(primary?.requested ?? AccountingAmount.zero),
      appliedQuantity: _absolute(primary?.applied ?? AccountingAmount.zero),
      unappliedQuantity: _absolute(primary?.unapplied ?? AccountingAmount.zero),
      custodyLegs: List<MovementCustodyLegEffect>.unmodifiable(custodyLegs),
      globalDeltasByAsset: Map<String, AccountingAmount>.unmodifiable(
        globalDeltas,
      ),
      feeEffect: ledger.acceptedMovementIds.contains(movement.id)
          ? resolveFeeEffect(movement)
          : FeeEffect.zero,
      transferAllocation: performance.transferAllocations[movement.id],
      issues: List<ProjectionIssue>.unmodifiable(
        issues.where((issue) => issue.movementId == movement.id),
      ),
      sale: sales[movement.id],
    );
  }
  return result;
}

LedgerLegKind _custodyLegKind(
  AccountingMovement movement,
  CustodyMovementEffect effect,
) {
  if (movement.type == MovementType.balanceAdjustment) {
    return LedgerLegKind.adjustment;
  }
  return effect.requested.compareTo(AccountingAmount.zero) < 0
      ? LedgerLegKind.custodyDebit
      : LedgerLegKind.custodyCredit;
}

CustodyMovementEffect? _primaryEffect(
  AccountingMovement movement,
  List<CustodyMovementEffect> effects,
) {
  final walletId = switch (movement.type) {
    MovementType.buy || MovementType.transferIn => movement.destinationWalletId,
    MovementType.sell || MovementType.transferOut => movement.sourceWalletId,
    MovementType.balanceAdjustment => movement.adjustmentWalletId,
  };
  for (final effect in effects) {
    if (effect.key.walletId == walletId && effect.key.asset == movement.asset) {
      return effect;
    }
  }
  if (movement.type == MovementType.transferOut) {
    for (final effect in effects) {
      if (effect.key.walletId == walletId &&
          effect.requested.compareTo(AccountingAmount.zero) < 0) {
        return effect;
      }
    }
  }
  return null;
}

LedgerTotals _totals(
  Iterable<WalletAssetProjection> positions,
  Iterable<MovementEffect> effects,
) {
  var custodyMarketValue = AccountingAmount.zero;
  var knownPositionMarketValue = AccountingAmount.zero;
  var knownCostBasis = AccountingAmount.zero;
  var realizedPnlKnown = AccountingAmount.zero;
  var unrealizedPnlKnown = AccountingAmount.zero;
  var fiatCostEffect = AccountingAmount.zero;
  for (final position in positions) {
    custodyMarketValue = custodyMarketValue + position.custodyMarketValue;
    knownPositionMarketValue =
        knownPositionMarketValue + position.knownPositionMarketValue;
    knownCostBasis = knownCostBasis + position.performance.knownCostBasis;
    realizedPnlKnown = realizedPnlKnown + position.performance.realizedPnlKnown;
    unrealizedPnlKnown =
        unrealizedPnlKnown + position.performance.unrealizedPnlKnown;
  }
  for (final effect in effects) {
    fiatCostEffect = fiatCostEffect + effect.feeEffect.fiatCostEffect;
  }
  return LedgerTotals(
    custodyMarketValue: custodyMarketValue,
    knownPositionMarketValue: knownPositionMarketValue,
    knownCostBasis: knownCostBasis,
    realizedPnlKnown: realizedPnlKnown,
    unrealizedPnlKnown: unrealizedPnlKnown,
    fiatCostEffect: fiatCostEffect,
  );
}

CustodyPosition _emptyCustodyPosition() => CustodyPosition(
  reconciledQuantity: AccountingAmount.zero,
  appliedCredits: AccountingAmount.zero,
  appliedDebits: AccountingAmount.zero,
  signedAdjustments: AccountingAmount.zero,
  resolvedAdjustmentQuantity: AccountingAmount.zero,
  requestedQuantity: AccountingAmount.zero,
  unappliedQuantity: AccountingAmount.zero,
  contributingMovementIds: const <String>[],
  issues: const <ProjectionIssue>[],
);

PerformancePosition _emptyPerformancePosition() => PerformancePosition(
  knownQuantity: AccountingAmount.zero,
  knownCostBasis: AccountingAmount.zero,
  averageCost: AccountingAmount.zero,
  investedCapital: AccountingAmount.zero,
  realizedPnlKnown: AccountingAmount.zero,
  unrealizedPnlKnown: AccountingAmount.zero,
  pendingPnlQuantity: AccountingAmount.zero,
  blockingMovementIds: const <String>[],
  issues: const <ProjectionIssue>[],
);

AccountingAmount _absolute(AccountingAmount value) =>
    value.compareTo(AccountingAmount.zero) < 0
    ? AccountingAmount.zero - value
    : value;
