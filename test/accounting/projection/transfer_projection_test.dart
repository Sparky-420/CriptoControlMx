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
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transfer consumes known and unknown segments proportionally', () {
    final allocation = allocateTransferProportionally(
      custodyBefore: AccountingAmount.parse('12'),
      knownAvailable: AccountingAmount.parse('10'),
      knownCostBasis: AccountingAmount.parse('200'),
      totalDebited: AccountingAmount.parse('6'),
    );

    expect(allocation.totalDebited.toJson(), '6');
    expect(allocation.knownQuantity.toJson(), '5');
    expect(allocation.unknownQuantity.toJson(), '1');
    expect(allocation.transferredCostBasis.toJson(), '100');
  });

  test('one internal transfer moves its proportional cost mix without pnl', () {
    final result = _project(<AccountingMovement>[
      buy(id: 'buy', walletId: sourceWalletId, quantity: '10'),
      adjustment(id: 'unknown', walletId: sourceWalletId, quantity: '2'),
      transfer(
        id: 'internal',
        destinationType: DestinationType.ownWallet,
        destinationWalletId: destinationWalletId,
        received: '5',
        fee: '1',
      ),
    ]);

    expect(
      result.custody.positions[sourceKey]!.reconciledQuantity.toJson(),
      '6',
    );
    expect(
      result.custody.positions[destinationKey]!.reconciledQuantity.toJson(),
      '5',
    );
    expect(
      result.performance.positions[sourceKey]!.knownQuantity.toJson(),
      '5',
    );
    expect(
      result.performance.positions[destinationKey]!.knownQuantity.toJson(),
      '4.16666666666666666',
    );
    expect(
      result.performance.positions[destinationKey]!.knownCostBasis.toJson(),
      '83.3333333333333332',
    );
    expect(
      result.performance.positions.values.fold<AccountingAmount>(
        AccountingAmount.zero,
        (total, position) => total + position.realizedPnlKnown,
      ),
      AccountingAmount.zero,
    );
  });

  test(
    'external transfer removes applied proportional mix with no owned credit',
    () {
      final result = _project(<AccountingMovement>[
        buy(id: 'buy', walletId: sourceWalletId, quantity: '10'),
        adjustment(id: 'unknown', walletId: sourceWalletId, quantity: '2'),
        transfer(
          id: 'external',
          destinationType: DestinationType.external,
          received: '5',
          fee: '1',
        ),
      ]);

      expect(
        result.custody.positions[sourceKey]!.reconciledQuantity.toJson(),
        '6',
      );
      expect(result.custody.positions.containsKey(destinationKey), isFalse);
      expect(
        result.performance.positions[sourceKey]!.knownQuantity.toJson(),
        '5',
      );
      expect(
        result.performance.positions[sourceKey]!.knownCostBasis.toJson(),
        '100',
      );
      expect(
        result.performance.positions[sourceKey]!.realizedPnlKnown,
        AccountingAmount.zero,
      );
    },
  );

  test(
    'historical insufficient transfer remains visible and applies only custody',
    () {
      final result = _project(<AccountingMovement>[
        buy(id: 'buy', walletId: sourceWalletId, quantity: '1'),
        transfer(
          id: 'historic',
          destinationType: DestinationType.external,
          received: '2',
        ),
      ]);
      final effect = result.custody.effectsFor('historic').single;

      expect(effect.requested.toJson(), '-2');
      expect(effect.applied.toJson(), '-1');
      expect(effect.unapplied.toJson(), '-1');
      expect(
        result.custody.positions[sourceKey]!.issues.map((issue) => issue.code),
        contains(ProjectionIssueCode.insufficientCustody),
      );
      expect(
        result.custody.positions[sourceKey]!.reconciledQuantity,
        AccountingAmount.zero,
      );
      expect(
        result.performance.positions[sourceKey]!.knownQuantity,
        AccountingAmount.zero,
      );
    },
  );

  test(
    'new transfer is rejected against the available custody before saving',
    () {
      final custody = const LedgerRebuilder().rebuild(<AccountingMovement>[
        buy(id: 'buy', walletId: sourceWalletId, quantity: '1'),
      ]);
      final candidate = transfer(
        id: 'new-insufficient',
        destinationType: DestinationType.external,
        received: '2',
      );

      expect(
        () => const TransferCustodyValidator().validateNew(candidate, custody),
        throwsArgumentError,
      );
    },
  );

  test('other-asset fee debits its custody and cost once without pnl', () {
    final result = _project(<AccountingMovement>[
      buy(id: 'buy', walletId: sourceWalletId, quantity: '10'),
      buy(
        id: 'eth-buy',
        walletId: sourceWalletId,
        quantity: '2',
      ).copyWith(asset: 'ETH'),
      transfer(
        id: 'other-asset-fee',
        destinationType: DestinationType.external,
        received: '5',
        fee: '0.5',
        feeAsset: 'ETH',
      ),
    ]);
    const ethKey = WalletAssetKey(sourceWalletId, 'ETH');

    expect(
      result.custody
          .effectsFor('other-asset-fee')
          .map((effect) => effect.requested.toJson()),
      <String>['-5', '-0.5'],
    );
    expect(
      result.custody.positions[sourceKey]!.reconciledQuantity.toJson(),
      '5',
    );
    expect(
      result.custody.positions[ethKey]!.reconciledQuantity.toJson(),
      '1.5',
    );
    expect(result.performance.positions[ethKey]!.knownQuantity.toJson(), '1.5');
    expect(result.performance.positions[ethKey]!.knownCostBasis.toJson(), '30');
    expect(
      result.performance.positions[ethKey]!.realizedPnlKnown,
      AccountingAmount.zero,
    );
  });

  test('Mercado Pago external fixture has no owned credit or realized pnl', () {
    final observedBalance = AccountingAmount.parse('127.75883985');
    const mercadoPagoWalletId = 'Mi Mercado Pago';
    const mercadoPagoKey = WalletAssetKey(mercadoPagoWalletId, 'UNI');
    final result = _project(<AccountingMovement>[
      buy(id: 'buy', walletId: mercadoPagoWalletId, quantity: '128.76051517'),
      transfer(
        id: 'mercado-pago',
        destinationType: DestinationType.external,
        received: '1',
        fee: '0.00167532',
      ).copyWith(sourceWalletId: mercadoPagoWalletId),
    ]);

    expect(
      result.custody.positions[mercadoPagoKey]!.reconciledQuantity,
      observedBalance,
    );
    expect(result.custody.positions.keys, isNot(contains(destinationKey)));
    expect(
      result.performance.positions[mercadoPagoKey]!.realizedPnlKnown,
      AccountingAmount.zero,
    );
  });
}

