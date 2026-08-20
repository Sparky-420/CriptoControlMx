import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cripto_control_mx/accounting/adapters/legacy_movement_adapter.dart';
import 'package:cripto_control_mx/accounting/adapters/legacy_persistence_bridge.dart';
import 'package:cripto_control_mx/accounting/application/wallet_lifecycle_coordinator.dart';
import 'package:cripto_control_mx/accounting/application/wallet_lifecycle_service.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:cripto_control_mx/accounting/domain/accounting_movement.dart';
import 'package:cripto_control_mx/accounting/domain/wallet.dart';
import 'package:cripto_control_mx/accounting/migration/accounting_migrator.dart';
import 'package:cripto_control_mx/accounting/persistence/accounting_document.dart';
import 'package:cripto_control_mx/accounting/persistence/shared_preferences_accounting_repository.dart';
import 'package:cripto_control_mx/cripto_control_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test(
    'app movement persistence forwards deleted movement ids to v3',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final document = _accountingDocumentForAppSeamTest();
      final repository = SharedPreferencesAccountingRepository();
      final bridge = LegacyPersistenceBridge(
        repository,
        const AccountingMigrator(LegacyMovementAdapter()),
        const LegacyMovementAdapter(),
        _NoopLifecycleCoordinator(),
      );

      final saved = await persistMovementsForApp(
        bridge: bridge,
        currentDocument: document,
        movements: const <Movement>[],
        deletedMovementIds: const <String>{'movement-to-delete'},
      );

      expect(saved.movements, isEmpty);
      expect(
        saved.legacyMovementMetadata.containsKey('movement-to-delete'),
        isFalse,
      );
      expect((await repository.read())!.toJson(), saved.toJson());
    },
  );

  test(
    'financial reset seam clears canonical v3 and runtime document',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final document = _accountingDocumentForAppSeamTest();
      final repository = SharedPreferencesAccountingRepository();
      await repository.write(document);
      final bridge = LegacyPersistenceBridge(
        repository,
        const AccountingMigrator(LegacyMovementAdapter()),
        const LegacyMovementAdapter(),
        _NoopLifecycleCoordinator(),
      );
      AccountingDocument? runtimeDocument = document;

      await clearFinancialResetAccountingState(
        bridge: bridge,
        clearRuntimeDocument: () => runtimeDocument = null,
      );

      expect(await repository.read(), isNull);
      expect(runtimeDocument, isNull);
    },
  );

  group('Mercado Pago OCR amount ranking', () {
    test('separates total, commission, unit price and crypto quantity', () {
      final Map<String, Object?> parsed = _parseOcrForTest('''
Mercado Pago
Compraste Bitcoin
Total \$1,970
Comisi\u00f3n \$30
Precio de Bitcoin \$1,234,567.89
Cantidad 0.0015 BTC
Fecha 2 jul 2026
''');

      expect(parsed['platform'], 'Mercado Pago');
      expect(parsed['coin'], 'BTC');
      expect(parsed['amount'], 1970);
      expect(parsed['commission'], 30);
      expect(parsed['unitPrice'], 1234567.89);
      expect(parsed['quantity'], 0.0015);
      expect(
        parsed['warnings'],
        contains('Revisa el monto y la comisi\u00f3n detectados.'),
      );
    });

    test('total pagado outranks an earlier commission', () {
      final Map<String, Object?> parsed = _parseOcrForTest('''
Mercado Pago
Comisi\u00f3n \$30
Total pagado \$1,970
''');

      expect(parsed['amount'], 1970);
      expect(parsed['commission'], 30);
    });

    test('unit price never replaces total', () {
      final Map<String, Object?> parsed = _parseOcrForTest('''
Mercado Pago
Precio de Bitcoin \$1,234,567.89
Comisi\u00f3n \$30
Total \$1,970
''');

      expect(parsed['amount'], 1970);
      expect(parsed['commission'], 30);
      expect(parsed['unitPrice'], 1234567.89);
    });

    test('associates values when ML Kit groups labels before amounts', () {
      final Map<String, Object?> parsed = _parseOcrForTest('''
LINK
5.22005934
Chainlink
Compra
Monto
Comisi\u00f3n de compra (1.5%)
Total
Precio
LINK 1 \$ 132.09
Medio de pago
N.\u00b0 de operaci\u00f3n
162944530096
\$ 689.50
Saldo Disponible en Mercado Pago Wallet
\$ 10.50
\$ 700.00
Creada el 6 de junio de 2026 - 23:10 hs
''');

      expect(parsed['platform'], 'Mercado Pago');
      expect(parsed['coin'], 'LINK');
      expect(parsed['amount'], 700);
      expect(parsed['commission'], 10.50);
      expect(parsed['unitPrice'], 132.09);
      expect(parsed['quantity'], 5.22005934);
    });

    test('keeps receiving platform and requests an explicit origin', () {
      final Map<String, Object?> parsed = _parseOcrForTest('''
LINK
12.80184227
Chainlink
Recepci\u00f3n
Equivalencia \$1,976.99
Recepci\u00f3n desde
Wallet externa
Precio
LINK 1 \u2248 \$154.43
Creada el 4 de abril de 2026 - 08:21 hs
¿Necesitas ayuda?
''');

      expect(parsed['platform'], 'Mercado Pago');
      expect(parsed['coin'], 'LINK');
      expect(parsed['amount'], 1976.99);
      expect(parsed['commission'], 0);
      expect(parsed['unitPrice'], 154.43);
      expect(parsed['quantity'], 12.80184227);
      expect(
        parsed['warnings'],
        contains(
          'Recepción detectada: elige la procedencia (Bitso, MetaMask, Binance, Coinbase u otra) antes de guardar.',
        ),
      );
    });

    test('requests an explicit destination for an outgoing transfer', () {
      final Map<String, Object?> parsed = _parseOcrForTest('''
Mercado Pago
Transferencia enviada
Cantidad 0.5 ETH
Equivalencia \$1,000
Precio de ETH \$2,000
Fecha 3 jul 2026
''');

      expect(parsed['platform'], 'Mercado Pago');
      expect(parsed['coin'], 'ETH');
      expect(parsed['amount'], 1000);
      expect(parsed['quantity'], 0.5);
      expect(parsed['unitPrice'], 2000);
      expect(
        parsed['warnings'],
        contains(
          'Transferencia de salida detectada: elige el destino (Bitso, MetaMask, Binance, Coinbase u otro) antes de guardar.',
        ),
      );
    });
  });

  test('Bitso OCR routing remains intact', () {
    final Map<String, Object?> parsed = _parseOcrForTest('''
Bitso
Buy
Monto gastado 1970 MXN
Cantidad 0.0015 BTC
1 BTC = 1313333.33 MXN
Date 2 jul 2026 12:00
''');

    expect(parsed['platform'], 'Bitso');
    expect(parsed['coin'], 'BTC');
    expect(parsed['amount'], 1970);
    expect(parsed['unitPrice'], 1313333.33);
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

Map<String, Object?> _parseOcrForTest(String text) {
  final dynamic state = MovementsTab(
    movements: <Movement>[],
    coins: const <String>['BTC', 'ETH'],
    onAdd: () async {},
    onAddFromOcr: (_) async {},
    onEdit: (_) async {},
    onDelete: (_) {},
  ).createState();
  return state.parseOcrForTesting(text) as Map<String, Object?>;
}

void _noop() {}

AccountingDocument _accountingDocumentForAppSeamTest() {
  final createdAt = DateTime.utc(2026, 8, 20);
  const walletId = '11111111-1111-4111-8111-111111111111';
  return AccountingDocument(
    schemaVersion: accountingSchemaVersion,
    wallets: <Wallet>[
      Wallet.create(
        id: walletId,
        name: 'Mercado Pago',
        provider: 'Mercado Pago',
        createdAt: createdAt,
      ),
    ],
    movements: <AccountingMovement>[
      AccountingMovement(
        id: 'movement-to-delete',
        type: MovementType.buy,
        asset: 'BTC',
        occurredAt: createdAt,
        quantity: AccountingAmount.parse('0.5'),
        unitPriceFiat: AccountingAmount.fromInt(100000),
        fiatFeeAmount: AccountingAmount.zero,
        destinationWalletId: walletId,
        destinationType: DestinationType.ownWallet,
        walletAssignmentStatus: WalletAssignmentStatus.assigned,
        reconciliationLinks: const <ReconciliationLink>[],
        cryptoFeeAmount: AccountingAmount.zero,
        fiatFeeTreatment: FiatFeeTreatment.none,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    ],
    appliedMigrationIds: const <String>{},
    updatedAt: createdAt,
    legacyMovementMetadata: const <String, Map<String, Object?>>{
      'movement-to-delete': <String, Object?>{
        'id': 'movement-to-delete',
        'type': 'buy',
        'coin': 'BTC',
        'date': '2026-08-20T00:00:00.000Z',
        'quantity': '0.5',
        'unitPrice': '100000',
        'fee': '0',
      },
    },
  );
}

final class _NoopLifecycleCoordinator implements WalletLifecycleCoordinator {
  @override
  Future<WalletDeleteCommitResult> commitDelete(
    PreparedWalletDeletion prepared,
  ) {
    throw UnsupportedError('not used by app seam tests');
  }

  @override
  Future<WalletImageCleanupResult> recoverPendingCleanup() async {
    return const WalletImageCleanupResult(
      deletedImageIds: <String>{},
      stillReferencedImageIds: <String>{},
      pendingRetryImageIds: <String>{},
    );
  }
}
