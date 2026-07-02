import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cripto_control_mx/cripto_control_app.dart';

void main() {
  test('movement parser keeps stored JSON values compatible', () {
    final Movement movement = Movement.fromJson(<String, dynamic>{
      'type': 'transfer_out',
      'coin': 'link',
      'date': '2026-05-22T12:00:00.000',
      'quantity': '2.5',
      'unit_price': '300',
      'commission': '4.5',
      'origen': 'exchange',
      'cartera': 'ledger',
      'red': 'ethereum',
      'note': 'cold wallet',
    });

    expect(movement.type, MovementType.transferOut);
    expect(movement.coin, 'LINK');
    expect(movement.quantity, 2.5);
    expect(movement.unitPrice, 300);
    expect(movement.fee, 4.5);
    expect(movement.source, 'exchange');
    expect(movement.wallet, 'ledger');
    expect(movement.network, 'ethereum');
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

  test('json number parser accepts nums, strings and missing values', () {
    expect(numberFromJson(12), 12);
    expect(numberFromJson(12.5), 12.5);
    expect(numberFromJson('42.75'), 42.75);
    expect(numberFromJson(null), 0);
    expect(numberFromJson('bad'), 0);
  });

  testWidgets('premium cards support compact width and large text', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 1000),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: const <Widget>[
                  PremiumActionTile(
                    icon: Icons.cloud_outlined,
                    title: 'Cuenta en la nube con un título extenso',
                    subtitle:
                        'Conectado: cuenta-muy-larga@example.com · Perfil cloud configurado correctamente.',
                    badge: 'No conectado',
                  ),
                  SizedBox(height: 12),
                  PremiumQuickActions(
                    expanded: true,
                    onCapture: _noop,
                    onAdd: _noop,
                  ),
                  SizedBox(height: 12),
                  PremiumMetricCard(
                    label: 'P&L no realizado',
                    value: r'$-123,456,789.99 MXN',
                    icon: Icons.trending_down,
                    statusLabel: 'Requiere atención',
                    statusTone: PremiumStatusTone.negative,
                  ),
                  SizedBox(height: 12),
                  PremiumInfoPanel(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Mayor posición de la cartera',
                    subtitle: r'CRIPTOACTIVO-LARGO · $123,456,789.99 MXN',
                    badge: 'Debajo del equilibrio',
                  ),
                  SizedBox(height: 12),
                  InfoLine(
                    'P&L no realizado de la instantánea',
                    r'$-123,456,789.99 MXN',
                    emphasized: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
