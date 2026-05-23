import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/main_v2_step3.dart';

void main() {
  test('movement parser keeps stored JSON values compatible', () {
    final Movement movement = Movement.fromJson(<String, dynamic>{
      'type': 'transfer_out',
      'coin': 'link',
      'date': '2026-05-22T12:00:00.000',
      'quantity': '2.5',
      'unit_price': '300',
      'commission': '4.5',
      'note': 'cold wallet',
    });

    expect(movement.type, MovementType.transferOut);
    expect(movement.coin, 'LINK');
    expect(movement.quantity, 2.5);
    expect(movement.unitPrice, 300);
    expect(movement.fee, 4.5);
    expect(movement.note, 'cold wallet');
  });

  test('coin stats calculate net break-even with exit fee', () {
    final CoinStats stats = CoinStats(
      coin: 'BTC',
      quantity: 2,
      costBase: 1000,
      currentPrice: 600,
    );

    expect(stats.avgPrice, 500);
    expect(stats.netBreakEvenPrice(1), closeTo(505.0505, 0.0001));
    expect(stats.isAtOrAboveNetBreakEven(1), isTrue);
  });
}
