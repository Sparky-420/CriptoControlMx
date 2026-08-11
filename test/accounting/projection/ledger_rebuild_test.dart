import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_movement.dart';
import 'package:cripto_control_mx/accounting/domain/ledger_validation.dart';
import 'package:cripto_control_mx/accounting/domain/movement_type.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/projection/custody_projection.dart';
import 'package:cripto_control_mx/accounting/projection/custody_projector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rebuilds exact custody after editing and deleting an adjustment', () {
    final rebuilder = const LedgerRebuilder();
    final buy = movement(id: 'buy-1', quantity: '127');
    final original = adjustment(id: 'adj-1', quantity: '0.75883985');
    final edited = adjustment(id: 'adj-1', quantity: '-2');

    expect(
      position(
        rebuilder.rebuild(<AccountingMovement>[buy, original]),
      ).reconciledQuantity.toJson(),
      '127.75883985',
    );
    expect(
      position(
        rebuilder.rebuild(<AccountingMovement>[buy, edited]),
      ).reconciledQuantity.toJson(),
      '125',
    );
    expect(
      position(
        rebuilder.rebuild(<AccountingMovement>[buy]),
      ).reconciledQuantity.toJson(),
      '127',
    );
  });

  test(
    'a reconciliation link leaves only the adjustment remainder in custody',
    () {
      final adjustmentMovement = adjustment(id: 'adj-1', quantity: '2');
      final actualBuy = movement(
        id: 'buy-real',
        quantity: '0.5',
      ).copyWith(occurredAt: DateTime.utc(2026, 7, 30, 20, 56));
      final linkedBuy = const DifferenceReconciliationService().link(
        actualBuy,
        adjustment: adjustmentMovement,
        justifiedQuantity: AccountingAmount.parse('0.5'),
      );

      final result = position(
        const LedgerRebuilder().rebuild(<AccountingMovement>[
          adjustmentMovement,
          linkedBuy,
        ]),
      );

      expect(result.reconciledQuantity.toJson(), '2');
      expect(result.appliedCredits.toJson(), '0.5');
      expect(result.signedAdjustments.toJson(), '1.5');
      expect(result.resolvedAdjustmentQuantity.toJson(), '0.5');
      expect(result.contributingMovementIds, <String>['adj-1', 'buy-real']);
    },
  );

  test(
    'reports only the signed adjustment remainder in its custody effect',
    () {
      final adjustmentMovement = adjustment(id: 'adj-1', quantity: '2');
      final actualBuy = movement(
        id: 'buy-real',
        quantity: '0.5',
      ).copyWith(occurredAt: DateTime.utc(2026, 7, 30, 20, 56));
      final linkedBuy = const DifferenceReconciliationService().link(
        actualBuy,
        adjustment: adjustmentMovement,
        justifiedQuantity: AccountingAmount.parse('0.5'),
      );

      final effect = const LedgerRebuilder()
          .rebuild(<AccountingMovement>[adjustmentMovement, linkedBuy])
          .effectsByMovementId['adj-1']!
          .single;

      expect(effect.requested.toJson(), '1.5');
      expect(effect.applied.toJson(), '1.5');
      expect(effect.unapplied, AccountingAmount.zero);
    },
  );

  test(
    'rejects reconciliation links with invalid magnitude, wallet, asset or sign',
    () {
      final service = const DifferenceReconciliationService();
      final positiveAdjustment = adjustment(id: 'adj-1', quantity: '2');
      final actualBuy = movement(id: 'buy-real', quantity: '0.5');

      expect(
        () => service.link(
          actualBuy,
          adjustment: positiveAdjustment,
          justifiedQuantity: AccountingAmount.parse('3'),
        ),
        throwsArgumentError,
      );
      expect(
        () => service.link(
          actualBuy.copyWith(destinationWalletId: 'other-wallet'),
          adjustment: positiveAdjustment,
          justifiedQuantity: AccountingAmount.parse('0.5'),
        ),
        throwsArgumentError,
      );
      expect(
        () => service.link(
          actualBuy.copyWith(asset: 'BTC'),
          adjustment: positiveAdjustment,
          justifiedQuantity: AccountingAmount.parse('0.5'),
        ),
        throwsArgumentError,
      );
      expect(
        () => service.link(
          actualBuy,
          adjustment: adjustment(id: 'negative-adj', quantity: '-2'),
          justifiedQuantity: AccountingAmount.parse('0.5'),
        ),
        throwsArgumentError,
      );
    },
  );

  test('reports a linked adjustment deletion until links are resolved', () {
    final orphanedLink = movement(id: 'buy-real', quantity: '0.5').copyWith(
      reconciliationLinks: <ReconciliationLink>[
        ReconciliationLink(
          adjustmentMovementId: 'deleted-adj',
          quantityResolved: AccountingAmount.parse('0.5'),
        ),
      ],
    );

    final result = position(
      const LedgerRebuilder().rebuild(<AccountingMovement>[orphanedLink]),
    );

    expect(
      result.issues.map((issue) => issue.code),
      contains(ProjectionIssueCode.linkedAdjustmentDeletion),
    );
  });

  test(
    'links an internal transfer credit to a positive destination adjustment',
    () {
      final transfer = internalTransfer(
        id: 'transfer-credit',
        asset: 'BTC',
        sourceWalletId: 'source-wallet',
        destinationWalletId: walletId,
      );
      final adjustmentMovement = adjustment(
        id: 'destination-adjustment',
        quantity: '1',
        asset: 'BTC',
        wallet: walletId,
        observed: '1',
      );

      final linked = const DifferenceReconciliationService().link(
        transfer,
        adjustment: adjustmentMovement,
        justifiedQuantity: AccountingAmount.fromInt(1),
      );

      expect(
        linked.reconciliationLinks.single.adjustmentMovementId,
        'destination-adjustment',
      );
      final replay = const LedgerRebuilder().rebuild(<AccountingMovement>[
        adjustmentMovement,
        linked,
      ]);
      final result = replay.positions[const WalletAssetKey(walletId, 'BTC')]!;
      expect(result.reconciledQuantity.toJson(), '1');
      expect(result.signedAdjustments, AccountingAmount.zero);
      expect(result.resolvedAdjustmentQuantity.toJson(), '1');
    },
  );

  test('links an other-asset transfer fee to a negative source adjustment', () {
    final transfer =
        internalTransfer(
          id: 'transfer-fee',
          asset: 'BTC',
          sourceWalletId: walletId,
          destinationWalletId: 'destination-wallet',
        ).copyWith(
          cryptoFeeAmount: AccountingAmount.parse('0.5'),
          cryptoFeeAsset: 'ETH',
        );
    final adjustmentMovement = adjustment(
      id: 'fee-adjustment',
      quantity: '-0.5',
      asset: 'ETH',
      wallet: walletId,
      observed: '0',
    );

    final linked = const DifferenceReconciliationService().link(
      transfer,
      adjustment: adjustmentMovement,
      justifiedQuantity: AccountingAmount.parse('0.5'),
    );

    expect(
      linked.reconciliationLinks.single.adjustmentMovementId,
      'fee-adjustment',
    );
    final ethBuy = movement(
      id: 'eth-buy',
      quantity: '0.5',
    ).copyWith(asset: 'ETH', destinationWalletId: walletId);
    final replay = const LedgerRebuilder().rebuild(<AccountingMovement>[
      ethBuy,
      adjustmentMovement,
      linked,
    ]);
    final result = replay.positions[const WalletAssetKey(walletId, 'ETH')]!;
    expect(result.reconciledQuantity, AccountingAmount.zero);
    expect(result.signedAdjustments, AccountingAmount.zero);
    expect(result.resolvedAdjustmentQuantity.toJson(), '0.5');
  });

  test('uses first adjustment metadata when a later duplicate has no leg', () {
    final first = adjustment(id: 'adj-duplicate', quantity: '1', observed: '1');
    final duplicate = adjustment(
      id: 'adj-duplicate',
      quantity: '-1',
      observed: '0',
    ).copyWith(occurredAt: DateTime.utc(2026, 7, 30, 20, 57));

    final result = position(
      const LedgerRebuilder().rebuild(<AccountingMovement>[first, duplicate]),
    );

    expect(result.reconciledQuantity.toJson(), '1');
    expect(result.lastObservedBalance!.toJson(), '1');
    expect(
      result.issues.map((issue) => issue.code),
      isNot(contains(ProjectionIssueCode.observedBalanceMismatch)),
    );
  });
}

