import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../entitlements/pro_entitlement.dart';
import 'simulation_snapshot.dart';
import 'smart_alert_store.dart';
import 'smart_simulation_evaluator.dart';

/// Env├¡a una notificaci├│n Pro. Devuelve `true` si Android la mostr├│.
abstract class SmartAlertNotifier {
  Future<bool> notify({
    required String simulationId,
    required String title,
    required String body,
  });
}

/// Usa el MethodChannel existente de alertas, con un m├⌐todo y canal Android
/// separados (`showSmartAlert` / `cripto_smart_pro`).
class MethodChannelSmartAlertNotifier implements SmartAlertNotifier {
  const MethodChannelSmartAlertNotifier({
    MethodChannel channel = const MethodChannel(
      'mx.criptocontrolmx.app/price_alerts',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  /// Reprograma el Worker ├║nico si cambi├│ la supervisi├│n Pro.
  Future<void> refreshBackgroundSchedule() async {
    try {
      await _channel.invokeMethod<void>('refreshBackgroundSchedule');
    } on PlatformException {
      // No bloquear la app si WorkManager no est├í disponible.
    } on MissingPluginException {
      // Tests/plataformas sin canal nativo.
    }
  }

  @override
  Future<bool> notify({
    required String simulationId,
    required String title,
    required String body,
  }) async {
    try {
      return await _channel.invokeMethod<bool>(
            'showSmartAlert',
            <String, Object>{'id': simulationId, 'title': title, 'body': body},
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

enum SmartRunOutcome { notPro, nothingMonitored, priceFailure, evaluated }

class SmartMonitorRunReport {
  const SmartMonitorRunReport({
    required this.outcome,
    this.notificationsSent = 0,
    this.evaluations = const <String, SmartEvaluation>{},
    this.diagnostic = '',
  });

  final SmartRunOutcome outcome;
  final int notificationsSent;
  final Map<String, SmartEvaluation> evaluations;
  final String diagnostic;
}

/// Motor de notificaciones inteligentes Pro (independiente de las alertas
/// gratuitas de `PriceAlertService`). S├│lo informa; nunca opera.
class SmartSimulationMonitor {
  SmartSimulationMonitor({
    required ProEntitlementReader entitlement,
    required SmartAlertStore store,
    required SmartAlertNotifier notifier,
    SmartSimulationEvaluator evaluator = const SmartSimulationEvaluator(),
    DateTime Function()? clock,
  }) : _entitlement = entitlement,
       _store = store,
       _notifier = notifier,
       _evaluator = evaluator,
       _clock = clock ?? DateTime.now;

  final ProEntitlementReader _entitlement;
  final SmartAlertStore _store;
  final SmartAlertNotifier _notifier;
  final SmartSimulationEvaluator _evaluator;
  final DateTime Function() _clock;

  static bool _running = false;

  /// Obtiene precios con [loadPrices] (fuente ya integrada en la app) y
  /// clasifica fallos de conexi├│n / proveedor sin generar alertas favorables.
  Future<SmartMonitorRunReport> runWithPriceLoader(
    Future<Map<String, double>> Function() loadPrices,
  ) async {
    if (!await _entitlement.isProActive()) {
      return const SmartMonitorRunReport(outcome: SmartRunOutcome.notPro);
    }
    Map<String, double>? prices;
    String failure = '';
    try {
      prices = await loadPrices();
    } on SocketException {
      failure = 'Sin conexi├│n: no se pudieron obtener cotizaciones.';
    } on TimeoutException {
      failure = 'Sin conexi├│n: la consulta de precios excedi├│ el tiempo.';
    } catch (error) {
      failure = 'Error del proveedor de precios: $error';
    }
    return run(prices: prices, priceFailure: failure);
  }

  Future<SmartMonitorRunReport> run({
    required Map<String, double>? prices,
    String priceFailure = '',
  }) async {
    if (_running) {
      return const SmartMonitorRunReport(
        outcome: SmartRunOutcome.nothingMonitored,
        diagnostic: 'Evaluaci├│n en curso; se omite ejecuci├│n simult├ínea.',
      );
    }
    _running = true;
    try {
      return await _run(prices, priceFailure);
    } finally {
      _running = false;
    }
  }

  Future<SmartMonitorRunReport> _run(
    Map<String, double>? prices,
    String priceFailure,
  ) async {
    if (!await _entitlement.isProActive()) {
      return const SmartMonitorRunReport(outcome: SmartRunOutcome.notPro);
    }
    final Set<String> monitored = await _store.reconcileMonitoredIds();
    final List<SmartSavedSimulation> simulations =
        (await _store.loadSavedSimulations())
            .where((SmartSavedSimulation s) => monitored.contains(s.id))
            .toList();
    final Map<String, SmartMonitorState> states = await _store.loadStates();

    if (simulations.isEmpty) {
      await _store.saveStates(states);
      return const SmartMonitorRunReport(
        outcome: SmartRunOutcome.nothingMonitored,
      );
    }

    final DateTime now = _clock();
    if (prices == null || prices.isEmpty) {
      final String diagnostic = priceFailure.isEmpty
          ? 'Respuesta de precios vac├¡a.'
          : priceFailure;
      for (final SmartSavedSimulation sim in simulations) {
        states[sim.id] = (states[sim.id] ?? const SmartMonitorState()).copyWith(
          lastStatus: 'priceError',
          lastEvaluatedAt: now,
          diagnostic: diagnostic,
        );
      }
      await _store.saveStates(states);
      return SmartMonitorRunReport(
        outcome: SmartRunOutcome.priceFailure,
        diagnostic: diagnostic,
      );
    }

    int sent = 0;
    final Map<String, SmartEvaluation> evaluations =
        <String, SmartEvaluation>{};
    for (final SmartSavedSimulation sim in simulations) {
      final SmartMonitorState previous =
          states[sim.id] ?? const SmartMonitorState();
      final SimulationSnapshot? snapshot = sim.snapshot;
      if (snapshot == null) {
        states[sim.id] = previous.copyWith(
          lastStatus: 'missingData',
          lastEvaluatedAt: now,
          diagnostic:
              'La simulaci├│n no tiene par├ímetros econ├│micos guardados; '
              'vuelve a guardarla para supervisarla.',
        );
        continue;
      }
      final SmartEvaluation eval = _evaluator.evaluate(snapshot, prices);
      evaluations[sim.id] = eval;
      switch (eval.status) {
        case SmartEvaluationStatus.missingData:
          // Error de evaluaci├│n: se conserva conditionMet para no re-notificar
          // por un fallo transitorio.
          states[sim.id] = previous.copyWith(
            lastStatus: 'missingData',
            lastEvaluatedAt: now,
            diagnostic: eval.reason,
          );

        case SmartEvaluationStatus.notFavorable:
          states[sim.id] = previous.copyWith(
            conditionMet: false,
            lastStatus: 'notFavorable',
            lastEvaluatedAt: now,
            lastCurrentValue: eval.currentValue,
            targetValue: eval.targetValue,
            diagnostic: eval.reason,
            clearLastNotifiedAt: true,
          );
        case SmartEvaluationStatus.favorable:
          if (previous.conditionMet) {
            states[sim.id] = previous.copyWith(
              lastStatus: 'favorable',
              lastEvaluatedAt: now,
              lastCurrentValue: eval.currentValue,
              targetValue: eval.targetValue,
              diagnostic: eval.reason,
            );
            break;
          }
          final SmartAlertMessage message = SmartAlertMessage.build(
            snapshot,
            eval,
          );
          final bool wasSent = await _notifier.notify(
            simulationId: sim.id,
            title: message.title,
            body: message.body,
          );
          if (wasSent) sent += 1;
          states[sim.id] = previous.copyWith(
            conditionMet: wasSent,
            lastStatus: 'favorable',
            lastEvaluatedAt: now,
            lastNotifiedAt: wasSent ? now : null,
            clearLastNotifiedAt: !wasSent,
            lastCurrentValue: eval.currentValue,
            targetValue: eval.targetValue,
            diagnostic: wasSent
                ? eval.reason
                : 'Oportunidad detectada, pero Android no permiti├│ mostrar '
                      'la notificaci├│n.',
          );
      }
    }
    await _store.saveStates(states);
    return SmartMonitorRunReport(
      outcome: SmartRunOutcome.evaluated,
      notificationsSent: sent,
      evaluations: evaluations,
    );
  }
}

/// Texto explicativo con valores reales del rec├ílculo.
class SmartAlertMessage {
  const SmartAlertMessage(this.title, this.body);

  final String title;
  final String body;

  static SmartAlertMessage build(SimulationSnapshot s, SmartEvaluation e) {
    const String intro =
        'Las condiciones actuales cumplen los objetivos de tu simulaci├│n '
        'guardada.';
    const String outro =
        'Motivo: se alcanzaron las condiciones configuradas en tu estrategia. '
        'CriptoControlMx no ejecuta operaciones.';
    switch (s) {
      case RotationSimulationSnapshot():
        return SmartAlertMessage(
          'Oportunidad de rotaci├│n ${s.originCoin} ΓåÆ ${s.targetCoin}',
          '$intro\n'
              'Activo de origen: ${s.originCoin} '
              '(${formatMxn(e.currentPrices[s.originCoin] ?? 0)}).\n'
              'Activo de destino: ${s.targetCoin} '
              '(${formatMxn(e.currentPrices[s.targetCoin] ?? 0)}).\n'
              'Cantidad estimada actual: ${formatQty(e.currentValue)} '
              '${s.targetCoin}.\n'
              'Cantidad objetivo de la simulaci├│n: ${formatQty(e.targetValue)} '
              '${s.targetCoin}.\n'
              'Resultado estimado despu├⌐s de comisiones: '
              '${formatMxn(e.netAfterFees)} convertidos '
              '(comisiones ${formatMxn(e.totalCommissions)}).\n'
              '$outro',
        );
      case BuySimulationSnapshot():
        return SmartAlertMessage(
          'Oportunidad de compra ${s.coin}',
          '$intro\n'
              'Precio actual ${s.coin}: '
              '${formatMxn(e.currentPrices[s.coin] ?? 0)} '
              '(simulado ${formatMxn(s.simPrice)}).\n'
              'Cantidad estimada actual: ${formatQty(e.currentValue)} ${s.coin}.\n'
              'Cantidad objetivo de la simulaci├│n: ${formatQty(e.targetValue)} '
              '${s.coin}.\n'
              'Capital neto despu├⌐s de comisiones: ${formatMxn(e.netAfterFees)}.\n'
              '$outro',
        );
      case SellSimulationSnapshot():
        return SmartAlertMessage(
          'Oportunidad de venta ${s.coin}',
          '$intro\n'
              'Precio actual ${s.coin}: '
              '${formatMxn(e.currentPrices[s.coin] ?? 0)} '
              '(simulado ${formatMxn(s.simPrice)}).\n'
              'Cantidad a vender: ${formatQty(s.quantity)} ${s.coin}.\n'
              'Resultado estimado despu├⌐s de comisiones: '
              '${formatMxn(e.currentValue)}.\n'
              'Objetivo de la simulaci├│n: ${formatMxn(e.targetValue)}.\n'
              '$outro',
        );
    }
  }

  static String formatQty(double value) =>
      value.toStringAsFixed(value.abs() >= 1 ? 4 : 8);

  static String formatMxn(double value) {
    final String fixed = value.abs().toStringAsFixed(2);
    final List<String> parts = fixed.split('.');
    final String integer = parts.first;
    final StringBuffer grouped = StringBuffer();
    for (int i = 0; i < integer.length; i += 1) {
      final int fromEnd = integer.length - i;
      grouped.write(integer[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) grouped.write(',');
    }
    return '${value < 0 ? '-' : ''}\$$grouped.${parts.last} MXN';
  }
}
