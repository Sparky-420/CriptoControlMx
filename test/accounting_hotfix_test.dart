import 'package:flutter_test/flutter_test.dart';
import 'package:cripto_control_mx/cripto_control_app.dart';

void main() {
  const List<String> coins = <String>['BTC', 'ETH', 'LINK', 'LTC', 'UNI'];
  final DateTime baseDate = DateTime.utc(2026, 7, 1, 12);

  Movement movement({
    required MovementType type,
    required String coin,
    required double quantity,
    required double unitPrice,
    double fee = 0,
    int minutes = 0,
  }) {
    return Movement(
      type: type,
      coin: coin,
      date: baseDate.add(Duration(minutes: minutes)),
      quantity: quantity,
      unitPrice: unitPrice,
      fee: fee,
      note: 'test',
    );
  }

  CoinStats statsFor(
    String coin,
    List<Movement> movements, {
    double currentPrice = 0,
  }) {
    return FinancialEngine.computeStats(
      coins: coins,
      movements: movements,
      currentPrices: <String, double>{coin: currentPrice},
    )[coin]!;
  }

  group('financial accounting hotfix', () {
    test('UNI case separates gross and estimated net result', () {
      const double quantity = 128.76051517;
      const double currentCostBasis = 8804.80;
      const double currentValue = 8691.33;
      const double currentPrice = currentValue / quantity;
      final CoinStats stats = CoinStats(
        coin: 'UNI',
        quantity: quantity,
        costBase: currentCostBasis,
        currentPrice: currentPrice,
      );

      expect(stats.avgPrice, closeTo(68.38, 0.01));
      expect(stats.unrealizedPL, closeTo(-113.47, 0.01));
      expect(stats.estimatedExitFee(1.5), closeTo(130.37, 0.01));
      expect(stats.estimatedNetValue(1.5), closeTo(8560.96, 0.01));
      expect(stats.estimatedNetPnl(1.5), closeTo(-243.84, 0.01));
      expect(stats.netBreakEvenPrice(1.5), closeTo(69.42, 0.01));
    });

    test('zero quantity never produces NaN or Infinity', () {
      final CoinStats stats = CoinStats(coin: 'UNI');

      expect(stats.avgPrice, 0);
      expect(stats.netBreakEvenPrice(1.5), 0);
      expect(stats.estimatedExitFee(1.5), 0);
      expect(stats.estimatedNetValue(1.5), 0);
      expect(stats.estimatedNetPnl(1.5), 0);
      expect(stats.avgPrice.isFinite, isTrue);
      expect(stats.netBreakEvenPrice(1.5).isFinite, isTrue);
    });

    test('zero commission keeps gross and net values equal', () {
      final CoinStats stats = CoinStats(
        coin: 'BTC',
        quantity: 2,
        costBase: 1000,
        currentPrice: 600,
      );

      expect(stats.estimatedExitFee(0), 0);
      expect(stats.estimatedNetValue(0), stats.currentValue);
      expect(stats.estimatedNetPnl(0), stats.unrealizedPL);
    });

    test('buy commission is capitalized once', () {
      final CoinStats stats = statsFor('BTC', <Movement>[
        movement(
          type: MovementType.buy,
          coin: 'BTC',
          quantity: 1,
          unitPrice: 100,
          fee: 10,
        ),
      ], currentPrice: 120);
      final CoinAudit audit = FinancialEngine.computeAudit(
        coin: 'BTC',
        movements: <Movement>[
          movement(
            type: MovementType.buy,
            coin: 'BTC',
            quantity: 1,
            unitPrice: 100,
            fee: 10,
          ),
        ],
      );

      expect(stats.costBase, 110);
      expect(stats.feesPaid, 10);
      expect(audit.buyGrossCost, 100);
      expect(audit.costBaseFromBuys, 110);
      expect(audit.capitalizedFees, 10);
      expect(audit.reconciledCostBase, stats.costBase);
    });

    test('transfer in with known cost basis is incorporated', () {
      final List<Movement> movements = <Movement>[
        movement(
          type: MovementType.transferIn,
          coin: 'ETH',
          quantity: 2,
          unitPrice: 100,
          fee: 5,
        ),
      ];
      final CoinStats stats = statsFor('ETH', movements, currentPrice: 120);
      final CoinAudit audit = FinancialEngine.computeAudit(
        coin: 'ETH',
        movements: movements,
      );

      expect(stats.quantity, 2);
      expect(stats.costBase, 205);
      expect(audit.transferInGrossCost, 200);
      expect(audit.costBaseFromTransferIns, 205);
      expect(audit.capitalizedFees, 5);
      expect(audit.undeterminedTransferInCount, 0);
    });

    test('transfer in without known cost basis does not invent cost', () {
      final Movement legacy = Movement.fromJson(<String, dynamic>{
        'type': 'transfer_in',
        'coin': 'LINK',
        'date': baseDate.toIso8601String(),
        'quantity': '3.5',
        'note': 'legacy without price',
      });
      final CoinStats stats = statsFor('LINK', <Movement>[legacy]);
      final CoinAudit audit = FinancialEngine.computeAudit(
        coin: 'LINK',
        movements: <Movement>[legacy],
      );

      expect(stats.quantity, 3.5);
      expect(stats.costBase, 0);
      expect(audit.undeterminedTransferInCount, 1);
      expect(audit.reconciledCostBase, 0);
    });

    test('partial transfer out removes weighted-average cost basis', () {
      final List<Movement> movements = <Movement>[
        movement(
          type: MovementType.buy,
          coin: 'LINK',
          quantity: 2,
          unitPrice: 100,
        ),
        movement(
          type: MovementType.transferOut,
          coin: 'LINK',
          quantity: 1,
          unitPrice: 120,
          minutes: 1,
        ),
      ];
      final CoinStats stats = statsFor('LINK', movements, currentPrice: 100);
      final CoinAudit audit = FinancialEngine.computeAudit(
        coin: 'LINK',
        movements: movements,
      );

      expect(stats.quantity, 1);
      expect(stats.costBase, 100);
      expect(audit.transferOutMarketValue, 120);
      expect(audit.costBaseTransferredOut, 100);
      expect(audit.reconciledCostBase, stats.costBase);
    });

    test('partial sale separates proceeds, sold cost and realized P&L', () {
      final List<Movement> movements = <Movement>[
        movement(
          type: MovementType.buy,
          coin: 'BTC',
          quantity: 2,
          unitPrice: 100,
        ),
        movement(
          type: MovementType.sell,
          coin: 'BTC',
          quantity: 1,
          unitPrice: 150,
          fee: 5,
          minutes: 1,
        ),
      ];
      final CoinStats stats = statsFor('BTC', movements, currentPrice: 150);
      final CoinAudit audit = FinancialEngine.computeAudit(
        coin: 'BTC',
        movements: movements,
      );

      expect(stats.quantity, 1);
      expect(stats.costBase, 100);
      expect(stats.realizedPL, 45);
      expect(audit.saleGrossProceeds, 150);
      expect(audit.costBaseSold, 100);
    });

    test('total sale clears remaining cost basis', () {
      final CoinStats stats = statsFor('BTC', <Movement>[
        movement(
          type: MovementType.buy,
          coin: 'BTC',
          quantity: 1,
          unitPrice: 100,
        ),
        movement(
          type: MovementType.sell,
          coin: 'BTC',
          quantity: 1,
          unitPrice: 150,
          minutes: 1,
        ),
      ]);

      expect(stats.quantity, 0);
      expect(stats.costBase, 0);
      expect(stats.realizedPL, 50);
    });

    test('multiple buys at different prices use weighted average', () {
      final CoinStats stats = statsFor('LTC', <Movement>[
        movement(
          type: MovementType.buy,
          coin: 'LTC',
          quantity: 1,
          unitPrice: 100,
        ),
        movement(
          type: MovementType.buy,
          coin: 'LTC',
          quantity: 3,
          unitPrice: 300,
          minutes: 1,
        ),
      ]);

      expect(stats.quantity, 4);
      expect(stats.costBase, 1000);
      expect(stats.avgPrice, 250);
    });

    test('buy plus transfer in plus transfer out plus fees reconciles', () {
      final List<Movement> movements = <Movement>[
        movement(
          type: MovementType.buy,
          coin: 'UNI',
          quantity: 10,
          unitPrice: 50,
          fee: 5,
        ),
        movement(
          type: MovementType.transferIn,
          coin: 'UNI',
          quantity: 5,
          unitPrice: 60,
          fee: 2,
          minutes: 1,
        ),
        movement(
          type: MovementType.transferOut,
          coin: 'UNI',
          quantity: 3,
          unitPrice: 40,
          fee: 1,
          minutes: 2,
        ),
      ];
      final CoinStats stats = statsFor('UNI', movements, currentPrice: 70);
      final CoinAudit audit = FinancialEngine.computeAudit(
        coin: 'UNI',
        movements: movements,
      );

      expect(stats.quantity, 12);
      expect(audit.costBaseTransferredOut, closeTo(161.4, 0.000001));
      expect(stats.costBase, closeTo(645.6, 0.000001));
      expect(audit.reconciledCostBase, closeTo(stats.costBase, 0.000001));
    });

    test('old JSON without new fields still restores movement defaults', () {
      final Movement restored = Movement.fromJson(<String, dynamic>{
        'type': 'compra',
        'crypto': 'uni',
        'date': baseDate.toIso8601String(),
        'quantity': '2',
        'unit_price': '50',
        'commission': '1',
      });

      expect(restored.type, MovementType.buy);
      expect(restored.coin, 'UNI');
      expect(restored.quantity, 2);
      expect(restored.unitPrice, 50);
      expect(restored.fee, 1);
      expect(restored.schemaVersion, 1);
    });

    test('internal calculations are not rounded to two decimals', () {
      final CoinStats stats = statsFor('ETH', <Movement>[
        movement(
          type: MovementType.buy,
          coin: 'ETH',
          quantity: 3,
          unitPrice: 100,
        ),
        movement(
          type: MovementType.sell,
          coin: 'ETH',
          quantity: 1,
          unitPrice: 101,
          minutes: 1,
        ),
      ]);

      expect(stats.costBase, closeTo(200, 0.0000001));
      expect(stats.avgPrice, closeTo(100, 0.0000001));
      expect(stats.avgPrice.toStringAsFixed(8), '100.00000000');
    });

    test('summary, coin stats and detail audit use the same cost basis', () {
      final List<Movement> movements = <Movement>[
        movement(
          type: MovementType.buy,
          coin: 'UNI',
          quantity: 4,
          unitPrice: 25,
        ),
        movement(
          type: MovementType.transferOut,
          coin: 'UNI',
          quantity: 1,
          unitPrice: 10,
          minutes: 1,
        ),
      ];
      final Map<String, CoinStats> stats = FinancialEngine.computeStats(
        coins: coins,
        movements: movements,
        currentPrices: const <String, double>{'UNI': 30},
      );
      final PortfolioTotals totals = FinancialEngine.totals(stats);
      final CoinAudit audit = FinancialEngine.computeAudit(
        coin: 'UNI',
        movements: movements,
      );

      expect(stats['UNI']!.costBase, 75);
      expect(totals.costBase, stats['UNI']!.costBase);
      expect(audit.reconciledCostBase, stats['UNI']!.costBase);
    });

    test('audit breakdown reconciles final cost basis exactly', () {
      final List<Movement> movements = <Movement>[
        movement(
          type: MovementType.buy,
          coin: 'BTC',
          quantity: 2,
          unitPrice: 100,
          fee: 4,
        ),
        movement(
          type: MovementType.sell,
          coin: 'BTC',
          quantity: 0.5,
          unitPrice: 150,
          fee: 1,
          minutes: 1,
        ),
      ];
      final CoinStats stats = statsFor('BTC', movements);
      final CoinAudit audit = FinancialEngine.computeAudit(
        coin: 'BTC',
        movements: movements,
      );

      expect(audit.reconciledCostBase, closeTo(stats.costBase, 0.0000001));
      expect(audit.accountingAdjustments, closeTo(0, 0.0000001));
    });

    test(
      'UNI audit reconciles reported cost basis without double-counting fees',
      () {
        final List<Movement> movements = <Movement>[
          movement(
            type: MovementType.buy,
            coin: 'UNI',
            quantity: 100,
            unitPrice: 67.6874,
            fee: 60,
          ),
          movement(
            type: MovementType.transferIn,
            coin: 'UNI',
            quantity: 36.4929023220236,
            unitPrice: 67.4657219169483,
            fee: 42.79,
            minutes: 1,
          ),
          movement(
            type: MovementType.transferOut,
            coin: 'UNI',
            quantity: 7.73238715202362,
            unitPrice: 44.708056283696,
            minutes: 2,
          ),
        ];
        final CoinStats stats = statsFor('UNI', movements);
        final CoinAudit audit = FinancialEngine.computeAudit(
          coin: 'UNI',
          movements: movements,
        );
        final double reconciled =
            audit.costBaseFromBuys +
            audit.costBaseFromTransferIns +
            audit.accountingAdjustments -
            audit.costBaseSold -
            audit.costBaseTransferredOut;

        expect(stats.quantity, closeTo(128.76051517, 0.00000001));
        expect(stats.costBase, closeTo(8804.80, 0.01));
        expect(audit.costBaseFromBuys, closeTo(6828.74, 0.01));
        expect(audit.costBaseFromTransferIns, closeTo(2504.81, 0.01));
        expect(audit.costBaseTransferredOut, closeTo(528.75, 0.01));
        expect(audit.transferOutMarketValue, closeTo(345.70, 0.01));
        expect(audit.fees, closeTo(102.79, 0.01));
        expect(reconciled, closeTo(8804.80, 0.01));
        expect(audit.reconciledCostBase, closeTo(stats.costBase, 0.01));
      },
    );

    test('accounting never returns NaN, Infinity or impossible negatives', () {
      final CoinStats stats = statsFor('UNI', <Movement>[
        movement(
          type: MovementType.buy,
          coin: 'UNI',
          quantity: 1,
          unitPrice: 100,
        ),
        movement(
          type: MovementType.transferOut,
          coin: 'UNI',
          quantity: 2,
          unitPrice: 100,
          minutes: 1,
        ),
      ]);

      expect(stats.quantity.isFinite, isTrue);
      expect(stats.costBase.isFinite, isTrue);
      expect(stats.avgPrice.isFinite, isTrue);
      expect(stats.currentValue.isFinite, isTrue);
      expect(stats.unrealizedPL.isFinite, isTrue);
      expect(stats.quantity, greaterThanOrEqualTo(0));
      expect(stats.costBase, greaterThanOrEqualTo(0));
    });
  });
}
