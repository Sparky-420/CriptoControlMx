import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PriceAlertService {
  PriceAlertService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String enabledKey = 'price_alerts_enabled';
  static const String thresholdPercentKey = 'price_alert_threshold_percent';
  static const String referencePricesKey = 'price_alert_reference_prices_json';
  static const String lastNotifiedAtKey = 'price_alert_last_notified_at_json';
  static const String lastNotifiedPricesKey =
      'price_alert_last_notified_prices_json';
  static const String recoveryEnabledKey = 'recovery_alerts_enabled';
  static const String recoveryThresholdPointsKey =
      'recovery_alert_threshold_points';
  static const String recoveryReferencePnlKey =
      'recovery_alert_reference_pnl_json';
  static const String recoveryLastNotifiedAtKey =
      'recovery_alert_last_notified_at_json';
  static const String automaticAlertsEnabledKey =
      'automatic_local_alerts_enabled';
  static const String automaticAlertsIntervalMinutesKey =
      'automatic_local_alerts_interval_minutes';

  static const int defaultAutomaticIntervalMinutes = 30;
  static const List<int> automaticIntervalOptions = <int>[15, 30, 60, 360, 1440];
  static const double defaultThresholdPercent = 0.0;
  static const double defaultRecoveryThresholdPoints = 0.0;
  static const String _channelName = 'mx.criptocontrolmx.app/price_alerts';

  final MethodChannel _channel;

  Future<void> initialize() async {
    try {
      await _channel.invokeMethod<void>('initialize');
    } on PlatformException {
      // La app debe seguir funcionando aunque las notificaciones no estén listas.
    } on MissingPluginException {
      // Tests/plataformas sin canal nativo: no interrumpir el flujo.
    }
  }

  Future<bool> areNotificationsAllowed() async {
    try {
      return await _channel.invokeMethod<bool>('areNotificationsAllowed') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> configureAutomaticAlerts({
    required bool enabled,
    required int intervalMinutes,
  }) async {
    try {
      await _channel.invokeMethod<void>(
        'configureAutomaticAlerts',
        <String, Object>{
          'enabled': enabled,
          'intervalMinutes': intervalMinutes,
        },
      );
    } on PlatformException {
      // Android puede no tener WorkManager disponible en algunos entornos.
    } on MissingPluginException {
      // Tests/plataformas sin canal nativo: no interrumpir el flujo.
    }
  }

  Future<void> runAutomaticAlertCheckNow() async {
    try {
      await _channel.invokeMethod<void>('runAutomaticAlertCheckNow');
    } on PlatformException {
      // No bloquear la app si Android rechaza la tarea inmediata.
    } on MissingPluginException {
      // Tests/plataformas sin canal nativo: no interrumpir el flujo.
    }
  }

  Future<bool> requestNotificationPermission() async {
    try {
      return await _channel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<PriceAlertSettings> loadSettings(SharedPreferences prefs) async {
    return PriceAlertSettings(
      enabled: prefs.getBool(enabledKey) ?? false,
      thresholdPercent:
          prefs.getDouble(thresholdPercentKey) ?? defaultThresholdPercent,
      referencePrices: _readDoubleMap(prefs.getString(referencePricesKey)),
      lastNotifiedPrices: _readDoubleMap(
        prefs.getString(lastNotifiedPricesKey),
      ),
      lastNotifiedAt: _readDateMap(prefs.getString(lastNotifiedAtKey)),
      recoveryEnabled: prefs.getBool(recoveryEnabledKey) ?? false,
      recoveryThresholdPoints:
          prefs.getDouble(recoveryThresholdPointsKey) ??
          defaultRecoveryThresholdPoints,
      recoveryReferencePnl: _readDoubleMap(
        prefs.getString(recoveryReferencePnlKey),
      ),
      recoveryLastNotifiedAt: _readDateMap(
        prefs.getString(recoveryLastNotifiedAtKey),
      ),
      automaticAlertsEnabled:
          prefs.getBool(automaticAlertsEnabledKey) ?? false,
      automaticIntervalMinutes: prefs.getInt(
            automaticAlertsIntervalMinutesKey,
          ) ??
          defaultAutomaticIntervalMinutes,
    );
  }

  Future<void> setAutomaticAlertsEnabled(
    SharedPreferences prefs,
    bool enabled,
  ) async {
    await prefs.setBool(automaticAlertsEnabledKey, enabled);
  }

  Future<void> setAutomaticAlertsIntervalMinutes(
    SharedPreferences prefs,
    int minutes,
  ) async {
    final int safeMinutes = automaticIntervalOptions.contains(minutes)
        ? minutes
        : defaultAutomaticIntervalMinutes;
    await prefs.setInt(automaticAlertsIntervalMinutesKey, safeMinutes);
  }

  Future<void> setEnabled(SharedPreferences prefs, bool enabled) async {
    await prefs.setBool(enabledKey, enabled);
  }

  Future<void> setThresholdPercent(
    SharedPreferences prefs,
    double thresholdPercent,
  ) async {
    await prefs.setDouble(thresholdPercentKey, thresholdPercent);
  }

  Future<void> setRecoveryEnabled(
    SharedPreferences prefs,
    bool enabled,
  ) async {
    await prefs.setBool(recoveryEnabledKey, enabled);
  }

  Future<void> setRecoveryThresholdPoints(
    SharedPreferences prefs,
    double thresholdPoints,
  ) async {
    await prefs.setDouble(recoveryThresholdPointsKey, thresholdPoints);
  }

  Future<PriceAlertSettings> resetReferences(
    SharedPreferences prefs,
    Map<String, double> currentPrices,
    Iterable<String> coins,
  ) async {
    final Map<String, double> references = <String, double>{};
    for (final String coin in coins) {
      final double price = currentPrices[coin] ?? 0.0;
      if (price > 0) references[coin] = price;
    }

    await prefs.setString(referencePricesKey, jsonEncode(references));
    return loadSettings(prefs);
  }

  Future<PriceAlertSettings> resetRecoveryReferences(
    SharedPreferences prefs,
    Map<String, RecoveryAlertPosition> positions,
    Iterable<String> coins,
  ) async {
    final Map<String, double> references = <String, double>{};
    for (final String coin in coins) {
      final RecoveryAlertPosition? position = positions[coin];
      if (position != null && position.hasPosition) {
        references[coin] = position.pnlPercent;
      }
    }

    await prefs.setString(recoveryReferencePnlKey, jsonEncode(references));
    return loadSettings(prefs);
  }

  Future<PriceAlertEvaluation> evaluatePrices({
    required SharedPreferences prefs,
    required Map<String, double> currentPrices,
    required Iterable<String> coins,
    Map<String, RecoveryAlertPosition> recoveryPositions =
        const <String, RecoveryAlertPosition>{},
  }) async {
    final PriceAlertSettings settings = await loadSettings(prefs);
    if (!settings.enabled && !settings.recoveryEnabled) {
      return PriceAlertEvaluation(settings: settings, notificationCount: 0);
    }

    final double threshold = math.max(0.01, settings.thresholdPercent);
    final Map<String, double> references = Map<String, double>.from(
      settings.referencePrices,
    );
    final Map<String, double> notifiedPrices = Map<String, double>.from(
      settings.lastNotifiedPrices,
    );
    final Map<String, DateTime> notifiedAt = Map<String, DateTime>.from(
      settings.lastNotifiedAt,
    );
    final Map<String, double> recoveryReferences = Map<String, double>.from(
      settings.recoveryReferencePnl,
    );
    final Map<String, DateTime> recoveryNotifiedAt = Map<String, DateTime>.from(
      settings.recoveryLastNotifiedAt,
    );

    var notificationCount = 0;

    if (settings.enabled) {
      for (final String coin in coins) {
        final double currentPrice = currentPrices[coin] ?? 0.0;
        if (currentPrice <= 0) continue;

        final double referencePrice = references[coin] ?? 0.0;
        if (referencePrice <= 0) {
          references[coin] = currentPrice;
          continue;
        }

        final double changePct =
            (currentPrice - referencePrice) / referencePrice * 100;
        if (changePct >= threshold || changePct <= -threshold) {
          final bool isUp = changePct > 0;
          final bool wasSent = await notifyPriceAlert(
            coin: coin,
            changePct: changePct,
            currentPrice: currentPrice,
            isUp: isUp,
          );

          if (wasSent) {
            notificationCount += 1;
            references[coin] = currentPrice;
            notifiedPrices[coin] = currentPrice;
            notifiedAt[coin] = DateTime.now();
          }
        }
      }
    }

    if (settings.recoveryEnabled) {
      final double recoveryThreshold = math.max(
        0.01,
        settings.recoveryThresholdPoints,
      );
      for (final String coin in coins) {
        final RecoveryAlertPosition? position = recoveryPositions[coin];
        if (position == null || !position.hasPosition) continue;

        final double currentPnlPct = position.pnlPercent;
        final double? referencePnlPct = recoveryReferences[coin];
        if (referencePnlPct == null) {
          recoveryReferences[coin] = currentPnlPct;
          continue;
        }

        final double deltaPoints = currentPnlPct - referencePnlPct;
        if (deltaPoints >= recoveryThreshold ||
            deltaPoints <= -recoveryThreshold) {
          final bool improved = deltaPoints > 0;
          final bool wasSent = await notifyRecoveryAlert(
            coin: coin,
            previousPnlPct: referencePnlPct,
            currentPnlPct: currentPnlPct,
            deltaPoints: deltaPoints,
            missingToBreakEven: position.missingToBreakEven,
            improved: improved,
          );

          if (wasSent) {
            notificationCount += 1;
            recoveryReferences[coin] = currentPnlPct;
            recoveryNotifiedAt[coin] = DateTime.now();
          }
        }
      }
    }

    await prefs.setString(referencePricesKey, jsonEncode(references));
    await prefs.setString(lastNotifiedPricesKey, jsonEncode(notifiedPrices));
    await prefs.setString(
      lastNotifiedAtKey,
      jsonEncode(_encodeDateMap(notifiedAt)),
    );
    await prefs.setString(
      recoveryReferencePnlKey,
      jsonEncode(recoveryReferences),
    );
    await prefs.setString(
      recoveryLastNotifiedAtKey,
      jsonEncode(_encodeDateMap(recoveryNotifiedAt)),
    );

    return PriceAlertEvaluation(
      settings: PriceAlertSettings(
        enabled: settings.enabled,
        thresholdPercent: settings.thresholdPercent,
        referencePrices: references,
        lastNotifiedPrices: notifiedPrices,
        lastNotifiedAt: notifiedAt,
        recoveryEnabled: settings.recoveryEnabled,
        recoveryThresholdPoints: settings.recoveryThresholdPoints,
        recoveryReferencePnl: recoveryReferences,
        recoveryLastNotifiedAt: recoveryNotifiedAt,
        automaticAlertsEnabled: settings.automaticAlertsEnabled,
        automaticIntervalMinutes: settings.automaticIntervalMinutes,
      ),
      notificationCount: notificationCount,
    );
  }

  Future<bool> notifyRecoveryAlert({
    required String coin,
    required double previousPnlPct,
    required double currentPnlPct,
    required double deltaPoints,
    required double missingToBreakEven,
    required bool improved,
  }) async {
    final String status = improved ? 'mejoró' : 'empeoró';
    final String signedPoints =
        '${deltaPoints >= 0 ? '+' : ''}${deltaPoints.toStringAsFixed(2)} pts';
    final String title = '$coin $status $signedPoints';
    final String previous = previousPnlPct.toStringAsFixed(2);
    final String current = currentPnlPct.toStringAsFixed(2);
    final String breakEvenText = missingToBreakEven > 0
        ? ' Faltan ${formatMxn(missingToBreakEven)} para break even.'
        : '';
    final String body =
        'Tu P&L pasó de $previous% a $current%.$breakEvenText';

    try {
      return await _channel.invokeMethod<bool>(
            'showPriceAlert',
            <String, Object>{'coin': coin, 'title': title, 'body': body},
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> notifyPriceAlert({
    required String coin,
    required double changePct,
    required double currentPrice,
    required bool isUp,
  }) async {
    final String direction = isUp ? 'subió' : 'bajó';
    final String signedPct =
        '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%';
    final String title = '$coin $direction $signedPct';
    final String body = 'Precio actual: ${formatMxn(currentPrice)}';

    try {
      return await _channel.invokeMethod<bool>(
            'showPriceAlert',
            <String, Object>{'coin': coin, 'title': title, 'body': body},
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static String formatMxn(double value) {
    final String fixedValue = value.abs().toStringAsFixed(
      value.abs() >= 1000 ? 0 : 2,
    );
    final List<String> parts = fixedValue.split('.');
    final String integer = parts.first;
    final StringBuffer grouped = StringBuffer();

    for (int i = 0; i < integer.length; i += 1) {
      final int positionFromEnd = integer.length - i;
      grouped.write(integer[i]);
      if (positionFromEnd > 1 && positionFromEnd % 3 == 1) {
        grouped.write(',');
      }
    }

    final String decimals = parts.length > 1 ? '.${parts.last}' : '';
    final String sign = value < 0 ? '-' : '';
    return '$sign\$${grouped.toString()}$decimals MXN';
  }

  static Map<String, double> _readDoubleMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, double>{};

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, double>{};

      return decoded.map<String, double>((dynamic key, dynamic value) {
        final double parsed = value is num
            ? value.toDouble()
            : double.tryParse(value.toString()) ?? 0.0;
        return MapEntry<String, double>(key.toString(), parsed);
      });
    } catch (_) {
      return <String, double>{};
    }
  }

  static Map<String, DateTime> _readDateMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, DateTime>{};

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, DateTime>{};

      final Map<String, DateTime> values = <String, DateTime>{};
      decoded.forEach((dynamic key, dynamic value) {
        final DateTime? parsed = DateTime.tryParse(value.toString());
        if (parsed != null) values[key.toString()] = parsed;
      });
      return values;
    } catch (_) {
      return <String, DateTime>{};
    }
  }

  static Map<String, String> _encodeDateMap(Map<String, DateTime> values) {
    return values.map(
      (String key, DateTime value) => MapEntry<String, String>(
        key,
        value.toIso8601String(),
      ),
    );
  }
}

class PriceAlertSettings {
  const PriceAlertSettings({
    required this.enabled,
    required this.thresholdPercent,
    required this.referencePrices,
    required this.lastNotifiedPrices,
    required this.lastNotifiedAt,
    required this.recoveryEnabled,
    required this.recoveryThresholdPoints,
    required this.recoveryReferencePnl,
    required this.recoveryLastNotifiedAt,
    required this.automaticAlertsEnabled,
    required this.automaticIntervalMinutes,
  });

  final bool enabled;
  final double thresholdPercent;
  final Map<String, double> referencePrices;
  final Map<String, double> lastNotifiedPrices;
  final Map<String, DateTime> lastNotifiedAt;
  final bool recoveryEnabled;
  final double recoveryThresholdPoints;
  final Map<String, double> recoveryReferencePnl;
  final Map<String, DateTime> recoveryLastNotifiedAt;
  final bool automaticAlertsEnabled;
  final int automaticIntervalMinutes;
}

class PriceAlertEvaluation {
  const PriceAlertEvaluation({
    required this.settings,
    required this.notificationCount,
  });

  final PriceAlertSettings settings;
  final int notificationCount;
}

class RecoveryAlertPosition {
  const RecoveryAlertPosition({
    required this.quantity,
    required this.investmentNet,
    required this.currentPrice,
    required this.sellFeePercent,
  });

  final double quantity;
  final double investmentNet;
  final double currentPrice;
  final double sellFeePercent;

  bool get hasPosition => quantity > 0 && investmentNet > 0 && currentPrice > 0;
  double get grossCurrentValue => quantity * currentPrice;
  double get netCurrentValue {
    final double multiplier = (1 - sellFeePercent / 100).clamp(0.0, 1.0);
    return grossCurrentValue * multiplier;
  }
  double get unrealizedPnl => netCurrentValue - investmentNet;
  double get pnlPercent =>
      investmentNet > 0 ? (unrealizedPnl / investmentNet) * 100 : 0.0;
  double get missingToBreakEven => unrealizedPnl < 0 ? -unrealizedPnl : 0.0;
}
