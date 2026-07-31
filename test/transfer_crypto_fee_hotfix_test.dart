import 'dart:convert';

import 'package:cripto_control_mx/cripto_control_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const List<String> coins = <String>['BTC', 'ETH', 'LINK', 'LTC', 'UNI'];
  final DateTime date = DateTime.utc(2026, 7, 31, 12);

  Movement buy({
    required String coin,
    required double quantity,
    required double unitPrice,
    required String platform,
    int minute = 0,
  }) => Movement(
    type: MovementType.buy,
    coin: coin,
    date: date.add(Duration(minutes: minute)),
    quantity: quantity,
    unitPrice: unitPrice,
    fee: 0,
    source: platform,
    note: 'saldo inicial',
  );

  Movement uniTransfer({
    double received = 1,
    double cryptoFee = 0.001703,
    String feeAsset = 'UNI',
    double totalDebited = 1.001703,
    double feeFiat = 0.132800,
  }) => Movement(
    type: MovementType.transferOut,
    coin: 'UNI',
    date: date.add(const Duration(minutes: 1)),
    quantity: received,
    unitPrice: 77.98,
    fee: feeFiat,
    receivedAmount: received,
    cryptoFeeAmount: cryptoFee,
    cryptoFeeAsset: feeAsset,
    totalDebitedAmount: totalDebited,
    feeFiatValue: feeFiat,
    sourcePlatform: 'Mercado Pago',
    destinationPlatform: 'Bitso',
    source: 'Mercado Pago',
    wallet: 'Bitso',
    network: 'Ethereum / ERC-20',
    note: 'transferencia propia',
  );

  group('OCR transfer amount semantics', () {
    test('extracts exact Mercado Pago to Bitso case', () {
      final Map<String, Object?> parsed = parseOcrForTest(r'''
Mercado Pago
Transferencia enviada
Activo UNI
La persona recibe
1 UNI
Comisión de red
0.001703 UNI
Total a descontar
1.001703 UNI
Precio de UNI $77.98
Origen
Mercado Pago
Destino
Bitso
Red
Ethereum / ERC-20
Fecha 31/07/2026 12:00
''');

      expect(parsed['coin'], 'UNI');
      expect(parsed['receivedAmount'], 1);
      expect(parsed['quantity'], 1);
      expect(parsed['cryptoFeeAmount'], 0.001703);
      expect(parsed['cryptoFeeAsset'], 'UNI');
      expect(parsed['totalDebitedAmount'], 1.001703);
      expect(parsed['feeFiatValue'], closeTo(0.13, 0.01));
      expect(parsed['sourcePlatform'], 'Mercado Pago');
      expect(parsed['destinationPlatform'], 'Bitso');
      expect(parsed['network'], 'Ethereum / ERC-20');
      expect(parsed['transferConsistent'], isTrue);
    });

    test('derives received from total plus fee', () {
      final TransferAmounts amounts = reconcileTransferAmounts(
        primaryAsset: 'UNI',
        cryptoFeeAmount: 0.001703,
        cryptoFeeAsset: 'UNI',
        totalDebitedAmount: 1.001703,
      );

      expect(amounts.receivedAmount, closeTo(1, transferAmountTolerance));
      expect(amounts.isConsistent('UNI'), isTrue);
    });

    test('derives total from received plus fee', () {
      final TransferAmounts amounts = reconcileTransferAmounts(
        primaryAsset: 'UNI',
        receivedAmount: 1,
        cryptoFeeAmount: 0.001703,
        cryptoFeeAsset: 'UNI',
      );

      expect(
        amounts.totalDebitedAmount,
        closeTo(1.001703, transferAmountTolerance),
      );
      expect(amounts.isConsistent('UNI'), isTrue);
    });

    test('derives fee from received plus total', () {
      final TransferAmounts amounts = reconcileTransferAmounts(
        primaryAsset: 'UNI',
        receivedAmount: 1,
        totalDebitedAmount: 1.001703,
      );

      expect(
        amounts.cryptoFeeAmount,
        closeTo(0.001703, transferAmountTolerance),
      );
      expect(amounts.cryptoFeeAsset, 'UNI');
    });

    test('marks three inconsistent figures for manual review', () {
      final TransferAmounts amounts = reconcileTransferAmounts(
        primaryAsset: 'UNI',
        receivedAmount: 1,
        cryptoFeeAmount: 0.001703,
        cryptoFeeAsset: 'UNI',
        totalDebitedAmount: 1.5,
      );

      expect(amounts.isConsistent('UNI'), isFalse);
      expect(
        amounts.warnings,
        contains(
          'Las cifras no cuadran: recibido + comisión debe ser igual al total descontado.',
        ),
      );
    });

    test('accepts point, comma decimal and thousands separators', () {
      expect(parseFlexibleDecimal('0,001703'), 0.001703);
      expect(parseFlexibleDecimal('1.001703'), 1.001703);
      expect(parseFlexibleDecimal('1.234.567,89'), 1234567.89);
      expect(parseFlexibleDecimal('1,234,567.89'), 1234567.89);
    });
  });

  group('owned-platform transfer accounting', () {
    test('moves principal, consumes only crypto fee and creates no P&L', () {
      final List<Movement> movements = <Movement>[
        buy(coin: 'UNI', quantity: 2, unitPrice: 70, platform: 'Mercado Pago'),
        uniTransfer(),
      ];
      final CoinStats stats = FinancialEngine.computeStats(
        coins: coins,
        movements: movements,
        currentPrices: const <String, double>{'UNI': 77.98},
      )['UNI']!;
      final CoinAudit audit = FinancialEngine.computeAudit(
        coin: 'UNI',
        movements: movements,
      );
      final Map<String, Map<String, double>> platforms =
          FinancialEngine.computePlatformBalances(movements: movements);

      expect(
        platforms['Mercado Pago']!['UNI'],
        closeTo(0.998297, transferAmountTolerance),
      );
      expect(platforms['Bitso']!['UNI'], 1);
      expect(stats.quantity, closeTo(1.998297, transferAmountTolerance));
      expect(2 - stats.quantity, closeTo(0.001703, transferAmountTolerance));
      expect(stats.realizedPL, 0);
      expect(audit.realizedPL, 0);
      expect(stats.avgPrice, closeTo(70, transferAmountTolerance));
      expect(stats.costBase, closeTo(139.88079, transferAmountTolerance));
      expect(
        movements.where((Movement m) => m.type == MovementType.sell),
        isEmpty,
      );
      expect(
        movements.where((Movement m) => m.type == MovementType.transferOut),
        hasLength(1),
      );
    });

    test('fee charged in another asset reduces only that asset', () {
      final List<Movement> movements = <Movement>[
        buy(coin: 'UNI', quantity: 2, unitPrice: 70, platform: 'Mercado Pago'),
        buy(
          coin: 'ETH',
          quantity: 1,
          unitPrice: 30000,
          platform: 'Mercado Pago',
          minute: 1,
        ),
        uniTransfer(
          cryptoFee: 0.01,
          feeAsset: 'ETH',
          totalDebited: 1,
          feeFiat: 300,
        ).copyWith(date: date.add(const Duration(minutes: 2))),
      ];
      final Map<String, CoinStats> stats = FinancialEngine.computeStats(
        coins: coins,
        movements: movements,
        currentPrices: const <String, double>{'UNI': 77.98, 'ETH': 30000},
      );

      expect(stats['UNI']!.quantity, 2);
      expect(stats['UNI']!.avgPrice, 70);
      expect(stats['ETH']!.quantity, closeTo(0.99, transferAmountTolerance));
      expect(stats['ETH']!.realizedPL, 0);
    });

    test('transfer without fee preserves global quantity and average', () {
      final List<Movement> movements = <Movement>[
        buy(coin: 'UNI', quantity: 2, unitPrice: 70, platform: 'Mercado Pago'),
        uniTransfer(cryptoFee: 0, totalDebited: 1, feeFiat: 0),
      ];
      final CoinStats stats = FinancialEngine.computeStats(
        coins: coins,
        movements: movements,
        currentPrices: const <String, double>{'UNI': 77.98},
      )['UNI']!;

      expect(stats.quantity, 2);
      expect(stats.costBase, 140);
      expect(stats.avgPrice, 70);
      expect(stats.realizedPL, 0);
    });

    test(
      'complete source balance transfer leaves received amount globally',
      () {
        final List<Movement> movements = <Movement>[
          buy(
            coin: 'UNI',
            quantity: 1.001703,
            unitPrice: 70,
            platform: 'Mercado Pago',
          ),
          uniTransfer(),
        ];
        final CoinStats stats = FinancialEngine.computeStats(
          coins: coins,
          movements: movements,
          currentPrices: const <String, double>{'UNI': 77.98},
        )['UNI']!;
        final Map<String, Map<String, double>> platforms =
            FinancialEngine.computePlatformBalances(movements: movements);

        expect(stats.quantity, closeTo(1, transferAmountTolerance));
        expect(
          platforms['Mercado Pago']!['UNI'],
          closeTo(0, transferAmountTolerance),
        );
        expect(platforms['Bitso']!['UNI'], 1);
      },
    );
  });

  group('persistence and compatibility', () {
    test('structured transfer survives local JSON and backup round trips', () {
      final Movement original = uniTransfer();
      final String stored = jsonEncode(original.toJson());
      final Movement restored = Movement.fromJson(
        Map<String, dynamic>.from(jsonDecode(stored) as Map),
      );
      final String backup = jsonEncode(<String, Object>{
        'version': 2,
        'movements': <Map<String, dynamic>>[original.toJson()],
        'currentPrices': <String, double>{'UNI': 77.98},
        'settings': <String, Object>{},
      });
      final Map<String, dynamic> decodedBackup = Map<String, dynamic>.from(
        jsonDecode(backup) as Map,
      );
      final Movement imported = Movement.fromJson(
        Map<String, dynamic>.from(
          (decodedBackup['movements'] as List).single as Map,
        ),
      );

      expect(restored.isFinanciallyIdenticalTo(original), isTrue);
      expect(imported.receivedAmount, 1);
      expect(imported.cryptoFeeAmount, 0.001703);
      expect(imported.cryptoFeeAsset, 'UNI');
      expect(imported.totalDebitedAmount, 1.001703);
      expect(imported.sourcePlatform, 'Mercado Pago');
      expect(imported.destinationPlatform, 'Bitso');
      expect(imported.network, 'Ethereum / ERC-20');
    });

    test('legacy transfer with MXN-only fee does not invent crypto fee', () {
      final Movement legacy = Movement.fromJson(<String, dynamic>{
        'type': 'transfer_out',
        'coin': 'UNI',
        'date': date.toIso8601String(),
        'quantity': '1',
        'unitPrice': '77.98',
        'commission': '0.13',
        'source': 'Mercado Pago',
        'wallet': 'Bitso',
      });

      expect(legacy.quantity, 1);
      expect(legacy.fee, 0.13);
      expect(legacy.cryptoFeeAmount, isNull);
      expect(legacy.totalDebitedAmount, isNull);
      expect(legacy.isStructuredOwnedTransfer, isFalse);
    });

    test('legacy cryptoAmount remains the received transfer amount', () {
      final Movement legacy = Movement.fromJson(<String, dynamic>{
        'type': 'transfer_out',
        'coin': 'UNI',
        'date': date.toIso8601String(),
        'cryptoAmount': '1',
        'unitPrice': '77.98',
        'fee': '0.13',
      });

      expect(legacy.quantity, 1);
      expect(legacy.effectiveReceivedAmount, 1);
      expect(legacy.cryptoFeeAmount, isNull);
      expect(legacy.totalDebitedAmount, isNull);
    });

    test('buy and sell accounting remains unchanged', () {
      final List<Movement> movements = <Movement>[
        Movement(
          type: MovementType.buy,
          coin: 'UNI',
          date: date,
          quantity: 1,
          unitPrice: 100,
          fee: 10,
          note: '',
        ),
        Movement(
          type: MovementType.sell,
          coin: 'UNI',
          date: date.add(const Duration(minutes: 1)),
          quantity: 0.5,
          unitPrice: 120,
          fee: 1,
          note: '',
        ),
      ];
      final CoinStats stats = FinancialEngine.computeStats(
        coins: coins,
        movements: movements,
        currentPrices: const <String, double>{'UNI': 120},
      )['UNI']!;

      expect(stats.quantity, 0.5);
      expect(stats.costBase, 55);
      expect(stats.realizedPL, 4);
    });
  });
}

Map<String, Object?> parseOcrForTest(String text) {
  final dynamic state = MovementsTab(
    movements: <Movement>[],
    coins: const <String>['BTC', 'ETH', 'LINK', 'LTC', 'UNI'],
    onAdd: () async {},
    onAddFromOcr: (_) async {},
    onEdit: (_) async {},
    onDelete: (_) {},
  ).createState();
  return state.parseOcrForTesting(text) as Map<String, Object?>;
}
