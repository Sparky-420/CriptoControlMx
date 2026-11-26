import 'dart:convert';

import 'package:cripto_control_mx/cripto_control_app.dart';
import 'package:cripto_control_mx/services/price_alert_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _channel = MethodChannel(
  'mx.criptocontrolmx.app/price_alerts',
);

Future<SharedPreferences> _prefsWith(Map<String, Object> values) async {
  SharedPreferences.resetStatic();
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('Umbrales predeterminados (paridad Dart / Kotlin / UI)', () {
    test('sin umbral guardado, el predeterminado es 2.0 en ambos sistemas',
        () async {
      final SharedPreferences prefs = await _prefsWith(<String, Object>{});
      final PriceAlertSettings settings = await PriceAlertService()
          .loadSettings(prefs);
      expect(settings.thresholdPercent, 2.0);
      expect(settings.recoveryThresholdPoints, 2.0);
    });

    test('+1% no notifica y +2% sí con el predeterminado', () async {
      final SharedPreferences prefs = await _prefsWith(<String, Object>{
        PriceAlertService.enabledKey: true,
        PriceAlertService.referencePricesKey: jsonEncode(<String, double>{
          'UNI': 100,
        }),
      });
      final PriceAlertService service = PriceAlertService();

      final PriceAlertEvaluation onePct = await service.evaluatePrices(
        prefs: prefs,
        currentPrices: <String, double>{'UNI': 101},
        coins: <String>['UNI'],
      );
      expect(onePct.notificationCount, 0);
      expect(calls, isEmpty);

      final PriceAlertEvaluation twoPct = await service.evaluatePrices(
        prefs: prefs,
        currentPrices: <String, double>{'UNI': 102},
        coins: <String>['UNI'],
      );
      expect(twoPct.notificationCount, 1);
      expect(calls.single.method, 'showPriceAlert');
      expect(
        (calls.single.arguments as Map)['title'],
        'UNI subió +2.00%',
      );
    });
  });

  group('Referencias de precio', () {
    test('primera vista con posición fija la base sin notificar', () async {
      final SharedPreferences prefs = await _prefsWith(<String, Object>{
        PriceAlertService.enabledKey: true,
      });
      final PriceAlertService service = PriceAlertService();

      final PriceAlertEvaluation seeded = await service.evaluatePrices(
        prefs: prefs,
        currentPrices: <String, double>{'UNI': 100},
        coins: <String>['UNI'],
      );
      expect(seeded.notificationCount, 0);
      expect(calls, isEmpty);
      expect(seeded.settings.referencePrices, <String, double>{'UNI': 100});

      final PriceAlertEvaluation moved = await service.evaluatePrices(
        prefs: prefs,
        currentPrices: <String, double>{'UNI': 102},
        coins: <String>['UNI'],
      );
      expect(moved.notificationCount, 1);
      expect(moved.settings.referencePrices['UNI'], 102);
    });

    test('una referencia existente no se sobrescribe al sembrar', () async {
      final SharedPreferences prefs = await _prefsWith(<String, Object>{
        PriceAlertService.enabledKey: true,
        PriceAlertService.referencePricesKey: jsonEncode(<String, double>{
          'UNI': 90,
        }),
      });
      final PriceAlertEvaluation evaluation = await PriceAlertService()
          .evaluatePrices(
            prefs: prefs,
            currentPrices: <String, double>{'UNI': 91},
            coins: <String>['UNI'],
          );
      // +1.11% sobre la base de 90, por debajo del 2%: no notifica y la
      // base se conserva.
      expect(evaluation.notificationCount, 0);
      expect(evaluation.settings.referencePrices['UNI'], 90);
    });
  });

  group('Recuperación de P&L', () {
    test('fija la base en la primera vista y avisa al mejorar 2 puntos',
        () async {
      final SharedPreferences prefs = await _prefsWith(<String, Object>{
        PriceAlertService.recoveryEnabledKey: true,
      });
      final PriceAlertService service = PriceAlertService();
      Map<String, RecoveryAlertPosition> positions(double price) =>
          <String, RecoveryAlertPosition>{
            'UNI': RecoveryAlertPosition(
              quantity: 1,
              investmentNet: 1000,
              currentPrice: price,
              sellFeePercent: 0,
            ),
          };

      final PriceAlertEvaluation seeded = await service.evaluatePrices(
        prefs: prefs,
        currentPrices: <String, double>{'UNI': 100},
        coins: <String>['UNI'],
        recoveryPositions: positions(100),
      );
      expect(seeded.notificationCount, 0);
      expect(seeded.settings.recoveryReferencePnl['UNI'], closeTo(-90, 1e-9));

      final PriceAlertEvaluation improved = await service.evaluatePrices(
        prefs: prefs,
        currentPrices: <String, double>{'UNI': 120},
        coins: <String>['UNI'],
        recoveryPositions: positions(120),
      );
      expect(improved.notificationCount, 1);
      expect(
        (calls.single.arguments as Map)['title'],
        'UNI mejoró +2.00 pts',
      );
    });
  });

  group('Espejo movements_json para AlertWorker', () {
    test('una compra se codifica con las claves que lee el Worker', () {
      final String raw = legacyMovementsMirrorJson(<Movement>[
        Movement(
          type: MovementType.buy,
          coin: 'BTC',
          date: DateTime.utc(2026, 11, 1, 12),
          quantity: 0.5,
          unitPrice: 1000000,
          fee: 10,
          note: '',
        ),
      ]);
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      final Map<String, dynamic> item =
          Map<String, dynamic>.from(decoded.single as Map);
      expect(item['coin'], 'BTC');
      expect(item['type'], 'buy');
      expect(item['quantity'], 0.5);
      expect(item['unitPrice'], 1000000);
      expect(item['fee'], 10);
      expect(DateTime.parse(item['date'] as String), isNotNull);
    });

    test('un traspaso estructurado conserva los campos que lo identifican',
        () {
      final String raw = legacyMovementsMirrorJson(<Movement>[
        Movement(
          type: MovementType.transferOut,
          coin: 'BTC',
          date: DateTime.utc(2026, 11, 2, 12),
          quantity: 0.5,
          unitPrice: 1000000,
          fee: 0,
          receivedAmount: 0.499,
          cryptoFeeAmount: 0.001,
          cryptoFeeAsset: 'BTC',
          totalDebitedAmount: 0.5,
          sourcePlatform: 'Exchange',
          destinationPlatform: 'Wallet',
          note: '',
        ),
      ]);
      final Map<String, dynamic> item =
          Map<String, dynamic>.from(
            (jsonDecode(raw) as List<dynamic>).single as Map,
          );
      expect(item['receivedAmount'], 0.499);
      expect(item['cryptoFeeAmount'], 0.001);
      expect(item['totalDebitedAmount'], 0.5);
      expect(item['sourcePlatform'], 'Exchange');
      expect(item['destinationPlatform'], 'Wallet');
    });
  });
}
