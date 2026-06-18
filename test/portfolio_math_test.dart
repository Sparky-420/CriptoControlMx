import 'package:flutter_test/flutter_test.dart';
import 'package:cripto_control_mx/domain/portfolio_math.dart';
import 'package:cripto_control_mx/domain/portfolio_models.dart';

void main() {
  test('computeStats keeps average-cost sell math stable', () {
    final List<Movement> movements = <Movement>[
      Movement(
        type: MovementType.buy,
        coin: 'BTC',
        date: DateTime(2026, 1, 1),
        quantity: 1,
        unitPrice: 100,
        fee: 2,
        note: 'buy',
      ),
      Movement(
        type: MovementType.sell,
        coin: 'BTC',
        date: DateTime(2026, 1, 2),
        quantity: 0.25,
        unitPrice: 120,
        fee: 1,
        note: 'sell',
      ),
    ];

    final Map<String, CoinStats> stats = PortfolioMath.computeStats(
      coins: const <String>['BTC'],
      movements: movements,
      currentPrices: const <String, double>{'BTC': 130},
    );

    final CoinStats btc = stats['BTC']!;

    expect(btc.quantity, 0.75);
    expect(btc.costBase, 76.5);
    expect(btc.realizedPL, 3.5);
    expect(btc.currentValue, 97.5);
    expect(btc.avgPrice, 102.0);
  });

  test('wouldCreateInvalidPosition rejects oversell', () {
    final Movement buy = Movement(
      type: MovementType.buy,
      coin: 'LINK',
      date: DateTime(2026, 1, 1),
      quantity: 10,
      unitPrice: 100,
      fee: 0,
      note: 'buy',
    );

    final Movement oversell = Movement(
      type: MovementType.sell,
      coin: 'LINK',
      date: DateTime(2026, 1, 2),
      quantity: 11,
      unitPrice: 110,
      fee: 0,
      note: 'oversell',
    );

    expect(
      PortfolioMath.wouldCreateInvalidPosition(
        coins: const <String>['LINK'],
        movements: <Movement>[buy],
        candidate: oversell,
      ),
      isTrue,
    );
  });
}
