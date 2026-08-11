import 'package:cripto_control_mx/accounting/adapters/legacy_financial_adapter.dart';
import 'package:cripto_control_mx/accounting/adapters/legacy_movement_adapter.dart';
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
import 'package:cripto_control_mx/cripto_control_app.dart' as legacy;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round trips every current Movement JSON field and unknown data', () {
    final historical = legacy.Movement(
      id: 'legacy-transfer',
      type: MovementType.transferOut,
      coin: 'UNI',
      date: DateTime.parse('2026-07-30T20:54:00-06:00'),
      quantity: 1,
      unitPrice: 70,
      fee: 15,
      receivedAmount: 1,
      cryptoFeeAmount: 0.00167532,
      cryptoFeeAsset: 'UNI',
      totalDebitedAmount: 1.00167532,
      feeFiatValue: 0.12,
      sourcePlatform: 'Mi Mercado Pago',
      destinationPlatform: 'Bitso',
      source: 'Mercado Pago alias',
      wallet: 'Cartera alias',
      network: 'Ethereum',
      note: 'Primo',
      createdAt: DateTime.parse('2026-07-30T20:53:00-06:00'),
      updatedAt: DateTime.parse('2026-07-30T20:55:00-06:00'),
      deletedAt: DateTime.parse('2026-08-01T10:00:00-06:00'),
      deviceId: 'device-1',
      schemaVersion: 2,
    );
    final json = Map<String, Object?>.from(historical.toJson())
      ..['futureField'] = <String, Object?>{'nested': true};
    final conversion = const LegacyMovementAdapter().fromLegacyJson(json);

    expect(conversion.movement.id, 'legacy-transfer');
    expect(conversion.movement.type, MovementType.transferOut);
    expect(conversion.movement.asset, 'UNI');
    expect(conversion.movement.occurredAt, historical.date);
    expect(conversion.movement.quantity!.toJson(), '1');
    expect(conversion.movement.unitPriceFiat!.toJson(), '70');
    expect(conversion.movement.fiatFeeAmount.toJson(), '15');
    expect(conversion.movement.receivedAmount!.toJson(), '1');
    expect(conversion.movement.cryptoFeeAmount.toJson(), '0.00167532');
    expect(conversion.movement.totalDebitedAmount!.toJson(), '1.00167532');
    expect(conversion.movement.feeFiatValue!.toJson(), '0.12');
    expect(
      conversion.movement.walletAssignmentStatus,
      WalletAssignmentStatus.legacyUnassigned,
    );
    expect(conversion.movement.sourceWalletId, isNull);
    expect(conversion.movement.destinationWalletId, isNull);
    expect(conversion.movement.destinationType, isNull);
    expect(conversion.preservedFields['sourcePlatform'], 'Mi Mercado Pago');
    expect(conversion.preservedFields['destinationPlatform'], 'Bitso');
    expect(conversion.preservedFields['deletedAt'], isNotNull);
    expect(conversion.preservedFields['deviceId'], 'device-1');
    expect(conversion.preservedFields['futureField'], <String, Object?>{
      'nested': true,
    });
    expect(
      const LegacyMovementAdapter().toLegacyJson(
        conversion.movement,
        preservedFields: conversion.preservedFields,
      ),
      json,
    );
  });

  test(
    'clears canonical nulls without dropping unrelated preserved fields',
    () {
      final json = <String, Object?>{
        'id': 'clearable',
        'type': 'transfer_out',
        'coin': 'UNI',
        'date': '2026-07-30T20:54:00-06:00',
        'quantity': 1.0,
        'unitPrice': 70.0,
        'fee': 0.0,
        'receivedAmount': 1.0,
        'cryptoFeeAmount': 0.1,
        'cryptoFeeAsset': 'UNI',
        'totalDebitedAmount': 1.1,
        'feeFiatValue': 7.0,
        'source': 'Origen',
        'wallet': 'Destino',
        'network': 'Ethereum',
        'note': 'Nota',
        'createdAt': '2026-07-30T20:54:00-06:00',
        'updatedAt': '2026-07-30T20:54:00-06:00',
        'deletedAt': '2026-08-01T10:00:00-06:00',
        'deviceId': 'device-1',
        'schemaVersion': 2,
        'futureField': 42,
      };
      final conversion = const LegacyMovementAdapter().fromLegacyJson(json);
      final cleared = conversion.movement.copyWith(
        receivedAmount: null,
        cryptoFeeAsset: null,
        totalDebitedAmount: null,
        feeFiatValue: null,
        network: null,
        note: null,
      );
      final output = const LegacyMovementAdapter().toLegacyJson(
        cleared,
        preservedFields: conversion.preservedFields,
      );

      expect(output.containsKey('receivedAmount'), isFalse);
      expect(output.containsKey('cryptoFeeAsset'), isFalse);
      expect(output.containsKey('totalDebitedAmount'), isFalse);
      expect(output.containsKey('feeFiatValue'), isFalse);
      expect(output.containsKey('network'), isFalse);
      expect(output.containsKey('note'), isFalse);
      expect(output['deletedAt'], json['deletedAt']);
      expect(output['deviceId'], 'device-1');
      expect(output['futureField'], 42);
    },
  );

  test('accepts movement aliases and balance adjustment fields losslessly', () {
    final aliases = <String, MovementType>{
      'compra': MovementType.buy,
      'venta': MovementType.sell,
      'transfer_in': MovementType.transferIn,
      'transferencia enviada': MovementType.transferOut,
      'ajuste de saldo': MovementType.balanceAdjustment,
    };
    for (final entry in aliases.entries) {
      final conversion = const LegacyMovementAdapter()
          .fromLegacyJson(<String, Object?>{
            'id': 'alias-${entry.value.name}',
            'type': entry.key,
            'crypto': 'uni',
            'date': '2026-07-30T20:54:00-06:00',
            'quantity': entry.value == MovementType.balanceAdjustment ? -2 : 1,
            'unit_price': 10,
            'commission': 1,
          });
      expect(conversion.movement.type, entry.value, reason: entry.key);
      expect(conversion.movement.asset, 'UNI', reason: entry.key);
    }

    final adjustmentJson = <String, Object?>{
      'id': 'legacy-adjustment',
      'tipo': 'ajuste',
      'crypto': 'uni',
      'occurred_at': '2026-07-30T20:54:00-06:00',
      'adjustment_quantity': '-2',
      'observed_balance': '125.75883985',
      'adjustment_reason': 'Corte manual',
      'wallet_assignment_status': 'legacyUnassigned',
      'created_at': '2026-07-30T20:54:00-06:00',
      'updated_at': '2026-07-30T20:55:00-06:00',
      'opaque': 'preserve-me',
    };
    final conversion = const LegacyMovementAdapter().fromLegacyJson(
      adjustmentJson,
    );

    expect(conversion.movement.type, MovementType.balanceAdjustment);
    expect(conversion.movement.adjustmentWalletId, isNull);
    expect(conversion.movement.adjustmentQuantity!.toJson(), '-2');
    expect(conversion.movement.observedBalance!.toJson(), '125.75883985');
    expect(conversion.movement.adjustmentReason, 'Corte manual');
    expect(
      const LegacyMovementAdapter().toLegacyJson(
        conversion.movement,
        preservedFields: conversion.preservedFields,
      ),
      adjustmentJson,
    );
  });

  test(
    'legacy structured transfer preserves global value without ownership',
    () {
      final adapter = const LegacyMovementAdapter();
      final buy = adapter.fromLegacyJson(<String, Object?>{
        'id': 'legacy-buy',
        'type': 'buy',
        'coin': 'UNI',
        'date': '2026-07-30T20:50:00-06:00',
        'quantity': 10,
        'unitPrice': 10,
        'fee': 0,
      }).movement;
      final transfer = adapter.fromLegacyJson(<String, Object?>{
        'id': 'legacy-transfer',
        'type': 'transfer_out',
        'coin': 'UNI',
        'date': '2026-07-30T20:54:00-06:00',
        'quantity': 4,
        'unitPrice': 0,
        'fee': 0,
        'receivedAmount': 4,
        'cryptoFeeAmount': 1,
        'cryptoFeeAsset': 'UNI',
        'totalDebitedAmount': 5,
        'sourcePlatform': 'Mercado Pago',
        'destinationPlatform': 'Bitso',
      }).movement;

      expect(transfer.sourceWalletId, isNull);
      expect(transfer.destinationWalletId, isNull);
      expect(transfer.destinationType, isNull);
      final projection = project(<AccountingMovement>[buy, transfer], const {});
      final position = projection
          .positions[const WalletAssetKey(virtualUnassignedWalletId, 'UNI')]!;
      expect(position.custody.reconciledQuantity.toJson(), '9');
      expect(position.performance.knownQuantity.toJson(), '9');
      expect(position.performance.knownCostBasis.toJson(), '90');
      expect(
        projection.issues.map((issue) => issue.code),
        contains(ProjectionIssueCode.missingDestinationClassification),
      );
      expect(
        projection.issues.map((issue) => issue.code),
        isNot(contains(ProjectionIssueCode.malformedHistoricalMovement)),
      );
    },
  );

  test('matches known-only weighted legacy stats audit and totals', () {
    final canonical = knownOnlyMovements();
    final projection = project(canonical, <String, AccountingAmount>{
      'UNI': AccountingAmount.fromInt(50),
    });
    final adapter = const LegacyFinancialAdapter();
    final data = adapter.coinStats(projection, const <String, double>{
      'UNI': 50,
    })['UNI']!;
    final auditData = adapter.audits(projection)['UNI']!;
    final totalData = adapter.totals(projection, const <String, double>{
      'UNI': 50,
    });
    final historical = knownOnlyLegacyMovements();
    final historicalStats = legacy.FinancialEngine.computeStats(
      coins: const <String>['UNI'],
      movements: historical,
      currentPrices: const <String, double>{'UNI': 50},
    )['UNI']!;
    final historicalAudit = legacy.FinancialEngine.computeAudit(
      coin: 'UNI',
      movements: historical,
    );
    final historicalTotals = legacy.FinancialEngine.totals(
      <String, legacy.CoinStats>{'UNI': historicalStats},
    );

    expect(data.quantity, closeTo(historicalStats.quantity, 0.00000001));
    expect(data.costBase, closeTo(historicalStats.costBase, 0.00000001));
    expect(
      data.realizedProfit,
      closeTo(historicalStats.realizedPL, 0.00000001),
    );
    expect(
      auditData.reconciledCostBase,
      closeTo(historicalAudit.reconciledCostBase, 0.00000001),
    );
    expect(totalData.costBase, closeTo(historicalTotals.costBase, 0.00000001));
    expect(
      totalData.currentValue,
      closeTo(historicalTotals.currentValue, 0.00000001),
    );
    expect(
      totalData.realizedProfit,
      closeTo(historicalTotals.realizedPL, 0.00000001),
    );

    final bridgedStats = legacy.CoinStats.fromLegacyData(
      data,
      currentPrice: 50,
    );
    final bridgedAudit = legacy.CoinAudit.fromLegacyData(auditData);
    final bridgedTotals = legacy.PortfolioTotals.fromLegacyData(totalData);
    final bridgedMovement = legacy.Movement.fromAccountingMovement(
      canonical.first,
    );
    expect(bridgedStats.costBase, data.costBase);
    expect(bridgedStats.currentValue, data.quantity * 50);
    expect(bridgedAudit.reconciledCostBase, auditData.reconciledCostBase);
    expect(bridgedTotals.costBase, totalData.costBase);
    expect(
      bridgedTotals.unrealizedPL,
      totalData.currentValue - totalData.costBase,
    );
    expect(bridgedMovement.type, MovementType.buy);
    expect(bridgedMovement.coin, 'UNI');
  });
}

