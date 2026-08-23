import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/wallets/ui/wallets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WalletsScreen', () {
    testWidgets('shows empty state when there are no wallets', (tester) async {
      await tester.pumpWidget(const _WalletsTestApp(wallets: <Wallet>[]));

      expect(find.text('Carteras'), findsOneWidget);
      expect(find.text('Aún no tienes carteras configuradas.'), findsOneWidget);
      expect(find.text('Nueva cartera'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });

    testWidgets('renders an active wallet', (tester) async {
      await tester.pumpWidget(
        _WalletsTestApp(wallets: <Wallet>[_wallet(name: 'Mercado Pago')]),
      );

      expect(find.text('Mercado Pago'), findsOneWidget);
      expect(find.text('Activa'), findsOneWidget);
      expect(find.text('MP'), findsOneWidget);
    });

    testWidgets('renders an archived wallet', (tester) async {
      await tester.pumpWidget(
        _WalletsTestApp(
          wallets: <Wallet>[
            _wallet(name: 'Cold Storage', status: WalletStatus.archived),
          ],
        ),
      );

      expect(find.text('Cold Storage'), findsOneWidget);
      expect(find.text('Archivada'), findsOneWidget);
      expect(find.text('CS'), findsOneWidget);
    });
  });
}

class _WalletsTestApp extends StatelessWidget {
  const _WalletsTestApp({required this.wallets});

  final List<Wallet> wallets;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: WalletsScreen(wallets: wallets));
  }
}

Wallet _wallet({
  required String name,
  WalletStatus status = WalletStatus.active,
}) {
  final now = DateTime.utc(2026, 8, 23);
  final wallet = Wallet.create(
    id: '11111111-1111-4111-8111-111111111111',
    name: name,
    provider: 'Proveedor',
    createdAt: now,
  );
  if (status == WalletStatus.active) return wallet;
  return Wallet(
    id: wallet.id,
    name: wallet.name,
    provider: wallet.provider,
    status: status,
    createdAt: wallet.createdAt,
    updatedAt: wallet.updatedAt,
    imageRef: wallet.imageRef,
    colorArgb: wallet.colorArgb,
    note: wallet.note,
    schemaVersion: wallet.schemaVersion,
  );
}
