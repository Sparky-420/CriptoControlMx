import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cripto_control_mx/ui/navigation/main_navigation_bar.dart';

void main() {
  testWidgets('MainNavigationBar exposes expected destinations', (
    WidgetTester tester,
  ) async {
    int selected = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Scaffold(
              bottomNavigationBar: MainNavigationBar(
                selectedIndex: selected,
                onDestinationSelected: (int index) {
                  setState(() => selected = index);
                },
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('Resumen'), findsOneWidget);
    expect(find.text('Movimientos'), findsOneWidget);
    expect(find.text('Simular'), findsOneWidget);
    expect(find.text('Monedas'), findsOneWidget);
    expect(find.text('Ajustes'), findsOneWidget);

    await tester.tap(find.text('Monedas'));
    await tester.pumpAndSettle();

    expect(selected, 3);
  });
}