const String walletA = '11111111-1111-4111-8111-111111111111';
const String walletB = '22222222-2222-4222-8222-222222222222';
final DateTime at = DateTime.utc(2026, 7, 30, 20, 54);

LedgerProjection project(
  List<AccountingMovement> movements,
  Map<String, AccountingAmount> prices,
) =>
    const AccountingLedgerEngine(
      DefaultMovementNormalizer(),
      DefaultCustodyProjector(),
      DefaultPerformanceProjector(),
    ).project(
      LedgerInput(
        wallets: <Wallet>[wallet(walletA), wallet(walletB)],
        movements: movements,
        currentPrices: prices,
        saleCostConsumptionPolicy: SaleCostConsumptionPolicy.knownFirst,
        transferCostAllocationPolicy: TransferCostAllocationPolicy.proportional,
        legacyAccountingPolicy: LegacyAccountingPolicy.preservePreviousGlobal,
      ),
    );

Wallet wallet(String id) => Wallet(
  id: id,
  name: id,
  provider: 'Bitso',
  status: WalletStatus.active,
  createdAt: at,
  updatedAt: at,
);

List<AccountingMovement> knownOnlyMovements() => <AccountingMovement>[
  canonical(
    id: '01-buy',
    type: MovementType.buy,
    quantity: '2',
    price: '100',
    fiatFee: '4',
    destinationWalletId: walletA,
  ),
  canonical(
    id: '02-buy',
    type: MovementType.buy,
    quantity: '1',
    price: '200',
    fiatFee: '2',
    destinationWalletId: walletA,
  ),
  canonical(
    id: '03-internal',
    type: MovementType.transferOut,
    quantity: '1',
    sourceWalletId: walletA,
    destinationWalletId: walletB,
    destinationType: DestinationType.ownWallet,
    receivedAmount: '1',
    totalDebitedAmount: '1',
  ),
  canonical(
    id: '04-sell',
    type: MovementType.sell,
    quantity: '0.5',
    price: '300',
    fiatFee: '1',
    sourceWalletId: walletB,
  ),
  canonical(
    id: '05-external',
    type: MovementType.transferOut,
    quantity: '0.5',
    sourceWalletId: walletA,
    destinationType: DestinationType.external,
    receivedAmount: '0.5',
    totalDebitedAmount: '0.5',
    externalRecipientName: 'Tercero',
    externalDestinationPlatform: 'Fuera',
  ),
];

