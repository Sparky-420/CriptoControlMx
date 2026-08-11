import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_movement.dart';
import 'package:cripto_control_mx/accounting/domain/ledger_validation.dart';
import 'package:cripto_control_mx/accounting/domain/movement_normalizer.dart';
import 'package:cripto_control_mx/accounting/domain/movement_type.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/projection/custody_projection.dart';
import 'package:cripto_control_mx/accounting/projection/custody_projector.dart';
import 'package:cripto_control_mx/accounting/projection/performance_projection.dart';
import 'package:cripto_control_mx/accounting/projection/performance_projector.dart';
import 'package:cripto_control_mx/cripto_control_app.dart' as legacy;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sale below known quantity keeps weighted cost and legacy fiat fee', () {
    final projection = project(<AccountingMovement>[
      buy(id: 'buy-1', quantity: '10', price: '20', fee: '10'),
      sell(id: 'sell-1', quantity: '4', price: '30', fee: '2'),
    ]);
    final sale = projection.sales.single;
    final position = projection.positions[key]!;

    expect(sale.status, SaleAccountingStatus.complete);
    expect(sale.hasDefinitiveTotal, isTrue);
    expect(sale.knownQuantity.toJson(), '4');
    expect(sale.demonstratedCostBasis.toJson(), '84');
    expect(sale.knownProceeds.toJson(), '120');
    expect(sale.allocatedKnownFiatFee.toJson(), '2');
    expect(sale.realizedPnlKnown.toJson(), '34');
    expect(sale.pendingCostQuantity, AccountingAmount.zero);
    expect(position.knownQuantity.toJson(), '6');
    expect(position.knownCostBasis.toJson(), '126');
    expect(position.realizedPnlKnown.toJson(), '34');

    final stats = legacy.FinancialEngine.computeStats(
      coins: const <String>['UNI'],
      movements: <legacy.Movement>[
        legacy.Movement(
          type: legacy.MovementType.buy,
          coin: 'UNI',
          date: at,
          quantity: 10,
          unitPrice: 20,
          fee: 10,
          note: 'test',
        ),
        legacy.Movement(
          type: legacy.MovementType.sell,
          coin: 'UNI',
          date: at.add(const Duration(minutes: 1)),
          quantity: 4,
          unitPrice: 30,
          fee: 2,
          note: 'test',
        ),
      ],
      currentPrices: const <String, double>{},
    )['UNI']!;
    expect(
      double.parse(position.knownQuantity.toJson()),
      closeTo(stats.quantity, 0.0000000001),
    );
    expect(
      double.parse(position.knownCostBasis.toJson()),
      closeTo(stats.costBase, 0.0000000001),
    );
    expect(
      double.parse(position.realizedPnlKnown.toJson()),
      closeTo(stats.realizedPL, 0.0000000001),
    );
  });

  test('sale equal to known quantity has a definitive total', () {
    final sale = project(<AccountingMovement>[
      buy(id: 'buy-1', quantity: '10', price: '20'),
      sell(id: 'sell-1', quantity: '10', price: '30'),
    ]).sales.single;

    expect(sale.status, SaleAccountingStatus.complete);
    expect(sale.hasDefinitiveTotal, isTrue);
    expect(sale.knownQuantity.toJson(), '10');
    expect(sale.demonstratedCostBasis.toJson(), '200');
    expect(sale.realizedPnlKnown.toJson(), '100');
    expect(sale.pendingCostQuantity, AccountingAmount.zero);
  });

  test(
    'sale above known quantity reports only a non-definitive known result',
    () {
      final sale = project(<AccountingMovement>[
        buy(id: 'buy-1', quantity: '10', price: '20'),
        adjustment(id: 'adjustment-1', quantity: '2', observed: '12'),
        sell(id: 'sell-1', quantity: '11', price: '30', fee: '11'),
      ]).sales.single;

      expect(sale.status, SaleAccountingStatus.partiallyKnown);
      expect(sale.hasDefinitiveTotal, isFalse);
      expect(sale.totalQuantity.toJson(), '11');
      expect(sale.knownQuantity.toJson(), '10');
      expect(sale.demonstratedCostBasis.toJson(), '200');
      expect(sale.knownProceeds.toJson(), '300');
      expect(sale.allocatedKnownFiatFee.toJson(), '10');
      expect(sale.realizedPnlKnown.toJson(), '90');
      expect(sale.pendingCostQuantity.toJson(), '1');
    },
  );

  test(
    'insufficient custody preserves the sale and never projects negative',
    () {
      final projection = project(<AccountingMovement>[
        buy(id: 'buy-1', quantity: '8', price: '20'),
        sell(id: 'sell-1', quantity: '9', price: '30'),
      ]);
      final sale = projection.sales.single;
      final custody = custodyFor(<AccountingMovement>[
        buy(id: 'buy-1', quantity: '8', price: '20'),
        sell(id: 'sell-1', quantity: '9', price: '30'),
      ]);

      expect(sale.status, SaleAccountingStatus.insufficientCustody);
      expect(sale.hasDefinitiveTotal, isFalse);
      expect(sale.totalQuantity.toJson(), '9');
      expect(sale.knownQuantity, AccountingAmount.zero);
      expect(sale.demonstratedCostBasis, AccountingAmount.zero);
      expect(sale.knownProceeds, AccountingAmount.zero);
      expect(sale.pendingCostQuantity, AccountingAmount.zero);
      expect(custody.positions[key]!.reconciledQuantity, AccountingAmount.zero);
      expect(projection.positions[key]!.knownQuantity.toJson(), '8');
      expect(projection.positions[key]!.knownCostBasis.toJson(), '160');
      expect(
        projection.positions[key]!.realizedPnlKnown,
        AccountingAmount.zero,
      );
      expect(
        projection.positions[key]!.issues.map((issue) => issue.code),
        contains(ProjectionIssueCode.insufficientCustody),
      );
    },
  );

  test('adjustments never alter known quantity cost or realized pnl', () {
    final withoutAdjustment = project(<AccountingMovement>[
      buy(id: 'buy-1', quantity: '10', price: '20'),
    ]).positions[key]!;
    final withAdjustment = project(<AccountingMovement>[
      buy(id: 'buy-1', quantity: '10', price: '20'),
      adjustment(id: 'adjustment-1', quantity: '2', observed: '12'),
    ]).positions[key]!;

    expect(withAdjustment.knownQuantity, withoutAdjustment.knownQuantity);
    expect(withAdjustment.knownCostBasis, withoutAdjustment.knownCostBasis);
    expect(withAdjustment.realizedPnlKnown, withoutAdjustment.realizedPnlKnown);
  });
}

