import 'dart:convert';
import 'dart:io';

import 'package:cripto_control_mx/entitlements/pro_entitlement.dart';
import 'package:cripto_control_mx/services/price_alert_service.dart';
import 'package:cripto_control_mx/smart_alerts/simulation_snapshot.dart';
import 'package:cripto_control_mx/smart_alerts/smart_alert_store.dart';
import 'package:cripto_control_mx/smart_alerts/smart_simulation_evaluator.dart';
import 'package:cripto_control_mx/smart_alerts/smart_simulation_monitor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNotifier implements SmartAlertNotifier {
  _FakeNotifier({this.allow = true});
  bool allow;
  final List<({String id, String title, String body})> sent =
      <({String id, String title, String body})>[];

  @override
  Future<bool> notify({
    required String simulationId,
    required String title,
    required String body,
  }) async {
    if (!allow) return false;
    sent.add((id: simulationId, title: title, body: body));
    return true;
  }
}

/// Rotaci├│n del ejemplo obligatorio: 0.01 BTC a $1,500,000 ΓåÆ 50 UNI a $300.
const RotationSimulationSnapshot btcToUni = RotationSimulationSnapshot(
  originCoin: 'BTC',
  targetCoin: 'UNI',
  originQuantity: 0.01,
  sellFeePercent: 0,
  buyFeePercent: 0,
  simOriginPrice: 1500000,
  simTargetPrice: 300,
  targetQuantity: 50,
);

const BuySimulationSnapshot buyUni = BuySimulationSnapshot(
  coin: 'UNI',
  grossAmount: 3000,
  buyFeePercent: 1,
  simPrice: 300,
  targetQuantity: 9.9, // (3000 - 30) / 300
);

const SellSimulationSnapshot sellLink = SellSimulationSnapshot(
  coin: 'LINK',
  quantity: 10,
  sellFeePercent: 0.5,
  simPrice: 400,
  targetNetReceived: 3980, // 4000 - 20
);

Future<SharedPreferences> _prefsWith({
  required List<Map<String, Object?>> simulations,
  Set<String> monitored = const <String>{},
  bool pro = true,
  Map<String, Object> extra = const <String, Object>{},
}) async {
  SharedPreferences.resetStatic();
  SharedPreferences.setMockInitialValues(<String, Object>{
    SmartAlertStore.savedSimulationsKey: jsonEncode(simulations),
    SmartAlertStore.monitoredIdsKey: jsonEncode(monitored.toList()),
    SharedPreferencesProEntitlementReader.activeKey: pro,
    ...extra,
  });
  return SharedPreferences.getInstance();
}

Map<String, Object?> _sim(String id, SimulationSnapshot? s) =>
    <String, Object?>{
      'id': id,
      'createdAt': '2026-06-01T10:00:00.000',
      'modeLabel': 'Simulaci├│n',
      'selectedAsset': id,
      if (s != null) 'smartParams': s.toJson(),
    };

