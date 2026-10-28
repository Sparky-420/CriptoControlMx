import 'package:cripto_control_mx/accounting/adapters/legacy_financial_adapter.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_movement.dart';
import 'package:cripto_control_mx/accounting/domain/ledger_validation.dart';
import 'package:cripto_control_mx/accounting/domain/movement_normalizer.dart';
import 'package:cripto_control_mx/accounting/domain/movement_type.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/projection/accounting_ledger_engine.dart';
import 'package:cripto_control_mx/accounting/projection/custody_projection.dart';
import 'package:cripto_control_mx/accounting/projection/custody_projector.dart';
import 'package:cripto_control_mx/accounting/projection/performance_projection.dart';
import 'package:cripto_control_mx/accounting/projection/performance_projector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('H1-10 integral projection rebuild matrix', () {
    for (final scenario in _scenarios()) {
      test('${scenario.name}: edit, delete and revert are exact', () {
        final originalMovements = <AccountingMovement>[
          ...scenario.base,
          scenario.original,
        ];
        final editedMovements = _replaceById(
          originalMovements,
          scenario.edited,
        );
        final deletedMovements = _deleteById(
          originalMovements,
          scenario.original.id,
        );
        final revertedMovements = _replaceById(
          editedMovements,
          scenario.original,
        );
        final original = _project(originalMovements);
        final originalSnapshot = _snapshot(original);

        scenario.verify(original);
        expect(
          _snapshot(_project(originalMovements.reversed.toList())),
          equals(originalSnapshot),
          reason: 'reordering the source list must rebuild the same ledger',
        );
        expect(
          _snapshot(_project(editedMovements)),
          isNot(equals(originalSnapshot)),
          reason: 'editing the event in place must change the full projection',
        );
        expect(
          _snapshot(_project(deletedMovements)),
          equals(
            _snapshot(_project(List<AccountingMovement>.of(scenario.base))),
          ),
          reason: 'deletion must equal a fresh rebuild of the remaining events',
        );
        expect(
          _snapshot(_project(revertedMovements)),
          equals(originalSnapshot),
          reason: 'reverting the edit must restore every projection field',
        );
      });
    }
  });
}