const String sourceWalletId = '11111111-1111-4111-8111-111111111111';
const String destinationWalletId = '22222222-2222-4222-8222-222222222222';
const WalletAssetKey sourceKey = WalletAssetKey(sourceWalletId, 'UNI');
const WalletAssetKey destinationKey = WalletAssetKey(
  destinationWalletId,
  'UNI',
);
final DateTime at = DateTime.utc(2026, 7, 30, 20, 54);

_ProjectionResult _project(List<AccountingMovement> movements) {
  final ledger = const DefaultMovementNormalizer().normalize(movements);
  final custody = const DefaultCustodyProjector().project(ledger);
  return _ProjectionResult(
    custody,
    const DefaultPerformanceProjector().project(
      ledger,
      custody,
      const <String, AccountingAmount>{},
      salePolicy: SaleCostConsumptionPolicy.knownFirst,
      transferPolicy: TransferCostAllocationPolicy.proportional,
    ),
  );
}

AccountingMovement buy({
  required String id,
  required String walletId,
  required String quantity,
}) => movement(
  id: id,
  type: MovementType.buy,
  quantity: quantity,
  unitPrice: '20',
  destinationWalletId: walletId,
);

AccountingMovement adjustment({
  required String id,
  required String walletId,
  required String quantity,
}) => movement(
  id: id,
  type: MovementType.balanceAdjustment,
  adjustmentWalletId: walletId,
  adjustmentQuantity: quantity,
  observedBalance: '12',
  adjustmentReason: 'Conciliacion',
);

AccountingMovement transfer({
  required String id,
  required DestinationType destinationType,
  String? destinationWalletId,
  required String received,
  String fee = '0',
  String? feeAsset,
}) => movement(
  id: id,
  type: MovementType.transferOut,
  quantity: received,
  sourceWalletId: sourceWalletId,
  destinationWalletId: destinationWalletId,
  destinationType: destinationType,
  externalRecipientName: destinationType == DestinationType.external
      ? 'Primo'
      : null,
  externalDestinationPlatform: destinationType == DestinationType.external
      ? 'Bitso'
      : null,
  receivedAmount: received,
  cryptoFeeAmount: fee,
  cryptoFeeAsset: fee == '0' ? null : feeAsset ?? 'UNI',
  totalDebitedAmount:
      (fee != '0' && (feeAsset ?? 'UNI') == 'UNI'
              ? AccountingAmount.parse(received) + AccountingAmount.parse(fee)
              : AccountingAmount.parse(received))
          .toJson(),
);

AccountingMovement movement({
  required String id,
  required MovementType type,
  String? quantity,
  String? unitPrice,
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
  String? adjustmentReason,
}) {
  final occurredAt = at.add(
    Duration(
      minutes: id == 'buy'
          ? 0
          : id == 'unknown'
          ? 1
          : 2,
    ),
  );
  return AccountingMovement(
    id: id,
    type: type,
    asset: 'UNI',
    occurredAt: occurredAt,
    quantity: quantity == null ? null : AccountingAmount.parse(quantity),
    unitPriceFiat: unitPrice == null ? null : AccountingAmount.parse(unitPrice),
    fiatFeeAmount: AccountingAmount.zero,
    sourceWalletId: sourceWalletId,
    destinationWalletId: destinationWalletId,
    destinationType: destinationType,
    externalRecipientName: externalRecipientName,
    externalDestinationPlatform: externalDestinationPlatform,
    walletAssignmentStatus: WalletAssignmentStatus.assigned,
    receivedAmount: receivedAmount == null
        ? null
        : AccountingAmount.parse(receivedAmount),
    cryptoFeeAmount: AccountingAmount.parse(cryptoFeeAmount),
    cryptoFeeAsset: cryptoFeeAsset,
    totalDebitedAmount: totalDebitedAmount == null
        ? null
        : AccountingAmount.parse(totalDebitedAmount),
    fiatFeeTreatment: FiatFeeTreatment.none,
    reconciliationLinks: const <ReconciliationLink>[],
    createdAt: occurredAt,
    updatedAt: occurredAt,
    adjustmentWalletId: adjustmentWalletId,
    adjustmentQuantity: adjustmentQuantity == null
        ? null
        : AccountingAmount.parse(adjustmentQuantity),
    observedBalance: observedBalance == null
        ? null
        : AccountingAmount.parse(observedBalance),
    adjustmentReason: adjustmentReason,
  );
}

final class _ProjectionResult {
  const _ProjectionResult(this.custody, this.performance);

  final CustodyProjection custody;
  final PerformanceProjection performance;
}
