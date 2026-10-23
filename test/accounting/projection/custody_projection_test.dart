import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_movement.dart';
import 'package:cripto_control_mx/accounting/domain/ledger_validation.dart';
import 'package:cripto_control_mx/accounting/domain/movement_normalizer.dart';
import 'package:cripto_control_mx/accounting/domain/movement_type.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/projection/custody_projection.dart';
import 'package:cripto_control_mx/accounting/projection/custody_projector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('positive adjustment changes custody but not known position', () {
    final result = const DefaultCustodyProjector()
        .project(
          const DefaultMovementNormalizer().normalize(<AccountingMovement>[
            buy(quantity: '127', walletId: walletId),
            adjustment(quantity: '0.75883985', observed: '127.75883985'),
          ]),
        )
        .positions[const WalletAssetKey(walletId, 'UNI')]!;

    expect(result.reconciledQuantity.toJson(), '127.75883985');
    expect(result.signedAdjustments.toJson(), '0.75883985');
    expect(result.lastObservedBalance!.toJson(), '127.75883985');
    expect(result.unappliedQuantity, AccountingAmount.zero);
  });

  test('negative adjustment reduces only reconciled custody', () {
    final result = projectCustody(<AccountingMovement>[
      buy(quantity: '127', walletId: walletId),
      adjustment(quantity: '-2', observed: '125'),
    ]).positions[const WalletAssetKey(walletId, 'UNI')]!;

    expect(result.reconciledQuantity.toJson(), '125');
    expect(result.signedAdjustments.toJson(), '-2');
    expect(result.appliedCredits.toJson(), '127');
    expect(result.appliedDebits, AccountingAmount.zero);
  });

  test('retains an inconsistent observed balance and reports it', () {
    final result = projectCustody(<AccountingMovement>[
      buy(quantity: '127', walletId: walletId),
      adjustment(quantity: '0.75883985', observed: '130'),
    ]).positions[const WalletAssetKey(walletId, 'UNI')]!;

    expect(result.reconciledQuantity.toJson(), '127.75883985');
    expect(result.lastObservedBalance!.toJson(), '130');
    expect(
      result.issues.map((issue) => issue.code),
      contains(ProjectionIssueCode.observedBalanceMismatch),
    );
  });

  test('limits an historical custody debit and retains its deficit', () {
    final projection = projectCustody(<AccountingMovement>[
      buy(quantity: '1', walletId: walletId),
      sell(quantity: '2'),
    ]);
    final result = projection.positions[const WalletAssetKey(walletId, 'UNI')]!;
    final effect = projection.effectsByMovementId['sell-1']!.single;

    expect(result.reconciledQuantity, AccountingAmount.zero);
    expect(result.unappliedQuantity.toJson(), '-1');
    expect(
      result.issues.map((issue) => issue.code),
      contains(ProjectionIssueCode.insufficientCustody),
    );
    expect(effect.requested.toJson(), '-2');
    expect(effect.applied.toJson(), '-1');
    expect(effect.unapplied.toJson(), '-1');
    expect(effect.after, AccountingAmount.zero);
  });
}

const String walletId = '11111111-1111-4111-8111-111111111111';

AccountingMovement buy({required String quantity, required String walletId}) =>
    movement(
      id: 'buy-1',
      type: MovementType.buy,
      quantity: quantity,
      destinationWalletId: walletId,
    );

AccountingMovement sell({required String quantity}) {
  final at = DateTime.utc(2026, 7, 30, 20, 55);
  return AccountingMovement(
    id: 'sell-1',
    type: MovementType.sell,
    asset: 'UNI',
    occurredAt: at,
    quantity: AccountingAmount.parse(quantity),
    fiatFeeAmount: AccountingAmount.zero,
    sourceWalletId: walletId,
    walletAssignmentStatus: WalletAssignmentStatus.assigned,
    cryptoFeeAmount: AccountingAmount.zero,
    fiatFeeTreatment: FiatFeeTreatment.none,
    reconciliationLinks: const <ReconciliationLink>[],
    createdAt: at,
    updatedAt: at,
  );
}

AccountingMovement adjustment({
  required String quantity,
  required String observed,
}) => movement(
  id: 'adjustment-1',
  type: MovementType.balanceAdjustment,
  adjustmentWalletId: walletId,
  adjustmentQuantity: quantity,
  observedBalance: observed,
).copyWith(occurredAt: DateTime.utc(2026, 7, 30, 20, 55));

AccountingMovement movement({
  required String id,
  required MovementType type,
  String? quantity,
  String? destinationWalletId,
  String? adjustmentWalletId,
  String? adjustmentQuantity,
  String? observedBalance,
}) {
  final at = DateTime.utc(2026, 7, 30, 20, 54);
  return AccountingMovement(
    id: id,
    type: type,
    asset: 'UNI',
    occurredAt: at,
    quantity: quantity == null ? null : AccountingAmount.parse(quantity),
    fiatFeeAmount: AccountingAmount.zero,
    destinationWalletId: destinationWalletId,
    walletAssignmentStatus: WalletAssignmentStatus.assigned,
    cryptoFeeAmount: AccountingAmount.zero,
    fiatFeeTreatment: FiatFeeTreatment.none,
    reconciliationLinks: const <ReconciliationLink>[],
    createdAt: at,
    updatedAt: at,
    adjustmentWalletId: adjustmentWalletId,
    adjustmentQuantity: adjustmentQuantity == null
        ? null
        : AccountingAmount.parse(adjustmentQuantity),
    observedBalance: observedBalance == null
        ? null
        : AccountingAmount.parse(observedBalance),
    adjustmentReason: type == MovementType.balanceAdjustment
        ? 'Corte de saldo'
        : null,
  );
}

CustodyProjection projectCustody(List<AccountingMovement> movements) =>
    const DefaultCustodyProjector().project(
      const DefaultMovementNormalizer().normalize(movements),
    );