List<_RebuildScenario> _scenarios() => <_RebuildScenario>[
  _RebuildScenario(
    name: 'documented external transferIn',
    base: const <AccountingMovement>[],
    original: _transferIn(
      id: '01-known-transfer-in',
      quantity: '2',
      price: '100',
      fiatFee: '5',
    ),
    edited: _transferIn(
      id: '01-known-transfer-in',
      quantity: '3',
      price: '100',
      fiatFee: '5',
    ),
    verify: (projection) {
      final position =
          projection.positions[const WalletAssetKey(_walletA, 'UNI')]!;
      expect(position.performance.knownQuantity.toJson(), '2');
      expect(position.performance.knownCostBasis.toJson(), '205');
      expect(position.custody.reconciledQuantity.toJson(), '2');
    },
  ),
  _RebuildScenario(
    name: 'rejected invalid buy',
    base: <AccountingMovement>[
      _buy(id: '01-valid-buy', quantity: '10', price: '10'),
    ],
    original: _buy(
      id: '02-invalid-buy',
      quantity: '-1',
      price: '10',
      minute: 2,
    ),
    edited: _buy(
      id: '02-invalid-buy',
      quantity: '1',
      price: '10',
      minute: 2,
      sourceWalletId: _walletB,
    ),
    verify: (projection) {
      final position =
          projection.positions[const WalletAssetKey(_walletA, 'UNI')]!;
      expect(position.performance.knownQuantity.toJson(), '10');
      expect(position.performance.knownCostBasis.toJson(), '100');
      expect(
        projection.issues.map((issue) => issue.code),
        contains(ProjectionIssueCode.invalidAmount),
      );
    },
  ),
  _RebuildScenario(
    name: 'final paid-separately fiat fee',
    base: <AccountingMovement>[
      _buy(id: '01-fee-buy', quantity: '10', price: '10'),
    ],
    original: _transferOut(
      id: '02-fiat-fee-transfer',
      received: '2',
      destinationType: DestinationType.external,
      fiatFee: '7',
      fiatFeeTreatment: FiatFeeTreatment.paidSeparately,
    ),
    edited: _transferOut(
      id: '02-fiat-fee-transfer',
      received: '2',
      destinationType: DestinationType.external,
      fiatFee: '9',
      fiatFeeTreatment: FiatFeeTreatment.paidSeparately,
    ),
    verify: (projection) {
      expect(projection.totals.fiatCostEffect.toJson(), '7');
      expect(
        projection.effects['02-fiat-fee-transfer']!.feeEffect.fiatCostEffect
            .toJson(),
        '7',
      );
      expect(projection.totals.realizedPnlKnown, AccountingAmount.zero);
    },
  ),
  _RebuildScenario(
    name: 'applied portion of insufficient sale',
    base: <AccountingMovement>[
      _buy(id: '01-sale-buy', quantity: '10', price: '10'),
    ],
    original: _sell(id: '02-insufficient-sale', quantity: '12', price: '20'),
    edited: _sell(id: '02-insufficient-sale', quantity: '11', price: '20'),
    verify: (projection) {
      final sale = projection.sales.single;
      expect(sale.status, SaleAccountingStatus.insufficientCustody);
      expect(sale.knownQuantity.toJson(), '10');
      expect(sale.pendingCostQuantity, AccountingAmount.zero);
      expect(sale.demonstratedCostBasis.toJson(), '100');
      expect(
        projection.effects['02-insufficient-sale']!.unappliedQuantity.toJson(),
        '2',
      );
    },
  ),
  _RebuildScenario(
    name: 'proportional transfer under custody deficit',
    base: <AccountingMovement>[
      _buy(id: '01-deficit-buy', quantity: '3', price: '1', fiatFee: '1'),
      _adjustment(id: '02-deficit-adjustment', quantity: '-1', observed: '2'),
    ],
    original: _transferOut(
      id: '03-deficit-transfer',
      received: '1',
      destinationType: DestinationType.ownWallet,
      destinationWalletId: _walletB,
    ),
    edited: _transferOut(
      id: '03-deficit-transfer',
      received: '0.5',
      destinationType: DestinationType.ownWallet,
      destinationWalletId: _walletB,
    ),
    verify: (projection) {
      final source =
          projection.positions[const WalletAssetKey(_walletA, 'UNI')]!;
      final destination =
          projection.positions[const WalletAssetKey(_walletB, 'UNI')]!;
      expect(
        source.performance.knownCostBasis.toJson(),
        '2.666666666666666667',
      );
      expect(
        destination.performance.knownCostBasis.toJson(),
        '1.333333333333333333',
      );
      expect(
        projection
            .effects['03-deficit-transfer']!
            .transferAllocation!
            .transferredCostBasis
            .toJson(),
        '1.333333333333333333',
      );
    },
  ),
  _RebuildScenario(
    name: 'incomplete legacy adapter position',
    base: <AccountingMovement>[
      _buy(id: '01-partial-buy', quantity: '10', price: '10'),
    ],
    original: _adjustment(
      id: '02-partial-adjustment',
      quantity: '2',
      observed: '12',
    ),
    edited: _adjustment(
      id: '02-partial-adjustment',
      quantity: '3',
      observed: '13',
    ),
    verify: (projection) {
      final stats = const LegacyFinancialAdapter().coinStats(
        projection,
        const <String, double>{'UNI': 50},
      )['UNI']!;
      expect(stats.quantity, 10);
      expect(stats.custodyQuantity, 12);
      expect(stats.unknownQuantity, 2);
      expect(stats.completeness, AccountingCompleteness.partiallyKnown);
      expect(stats.hasDefinitivePerformance, isFalse);
    },
  ),
  _RebuildScenario(
    name: 'multi-leg cross-asset transfer effect',
    base: <AccountingMovement>[
      _buy(id: '01-btc-buy', asset: 'BTC', quantity: '5', price: '10'),
      _buy(
        id: '02-eth-buy',
        asset: 'ETH',
        quantity: '2',
        price: '20',
        minute: 2,
      ),
    ],
    original: _transferOut(
      id: '03-cross-asset-transfer',
      asset: 'BTC',
      received: '2',
      cryptoFee: '1',
      cryptoFeeAsset: 'ETH',
      destinationType: DestinationType.ownWallet,
      destinationWalletId: _walletB,
    ),
    edited: _transferOut(
      id: '03-cross-asset-transfer',
      asset: 'BTC',
      received: '1',
      cryptoFee: '1',
      cryptoFeeAsset: 'ETH',
      destinationType: DestinationType.ownWallet,
      destinationWalletId: _walletB,
    ),
    verify: (projection) {
      final effect = projection.effects['03-cross-asset-transfer']!;
      expect(effect.custodyLegs, hasLength(3));
      expect(effect.globalDeltasByAsset['BTC'], AccountingAmount.zero);
      expect(effect.globalDeltasByAsset['ETH']!.toJson(), '-1');
      expect(effect.feeEffect.otherAssetCustodyDebit['ETH']!.toJson(), '1');
      expect(effect.transferAllocation!.knownQuantity.toJson(), '2');
    },
  ),
];

