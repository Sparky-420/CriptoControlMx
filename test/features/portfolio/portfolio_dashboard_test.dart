import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cripto_control_mx/features/portfolio/domain/models/portfolio_dashboard_data.dart';
import 'package:cripto_control_mx/features/portfolio/presentation/portfolio_dashboard.dart';

void main() {
  testWidgets('renders portfolio totals and assets from supplied projection', (tester) async {
    const data = PortfolioDashboardData(
      totalValueMxn: 154500.5,
      investedMxn: 120000,
      unrealizedPnlMxn: 34500.5,
      unrealizedPnlPercent: 28.75,
      assets: [
        PortfolioDashboardAsset(
          symbol: 'BTC',
          name: 'Bitcoin',
          quantity: 0.12,
          valueMxn: 132000,
          pnlMxn: 36000,
          pnlPercent: 37.5,
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PortfolioDashboard(data: data)),
    ));

    expect(find.text('VALOR TOTAL ESTIMADO'), findsOneWidget);
    expect(find.textContaining('154,500.50 MXN'), findsOneWidget);
    expect(find.text('Bitcoin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
