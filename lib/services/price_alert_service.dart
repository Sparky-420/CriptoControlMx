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

  static const double defaultThresholdPercent = 2.0;
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
    );
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

  Future<PriceAlertEvaluation> evaluatePrices({
    required SharedPreferences prefs,
    required Map<String, double> currentPrices,
    required Iterable<String> coins,
  }) async {
    final PriceAlertSettings settings = await loadSettings(prefs);
    if (!settings.enabled) {
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

    var notificationCount = 0;

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

    await prefs.setString(referencePricesKey, jsonEncode(references));
    await prefs.setString(lastNotifiedPricesKey, jsonEncode(notifiedPrices));
    await prefs.setString(
      lastNotifiedAtKey,
      jsonEncode(_encodeDateMap(notifiedAt)),
    );

    return PriceAlertEvaluation(
      settings: PriceAlertSettings(
        enabled: settings.enabled,
        thresholdPercent: settings.thresholdPercent,
        referencePrices: references,
        lastNotifiedPrices: notifiedPrices,
        lastNotifiedAt: notifiedAt,
      ),
      notificationCount: notificationCount,
    );
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
  });

  final bool enabled;
  final double thresholdPercent;
  final Map<String, double> referencePrices;
  final Map<String, double> lastNotifiedPrices;
  final Map<String, DateTime> lastNotifiedAt;
}

class PriceAlertEvaluation {
  const PriceAlertEvaluation({
    required this.settings,
    required this.notificationCount,
  });

  final PriceAlertSettings settings;
  final int notificationCount;
}