final class _RebuildScenario {
  const _RebuildScenario({
    required this.name,
    required this.base,
    required this.original,
    required this.edited,
    required this.verify,
  });

  final String name;
  final List<AccountingMovement> base;
  final AccountingMovement original;
  final AccountingMovement edited;
  final void Function(LedgerProjection projection) verify;
}

const String _walletA = '11111111-1111-4111-8111-111111111111';
const String _walletB = '22222222-2222-4222-8222-222222222222';
const String _walletC = '33333333-3333-4333-8333-333333333333';
final DateTime _at = DateTime.utc(2026, 8, 11, 12);

List<AccountingMovement> _replaceById(
  List<AccountingMovement> movements,
  AccountingMovement replacement,
) => <AccountingMovement>[
  for (final movement in movements)
    if (movement.id == replacement.id) replacement else movement,
];

List<AccountingMovement> _deleteById(
  List<AccountingMovement> movements,
  String movementId,
) => <AccountingMovement>[
  for (final movement in movements)
    if (movement.id != movementId) movement,
];

LedgerProjection _project(List<AccountingMovement> movements) =>
    const AccountingLedgerEngine(
      DefaultMovementNormalizer(),
      DefaultCustodyProjector(),
      DefaultPerformanceProjector(),
    ).project(
      LedgerInput(
        wallets: <Wallet>[
          _wallet(_walletA),
          _wallet(_walletB),
          _wallet(_walletC),
        ],
        movements: movements,
        currentPrices: <String, AccountingAmount>{
          'UNI': _amount('50'),
          'BTC': _amount('100'),
          'ETH': _amount('20'),
        },
        saleCostConsumptionPolicy: SaleCostConsumptionPolicy.knownFirst,
        transferCostAllocationPolicy: TransferCostAllocationPolicy.proportional,
        legacyAccountingPolicy: LegacyAccountingPolicy.preservePreviousGlobal,
      ),
    );

Wallet _wallet(String id) => Wallet(
  id: id,
  name: id,
  provider: 'Bitso',
  status: WalletStatus.active,
  createdAt: _at,
  updatedAt: _at,
);

AccountingAmount _amount(String value) => AccountingAmount.parse(value);

