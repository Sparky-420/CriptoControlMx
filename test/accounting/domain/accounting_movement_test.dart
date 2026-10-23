import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_movement.dart';
import 'package:cripto_control_mx/accounting/domain/movement_type.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'round trips a balance adjustment with exact amounts and clears fields',
    () {
      final movement = AccountingMovement(
        id: 'adjustment-1',
        type: MovementType.balanceAdjustment,
        asset: 'UNI',
        occurredAt: DateTime.parse('2026-07-30T20:54:00-06:00'),
        fiatFeeAmount: AccountingAmount.zero,
        walletAssignmentStatus: WalletAssignmentStatus.assigned,
        cryptoFeeAmount: AccountingAmount.zero,
        fiatFeeTreatment: FiatFeeTreatment.none,
        reconciliationLinks: const <ReconciliationLink>[],
        createdAt: DateTime.parse('2026-07-30T20:54:00-06:00'),
        updatedAt: DateTime.parse('2026-07-30T20:54:00-06:00'),
        sourceWalletId: 'wallet-1',
        adjustmentWalletId: 'wallet-1',
        adjustmentQuantity: AccountingAmount.parse('0.75883985'),
        observedBalance: AccountingAmount.parse('127.75883985'),
        adjustmentReason: 'Saldo observado',
        note: 'Mercado Pago',
      );
      final json = movement.toJson();
      expect(json['adjustmentQuantity'], '0.75883985');
      expect(json['observedBalance'], '127.75883985');
      expect(AccountingMovement.fromJson(json).toJson(), json);
      expect(movement.copyWith(sourceWalletId: null).sourceWalletId, isNull);
    },
  );

  test('copyWith updates fields and independently clears nullables', () {
    final original = AccountingMovement(
      id: 'id',
      type: MovementType.buy,
      asset: 'BTC',
      occurredAt: DateTime.utc(2026),
      fiatFeeAmount: AccountingAmount.zero,
      walletAssignmentStatus: WalletAssignmentStatus.assigned,
      cryptoFeeAmount: AccountingAmount.zero,
      fiatFeeTreatment: FiatFeeTreatment.none,
      reconciliationLinks: const [],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      quantity: AccountingAmount.fromInt(1),
      note: 'note',
      network: 'net',
      destinationWalletId: 'wallet',
    );
    final changed = original.copyWith(
      type: MovementType.sell,
      asset: 'ETH',
      quantity: null,
      note: null,
      network: null,
      destinationWalletId: null,
      reconciliationLinks: <ReconciliationLink>[
        ReconciliationLink(
          adjustmentMovementId: 'a',
          quantityResolved: AccountingAmount.fromInt(1),
        ),
      ],
      schemaVersion: 4,
    );
    expect(changed.type, MovementType.sell);
    expect(changed.asset, 'ETH');
    expect(changed.quantity, isNull);
    expect(changed.note, isNull);
    expect(changed.network, isNull);
    expect(changed.destinationWalletId, isNull);
    expect(changed.schemaVersion, 4);
    expect(changed.reconciliationLinks, hasLength(1));
  });
}
