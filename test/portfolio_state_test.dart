import 'package:flutter_test/flutter_test.dart';
import 'package:cripto_control_mx/domain/portfolio_models.dart';
import 'package:cripto_control_mx/domain/portfolio_state.dart';

void main() {
  test('PortfolioState projects stats and totals from inputs', () {
    final PortfolioState state = PortfolioState.fromInputs(
      coins: const <String>['ETH'],
      movements: <Movement>[
        Movement(
          type: MovementType.buy,
          coin: 'ETH',
          date: DateTime(2026, 1, 1),
          quantity: 2,
          unitPrice: 50,
          fee: 0,
          note: 'buy',
        ),
      ],
      currentPrices: const <String, double>{'ETH': 60},
    );

    expect(state.stats['ETH']!.quantity, 2);
    expect(state.totals.costBase, 100);
    expect(state.totals.currentValue, 120);
    expect(state.totals.unrealizedPL, 20);
  });
}