AccountingMovement _buy({
  required String id,
  String asset = 'UNI',
  required String quantity,
  required String price,
  String destinationWalletId = _walletA,
  String? sourceWalletId,
  String fiatFee = '0',
  int minute = 1,
}) => _movement(
  id: id,
  type: MovementType.buy,
  asset: asset,
  quantity: quantity,
  price: price,
  sourceWalletId: sourceWalletId,
  destinationWalletId: destinationWalletId,
  fiatFee: fiatFee,
  fiatFeeTreatment: fiatFee == '0'
      ? FiatFeeTreatment.none
      : FiatFeeTreatment.paidSeparately,
  minute: minute,
);

AccountingMovement _transferIn({
  required String id,
  required String quantity,
  required String price,
  required String fiatFee,
}) => _movement(
  id: id,
  type: MovementType.transferIn,
  asset: 'UNI',
  quantity: quantity,
  price: price,
  destinationWalletId: _walletA,
  fiatFee: fiatFee,
  fiatFeeTreatment: FiatFeeTreatment.paidSeparately,
  minute: 1,
);

AccountingMovement _sell({
  required String id,
  required String quantity,
  required String price,
}) => _movement(
  id: id,
  type: MovementType.sell,
  asset: 'UNI',
  quantity: quantity,
  price: price,
  sourceWalletId: _walletA,
  minute: 2,
);

AccountingMovement _adjustment({
  required String id,
  required String quantity,
  required String observed,
}) => _movement(
  id: id,
  type: MovementType.balanceAdjustment,
  asset: 'UNI',
  adjustmentWalletId: _walletA,
  adjustmentQuantity: quantity,
  observedBalance: observed,
  minute: 2,
);

AccountingMovement _transferOut({
  required String id,
  String asset = 'UNI',
  required String received,
  String cryptoFee = '0',
  String? cryptoFeeAsset,
  required DestinationType destinationType,
  String? destinationWalletId,
  String fiatFee = '0',
  FiatFeeTreatment fiatFeeTreatment = FiatFeeTreatment.none,
}) => _movement(
  id: id,
  type: MovementType.transferOut,
  asset: asset,
  quantity: received,
  sourceWalletId: _walletA,
  destinationWalletId: destinationWalletId,
  destinationType: destinationType,
  externalRecipientName: destinationType == DestinationType.external
      ? 'Tercero'
      : null,
  externalDestinationPlatform: destinationType == DestinationType.external
      ? 'Otra plataforma'
      : null,
  receivedAmount: received,
  cryptoFee: cryptoFee,
  cryptoFeeAsset: cryptoFee == '0' ? null : cryptoFeeAsset ?? asset,
  totalDebited: (cryptoFee != '0' && (cryptoFeeAsset ?? asset) == asset)
      ? (_amount(received) + _amount(cryptoFee)).toJson()
      : received,
  fiatFee: fiatFee,
  fiatFeeTreatment: fiatFeeTreatment,
  minute: 3,
);

AccountingMovement _movement({
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
  String cryptoFee = '0',
  String? cryptoFeeAsset,
  String? totalDebited,
  String? adjustmentWalletId,
  String? adjustmentQuantity,
  String? observedBalance,
  String fiatFee = '0',
  FiatFeeTreatment fiatFeeTreatment = FiatFeeTreatment.none,
  required int minute,
}) {
  final occurredAt = _at.add(Duration(minutes: minute));
  return AccountingMovement(
    id: id,
    type: type,
    asset: asset,
    occurredAt: occurredAt,
    quantity: quantity == null ? null : _amount(quantity),
    unitPriceFiat: price == null ? null : _amount(price),
    fiatFeeAmount: _amount(fiatFee),
    sourceWalletId: sourceWalletId,
    destinationWalletId: destinationWalletId,
    destinationType: destinationType,
    externalRecipientName: externalRecipientName,
    externalDestinationPlatform: externalDestinationPlatform,
    walletAssignmentStatus: WalletAssignmentStatus.assigned,
    receivedAmount: receivedAmount == null ? null : _amount(receivedAmount),
    cryptoFeeAmount: _amount(cryptoFee),
    cryptoFeeAsset: cryptoFeeAsset,
    totalDebitedAmount: totalDebited == null ? null : _amount(totalDebited),
    fiatFeeTreatment: fiatFeeTreatment,
    reconciliationLinks: const <ReconciliationLink>[],
    createdAt: occurredAt,
    updatedAt: occurredAt,
    adjustmentWalletId: adjustmentWalletId,
    adjustmentQuantity: adjustmentQuantity == null
        ? null
        : _amount(adjustmentQuantity),
    observedBalance: observedBalance == null ? null : _amount(observedBalance),
    adjustmentReason: type == MovementType.balanceAdjustment ? 'Corte' : null,
  );
}

