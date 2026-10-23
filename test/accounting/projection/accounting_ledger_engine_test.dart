import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_movement.dart';
import 'package:cripto_control_mx/accounting/domain/ledger_validation.dart';
import 'package:cripto_control_mx/accounting/domain/movement_normalizer.dart';
import 'package:cripto_control_mx/accounting/domain/movement_type.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/projection/accounting_ledger_engine.dart';
import 'package:cripto_control_mx/accounting/projection/custody_projection.dart';
import 'package:cripto_control_mx/accounting/projection/custody_projector.dart';
import 'package:cripto_control_mx/accounting/projection/performance_projector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports all four accounting completeness states', () {
    final projection = project(
      <AccountingMovement>[
        buy(
          id: 'complete-buy',
          asset: 'UNI',
          quantity: '2',
          price: '10',
          destinationWalletId: completeWalletId,
        ),
        buy(
          id: 'partial-buy',
          asset: 'UNI',
          quantity: '2',
          price: '10',
          destinationWalletId: partialWalletId,
        ),
        adjustment(
          id: 'partial-adjustment',
          walletId: partialWalletId,
          asset: 'UNI',
          quantity: '1',
          observed: '3',
        ),
        buy(
          id: 'pending-buy',
          asset: 'BTC',
          quantity: '4',
          price: '10',
          assignment: WalletAssignmentStatus.pending,
        ),
        transferIn(
          id: 'legacy-in',
          asset: 'ETH',
          quantity: '5',
          assignment: WalletAssignmentStatus.legacyUnassigned,
        ),
      ],
      prices: <String, AccountingAmount>{
        'UNI': amount('5'),
        'BTC': amount('100'),
        'ETH': amount('2'),
      },
    );

    expect(
      projection.positions.values
          .map((value) => value.completeness.state)
          .toSet(),
      <AccountingCompleteness>{
        AccountingCompleteness.complete,
        AccountingCompleteness.partiallyKnown,
        AccountingCompleteness.pendingAssignment,
        AccountingCompleteness.unassignedLegacy,
      },
    );

    final complete =
        projection.positions[const WalletAssetKey(completeWalletId, 'UNI')]!;
    expect(complete.reconciliationDifference, AccountingAmount.zero);
    expect(complete.availability.knownAvailable.toJson(), '2');
    expect(complete.availability.unknownAvailable, AccountingAmount.zero);
    expect(complete.availability.custodyDeficit, AccountingAmount.zero);
    expect(complete.knownAvailable.toJson(), '2');
    expect(complete.unknownAvailable, AccountingAmount.zero);
    expect(complete.custodyDeficit, AccountingAmount.zero);
    expect(complete.custodyMarketValue.toJson(), '10');
    expect(complete.knownPositionMarketValue.toJson(), '10');
    expect(complete.completeness.cause, isNull);
    expect(complete.completeness.causingMovementIds, isEmpty);

    final partial =
        projection.positions[const WalletAssetKey(partialWalletId, 'UNI')]!;
    expect(partial.reconciliationDifference.toJson(), '1');
    expect(partial.knownAvailable.toJson(), '2');
    expect(partial.unknownAvailable.toJson(), '1');
    expect(partial.custodyDeficit, AccountingAmount.zero);
    expect(partial.completeness.cause, ProjectionIssueCode.unknownCostBasis);
    expect(
      partial.completeness.causingMovementIds,
      contains('partial-adjustment'),
    );

    final pending = projection
        .positions[const WalletAssetKey(virtualPendingWalletId, 'BTC')]!;
    expect(pending.completeness.totalQuantity.toJson(), '4');
    expect(pending.completeness.knownQuantity.toJson(), '4');
    expect(pending.completeness.unknownQuantity, AccountingAmount.zero);
    expect(
      pending.completeness.cause,
      ProjectionIssueCode.missingWalletAssignment,
    );
    expect(pending.completeness.causingMovementIds, <String>['pending-buy']);

    final legacy = projection
        .positions[const WalletAssetKey(virtualUnassignedWalletId, 'ETH')]!;
    expect(legacy.completeness.totalQuantity.toJson(), '5');
    expect(legacy.completeness.knownQuantity, AccountingAmount.zero);
    expect(legacy.completeness.unknownQuantity.toJson(), '5');
    expect(
      legacy.completeness.cause,
      ProjectionIssueCode.legacyAccountingSemantics,
    );
    expect(legacy.completeness.causingMovementIds, <String>['legacy-in']);

    expect(
      projection.positions.keys.map((key) => key.walletId),
      isNot(contains('Bitso')),
    );
    expect(projection.totals.custodyMarketValue.toJson(), '435');
    expect(projection.totals.knownPositionMarketValue.toJson(), '420');
    expect(projection.totals.knownCostBasis.toJson(), '80');
    expect(projection.totals.realizedPnlKnown, AccountingAmount.zero);
    expect(projection.totals.unrealizedPnlKnown.toJson(), '340');
    expect(projection.migrationProgress.assigned, 3);
    expect(projection.migrationProgress.total, 5);
    expect(
      projection.issues.map((issue) => issue.movementId),
      containsAll(<String>['pending-buy', 'legacy-in']),
    );
  });

  test('exposes custody deficit and its typed unknown-cost issue', () {
    final projection = project(
      <AccountingMovement>[
        buy(
          id: 'deficit-buy',
          asset: 'UNI',
          quantity: '10',
          price: '10',
          destinationWalletId: completeWalletId,
        ),
        adjustment(
          id: 'deficit-adjustment',
          walletId: completeWalletId,
          asset: 'UNI',
          quantity: '-2',
          observed: '8',
        ),
      ],
      prices: <String, AccountingAmount>{'UNI': amount('5')},
    );
    final position =
        projection.positions[const WalletAssetKey(completeWalletId, 'UNI')]!;

    expect(position.reconciliationDifference.toJson(), '-2');
    expect(position.knownAvailable.toJson(), '8');
    expect(position.unknownAvailable, AccountingAmount.zero);
    expect(position.custodyDeficit.toJson(), '2');
    expect(position.completeness.totalQuantity.toJson(), '8');
    expect(position.completeness.knownQuantity.toJson(), '8');
    expect(position.completeness.unknownQuantity, AccountingAmount.zero);
    expect(position.completeness.causingMovementIds, <String>[
      'deficit-adjustment',
    ]);
    expect(position.custodyMarketValue.toJson(), '40');
    expect(position.knownPositionMarketValue.toJson(), '50');
    expect(
      projection.issues
          .where(
            (issue) =>
                issue.code == ProjectionIssueCode.unknownCostBasis &&
                issue.movementId == 'deficit-adjustment',
          )
          .length,
      1,
    );
  });

  test('counts one internal transfer debit and its fee exactly once', () {
    final projection = project(
      <AccountingMovement>[
        buy(
          id: 'internal-buy',
          asset: 'UNI',
          quantity: '10',
          price: '10',
          destinationWalletId: completeWalletId,
        ),
        transferOut(
          id: 'internal-transfer',
          asset: 'UNI',
          received: '4',
          fee: '1',
          sourceWalletId: completeWalletId,
          destinationWalletId: partialWalletId,
          destinationType: DestinationType.ownWallet,
        ),
      ],
      prices: <String, AccountingAmount>{'UNI': amount('5')},
    );
    final effect = projection.effects['internal-transfer']!;

    expect(effect.requestedQuantity.toJson(), '5');
    expect(effect.appliedQuantity.toJson(), '5');
    expect(effect.unappliedQuantity, AccountingAmount.zero);
    expect(effect.issues, isEmpty);
    expect(effect.sale, isNull);
    expect(effect.custodyLegs, hasLength(2));
    expect(effect.custodyLegs.map((leg) => leg.kind), <LedgerLegKind>[
      LedgerLegKind.custodyDebit,
      LedgerLegKind.custodyCredit,
    ]);
    expect(effect.custodyLegs.map((leg) => leg.applied.toJson()), <String>[
      '-5',
      '4',
    ]);
    expect(effect.globalDeltasByAsset['UNI']!.toJson(), '-1');
    expect(effect.feeEffect.assetCustodyDebit.toJson(), '1');
    expect(effect.feeEffect.otherAssetCustodyDebit, isEmpty);
    expect(effect.feeEffect.fiatCostEffect, AccountingAmount.zero);
    expect(effect.transferAllocation!.totalDebited.toJson(), '5');
    expect(effect.transferAllocation!.knownQuantity.toJson(), '5');
    expect(effect.transferAllocation!.unknownQuantity, AccountingAmount.zero);
    expect(effect.transferAllocation!.transferredCostBasis.toJson(), '50');
    expect(projection.totals.custodyMarketValue.toJson(), '45');
    expect(projection.totals.knownPositionMarketValue.toJson(), '45');
    expect(projection.totals.knownCostBasis.toJson(), '90');
    expect(projection.totals.realizedPnlKnown, AccountingAmount.zero);
  });

  test('H1-04 final ledger records paidSeparately fiat cost once', () {
    final projection = project(<AccountingMovement>[
      buy(
        id: 'a-fiat-seed',
        asset: 'UNI',
        quantity: '10',
        price: '10',
        destinationWalletId: completeWalletId,
      ),
      transferOut(
        id: 'b-fiat-paid-separately',
        asset: 'UNI',
        received: '2',
        fee: '0',
        sourceWalletId: completeWalletId,
        destinationType: DestinationType.external,
        fiatFeeAmount: '7',
        fiatFeeTreatment: FiatFeeTreatment.paidSeparately,
      ),
    ]);
    final effect = projection.effects['b-fiat-paid-separately']!;

    expect(effect.feeEffect.fiatCostEffect.toJson(), '7');
    expect(projection.totals.fiatCostEffect.toJson(), '7');
    expect(projection.totals.realizedPnlKnown, AccountingAmount.zero);
  });

  test('H1-04 final ledger records combined fiat and crypto fees once', () {
    final projection = project(<AccountingMovement>[
      buy(
        id: 'a-combined-seed',
        asset: 'UNI',
        quantity: '10',
        price: '10',
        destinationWalletId: completeWalletId,
      ),
      transferOut(
        id: 'b-combined-transfer',
        asset: 'UNI',
        received: '2',
        fee: '1',
        sourceWalletId: completeWalletId,
        destinationType: DestinationType.external,
        fiatFeeAmount: '5',
        fiatFeeTreatment: FiatFeeTreatment.combined,
      ),
    ]);
    final effect = projection.effects['b-combined-transfer']!;

    expect(effect.feeEffect.assetCustodyDebit.toJson(), '1');
    expect(effect.feeEffect.fiatCostEffect.toJson(), '5');
    expect(effect.custodyLegs.single.applied.toJson(), '-3');
    expect(effect.globalDeltasByAsset['UNI']!.toJson(), '-3');
    expect(projection.totals.fiatCostEffect.toJson(), '5');
    expect(projection.totals.realizedPnlKnown, AccountingAmount.zero);
  });

  test('H1-07 cross-asset fee publishes every leg and global delta', () {
    final projection = project(<AccountingMovement>[
      buy(
        id: 'a-cross-uni-seed',
        asset: 'UNI',
        quantity: '10',
        price: '10',
        destinationWalletId: completeWalletId,
      ),
      buy(
        id: 'b-cross-eth-seed',
        asset: 'ETH',
        quantity: '2',
        price: '20',
        destinationWalletId: completeWalletId,
      ),
      transferOut(
        id: 'c-cross-asset-transfer',
        asset: 'UNI',
        received: '4',
        fee: '0.5',
        feeAsset: 'ETH',
        sourceWalletId: completeWalletId,
        destinationWalletId: partialWalletId,
        destinationType: DestinationType.ownWallet,
      ),
    ]);
    final effect = projection.effects['c-cross-asset-transfer']!;

    expect(effect.custodyLegs, hasLength(3));
    expect(
      effect.custodyLegs.map(
        (leg) =>
            '${leg.kind.name}:${leg.key.walletId}:${leg.key.asset}:${leg.applied.toJson()}',
      ),
      <String>[
        'custodyDebit:$completeWalletId:UNI:-4',
        'custodyCredit:$partialWalletId:UNI:4',
        'custodyDebit:$completeWalletId:ETH:-0.5',
      ],
    );
    expect(effect.globalDeltasByAsset['UNI'], AccountingAmount.zero);
    expect(effect.globalDeltasByAsset['ETH']!.toJson(), '-0.5');
    expect(effect.feeEffect.assetCustodyDebit, AccountingAmount.zero);
    expect(effect.feeEffect.otherAssetCustodyDebit['ETH']!.toJson(), '0.5');
    expect(effect.transferAllocation!.knownQuantity.toJson(), '4');
    expect(effect.transferAllocation!.transferredCostBasis.toJson(), '40');
    expect(() => effect.custodyLegs.clear(), throwsUnsupportedError);
    expect(
      () => effect.globalDeltasByAsset['BTC'] = AccountingAmount.zero,
      throwsUnsupportedError,
    );
    expect(
      () => effect.feeEffect.otherAssetCustodyDebit['BTC'] =
          AccountingAmount.zero,
      throwsUnsupportedError,
    );
    expect(
      () => effect.issues.add(
        const ProjectionIssue(
          ProjectionIssueCode.invalidAmount,
          'c-cross-asset-transfer',
          'No debe agregarse',
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test('H1-07 partial transfer effect retains every requested remainder', () {
    final projection = project(<AccountingMovement>[
      buy(
        id: 'a-partial-effect-seed',
        asset: 'UNI',
        quantity: '1',
        price: '10',
        destinationWalletId: completeWalletId,
      ),
      transferOut(
        id: 'b-partial-effect-transfer',
        asset: 'UNI',
        received: '3',
        fee: '0',
        sourceWalletId: completeWalletId,
        destinationWalletId: partialWalletId,
        destinationType: DestinationType.ownWallet,
      ),
    ]);
    final effect = projection.effects['b-partial-effect-transfer']!;

    expect(effect.requestedQuantity.toJson(), '3');
    expect(effect.appliedQuantity.toJson(), '1');
    expect(effect.unappliedQuantity.toJson(), '2');
    expect(effect.custodyLegs, hasLength(2));
    expect(effect.custodyLegs[0].requested.toJson(), '-3');
    expect(effect.custodyLegs[0].applied.toJson(), '-1');
    expect(effect.custodyLegs[0].unapplied.toJson(), '-2');
    expect(effect.custodyLegs[1].requested.toJson(), '3');
    expect(effect.custodyLegs[1].applied.toJson(), '1');
    expect(effect.custodyLegs[1].unapplied.toJson(), '2');
    expect(effect.globalDeltasByAsset['UNI'], AccountingAmount.zero);
    expect(effect.transferAllocation!.totalDebited.toJson(), '1');
    expect(effect.transferAllocation!.knownQuantity.toJson(), '1');
    expect(effect.transferAllocation!.transferredCostBasis.toJson(), '10');
  });

  test(
    'preserves legacy global principal in the unassigned virtual bucket',
    () {
      final projection = project(<AccountingMovement>[
        buy(
          id: 'legacy-buy',
          asset: 'UNI',
          quantity: '10',
          price: '10',
          assignment: WalletAssignmentStatus.legacyUnassigned,
        ),
        transferOut(
          id: 'legacy-owned-transfer',
          asset: 'UNI',
          received: '4',
          fee: '1',
          destinationType: DestinationType.ownWallet,
          assignment: WalletAssignmentStatus.legacyUnassigned,
        ),
      ]);
      final position = projection
          .positions[const WalletAssetKey(virtualUnassignedWalletId, 'UNI')]!;
      final effect = projection.effects['legacy-owned-transfer']!;

      expect(projection.positions, hasLength(1));
      expect(position.custody.reconciledQuantity.toJson(), '9');
      expect(position.performance.knownQuantity.toJson(), '9');
      expect(position.performance.knownCostBasis.toJson(), '90');
      expect(effect.requestedQuantity.toJson(), '5');
      expect(effect.appliedQuantity.toJson(), '5');
      expect(effect.unappliedQuantity, AccountingAmount.zero);
      expect(
        projection.issues.map((issue) => issue.code),
        isNot(contains(ProjectionIssueCode.sameWalletTransfer)),
      );
    },
  );

  test('attributes transferred unknown quantity to the transfer movement', () {
    final projection = project(<AccountingMovement>[
      buy(
        id: 'mixed-buy',
        asset: 'UNI',
        quantity: '10',
        price: '10',
        destinationWalletId: completeWalletId,
      ),
      adjustment(
        id: 'mixed-adjustment',
        walletId: completeWalletId,
        asset: 'UNI',
        quantity: '2',
        observed: '12',
      ),
      transferOut(
        id: 'mixed-transfer',
        asset: 'UNI',
        received: '6',
        fee: '0',
        sourceWalletId: completeWalletId,
        destinationWalletId: partialWalletId,
        destinationType: DestinationType.ownWallet,
      ),
    ]);
    final destination =
        projection.positions[const WalletAssetKey(partialWalletId, 'UNI')]!;

    expect(
      destination.completeness.state,
      AccountingCompleteness.partiallyKnown,
    );
    expect(destination.knownAvailable.toJson(), '5');
    expect(destination.unknownAvailable.toJson(), '1');
    expect(destination.completeness.causingMovementIds, <String>[
      'mixed-transfer',
    ]);
    expect(
      projection.issues
          .where(
            (issue) =>
                issue.code == ProjectionIssueCode.unknownCostBasis &&
                issue.movementId == 'mixed-transfer',
          )
          .length,
      1,
    );
  });

  test(
    'bounds a malformed legacy fee-only transfer and keeps typed effects',
    () {
      final projection = project(<AccountingMovement>[
        buy(
          id: 'fee-only-balance',
          asset: 'UNI',
          quantity: '0.5',
          price: '10',
          assignment: WalletAssignmentStatus.legacyUnassigned,
        ),
        movement(
          id: 'fee-only-transfer',
          type: MovementType.transferOut,
          asset: 'UNI',
          cryptoFeeAmount: '0.75',
          cryptoFeeAsset: 'UNI',
          assignment: WalletAssignmentStatus.legacyUnassigned,
        ),
      ]);
      final effect = projection.effects['fee-only-transfer']!;

      expect(effect.requestedQuantity.toJson(), '0.75');
      expect(effect.appliedQuantity.toJson(), '0.5');
      expect(effect.unappliedQuantity.toJson(), '0.25');
      expect(
        effect.issues.map((issue) => issue.code),
        containsAll(<ProjectionIssueCode>[
          ProjectionIssueCode.invalidAmount,
          ProjectionIssueCode.insufficientCustody,
          ProjectionIssueCode.missingDestinationClassification,
        ]),
      );
      expect(
        projection
            .positions[const WalletAssetKey(virtualUnassignedWalletId, 'UNI')]!
            .custody
            .reconciledQuantity,
        AccountingAmount.zero,
      );
    },
  );

  test('reports bounded effects for a fee-only transfer in another asset', () {
    final projection = project(<AccountingMovement>[
      buy(
        id: 'other-fee-balance',
        asset: 'ETH',
        quantity: '0.5',
        price: '10',
        assignment: WalletAssignmentStatus.legacyUnassigned,
      ),
      movement(
        id: 'other-fee-transfer',
        type: MovementType.transferOut,
        asset: 'UNI',
        cryptoFeeAmount: '0.75',
        cryptoFeeAsset: 'ETH',
        assignment: WalletAssignmentStatus.legacyUnassigned,
      ),
    ]);
    final effect = projection.effects['other-fee-transfer']!;

    expect(effect.requestedQuantity.toJson(), '0.75');
    expect(effect.appliedQuantity.toJson(), '0.5');
    expect(effect.unappliedQuantity.toJson(), '0.25');
    expect(
      effect.issues.map((issue) => issue.code),
      contains(ProjectionIssueCode.insufficientCustody),
    );
  });

  test('routes broken wallet references to an explicit virtual bucket', () {
    const archivedWalletId = '33333333-3333-4333-8333-333333333333';
    final projection = project(
      <AccountingMovement>[
        buy(
          id: 'broken-wallet-buy',
          asset: 'UNI',
          quantity: '1',
          price: '10',
          destinationWalletId: 'missing-wallet-id',
        ),
        buy(
          id: 'archived-wallet-buy',
          asset: 'UNI',
          quantity: '2',
          price: '10',
          destinationWalletId: archivedWalletId,
        ),
        buy(
          id: 'spoofed-virtual-buy',
          asset: 'UNI',
          quantity: '1',
          price: '10',
          destinationWalletId: 'virtual:spoofed',
        ),
      ],
      wallets: <Wallet>[
        wallet(completeWalletId),
        wallet(archivedWalletId, status: WalletStatus.archived),
      ],
    );

    expect(
      projection.positions.keys.map((key) => key.walletId),
      isNot(containsAll(<String>['missing-wallet-id', 'virtual:spoofed'])),
    );
    final unknown =
        projection.positions[const WalletAssetKey('virtual:unknown', 'UNI')]!;
    expect(unknown.custody.reconciledQuantity.toJson(), '2');
    expect(unknown.completeness.cause?.name, 'unknownWallet');
    expect(
      unknown.completeness.causingMovementIds,
      containsAll(<String>['broken-wallet-buy', 'spoofed-virtual-buy']),
    );
    expect(
      projection.issues.where(
        (issue) =>
            issue.code.name == 'unknownWallet' &&
            issue.movementId == 'broken-wallet-buy',
      ),
      hasLength(1),
    );
    expect(
      projection.issues.where(
        (issue) =>
            issue.code.name == 'unknownWallet' &&
            issue.movementId == 'spoofed-virtual-buy',
      ),
      hasLength(1),
    );
    expect(
      projection
          .positions[const WalletAssetKey(archivedWalletId, 'UNI')]!
          .custody
          .reconciledQuantity
          .toJson(),
      '2',
    );
  });

  test('rejects supplied wallets in the reserved virtual namespace', () {
    const archivedWalletId = '33333333-3333-4333-8333-333333333333';
    const reservedWalletIds = <String>[
      virtualUnassignedWalletId,
      virtualPendingWalletId,
      virtualUnknownWalletId,
      'virtual:arbitrary',
    ];
    final reservedMovementIds = <String>[
      for (var index = 0; index < reservedWalletIds.length; index++)
        'reserved-wallet-buy-$index',
    ];
    final projection = project(
      <AccountingMovement>[
        for (var index = 0; index < reservedWalletIds.length; index++)
          buy(
            id: reservedMovementIds[index],
            asset: 'UNI',
            quantity: '1',
            price: '10',
            destinationWalletId: reservedWalletIds[index],
          ),
        buy(
          id: 'archived-wallet-history',
          asset: 'UNI',
          quantity: '2',
          price: '10',
          destinationWalletId: archivedWalletId,
        ),
      ],
      wallets: <Wallet>[
        for (final walletId in reservedWalletIds) wallet(walletId),
        wallet(archivedWalletId, status: WalletStatus.archived),
      ],
    );

    expect(
      projection.positions.keys.map((key) => key.walletId),
      isNot(
        containsAll(<String>[
          virtualUnassignedWalletId,
          virtualPendingWalletId,
          'virtual:arbitrary',
        ]),
      ),
    );
    final unknown = projection
        .positions[const WalletAssetKey(virtualUnknownWalletId, 'UNI')]!;
    expect(unknown.custody.reconciledQuantity.toJson(), '4');
    expect(unknown.completeness.cause?.name, 'unknownWallet');
    expect(
      unknown.completeness.causingMovementIds,
      containsAll(reservedMovementIds),
    );
    final unknownWalletIssues = projection.issues
        .where((issue) => issue.code == ProjectionIssueCode.unknownWallet)
        .toList();
    expect(unknownWalletIssues, hasLength(reservedWalletIds.length));
    expect(
      unknownWalletIssues.map((issue) => issue.movementId),
      containsAll(reservedMovementIds),
    );
    for (final movementId in reservedMovementIds) {
      expect(
        projection.effects[movementId]!.issues.map((issue) => issue.code),
        contains(ProjectionIssueCode.unknownWallet),
      );
    }
    final archived =
        projection.positions[const WalletAssetKey(archivedWalletId, 'UNI')]!;
    expect(archived.custody.reconciledQuantity.toJson(), '2');
    expect(archived.completeness.cause, isNull);
    expect(projection.migrationProgress.assigned, 1);
    expect(projection.migrationProgress.total, 5);
  });
}

const String completeWalletId = '11111111-1111-4111-8111-111111111111';
const String partialWalletId = '22222222-2222-4222-8222-222222222222';
final DateTime baseTime = DateTime.utc(2026, 7, 30, 20, 54);

AccountingAmount amount(String value) => AccountingAmount.parse(value);

LedgerProjection project(
  List<AccountingMovement> movements, {
  Map<String, AccountingAmount> prices = const <String, AccountingAmount>{},
  List<Wallet>? wallets,
}) =>
    const AccountingLedgerEngine(
      DefaultMovementNormalizer(),
      DefaultCustodyProjector(),
      DefaultPerformanceProjector(),
    ).project(
      LedgerInput(
        wallets:
            wallets ??
            <Wallet>[wallet(completeWalletId), wallet(partialWalletId)],
        movements: movements,
        currentPrices: prices,
        saleCostConsumptionPolicy: SaleCostConsumptionPolicy.knownFirst,
        transferCostAllocationPolicy: TransferCostAllocationPolicy.proportional,
        legacyAccountingPolicy: LegacyAccountingPolicy.preservePreviousGlobal,
      ),
    );

Wallet wallet(String id, {WalletStatus status = WalletStatus.active}) => Wallet(
  id: id,
  name: 'Wallet $id',
  provider: 'Bitso',
  status: status,
  createdAt: baseTime,
  updatedAt: baseTime,
);

AccountingMovement buy({
  required String id,
  required String asset,
  required String quantity,
  required String price,
  String? destinationWalletId,
  WalletAssignmentStatus assignment = WalletAssignmentStatus.assigned,
}) => movement(
  id: id,
  type: MovementType.buy,
  asset: asset,
  quantity: quantity,
  price: price,
  destinationWalletId: destinationWalletId,
  assignment: assignment,
);

AccountingMovement transferIn({
  required String id,
  required String asset,
  required String quantity,
  required WalletAssignmentStatus assignment,
}) => movement(
  id: id,
  type: MovementType.transferIn,
  asset: asset,
  quantity: quantity,
  assignment: assignment,
);

AccountingMovement transferOut({
  required String id,
  required String asset,
  required String received,
  required String fee,
  String? feeAsset,
  String? sourceWalletId,
  String? destinationWalletId,
  required DestinationType destinationType,
  WalletAssignmentStatus assignment = WalletAssignmentStatus.assigned,
  String fiatFeeAmount = '0',
  FiatFeeTreatment fiatFeeTreatment = FiatFeeTreatment.none,
}) => movement(
  id: id,
  type: MovementType.transferOut,
  asset: asset,
  quantity: received,
  sourceWalletId: sourceWalletId,
  destinationWalletId: destinationWalletId,
  destinationType: destinationType,
  externalRecipientName: destinationType == DestinationType.external
      ? 'Tercero'
      : null,
  externalDestinationPlatform: destinationType == DestinationType.external
      ? 'Bitso'
      : null,
  receivedAmount: received,
  cryptoFeeAmount: fee,
  cryptoFeeAsset: fee == '0' ? null : feeAsset ?? asset,
  totalDebitedAmount:
      (fee != '0' && (feeAsset ?? asset) == asset
              ? amount(received) + amount(fee)
              : amount(received))
          .toJson(),
  fiatFeeAmount: fiatFeeAmount,
  fiatFeeTreatment: fiatFeeTreatment,
  assignment: assignment,
);

AccountingMovement adjustment({
  required String id,
  required String walletId,
  required String asset,
  required String quantity,
  required String observed,
}) => movement(
  id: id,
  type: MovementType.balanceAdjustment,
  asset: asset,
  adjustmentWalletId: walletId,
  adjustmentQuantity: quantity,
  observedBalance: observed,
  assignment: WalletAssignmentStatus.assigned,
);

AccountingMovement movement({
  required String id,
  required MovementType type,
  required String asset,
  String? quantity,
  String? price,
  String? sourceWalletId,
  String? destinationWalletId,
  DestinationType? destinationType,
  String? externalRecipientName,
  String? externalDestinationPlatform,
  String? receivedAmount,
  String cryptoFeeAmount = '0',
  String? cryptoFeeAsset,
  String? totalDebitedAmount,
  String? adjustmentWalletId,
  String? adjustmentQuantity,
  String? observedBalance,
  required WalletAssignmentStatus assignment,
  String fiatFeeAmount = '0',
  FiatFeeTreatment fiatFeeTreatment = FiatFeeTreatment.none,
}) {
  final occurredAt = baseTime.add(
    Duration(
      minutes: switch (id) {
        'complete-buy' => 0,
        'partial-buy' => 1,
        'partial-adjustment' => 2,
        'pending-buy' => 3,
        'legacy-in' => 4,
        'deficit-buy' || 'internal-buy' || 'legacy-buy' => 0,
        'deficit-adjustment' ||
        'internal-transfer' ||
        'legacy-owned-transfer' => 1,
        'mixed-buy' => 0,
        'mixed-adjustment' => 1,
        'mixed-transfer' => 2,
        _ => 5,
      },
    ),
  );
  return AccountingMovement(
    id: id,
    type: type,
    asset: asset,
    occurredAt: occurredAt,
    quantity: quantity == null ? null : amount(quantity),
    unitPriceFiat: price == null ? null : amount(price),
    fiatFeeAmount: amount(fiatFeeAmount),
    sourceWalletId: sourceWalletId,
    destinationWalletId: destinationWalletId,
    destinationType: destinationType,
    externalRecipientName: externalRecipientName,
    externalDestinationPlatform: externalDestinationPlatform,
    walletAssignmentStatus: assignment,
    receivedAmount: receivedAmount == null ? null : amount(receivedAmount),
    cryptoFeeAmount: amount(cryptoFeeAmount),
    cryptoFeeAsset: cryptoFeeAsset,
    totalDebitedAmount: totalDebitedAmount == null
        ? null
        : amount(totalDebitedAmount),
    fiatFeeTreatment: fiatFeeTreatment,
    reconciliationLinks: const <ReconciliationLink>[],
    createdAt: occurredAt,
    updatedAt: occurredAt,
    adjustmentWalletId: adjustmentWalletId,
    adjustmentQuantity: adjustmentQuantity == null
        ? null
        : amount(adjustmentQuantity),
    observedBalance: observedBalance == null ? null : amount(observedBalance),
    adjustmentReason: type == MovementType.balanceAdjustment ? 'Corte' : null,
  );
}
