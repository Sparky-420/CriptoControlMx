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
  test('legacy conversion issue JSON is lossless for migration quarantine', () {
    const issue = LegacyConversionIssue(
      code: LegacyConversionIssueCode.unknownMovementType,
      message: 'tipo no reconocido',
      rawValue: <String, Object?>{
        'nested': <Object?>[1, true],
      },
    );

    expect(
      LegacyConversionIssue.fromJson(issue.toJson()).rawValue,
      issue.rawValue,
    );
    expect(LegacyConversionIssue.fromJson(issue.toJson()).code, issue.code);
    expect(
      LegacyConversionIssue.fromJson(issue.toJson()).message,
      issue.message,
    );
  });
  test('H1-08 malformed legacy input stays raw without semantic movement', () {
    final raw = <String, Object?>{
      'id': 'broken-legacy',
      'type': 'mystery-operation',
      'coin': '   ',
      'date': 'not-a-date',
      'quantity': 2,
      'futureField': <String, Object?>{'keep': true},
    };

    final conversion = const LegacyMovementAdapter().fromLegacyJson(raw);

    expect(conversion.movementOrNull, isNull);
    expect(
      conversion.issues.map((issue) => issue.code),
      containsAll(<LegacyConversionIssueCode>[
        LegacyConversionIssueCode.unknownMovementType,
        LegacyConversionIssueCode.missingAsset,
        LegacyConversionIssueCode.invalidOccurredAt,
      ]),
    );
    expect(conversion.toLegacyJson(), raw);
    expect(() => conversion.movement, throwsStateError);
  });

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
    expect(conversion.movement.destinationType, DestinationType.ownWallet);
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

  test('synthesizes stable distinct IDs while retaining real duplicates', () {
    final adapter = const LegacyMovementAdapter();
    final firstJson = <String, Object?>{
      'type': 'buy',
      'coin': 'UNI',
      'date': '2026-07-30T20:54:00-06:00',
      'quantity': 1,
      'unitPrice': 10,
      'fee': 0,
    };
    final secondJson = <String, Object?>{...firstJson, 'quantity': 2};
    final first = adapter.fromLegacyJson(firstJson).movement;
    final sameAgain = adapter.fromLegacyJson(firstJson).movement;
    final second = adapter.fromLegacyJson(secondJson).movement;

    expect(first.id, sameAgain.id);
    expect(second.id, isNot(first.id));
    final distinctProjection = project(<AccountingMovement>[
      first,
      second,
    ], const <String, AccountingAmount>{});
    expect(
      distinctProjection
          .positions[const WalletAssetKey(virtualUnassignedWalletId, 'UNI')]!
          .custody
          .reconciledQuantity
          .toJson(),
      '3',
    );
    expect(distinctProjection.migrationProgress.total, 2);

    final duplicateLedger = const DefaultMovementNormalizer().normalize(
      <AccountingMovement>[first, sameAgain],
    );
    expect(duplicateLedger.movements, hasLength(2));
    expect(
      duplicateLedger.issues.map((issue) => issue.code),
      contains(ProjectionIssueCode.duplicateMovementId),
    );
  });

  test('preserves semantically unchanged reconciliation link JSON', () {
    final json = <String, Object?>{
      'id': 'legacy-link',
      'type': 'buy',
      'coin': 'UNI',
      'date': '2026-07-30T20:54:00-06:00',
      'quantity': 1,
      'unitPrice': 10,
      'fee': 0,
      'reconciliation_links': <Object?>[
        <String, Object?>{
          'adjustment_movement_id': 'adjustment-1',
          'quantity_resolved': 0.5,
          'futureLinkField': true,
        },
      ],
    };
    final conversion = const LegacyMovementAdapter().fromLegacyJson(json);

    expect(conversion.movement.reconciliationLinks, hasLength(1));
    expect(
      conversion.movement.reconciliationLinks.single.quantityResolved.toJson(),
      '0.5',
    );
    expect(
      const LegacyMovementAdapter().toLegacyJson(
        conversion.movement,
        preservedFields: conversion.preservedFields,
      ),
      json,
    );
  });

  test(
    'preserves legacy source and wallet fallback classification evidence',
    () {
      final json = <String, Object?>{
        'id': 'legacy-fallback-transfer',
        'type': 'transfer_out',
        'coin': 'UNI',
        'date': '2026-07-30T20:54:00-06:00',
        'quantity': 1,
        'unitPrice': 0,
        'fee': 0,
        'receivedAmount': 1,
        'cryptoFeeAmount': 0,
        'totalDebitedAmount': 1,
        'sourcePlatform': ' ',
        'destinationPlatform': '',
        'source': 'Origen histórico',
        'wallet': 'Destino histórico',
      };
      final conversion = const LegacyMovementAdapter().fromLegacyJson(json);

      expect(conversion.movement.destinationType, DestinationType.ownWallet);
      expect(conversion.movement.sourceWalletId, isNull);
      expect(conversion.movement.destinationWalletId, isNull);
      expect(
        const LegacyMovementAdapter().toLegacyJson(
          conversion.movement,
          preservedFields: conversion.preservedFields,
        ),
        json,
      );
    },
  );

  test(
    'requires a parsed structured value for historical internal evidence',
    () {
      final conversion = const LegacyMovementAdapter()
          .fromLegacyJson(<String, Object?>{
            'id': 'legacy-null-structure',
            'type': 'transfer_out',
            'coin': 'UNI',
            'date': '2026-07-30T20:54:00-06:00',
            'quantity': 1,
            'unitPrice': 0,
            'fee': 0,
            'receivedAmount': null,
            'cryptoFeeAmount': null,
            'totalDebitedAmount': null,
            'sourcePlatform': 'Origen histórico',
            'destinationPlatform': 'Destino histórico',
          });

      expect(conversion.movement.destinationType, isNull);
    },
  );

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
      expect(transfer.destinationType, DestinationType.ownWallet);
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

  test(
    'preserves the historical external branch for structured legacy transfer',
    () {
      final historical = <legacy.Movement>[
        legacy.Movement(
          id: 'external-buy',
          type: MovementType.buy,
          coin: 'UNI',
          date: at,
          quantity: 10,
          unitPrice: 10,
          fee: 0,
          note: 'Compra',
        ),
        legacy.Movement(
          id: 'external-transfer',
          type: MovementType.transferOut,
          coin: 'UNI',
          date: at.add(const Duration(minutes: 1)),
          quantity: 4,
          unitPrice: 0,
          fee: 0,
          receivedAmount: 4,
          cryptoFeeAmount: 1,
          cryptoFeeAsset: 'UNI',
          totalDebitedAmount: 5,
          note: 'Destino no clasificado',
        ),
      ];
      final expected = legacy.FinancialEngine.computeStats(
        coins: const <String>['UNI'],
        movements: historical,
        currentPrices: const <String, double>{'UNI': 0},
      )['UNI']!;
      final adapter = const LegacyMovementAdapter();
      final projection = project(
        historical
            .map(
              (movement) => adapter
                  .fromLegacyJson(Map<String, Object?>.from(movement.toJson()))
                  .movement,
            )
            .toList(),
        const <String, AccountingAmount>{},
      );
      final position = projection
          .positions[const WalletAssetKey(virtualUnassignedWalletId, 'UNI')]!;

      expect(expected.quantity, 6);
      expect(
        double.parse(position.custody.reconciledQuantity.toJson()),
        closeTo(expected.quantity, 0.00000001),
      );
      expect(
        double.parse(position.performance.knownCostBasis.toJson()),
        closeTo(expected.costBase, 0.00000001),
      );
      expect(
        projection.effects['external-transfer']!.requestedQuantity.toJson(),
        '4',
      );
      expect(
        projection.issues.map((issue) => issue.code),
        contains(ProjectionIssueCode.missingDestinationClassification),
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

  test('H1-01 legacy transferIn keeps documented cost compatibility', () {
    final adapter = const LegacyMovementAdapter();
    final documented = adapter.fromLegacyJson(<String, Object?>{
      'id': 'legacy-in-known',
      'type': 'transfer_in',
      'coin': 'UNI',
      'date': '2026-07-30T20:54:00Z',
      'quantity': 2,
      'unitPrice': 100,
      'fee': 5,
    }).movement;
    final unknown = adapter.fromLegacyJson(<String, Object?>{
      'id': 'legacy-in-unknown',
      'type': 'transfer_in',
      'coin': 'UNI',
      'date': '2026-07-30T20:54:00Z',
      'quantity': 2,
      'fee': 0,
    }).movement;
    final financial = const LegacyFinancialAdapter();
    final knownProjection = project(<AccountingMovement>[documented], const {});
    final unknownProjection = project(<AccountingMovement>[unknown], const {});
    final knownData = financial.coinStats(knownProjection, const {})['UNI']!;
    final unknownData = financial.coinStats(
      unknownProjection,
      const {},
    )['UNI']!;

    expect(knownData.quantity, 2);
    expect(knownData.custodyQuantity, 2);
    expect(knownData.costBase, 205);
    expect(knownData.completeness, AccountingCompleteness.unassignedLegacy);
    expect(unknownData.quantity, 0);
    expect(unknownData.custodyQuantity, 2);
    expect(unknownData.costBase, 0);
    expect(unknownData.hasDefinitivePerformance, isFalse);
  });

  test('H1-06 legacy DTO separates known performance from partial custody', () {
    final projection = project(
      <AccountingMovement>[
        canonical(
          id: '01-partial-buy',
          type: MovementType.buy,
          quantity: '10',
          price: '10',
          destinationWalletId: walletA,
        ),
        canonicalAdjustment(
          id: '02-partial-adjustment',
          quantity: '2',
          observed: '12',
        ),
      ],
      <String, AccountingAmount>{'UNI': AccountingAmount.fromInt(50)},
    );
    final adapter = const LegacyFinancialAdapter();
    final data = adapter.coinStats(projection, const {'UNI': 50})['UNI']!;
    final totals = adapter.totals(projection, const {'UNI': 50});

    expect(data.quantity, 10);
    expect(data.custodyQuantity, 12);
    expect(data.unknownQuantity, 2);
    expect(data.costBase, 100);
    expect(data.completeness, AccountingCompleteness.partiallyKnown);
    expect(data.hasDefinitivePerformance, isFalse);
    expect(totals.currentValue, 500);
    expectIncompleteLegacyBridge(
      data: data,
      totals: totals,
      custodyQuantity: 12,
      unknownQuantity: 2,
      knownUnrealizedPnl: 400,
    );
  });

  test('H1-06 legacy DTO exposes deficit without zero-cost inference', () {
    final projection = project(
      <AccountingMovement>[
        canonical(
          id: '01-deficit-buy',
          type: MovementType.buy,
          quantity: '10',
          price: '10',
          destinationWalletId: walletA,
        ),
        canonicalAdjustment(
          id: '02-deficit-adjustment',
          quantity: '-2',
          observed: '8',
        ),
      ],
      <String, AccountingAmount>{'UNI': AccountingAmount.fromInt(50)},
    );
    final adapter = const LegacyFinancialAdapter();
    final data = adapter.coinStats(projection, const {'UNI': 50})['UNI']!;
    final totals = adapter.totals(projection, const {'UNI': 50});

    expect(data.quantity, 10);
    expect(data.custodyQuantity, 8);
    expect(data.unknownQuantity, 0);
    expect(data.costBase, 100);
    expect(data.completeness, AccountingCompleteness.partiallyKnown);
    expect(data.hasDefinitivePerformance, isFalse);
    expectIncompleteLegacyBridge(
      data: data,
      totals: totals,
      custodyQuantity: 8,
      unknownQuantity: 0,
      knownUnrealizedPnl: 400,
    );
  });

  test('H1-06 fully unknown custody never creates performance value', () {
    final projection = project(
      <AccountingMovement>[
        canonicalAdjustment(
          id: '01-unknown-adjustment',
          quantity: '2',
          observed: '2',
        ),
      ],
      <String, AccountingAmount>{'UNI': AccountingAmount.fromInt(50)},
    );
    final adapter = const LegacyFinancialAdapter();
    final data = adapter.coinStats(projection, const {'UNI': 50})['UNI']!;
    final totals = adapter.totals(projection, const {'UNI': 50});

    expect(data.quantity, 0);
    expect(data.custodyQuantity, 2);
    expect(data.unknownQuantity, 2);
    expect(data.costBase, 0);
    expect(data.hasDefinitivePerformance, isFalse);
    expect(totals.currentValue, 0);
    expectIncompleteLegacyBridge(
      data: data,
      totals: totals,
      custodyQuantity: 2,
      unknownQuantity: 2,
      knownUnrealizedPnl: 0,
    );
  });

  test('normalizes price lookup and treats a missing price as zero', () {
    final projection = project(
      <AccountingMovement>[
        canonical(
          id: '01-lowercase-price',
          type: MovementType.buy,
          quantity: '1',
          price: '10',
          destinationWalletId: walletA,
        ),
      ],
      <String, AccountingAmount>{'UNI': AccountingAmount.fromInt(50)},
    );
    final adapter = const LegacyFinancialAdapter();

    expect(
      adapter.totals(projection, const <String, double>{
        'uni': 50,
      }).currentValue,
      50,
    );
    expect(
      adapter.totals(projection, const <String, double>{}).currentValue,
      0,
    );
  });
}

void expectIncompleteLegacyBridge({
  required LegacyCoinStatsData data,
  required LegacyPortfolioTotalsData totals,
  required double custodyQuantity,
  required double unknownQuantity,
  required double knownUnrealizedPnl,
}) {
  final bridgedStats = legacy.CoinStats.fromLegacyData(data, currentPrice: 50);
  final bridgedTotals = legacy.PortfolioTotals.fromLegacyData(totals);

  expect(bridgedStats.completeness, AccountingCompleteness.partiallyKnown);
  expect(bridgedStats.hasDefinitivePerformance, isFalse);
  expect(bridgedStats.knownQuantity, data.quantity);
  expect(bridgedStats.custodyQuantity, custodyQuantity);
  expect(bridgedStats.unknownQuantity, unknownQuantity);
  expect(bridgedStats.knownUnrealizedPL, knownUnrealizedPnl);
  expect(bridgedStats.definitiveUnrealizedPL, isNull);
  expect(bridgedStats.definitiveEstimatedNetPnl(1.5), isNull);

  expect(totals.completeness, AccountingCompleteness.partiallyKnown);
  expect(totals.hasDefinitivePerformance, isFalse);
  expect(totals.knownUnrealizedProfit, knownUnrealizedPnl);
  expect(totals.definitiveUnrealizedProfit, isNull);
  expect(bridgedTotals.completeness, AccountingCompleteness.partiallyKnown);
  expect(bridgedTotals.hasDefinitivePerformance, isFalse);
  expect(bridgedTotals.knownUnrealizedPL, knownUnrealizedPnl);
  expect(bridgedTotals.definitiveUnrealizedPL, isNull);
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

AccountingMovement canonicalAdjustment({
  required String id,
  required String quantity,
  required String observed,
}) {
  final occurredAt = at.add(Duration(minutes: int.parse(id.substring(0, 2))));
  return AccountingMovement(
    id: id,
    type: MovementType.balanceAdjustment,
    asset: 'UNI',
    occurredAt: occurredAt,
    fiatFeeAmount: AccountingAmount.zero,
    walletAssignmentStatus: WalletAssignmentStatus.assigned,
    cryptoFeeAmount: AccountingAmount.zero,
    fiatFeeTreatment: FiatFeeTreatment.none,
    reconciliationLinks: const <ReconciliationLink>[],
    createdAt: occurredAt,
    updatedAt: occurredAt,
    adjustmentWalletId: walletA,
    adjustmentQuantity: AccountingAmount.parse(quantity),
    observedBalance: AccountingAmount.parse(observed),
    adjustmentReason: 'Corte',
  );
}