Map<String, Object?> _snapshot(LedgerProjection projection) {
  final positions = projection.positions.entries.toList()
    ..sort((left, right) => _key(left.key).compareTo(_key(right.key)));
  final effects = projection.effects.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  final legacyStats = const LegacyFinancialAdapter().coinStats(
    projection,
    const <String, double>{'UNI': 50, 'BTC': 100, 'ETH': 20},
  );
  final legacyEntries = legacyStats.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return <String, Object?>{
    'positions': <String, Object?>{
      for (final entry in positions) _key(entry.key): _position(entry.value),
    },
    'sales': projection.sales.map(_sale).toList(growable: false),
    'effects': <String, Object?>{
      for (final entry in effects) entry.key: _effect(entry.value),
    },
    'totals': <String, Object?>{
      'custodyMarketValue': projection.totals.custodyMarketValue.toJson(),
      'knownPositionMarketValue': projection.totals.knownPositionMarketValue
          .toJson(),
      'knownCostBasis': projection.totals.knownCostBasis.toJson(),
      'realizedPnlKnown': projection.totals.realizedPnlKnown.toJson(),
      'unrealizedPnlKnown': projection.totals.unrealizedPnlKnown.toJson(),
      'fiatCostEffect': projection.totals.fiatCostEffect.toJson(),
    },
    'issues': projection.issues.map(_issue).toList(growable: false),
    'migration': <String, Object?>{
      'assigned': projection.migrationProgress.assigned,
      'total': projection.migrationProgress.total,
    },
    'legacyStats': <String, Object?>{
      for (final entry in legacyEntries)
        entry.key: <String, Object?>{
          'quantity': entry.value.quantity,
          'custodyQuantity': entry.value.custodyQuantity,
          'unknownQuantity': entry.value.unknownQuantity,
          'completeness': entry.value.completeness.name,
          'hasDefinitivePerformance': entry.value.hasDefinitivePerformance,
          'costBase': entry.value.costBase,
          'realizedProfit': entry.value.realizedProfit,
        },
    },
  };
}

String _key(WalletAssetKey key) => '${key.walletId}|${key.asset}';