SmartSimulationMonitor _monitor(SharedPreferences prefs, _FakeNotifier n) =>
    SmartSimulationMonitor(
      entitlement: SharedPreferencesProEntitlementReader(prefs),
      store: SmartAlertStore(prefs),
      notifier: n,
      clock: () => DateTime.utc(2026, 6, 10, 12),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const SmartSimulationEvaluator evaluator = SmartSimulationEvaluator();

  group('Evaluador (f├│rmulas del simulador)', () {
    test('1. compra que alcanza sus condiciones', () {
      final SmartEvaluation e = evaluator.evaluate(buyUni, <String, double>{
        'UNI': 290,
      });
      expect(e.status, SmartEvaluationStatus.favorable);
      expect(e.currentValue, closeTo(2970 / 290, 1e-12));
      expect(e.netAfterFees, closeTo(2970, 1e-9));
    });

    test('2. compra que no alcanza sus condiciones', () {
      final SmartEvaluation e = evaluator.evaluate(buyUni, <String, double>{
        'UNI': 310,
      });
      expect(e.status, SmartEvaluationStatus.notFavorable);
      expect(e.currentValue, closeTo(2970 / 310, 1e-12));
    });

    test('3. venta que alcanza sus condiciones', () {
      final SmartEvaluation e = evaluator.evaluate(sellLink, <String, double>{
        'LINK': 420,
      });
      expect(e.status, SmartEvaluationStatus.favorable);
      expect(e.currentValue, closeTo(4200 * 0.995, 1e-9));
    });

    test('4. venta que no alcanza sus condiciones', () {
      final SmartEvaluation e = evaluator.evaluate(sellLink, <String, double>{
        'LINK': 399,
      });
      expect(e.status, SmartEvaluationStatus.notFavorable);
      expect(e.currentValue, closeTo(3990 * 0.995, 1e-9));
    });

    test('5. rotaci├│n BTCΓåÆUNI con variaci├│n de ambos precios', () {
      // BTC baja 2% pero UNI baja 5%: 14,700 / 285 = 51.5789 UNI ΓëÑ 50.
      final SmartEvaluation e = evaluator.evaluate(btcToUni, <String, double>{
        'BTC': 1470000,
        'UNI': 285,
      });
      expect(e.status, SmartEvaluationStatus.favorable);
      expect(e.currentValue, closeTo(14700 / 285, 1e-12));
      expect(e.currentPrices, <String, double>{'BTC': 1470000, 'UNI': 285});
    });

    test('6. UNI sube pero BTC sube m├ís: sigue favorable; UNI sube m├ís que '
        'BTC: deja de serlo', () {
      final SmartEvaluation both = evaluator.evaluate(
        btcToUni,
        <String, double>{'BTC': 1650000, 'UNI': 320}, // 16,500/320 = 51.56
      );
      expect(both.status, SmartEvaluationStatus.favorable);
      final SmartEvaluation worse = evaluator.evaluate(
        btcToUni,
        <String, double>{'BTC': 1530000, 'UNI': 330}, // 15,300/330 = 46.36
      );
      expect(worse.status, SmartEvaluationStatus.notFavorable);
      expect(worse.currentValue, closeTo(15300 / 330, 1e-12));
      // Vigilar s├│lo UNI ser├¡a enga├▒oso: UNI subi├│ en ambos casos.
    });

    test(
      '7. cantidades despu├⌐s de comisiones (rotaci├│n con 0.5% + 0.6%)',
      () {
        const RotationSimulationSnapshot withFees = RotationSimulationSnapshot(
          originCoin: 'BTC',
          targetCoin: 'UNI',
          originQuantity: 0.01,
          sellFeePercent: 0.5,
          buyFeePercent: 0.6,
          simOriginPrice: 1500000,
          simTargetPrice: 300,
          targetQuantity: 15000 * 0.995 * 0.994 / 300,
        );
        final SmartEvaluation e = evaluator.evaluate(withFees, <String, double>{
          'BTC': 1500000,
          'UNI': 300,
        });
        // 15,000 ΓêÆ 75 = 14,925; ΓêÆ 89.55 = 14,835.45 ΓåÆ 49.4515 UNI.
        expect(e.netAfterFees, closeTo(14835.45, 1e-6));
        expect(e.totalCommissions, closeTo(75 + 89.55, 1e-6));
        expect(e.currentValue, closeTo(49.4515, 1e-9));
        expect(e.status, SmartEvaluationStatus.favorable); // igual al objetivo
        final SmartEvaluation noFees = evaluator.evaluate(
          btcToUni,
          e.currentPrices,
        );
        expect(noFees.currentValue, 50);
      },
    );

    test('8. cotizaciones faltantes ΓåÆ missingData, nunca favorable', () {
      final SmartEvaluation e = evaluator.evaluate(btcToUni, <String, double>{
        'BTC': 1500000,
      });
      expect(e.status, SmartEvaluationStatus.missingData);
      expect(e.reason, contains('UNI'));
      expect(
        evaluator.evaluate(btcToUni, <String, double>{
          'BTC': 1500000,
          'UNI': 0,
        }).status,
        SmartEvaluationStatus.missingData,
      );
    });
    test('9. rechaza cotizaciones NaN e infinitas', () {
      for (final double invalidPrice in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
        0,
        -1,
      ]) {
        expect(
          evaluator.evaluate(buyUni, <String, double>{
            'UNI': invalidPrice,
          }).status,
          SmartEvaluationStatus.missingData,
        );

        expect(
          evaluator.evaluate(btcToUni, <String, double>{
            'BTC': 1500000,
            'UNI': invalidPrice,
          }).status,
          SmartEvaluationStatus.missingData,
        );
      }
    });
    test('10. rechaza parámetros económicos no finitos', () {
      final List<SimulationSnapshot> invalidSnapshots = <SimulationSnapshot>[
        BuySimulationSnapshot(
          coin: 'UNI',
          grossAmount: double.infinity,
          buyFeePercent: 1,
          simPrice: 300,
          targetQuantity: 9.9,
        ),
        BuySimulationSnapshot(
          coin: 'UNI',
          grossAmount: 3000,
          buyFeePercent: double.nan,
          simPrice: 300,
          targetQuantity: 9.9,
        ),
        SellSimulationSnapshot(
          coin: 'LINK',
          quantity: double.infinity,
          sellFeePercent: 0.5,
          simPrice: 400,
          targetNetReceived: 3980,
        ),
        RotationSimulationSnapshot(
          originCoin: 'BTC',
          targetCoin: 'UNI',
          originQuantity: double.infinity,
          sellFeePercent: 0,
          buyFeePercent: 0,
          simOriginPrice: 1500000,
          simTargetPrice: 300,
          targetQuantity: 50,
        ),
      ];

      for (final SimulationSnapshot snapshot in invalidSnapshots) {
        final Map<String, double> prices = <String, double>{
          for (final String coin in snapshot.coins) coin: 300,
        };

        expect(
          evaluator.evaluate(snapshot, prices).status,
          SmartEvaluationStatus.missingData,
          reason: 'Debe rechazar ${snapshot.kind} con parámetros inválidos.',
        );
      }
    });
    test('11. rechaza resultados con desbordamiento numérico', () {
      const BuySimulationSnapshot overflowingBuy = BuySimulationSnapshot(
        coin: 'UNI',
        grossAmount: double.maxFinite,
        buyFeePercent: 0,
        simPrice: 300,
        targetQuantity: 1,
      );

      expect(
        evaluator.evaluate(overflowingBuy, <String, double>{
          'UNI': double.minPositive,
        }).status,
        SmartEvaluationStatus.missingData,
      );

      const SellSimulationSnapshot overflowingSell = SellSimulationSnapshot(
        coin: 'LINK',
        quantity: double.maxFinite,
        sellFeePercent: 0,
        simPrice: 400,
        targetNetReceived: 1,
      );

      expect(
        evaluator.evaluate(overflowingSell, <String, double>{'LINK': 2}).status,
        SmartEvaluationStatus.missingData,
      );

      const RotationSimulationSnapshot overflowingRotation =
          RotationSimulationSnapshot(
            originCoin: 'BTC',
            targetCoin: 'UNI',
            originQuantity: double.maxFinite,
            sellFeePercent: 0,
            buyFeePercent: 0,
            simOriginPrice: 1500000,
            simTargetPrice: 300,
            targetQuantity: 50,
          );

      expect(
        evaluator.evaluate(overflowingRotation, <String, double>{
          'BTC': 2,
          'UNI': 300,
        }).status,
        SmartEvaluationStatus.missingData,
      );
    });
  });
  group('Monitor Pro', () {
    test(
      '9. error del proveedor de precios: sin alerta y diagn├│stico',
      () async {
        final SharedPreferences prefs = await _prefsWith(
          simulations: <Map<String, Object?>>[_sim('rot', btcToUni)],
          monitored: <String>{'rot'},
        );
        final _FakeNotifier n = _FakeNotifier();
        final SmartMonitorRunReport r = await _monitor(
          prefs,
          n,
        ).runWithPriceLoader(() async => throw const FormatException('bad'));
        expect(r.outcome, SmartRunOutcome.priceFailure);
        expect(n.sent, isEmpty);
        final SmartMonitorState s = (await SmartAlertStore(
          prefs,
        ).loadStates())['rot']!;
        expect(s.lastStatus, 'priceError');
        expect(s.diagnostic, contains('proveedor'));
      },
    );

    test('10. sin conexi├│n', () async {
      final SharedPreferences prefs = await _prefsWith(
        simulations: <Map<String, Object?>>[_sim('rot', btcToUni)],
        monitored: <String>{'rot'},
      );
      final _FakeNotifier n = _FakeNotifier();
      final SmartMonitorRunReport r = await _monitor(
        prefs,
        n,
      ).runWithPriceLoader(() async => throw const SocketException('off'));
      expect(r.outcome, SmartRunOutcome.priceFailure);
      expect(r.diagnostic, contains('Sin conexi├│n'));
      expect(n.sent, isEmpty);
    });

    test('11. monitoreo desactivado no notifica', () async {
      final SharedPreferences prefs = await _prefsWith(
        simulations: <Map<String, Object?>>[_sim('rot', btcToUni)],
      );
      final _FakeNotifier n = _FakeNotifier();
      final SmartMonitorRunReport r = await _monitor(
        prefs,
        n,
      ).run(prices: <String, double>{'BTC': 1600000, 'UNI': 280});
      expect(r.outcome, SmartRunOutcome.nothingMonitored);
      expect(n.sent, isEmpty);
    });

    test('12. usuario sin Pro: el motor no eval├║a ni notifica', () async {
      final SharedPreferences prefs = await _prefsWith(
        simulations: <Map<String, Object?>>[_sim('rot', btcToUni)],
        monitored: <String>{'rot'},
        pro: false,
      );
      final _FakeNotifier n = _FakeNotifier();
      final SmartMonitorRunReport r = await _monitor(
        prefs,
        n,
      ).run(prices: <String, double>{'BTC': 1600000, 'UNI': 280});
      expect(r.outcome, SmartRunOutcome.notPro);
      expect(n.sent, isEmpty);
      expect(prefs.getString(SmartAlertStore.stateKey), isNull);
    });

    test(
      '13. usuario con Pro: notificaci├│n explicativa con valores reales',
      () async {
        final SharedPreferences prefs = await _prefsWith(
          simulations: <Map<String, Object?>>[_sim('rot', btcToUni)],
          monitored: <String>{'rot'},
        );
        final _FakeNotifier n = _FakeNotifier();
        final SmartMonitorRunReport r = await _monitor(
          prefs,
          n,
        ).run(prices: <String, double>{'BTC': 1470000, 'UNI': 285});
        expect(r.notificationsSent, 1);
        expect(n.sent.single.title, 'Oportunidad de rotaci├│n BTC ΓåÆ UNI');
        expect(
          n.sent.single.body,
          contains('Cantidad estimada actual: 51.5789 UNI'),
        );
        expect(
          n.sent.single.body,
          contains('Cantidad objetivo de la simulaci├│n: 50.0000 UNI'),
        );
        expect(n.sent.single.body, contains('\$14,700.00 MXN convertidos'));
        expect(
          n.sent.single.body,
          contains('Activo de origen: BTC (\$1,470,000.00 MXN)'),
        );
      },
    );

    test('14 + 15. persistencia tras reinicio y sin duplicados', () async {
      SharedPreferences prefs = await _prefsWith(
        simulations: <Map<String, Object?>>[_sim('rot', btcToUni)],
        monitored: <String>{'rot'},
      );
      final _FakeNotifier n = _FakeNotifier();
      const Map<String, double> good = <String, double>{
        'BTC': 1470000,
        'UNI': 285,
      };
      await _monitor(prefs, n).run(prices: good);
      await _monitor(prefs, n).run(prices: good);
      expect(n.sent, hasLength(1));

      // "Reinicio": se descarta la instancia y se recarga desde el disco.
      final Map<String, Object> disk = <String, Object>{
        for (final String k in prefs.getKeys()) k: prefs.get(k)!,
      };
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues(disk);
      prefs = await SharedPreferences.getInstance();
      expect(await SmartAlertStore(prefs).loadMonitoredIds(), <String>{'rot'});
      final SmartMonitorState s = (await SmartAlertStore(
        prefs,
      ).loadStates())['rot']!;
      expect(s.conditionMet, isTrue);
      expect(s.lastNotifiedAt, DateTime.utc(2026, 6, 10, 12));
      await _monitor(prefs, n).run(prices: good);
      expect(n.sent, hasLength(1));
    });

    test(
      '16 + 17. restablece al dejar de cumplirse y vuelve a avisar',
      () async {
        final SharedPreferences prefs = await _prefsWith(
          simulations: <Map<String, Object?>>[_sim('rot', btcToUni)],
          monitored: <String>{'rot'},
        );
        final _FakeNotifier n = _FakeNotifier();
        final SmartSimulationMonitor m = _monitor(prefs, n);
        await m.run(prices: <String, double>{'BTC': 1470000, 'UNI': 285});
        await m.run(prices: <String, double>{'BTC': 1530000, 'UNI': 330});
        SmartMonitorState s = (await SmartAlertStore(
          prefs,
        ).loadStates())['rot']!;
        expect(s.conditionMet, isFalse);
        expect(s.lastStatus, 'notFavorable');
        // Un fallo transitorio de cotizaci├│n no reinicia el estado.
        await m.run(prices: <String, double>{'BTC': 1530000});
        expect(n.sent, hasLength(1));
        await m.run(prices: <String, double>{'BTC': 1600000, 'UNI': 300});
        expect(n.sent, hasLength(2));
        s = (await SmartAlertStore(prefs).loadStates())['rot']!;
        expect(s.conditionMet, isTrue);
      },
    );

    test('Permiso denegado: no marca como notificada y reintenta', () async {
      final SharedPreferences prefs = await _prefsWith(
        simulations: <Map<String, Object?>>[_sim('buy', buyUni)],
        monitored: <String>{'buy'},
      );
      final _FakeNotifier n = _FakeNotifier(allow: false);
      await _monitor(prefs, n).run(prices: <String, double>{'UNI': 280});
      expect(
        (await SmartAlertStore(prefs).loadStates())['buy']!.conditionMet,
        isFalse,
      );
      n.allow = true;
      await _monitor(prefs, n).run(prices: <String, double>{'UNI': 280});
      expect(n.sent.single.title, 'Oportunidad de compra UNI');
    });

    test(
      'Simulaci├│n antigua sin par├ímetros y simulaci├│n eliminada',
      () async {
        final SharedPreferences prefs = await _prefsWith(
          simulations: <Map<String, Object?>>[_sim('old', null)],
          monitored: <String>{'old', 'deleted'},
          extra: <String, Object>{
            SmartAlertStore.stateKey: jsonEncode(<String, Object>{
              'deleted': <String, Object>{'conditionMet': true},
            }),
          },
        );
        final _FakeNotifier n = _FakeNotifier();
        await _monitor(prefs, n).run(prices: <String, double>{'UNI': 1});
        final Map<String, SmartMonitorState> states = await SmartAlertStore(
          prefs,
        ).loadStates();
        expect(n.sent, isEmpty);
        expect(states.containsKey('deleted'), isFalse);
        expect(await SmartAlertStore(prefs).loadMonitoredIds(), <String>{
          'old',
        });
        expect(states['old']!.lastStatus, 'missingData');
      },
    );

    test('Snapshot JSON ida y vuelta conserva par├ímetros originales', () {
      for (final SimulationSnapshot s in <SimulationSnapshot>[
        btcToUni,
        buyUni,
        sellLink,
      ]) {
        expect(SimulationSnapshot.fromJson(s.toJson())!.toJson(), s.toJson());
      }
      expect(
        SimulationSnapshot.fromJson(<String, Object>{'kind': 'buy'}),
        isNull,
      );
    });
  });

  group('18. Alertas gratuitas siguen funcionando sin Pro', () {
    const MethodChannel channel = MethodChannel(
      'mx.criptocontrolmx.app/price_alerts',
    );
    final List<MethodCall> calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            calls.add(call);
            return true;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'UNI +2% notifica a usuario sin Pro y el motor Pro no interviene',
      () async {
        final SharedPreferences prefs = await _prefsWith(
          simulations: <Map<String, Object?>>[_sim('rot', btcToUni)],
          monitored: <String>{'rot'},
          pro: false,
          extra: <String, Object>{
            PriceAlertService.enabledKey: true,
            PriceAlertService.thresholdPercentKey: 1.5,
            PriceAlertService.referencePricesKey: jsonEncode(<String, double>{
              'UNI': 100,
            }),
          },
        );
        final PriceAlertEvaluation e = await PriceAlertService().evaluatePrices(
          prefs: prefs,
          currentPrices: <String, double>{'UNI': 102},
          coins: <String>['UNI'],
        );
        expect(e.notificationCount, 1);
        expect(calls.single.method, 'showPriceAlert');
        expect(
          (calls.single.arguments as Map)['title'],
          'UNI subi\u00f3 +2.00%',
        );

        final SmartMonitorRunReport r = await SmartSimulationMonitor(
          entitlement: SharedPreferencesProEntitlementReader(prefs),
          store: SmartAlertStore(prefs),
          notifier: const MethodChannelSmartAlertNotifier(),
        ).run(prices: <String, double>{'BTC': 1600000, 'UNI': 102});
        expect(r.outcome, SmartRunOutcome.notPro);
        expect(
          calls.where((MethodCall c) => c.method == 'showSmartAlert'),
          isEmpty,
        );
      },
    );
  });
}