const String walletId = '11111111-1111-4111-8111-111111111111';

CustodyPosition position(CustodyProjection projection) =>
    projection.positions[const WalletAssetKey(walletId, 'UNI')]!;

AccountingMovement movement({required String id, required String quantity}) {
  final at = DateTime.utc(2026, 7, 30, 20, 54);
  return AccountingMovement(
    id: id,
    type: MovementType.buy,
    asset: 'UNI',
    occurredAt: at,
    quantity: AccountingAmount.parse(quantity),
    fiatFeeAmount: AccountingAmount.zero,
    destinationWalletId: walletId,
    walletAssignmentStatus: WalletAssignmentStatus.assigned,
    cryptoFeeAmount: AccountingAmount.zero,
    fiatFeeTreatment: FiatFeeTreatment.none,
    reconciliationLinks: const <ReconciliationLink>[],
    createdAt: at,
    updatedAt: at,
  );
}

AccountingMovement adjustment({
  required String id,
  required String quantity,
  String asset = 'UNI',
  String wallet = walletId,
  String observed = '127.75883985',
}) {
  final at = DateTime.utc(2026, 7, 30, 20, 55);
  return AccountingMovement(
    id: id,
    type: MovementType.balanceAdjustment,
    asset: asset,
    occurredAt: at,
    fiatFeeAmount: AccountingAmount.zero,
    walletAssignmentStatus: WalletAssignmentStatus.assigned,
    cryptoFeeAmount: AccountingAmount.zero,
    fiatFeeTreatment: FiatFeeTreatment.none,
    reconciliationLinks: const <ReconciliationLink>[],
    createdAt: at,
    updatedAt: at,
    adjustmentWalletId: wallet,
    adjustmentQuantity: AccountingAmount.parse(quantity),
    observedBalance: AccountingAmount.parse(observed),
    adjustmentReason: 'Corte de saldo',
  );
}

AccountingMovement internalTransfer({
  required String id,
  required String asset,
  required String sourceWalletId,
  required String destinationWalletId,
}) {
  final at = DateTime.utc(2026, 7, 30, 20, 56);
  return AccountingMovement(
    id: id,
    type: MovementType.transferOut,
    asset: asset,
    occurredAt: at,
    quantity: AccountingAmount.fromInt(1),
    fiatFeeAmount: AccountingAmount.zero,
    sourceWalletId: sourceWalletId,
    destinationWalletId: destinationWalletId,
    destinationType: DestinationType.ownWallet,
    walletAssignmentStatus: WalletAssignmentStatus.assigned,
    receivedAmount: AccountingAmount.fromInt(1),
    cryptoFeeAmount: AccountingAmount.zero,
    totalDebitedAmount: AccountingAmount.fromInt(1),
    fiatFeeTreatment: FiatFeeTreatment.none,
    reconciliationLinks: const <ReconciliationLink>[],
    createdAt: at,
    updatedAt: at,
  );
}