Map<String, Object?> _position(
  WalletAssetProjection position,
) => <String, Object?>{
  'custody': <String, Object?>{
    'reconciled': position.custody.reconciledQuantity.toJson(),
    'credits': position.custody.appliedCredits.toJson(),
    'debits': position.custody.appliedDebits.toJson(),
    'adjustments': position.custody.signedAdjustments.toJson(),
    'resolved': position.custody.resolvedAdjustmentQuantity.toJson(),
    'observed': position.custody.lastObservedBalance?.toJson(),
    'requested': position.custody.requestedQuantity.toJson(),
    'unapplied': position.custody.unappliedQuantity.toJson(),
    'contributors': position.custody.contributingMovementIds,
    'issues': position.custody.issues.map(_issue).toList(growable: false),
  },
  'performance': <String, Object?>{
    'knownQuantity': position.performance.knownQuantity.toJson(),
    'knownCostBasis': position.performance.knownCostBasis.toJson(),
    'averageCost': position.performance.averageCost.toJson(),
    'investedCapital': position.performance.investedCapital.toJson(),
    'realizedPnlKnown': position.performance.realizedPnlKnown.toJson(),
    'unrealizedPnlKnown': position.performance.unrealizedPnlKnown.toJson(),
    'pendingPnlQuantity': position.performance.pendingPnlQuantity.toJson(),
    'blockers': position.performance.blockingMovementIds,
    'issues': position.performance.issues.map(_issue).toList(growable: false),
  },
  'availability': <String, Object?>{
    'difference': position.availability.reconciliationDifference.toJson(),
    'known': position.availability.knownAvailable.toJson(),
    'unknown': position.availability.unknownAvailable.toJson(),
    'deficit': position.availability.custodyDeficit.toJson(),
  },
  'completeness': <String, Object?>{
    'state': position.completeness.state.name,
    'total': position.completeness.totalQuantity.toJson(),
    'known': position.completeness.knownQuantity.toJson(),
    'unknown': position.completeness.unknownQuantity.toJson(),
    'cause': position.completeness.cause?.name,
    'movements': position.completeness.causingMovementIds,
  },
  'custodyMarketValue': position.custodyMarketValue.toJson(),
  'knownPositionMarketValue': position.knownPositionMarketValue.toJson(),
};

Map<String, Object?> _effect(MovementEffect effect) {
  final deltas = effect.globalDeltasByAsset.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  final otherFees = effect.feeEffect.otherAssetCustodyDebit.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return <String, Object?>{
    'movementId': effect.movementId,
    'requested': effect.requestedQuantity.toJson(),
    'applied': effect.appliedQuantity.toJson(),
    'unapplied': effect.unappliedQuantity.toJson(),
    'custodyLegs': effect.custodyLegs
        .map(
          (leg) => <String, Object?>{
            'key': _key(leg.key),
            'kind': leg.kind.name,
            'before': leg.before.toJson(),
            'requested': leg.requested.toJson(),
            'applied': leg.applied.toJson(),
            'unapplied': leg.unapplied.toJson(),
            'after': leg.after.toJson(),
          },
        )
        .toList(growable: false),
    'globalDeltas': <String, String>{
      for (final entry in deltas) entry.key: entry.value.toJson(),
    },
    'fee': <String, Object?>{
      'assetDebit': effect.feeEffect.assetCustodyDebit.toJson(),
      'otherDebits': <String, String>{
        for (final entry in otherFees) entry.key: entry.value.toJson(),
      },
      'fiatCost': effect.feeEffect.fiatCostEffect.toJson(),
    },
    'transfer': effect.transferAllocation == null
        ? null
        : <String, Object?>{
            'totalDebited': effect.transferAllocation!.totalDebited.toJson(),
            'known': effect.transferAllocation!.knownQuantity.toJson(),
            'unknown': effect.transferAllocation!.unknownQuantity.toJson(),
            'cost': effect.transferAllocation!.transferredCostBasis.toJson(),
          },
    'sale': effect.sale == null ? null : _sale(effect.sale!),
    'issues': effect.issues.map(_issue).toList(growable: false),
  };
}

Map<String, Object?> _sale(SaleResult sale) => <String, Object?>{
  'movementId': sale.movementId,
  'status': sale.status.name,
  'total': sale.totalQuantity.toJson(),
  'known': sale.knownQuantity.toJson(),
  'cost': sale.demonstratedCostBasis.toJson(),
  'proceeds': sale.knownProceeds.toJson(),
  'fee': sale.allocatedKnownFiatFee.toJson(),
  'pnl': sale.realizedPnlKnown.toJson(),
  'pending': sale.pendingCostQuantity.toJson(),
};

Map<String, Object?> _issue(ProjectionIssue issue) => <String, Object?>{
  'code': issue.code.name,
  'movementId': issue.movementId,
  'message': issue.message,
};