List<legacy.Movement> knownOnlyLegacyMovements() => <legacy.Movement>[
  legacyMovement(MovementType.buy, 2, 100, fee: 4, minute: 1),
  legacyMovement(MovementType.buy, 1, 200, fee: 2, minute: 2),
  legacy.Movement(
    id: '03-internal',
    type: MovementType.transferOut,
    coin: 'UNI',
    date: at.add(const Duration(minutes: 3)),
    quantity: 1,
    unitPrice: 0,
    fee: 0,
    receivedAmount: 1,
    cryptoFeeAmount: 0,
    cryptoFeeAsset: 'UNI',
    totalDebitedAmount: 1,
    sourcePlatform: 'Bitso A',
    destinationPlatform: 'Bitso B',
    note: 'Interna histórica',
  ),
  legacyMovement(MovementType.sell, 0.5, 300, fee: 1, minute: 4),
  legacyMovement(MovementType.transferOut, 0.5, 0, minute: 5),
];

legacy.Movement legacyMovement(
  MovementType type,
  double quantity,
  double price, {
  double fee = 0,
  required int minute,
}) => legacy.Movement(
  id: '$minute-${type.name}',
  type: type,
  coin: 'UNI',
  date: at.add(Duration(minutes: minute)),
  quantity: quantity,
  unitPrice: price,
  fee: fee,
  note: 'legacy',
);

