import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'simulation_snapshot.dart';

/// Persistencia del monitoreo Pro. Claves compartidas con `AlertWorker`
/// (Android las lee como `flutter.<clave>` en FlutterSharedPreferences).
///
/// - [monitoredIdsKey]: escrita s├│lo por Dart (decisi├│n del usuario).
/// - [stateKey]: estado de evaluaci├│n / anti-duplicados, escrito por el motor
///   Dart en primer plano y por el Worker nativo en segundo plano.
class SmartAlertStore {
  SmartAlertStore(this._prefs);

  static const String savedSimulationsKey = 'saved_simulations_v1_json';
  static const String monitoredIdsKey = 'smart_alerts_monitored_ids_v1_json';
  static const String stateKey = 'smart_alerts_state_v1_json';

  final SharedPreferences _prefs;

  Future<Set<String>> loadMonitoredIds() async {
    await _prefs.reload();
    return _readIds(_prefs.getString(monitoredIdsKey));
  }

  Future<void> setMonitored(String id, bool enabled) async {
    final Set<String> ids = await loadMonitoredIds();
    if (enabled) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    await _prefs.setString(monitoredIdsKey, jsonEncode(ids.toList()..sort()));
    if (!enabled) {
      final Map<String, SmartMonitorState> states = await loadStates();
      if (states.remove(id) != null) await saveStates(states);
    }
  }

  /// Elimina identificadores y estados que ya no corresponden
  /// a simulaciones guardadas y supervisadas.
  Future<Set<String>> reconcileMonitoredIds() async {
    final List<SmartSavedSimulation> simulations = await loadSavedSimulations();

    final Set<String> existingIds = simulations.map((s) => s.id).toSet();

    final Set<String> monitoredIds = await loadMonitoredIds();

    final Set<String> validIds = monitoredIds.intersection(existingIds);

    if (validIds.length != monitoredIds.length) {
      await _prefs.setString(
        monitoredIdsKey,
        jsonEncode(validIds.toList()..sort()),
      );
    }

    final Map<String, SmartMonitorState> states = await loadStates();

    final int previousStateCount = states.length;

    states.removeWhere((String id, _) => !validIds.contains(id));

    if (states.length != previousStateCount) {
      await saveStates(states);
    }

    return validIds;
  }

  Future<Map<String, SmartMonitorState>> loadStates() async {
    await _prefs.reload();
    final String? raw = _prefs.getString(stateKey);
    if (raw == null || raw.trim().isEmpty) return <String, SmartMonitorState>{};
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, SmartMonitorState>{};
      return <String, SmartMonitorState>{
        for (final MapEntry<dynamic, dynamic> e in decoded.entries)
          if (e.value is Map)
            e.key.toString(): SmartMonitorState.fromJson(
              Map<String, dynamic>.from(e.value as Map),
            ),
      };
    } catch (_) {
      return <String, SmartMonitorState>{};
    }
  }

  Future<void> saveStates(Map<String, SmartMonitorState> states) async {
    await _prefs.setString(
      stateKey,
      jsonEncode(<String, Object?>{
        for (final MapEntry<String, SmartMonitorState> e in states.entries)
          e.key: e.value.toJson(),
      }),
    );
  }

  /// Lee las simulaciones guardadas por `SimulationTab`.
  Future<List<SmartSavedSimulation>> loadSavedSimulations() async {
    await _prefs.reload();
    final String? raw = _prefs.getString(savedSimulationsKey);
    if (raw == null || raw.trim().isEmpty) return <SmartSavedSimulation>[];
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return <SmartSavedSimulation>[];
      final Map<String, SmartSavedSimulation> unique =
          <String, SmartSavedSimulation>{};
      for (final dynamic item in decoded) {
        if (item is! Map) continue;
        final String id = (item['id'] ?? '').toString();
        if (id.isEmpty || unique.containsKey(id)) continue;
        unique[id] = SmartSavedSimulation(
          id: id,
          title: '${item['modeLabel'] ?? ''} ${item['selectedAsset'] ?? ''}'
              .trim(),
          snapshot: SimulationSnapshot.fromJson(item['smartParams']),
        );
      }
      return unique.values.toList();
    } catch (_) {
      return <SmartSavedSimulation>[];
    }
  }

  static Set<String> _readIds(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String>{};
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded.map((dynamic e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }
}

class SmartSavedSimulation {
  const SmartSavedSimulation({
    required this.id,
    required this.title,
    required this.snapshot,
  });

  final String id;
  final String title;
  final SimulationSnapshot? snapshot;
}

/// ├Ültimo resultado de evaluaci├│n de una simulaci├│n supervisada.
class SmartMonitorState {
  const SmartMonitorState({
    this.conditionMet = false,
    this.lastStatus = 'pending',
    this.lastEvaluatedAt,
    this.lastNotifiedAt,
    this.lastCurrentValue,
    this.targetValue,
    this.diagnostic = '',
  });

  /// `true` mientras la oportunidad sigue vigente y ya fue notificada.
  final bool conditionMet;

  /// favorable | notFavorable | missingData | priceError | pending
  final String lastStatus;
  final DateTime? lastEvaluatedAt;
  final DateTime? lastNotifiedAt;
  final double? lastCurrentValue;
  final double? targetValue;
  final String diagnostic;

  SmartMonitorState copyWith({
    bool? conditionMet,
    String? lastStatus,
    DateTime? lastEvaluatedAt,
    DateTime? lastNotifiedAt,
    double? lastCurrentValue,
    double? targetValue,
    String? diagnostic,
    bool clearLastNotifiedAt = false,
  }) => SmartMonitorState(
    conditionMet: conditionMet ?? this.conditionMet,
    lastStatus: lastStatus ?? this.lastStatus,
    lastEvaluatedAt: lastEvaluatedAt ?? this.lastEvaluatedAt,
    lastNotifiedAt: clearLastNotifiedAt
        ? null
        : lastNotifiedAt ?? this.lastNotifiedAt,
    lastCurrentValue: lastCurrentValue ?? this.lastCurrentValue,
    targetValue: targetValue ?? this.targetValue,
    diagnostic: diagnostic ?? this.diagnostic,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'conditionMet': conditionMet,
    'lastStatus': lastStatus,
    'lastEvaluatedAt': lastEvaluatedAt?.toIso8601String(),
    'lastNotifiedAt': lastNotifiedAt?.toIso8601String(),
    'lastCurrentValue': lastCurrentValue,
    'targetValue': targetValue,
    'diagnostic': diagnostic,
  };

  static SmartMonitorState fromJson(Map<String, dynamic> json) {
    double? d(String k) => json[k] is num ? (json[k] as num).toDouble() : null;
    DateTime? t(String k) => DateTime.tryParse('${json[k] ?? ''}');
    return SmartMonitorState(
      conditionMet: json['conditionMet'] == true,
      lastStatus: (json['lastStatus'] ?? 'pending').toString(),
      lastEvaluatedAt: t('lastEvaluatedAt'),
      lastNotifiedAt: t('lastNotifiedAt'),
      lastCurrentValue: d('lastCurrentValue'),
      targetValue: d('targetValue'),
      diagnostic: (json['diagnostic'] ?? '').toString(),
    );
  }
}
