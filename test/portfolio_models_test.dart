import 'package:flutter_test/flutter_test.dart';
import 'package:cripto_control_mx/domain/portfolio_models.dart';

void main() {
  test('Movement.fromJson accepts legacy and Spanish aliases', () {
    final Movement movement = Movement.fromJson(<String, dynamic>{
      'type': 'venta',
      'crypto': 'link',
      'date': '2026-06-17T00:00:00.000',
      'quantity': '10.5',
      'unit_price': '120.25',
      'commission': '1.5',
      'origin': 'Mercado Pago',
      'cartera': 'Principal',
      'red': 'Ethereum',
      'note': 'compat',
    });

    expect(movement.type, MovementType.sell);
    expect(movement.coin, 'LINK');
    expect(movement.quantity, 10.5);
    expect(movement.unitPrice, 120.25);
    expect(movement.fee, 1.5);
    expect(movement.source, 'Mercado Pago');
    expect(movement.wallet, 'Principal');
    expect(movement.network, 'Ethereum');
  });

  test('CoinStats keeps break-even formulas stable', () {
    final CoinStats stats = CoinStats(
      coin: 'UNI',
      quantity: 10,
      costBase: 1000,
      currentPrice: 90,
    );

    expect(stats.avgPrice, 100);
    expect(stats.currentValue, 900);
    expect(stats.unrealizedPL, -100);
    expect(stats.netBreakEvenPrice(0), 100);
    expect(stats.netBreakEvenPrice(1.5).toStringAsFixed(8), '101.52284264');
    expect(stats.isAtOrAboveNetBreakEven(0), isFalse);
  });
}