AccountingMovement canonical({
  required String id,
  required MovementType type,
  required String quantity,
  String price = '0',
  String fiatFee = '0',
  String? sourceWalletId,
  String? destinationWalletId,
  DestinationType? destinationType,
  String? receivedAmount,
  String? totalDebitedAmount,
  String? externalRecipientName,
  String? externalDestinationPlatform,
}) {
  final occurredAt = at.add(Duration(minutes: int.parse(id.substring(0, 2))));
  return AccountingMovement(
    id: id,
    type: type,
    asset: 'UNI',
    occurredAt: occurredAt,
    quantity: AccountingAmount.parse(quantity),
    unitPriceFiat: AccountingAmount.parse(price),
    fiatFeeAmount: AccountingAmount.parse(fiatFee),
    sourceWalletId: sourceWalletId,
    destinationWalletId: destinationWalletId,
    destinationType: destinationType,
    externalRecipientName: externalRecipientName,
    externalDestinationPlatform: externalDestinationPlatform,
    walletAssignmentStatus: WalletAssignmentStatus.assigned,
    receivedAmount: receivedAmount == null
        ? null
        : AccountingAmount.parse(receivedAmount),
    cryptoFeeAmount: AccountingAmount.zero,
    cryptoFeeAsset: type == MovementType.transferOut ? 'UNI' : null,
    totalDebitedAmount: totalDebitedAmount == null
        ? null
        : AccountingAmount.parse(totalDebitedAmount),
    fiatFeeTreatment: FiatFeeTreatment.none,
    reconciliationLinks: const <ReconciliationLink>[],
    createdAt: occurredAt,
    updatedAt: occurredAt,
  );
}