const String walletId = '11111111-1111-4111-8111-111111111111';
const WalletAssetKey key = WalletAssetKey(walletId, 'UNI');
final DateTime at = DateTime.utc(2026, 7, 30, 20, 54);

PerformanceProjection project(List<AccountingMovement> movements) {
  final ledger = const DefaultMovementNormalizer().normalize(movements);
  return const DefaultPerformanceProjector().project(
    ledger,
    const DefaultCustodyProjector().project(ledger),
    const <String, AccountingAmount>{},
    salePolicy: SaleCostConsumptionPolicy.knownFirst,
    transferPolicy: TransferCostAllocationPolicy.proportional,
  );
}

CustodyProjection custodyFor(List<AccountingMovement> movements) =>
    const DefaultCustodyProjector().project(
      const DefaultMovementNormalizer().normalize(movements),
    );

AccountingMovement buy({
  required String id,
  required String quantity,
  required String price,
  String fee = '0',
}) => movement(
  id: id,
  type: MovementType.buy,
  quantity: quantity,
  price: price,
  fee: fee,
  destinationWalletId: walletId,
);

AccountingMovement sell({
  required String id,
  required String quantity,
  required String price,
  String fee = '0',
}) => movement(
  id: id,
  type: MovementType.sell,
  quantity: quantity,
  price: price,
  fee: fee,
  sourceWalletId: walletId,
);

AccountingMovement adjustment({
  required String id,
  required String quantity,
  required String observed,
}) => movement(
  id: id,
  type: MovementType.balanceAdjustment,
  adjustmentQuantity: quantity,
  observedBalance: observed,
);

AccountingMovement movement({
  required String id,
  required MovementType type,
  String? quantity,
  String? price,
  String fee = '0',
  String? sourceWalletId,
  String? destinationWalletId,
  String? adjustmentQuantity,
  String? observedBalance,
}) {
  final occurredAt = at.add(Duration(minutes: id == 'buy-1' ? 0 : 1));
  return AccountingMovement(
    id: id,
    type: type,
    asset: 'UNI',
    occurredAt: occurredAt,
    quantity: quantity == null ? null : AccountingAmount.parse(quantity),
    unitPriceFiat: price == null ? null : AccountingAmount.parse(price),
    fiatFeeAmount: AccountingAmount.parse(fee),
    sourceWalletId: sourceWalletId,
    destinationWalletId: destinationWalletId,
    walletAssignmentStatus: WalletAssignmentStatus.assigned,
    cryptoFeeAmount: AccountingAmount.zero,
    fiatFeeTreatment: FiatFeeTreatment.none,
    reconciliationLinks: const <ReconciliationLink>[],
    createdAt: occurredAt,
    updatedAt: occurredAt,
    adjustmentWalletId: type == MovementType.balanceAdjustment
        ? walletId
        : null,
    adjustmentQuantity: adjustmentQuantity == null
        ? null
        : AccountingAmount.parse(adjustmentQuantity),
    observedBalance: observedBalance == null
        ? null
        : AccountingAmount.parse(observedBalance),
    adjustmentReason: type == MovementType.balanceAdjustment ? 'Corte' : null,
  );
}
