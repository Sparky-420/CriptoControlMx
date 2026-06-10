import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/price_alert_service.dart';
import 'services/price_service.dart';

class CriptoControlApp extends StatefulWidget {
  const CriptoControlApp({super.key});

  @override
  State<CriptoControlApp> createState() => _CriptoControlAppState();
}

class _CriptoControlAppState extends State<CriptoControlApp> {
  static const List<String> _coins = ['BTC', 'ETH', 'LINK', 'LTC', 'UNI'];

  static const String _movementsKey = 'movements_json';
  static const String _pricesKey = PriceService.pricesKey;
  static const String _sellFeePercentKey = 'sell_fee_percent';
  static const String _snapshotsKey = 'portfolio_snapshots_v23_json';
  static const String _darkModeKey = 'dark_mode_v24';
  static const String _themeModeKey = 'theme_mode_v25';
  static const String _accentColorKey = 'accent_color_v25';
  static const String _themeStyleKey = 'theme_style_v26';
  static const String _visiblePositionsKey = 'visible_positions_v26';
  static const String _positionSortKey = 'position_sort_v26';
  static const String _snapshotModeKey = 'snapshot_mode_v26';
  static const String _snapshotRetentionKey = 'snapshot_retention_v26';

  final List<Movement> _movements = <Movement>[];
  final List<PortfolioSnapshot> _snapshots = <PortfolioSnapshot>[];
  final PriceService _priceService = PriceService();
  final PriceAlertService _priceAlertService = PriceAlertService();

  final Map<String, double> _currentPrices = <String, double>{
    'BTC': 0.0,
    'ETH': 0.0,
    'LINK': 0.0,
    'LTC': 0.0,
    'UNI': 0.0,
  };

  int _currentIndex = 0;
  double _sellFeePercent = 0.0;
  AppVisualMode _visualMode = AppVisualMode.system;
  AppThemeStyle _themeStyle = AppThemeStyle.proDark;
  VisiblePositions _visiblePositions = VisiblePositions.three;
  PositionSortMode _positionSortMode = PositionSortMode.largestValue;
  SnapshotAutomationMode _snapshotAutomationMode =
      SnapshotAutomationMode.manual;
  SnapshotRetention _snapshotRetention = SnapshotRetention.last30;
  SimulationMode _requestedSimulationMode = SimulationMode.operation;
  int _simulationOpenNonce = 0;
  DateTime? _pricesUpdatedAt;
  bool _isRefreshingPrices = false;
  bool _priceAlertsEnabled = false;
  bool _notificationsAllowed = true;
  bool _automaticLocalAlertsEnabled = false;
  int _automaticLocalAlertsIntervalMinutes =
      PriceAlertService.defaultAutomaticIntervalMinutes;
  double _priceAlertThresholdPercent =
      PriceAlertService.defaultThresholdPercent;
  Map<String, double> _priceAlertReferences = <String, double>{};
  bool _recoveryAlertsEnabled = false;
  double _recoveryAlertThresholdPoints =
      PriceAlertService.defaultRecoveryThresholdPoints;
  Map<String, double> _recoveryAlertReferences = <String, double>{};

  @override
  void initState() {
    super.initState();
    _priceAlertService.initialize();
    _loadData();
  }

  Future<void> _loadData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final String? movementsRaw = prefs.getString(_movementsKey);
    if (movementsRaw != null && movementsRaw.trim().isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(movementsRaw);
        if (decoded is List) {
          _movements
            ..clear()
            ..addAll(
              decoded.map(
                (dynamic e) =>
                    Movement.fromJson(Map<String, dynamic>.from(e as Map)),
              ),
            );
        }
      } catch (_) {}
    }

    final PriceCache priceCache = await _priceService.loadCachedPrices(prefs);
    _applyPriceCache(priceCache);

    final String? snapshotsRaw = prefs.getString(_snapshotsKey);
    if (snapshotsRaw != null && snapshotsRaw.trim().isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(snapshotsRaw);
        if (decoded is List) {
          _snapshots
            ..clear()
            ..addAll(
              decoded.map(
                (dynamic e) => PortfolioSnapshot.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              ),
            );
          _snapshots.sort(
            (PortfolioSnapshot a, PortfolioSnapshot b) =>
                b.createdAt.compareTo(a.createdAt),
          );
        }
      } catch (_) {}
    }

    _sellFeePercent = prefs.getDouble(_sellFeePercentKey) ?? 0.0;
    final String? savedVisualMode = prefs.getString(_themeModeKey);
    if (savedVisualMode != null) {
      _visualMode = appVisualModeFromName(savedVisualMode);
    } else if (prefs.containsKey(_darkModeKey)) {
      _visualMode = (prefs.getBool(_darkModeKey) ?? false)
          ? AppVisualMode.dark
          : AppVisualMode.light;
    } else {
      _visualMode = AppVisualMode.system;
    }
    _themeStyle = appThemeStyleFromName(
      prefs.getString(_themeStyleKey) ?? prefs.getString(_accentColorKey),
    );
    _visiblePositions = visiblePositionsFromName(
      prefs.getString(_visiblePositionsKey),
    );
    _positionSortMode = positionSortModeFromName(
      prefs.getString(_positionSortKey),
    );
    _snapshotAutomationMode = snapshotAutomationModeFromName(
      prefs.getString(_snapshotModeKey),
    );
    _snapshotRetention = snapshotRetentionFromName(
      prefs.getString(_snapshotRetentionKey),
    );
    await _loadPriceAlertSettings(prefs);

    if (mounted) setState(() {});

    await _captureAutomaticSnapshotIfNeeded(SnapshotTrigger.appOpen);

    await _refreshPricesIfNeeded(prefs);
  }

  void _applyPriceCache(PriceCache cache) {
    for (final String coin in _coins) {
      _currentPrices[coin] = cache.prices[coin] ?? 0.0;
    }
    _pricesUpdatedAt = cache.updatedAt;
  }

  Future<void> _loadPriceAlertSettings(SharedPreferences prefs) async {
    final PriceAlertSettings settings = await _priceAlertService.loadSettings(
      prefs,
    );
    final bool notificationsAllowed = await _priceAlertService
        .areNotificationsAllowed();

    _priceAlertsEnabled = settings.enabled;
    _priceAlertThresholdPercent = settings.thresholdPercent;
    _priceAlertReferences = settings.referencePrices;
    _recoveryAlertsEnabled = settings.recoveryEnabled;
    _recoveryAlertThresholdPoints = settings.recoveryThresholdPoints;
    _recoveryAlertReferences = settings.recoveryReferencePnl;
    _notificationsAllowed = notificationsAllowed;
    _automaticLocalAlertsEnabled = settings.automaticAlertsEnabled;
    _automaticLocalAlertsIntervalMinutes = settings.automaticIntervalMinutes;
    await _priceAlertService.configureAutomaticAlerts(
      enabled: settings.automaticAlertsEnabled,
      intervalMinutes: settings.automaticIntervalMinutes,
    );
  }

  Future<void> _evaluatePriceAlerts(SharedPreferences prefs) async {
    final PriceAlertEvaluation evaluation = await _priceAlertService
        .evaluatePrices(
          prefs: prefs,
          currentPrices: _currentPrices,
          coins: _coins,
          recoveryPositions: _recoveryAlertPositions(_computeStats()),
        );
    final bool notificationsAllowed = await _priceAlertService
        .areNotificationsAllowed();

    if (!mounted) return;
    setState(() {
      _priceAlertsEnabled = evaluation.settings.enabled;
      _priceAlertThresholdPercent = evaluation.settings.thresholdPercent;
      _priceAlertReferences = evaluation.settings.referencePrices;
      _recoveryAlertsEnabled = evaluation.settings.recoveryEnabled;
      _recoveryAlertThresholdPoints =
          evaluation.settings.recoveryThresholdPoints;
      _recoveryAlertReferences = evaluation.settings.recoveryReferencePnl;
      _notificationsAllowed = notificationsAllowed;
      _automaticLocalAlertsEnabled = evaluation.settings.automaticAlertsEnabled;
      _automaticLocalAlertsIntervalMinutes =
          evaluation.settings.automaticIntervalMinutes;
    });
  }

  Map<String, RecoveryAlertPosition> _recoveryAlertPositions(
    Map<String, CoinStats> stats,
  ) {
    return <String, RecoveryAlertPosition>{
      for (final String coin in _coins)
        coin: RecoveryAlertPosition(
          quantity: stats[coin]?.quantity ?? 0.0,
          investmentNet: stats[coin]?.costBase ?? 0.0,
          currentPrice: stats[coin]?.currentPrice ?? 0.0,
          sellFeePercent: _sellFeePercent,
        ),
    };
  }

  Future<void> _togglePriceAlerts(
    BuildContext pageContext,
    bool enabled,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    var notificationsAllowed = await _priceAlertService
        .areNotificationsAllowed();

    if (enabled && !notificationsAllowed) {
      notificationsAllowed = await _priceAlertService
          .requestNotificationPermission();
    }

    await _priceAlertService.setEnabled(prefs, enabled);
    await _loadPriceAlertSettings(prefs);
    if (mounted) setState(() {});

    if (enabled && !notificationsAllowed && pageContext.mounted) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(
          content: Text(
            'Activa el permiso de notificaciones para recibir alertas.',
          ),
        ),
      );
    }
  }

  Future<void> _toggleAutomaticLocalAlerts(
    BuildContext pageContext,
    bool enabled,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    var notificationsAllowed = await _priceAlertService
        .areNotificationsAllowed();

    if (enabled && !notificationsAllowed) {
      notificationsAllowed = await _priceAlertService
          .requestNotificationPermission();
    }

    await _priceAlertService.setAutomaticAlertsEnabled(prefs, enabled);
    await _priceAlertService.configureAutomaticAlerts(
      enabled: enabled,
      intervalMinutes: _automaticLocalAlertsIntervalMinutes,
    );
    if (enabled) await _priceAlertService.runAutomaticAlertCheckNow();
    await _loadPriceAlertSettings(prefs);
    if (mounted) setState(() {});

    if (enabled && !notificationsAllowed && pageContext.mounted) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(
          content: Text(
            'Permiso denegado: las alertas internas siguen activas, pero Android no mostrará notificaciones automáticas.',
          ),
        ),
      );
    }
  }

  Future<void> _changeAutomaticLocalAlertInterval(int minutes) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await _priceAlertService.setAutomaticAlertsIntervalMinutes(prefs, minutes);
    setState(() => _automaticLocalAlertsIntervalMinutes = minutes);
    await _priceAlertService.configureAutomaticAlerts(
      enabled: _automaticLocalAlertsEnabled,
      intervalMinutes: minutes,
    );
  }

  Future<void> _toggleRecoveryAlerts(
    BuildContext pageContext,
    bool enabled,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    var notificationsAllowed = await _priceAlertService
        .areNotificationsAllowed();

    if (enabled && !notificationsAllowed) {
      notificationsAllowed = await _priceAlertService
          .requestNotificationPermission();
    }

    await _priceAlertService.setRecoveryEnabled(prefs, enabled);
    await _loadPriceAlertSettings(prefs);
    if (mounted) setState(() {});

    if (enabled && !notificationsAllowed && pageContext.mounted) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(
          content: Text(
            'Activa el permiso de notificaciones para recibir alertas.',
          ),
        ),
      );
    }
  }

  Future<void> _showRecoveryAlertThresholdDialog(
    BuildContext pageContext,
  ) async {
    final TextEditingController controller = TextEditingController(
      text: compact(_recoveryAlertThresholdPoints),
    );

    await showDialog<void>(
      context: pageContext,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Umbral de recuperación'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Puntos porcentuales',
            helperText: 'Predeterminado: 2.0',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final double? value = double.tryParse(controller.text.trim());
              if (value == null || value <= 0 || value > 100) return;

              final SharedPreferences prefs =
                  await SharedPreferences.getInstance();
              await _priceAlertService.setRecoveryThresholdPoints(
                prefs,
                value,
              );
              await _loadPriceAlertSettings(prefs);
              if (mounted) setState(() {});
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPriceAlertThresholdDialog(BuildContext pageContext) async {
    final TextEditingController controller = TextEditingController(
      text: compact(_priceAlertThresholdPercent),
    );

    await showDialog<void>(
      context: pageContext,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Umbral'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Umbral %',
            helperText: 'Predeterminado: 2.0',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final double? value = double.tryParse(controller.text.trim());
              if (value == null || value <= 0 || value > 100) return;

              final SharedPreferences prefs =
                  await SharedPreferences.getInstance();
              await _priceAlertService.setThresholdPercent(prefs, value);
              await _loadPriceAlertSettings(prefs);
              if (mounted) setState(() {});
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetPriceAlertReferences(BuildContext pageContext) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final PriceAlertSettings settings = await _priceAlertService
        .resetReferences(prefs, _currentPrices, _coins);

    if (!mounted) return;
    setState(() {
      _priceAlertReferences = settings.referencePrices;
      _priceAlertThresholdPercent = settings.thresholdPercent;
      _priceAlertsEnabled = settings.enabled;
    });

    if (pageContext.mounted) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(content: Text('Referencias reiniciadas')),
      );
    }
  }

  Future<void> _resetRecoveryAlertReferences(BuildContext pageContext) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final PriceAlertSettings settings = await _priceAlertService
        .resetRecoveryReferences(
          prefs,
          _recoveryAlertPositions(_computeStats()),
          _coins,
        );

    if (!mounted) return;
    setState(() {
      _recoveryAlertReferences = settings.recoveryReferencePnl;
      _recoveryAlertThresholdPoints = settings.recoveryThresholdPoints;
      _recoveryAlertsEnabled = settings.recoveryEnabled;
    });

    if (pageContext.mounted) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(
          content: Text('Referencias de recuperación reiniciadas'),
        ),
      );
    }
  }

  Future<void> _refreshPricesIfNeeded(SharedPreferences prefs) async {
    final PriceCache priceCache = await _priceService.refreshIfStale(prefs);
    _applyPriceCache(priceCache);
    await _evaluatePriceAlerts(prefs);
    if (!mounted) return;

    setState(() {});
  }

  Future<void> _refreshPricesNow(BuildContext pageContext) async {
    if (_isRefreshingPrices) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);
    setState(() => _isRefreshingPrices = true);
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PriceCache priceCache = await _priceService.fetchAndCachePrices(
        prefs,
      );
      if (!mounted) return;

      _applyPriceCache(priceCache);
      await _evaluatePriceAlerts(prefs);
      setState(() {});
      await _captureAutomaticSnapshotIfNeeded(SnapshotTrigger.priceUpdate);
      messenger.showSnackBar(
        const SnackBar(content: Text('Precios actualizados')),
      );
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No se pudieron actualizar los precios'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshingPrices = false);
      }
    }
  }

  Future<void> _saveData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _movementsKey,
      jsonEncode(_movements.map((Movement m) => m.toJson()).toList()),
    );

    await prefs.setString(_pricesKey, jsonEncode(_currentPrices));
    await prefs.setDouble(_sellFeePercentKey, _sellFeePercent);
    await prefs.setString(_themeModeKey, _visualMode.name);
    await prefs.setString(_themeStyleKey, _themeStyle.name);
    await prefs.setString(_accentColorKey, _themeStyle.name);
    await prefs.setString(_visiblePositionsKey, _visiblePositions.name);
    await prefs.setString(_positionSortKey, _positionSortMode.name);
    await prefs.setString(_snapshotModeKey, _snapshotAutomationMode.name);
    await prefs.setString(_snapshotRetentionKey, _snapshotRetention.name);
    await prefs.setBool(_darkModeKey, _visualMode == AppVisualMode.dark);
  }

  Future<void> _saveSnapshots() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _snapshotsKey,
      jsonEncode(_snapshots.map((PortfolioSnapshot s) => s.toJson()).toList()),
    );
    await _saveData();
  }

  PortfolioSnapshot _buildCurrentSnapshot() {
    final Map<String, CoinStats> stats = _computeStats();
    final PortfolioTotals totals = _totals(stats);

    return PortfolioSnapshot(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      totalCostBase: totals.costBase,
      totalCurrentValue: totals.currentValue,
      totalUnrealizedPL: totals.unrealizedPL,
      totalRealizedPL: totals.realizedPL,
      movementCount: _movements.length,
      coins: _coins
          .map((String coin) => CoinSnapshot.fromStats(stats[coin]!))
          .toList(),
    );
  }

  void _insertSnapshot(PortfolioSnapshot snapshot) {
    _snapshots.insert(0, snapshot);
    _snapshots.sort(
      (PortfolioSnapshot a, PortfolioSnapshot b) =>
          b.createdAt.compareTo(a.createdAt),
    );
    _enforceSnapshotRetention();
  }

  void _enforceSnapshotRetention() {
    final int? limit = _snapshotRetention.limit;
    if (limit != null && _snapshots.length > limit) {
      _snapshots.removeRange(limit, _snapshots.length);
    }
  }

  Future<void> _captureAutomaticSnapshotIfNeeded(
    SnapshotTrigger trigger,
  ) async {
    if (!_snapshotAutomationMode.shouldCapture(trigger, _snapshots)) return;
    if (!mounted) return;
    setState(() => _insertSnapshot(_buildCurrentSnapshot()));
    await _saveSnapshots();
  }

  Future<void> _saveMovementAndMaybeSnapshot(SnapshotTrigger trigger) async {
    await _captureAutomaticSnapshotIfNeeded(trigger);
    await _saveData();
  }

  Map<String, CoinStats> _computeStats() {
    final Map<String, CoinStats> stats = <String, CoinStats>{
      for (final String coin in _coins)
        coin: CoinStats(coin: coin, currentPrice: _currentPrices[coin] ?? 0.0),
    };

    final List<MapEntry<int, Movement>> indexed =
        _movements.asMap().entries.toList()
          ..sort((MapEntry<int, Movement> a, MapEntry<int, Movement> b) {
            final int dateCompare = a.value.date.compareTo(b.value.date);
            if (dateCompare != 0) return dateCompare;
            return a.key.compareTo(b.key);
          });

    for (final MapEntry<int, Movement> entry in indexed) {
      final Movement movement = entry.value;
      final CoinStats? stat = stats[movement.coin];
      if (stat == null) continue;

      switch (movement.type) {
        case MovementType.buy:
        case MovementType.transferIn:
          stat.quantity += movement.quantity;
          stat.costBase +=
              (movement.quantity * movement.unitPrice) + movement.fee;
          stat.feesPaid += movement.fee;
          break;

        case MovementType.sell:
          final double average = stat.quantity > 0
              ? stat.costBase / stat.quantity
              : 0.0;
          final double quantityToRemove = movement.quantity > stat.quantity
              ? stat.quantity
              : movement.quantity;
          final double removedCost = average * quantityToRemove;
          final double proceeds =
              (movement.quantity * movement.unitPrice) - movement.fee;

          stat.realizedPL += proceeds - removedCost;
          stat.quantity -= quantityToRemove;
          stat.costBase -= removedCost;
          stat.feesPaid += movement.fee;
          break;

        case MovementType.transferOut:
          final double average = stat.quantity > 0
              ? stat.costBase / stat.quantity
              : 0.0;
          final double quantityToRemove = movement.quantity > stat.quantity
              ? stat.quantity
              : movement.quantity;
          final double removedCost = average * quantityToRemove;

          stat.quantity -= quantityToRemove;
          stat.costBase -= removedCost;
          stat.feesPaid += movement.fee;
          break;
      }

      if (stat.quantity.abs() < 0.0000000001) {
        stat.quantity = 0.0;
        stat.costBase = 0.0;
      }

      if (stat.costBase.abs() < 0.00000001) {
        stat.costBase = 0.0;
      }
    }

    for (final String coin in _coins) {
      stats[coin]!.currentPrice = _currentPrices[coin] ?? 0.0;
    }

    return stats;
  }

  CoinAudit _auditCoin(String coin) {
    double buys = 0.0;
    double sells = 0.0;
    double transferIns = 0.0;
    double transferOuts = 0.0;
    double fees = 0.0;

    for (final Movement movement in _movements.where(
      (Movement m) => m.coin == coin,
    )) {
      final double total = movement.quantity * movement.unitPrice;
      fees += movement.fee;

      switch (movement.type) {
        case MovementType.buy:
          buys += total + movement.fee;
          break;
        case MovementType.sell:
          sells += total - movement.fee;
          break;
        case MovementType.transferIn:
          transferIns += total + movement.fee;
          break;
        case MovementType.transferOut:
          transferOuts += total + movement.fee;
          break;
      }
    }

    return CoinAudit(
      buys: buys,
      sells: sells,
      transferIns: transferIns,
      transferOuts: transferOuts,
      fees: fees,
    );
  }

  PortfolioTotals _totals(Map<String, CoinStats> stats) {
    return PortfolioTotals(
      costBase: stats.values.fold<double>(
        0.0,
        (double sum, CoinStats s) => sum + s.costBase,
      ),
      currentValue: stats.values.fold<double>(
        0.0,
        (double sum, CoinStats s) => sum + s.currentValue,
      ),
      unrealizedPL: stats.values.fold<double>(
        0.0,
        (double sum, CoinStats s) => sum + s.unrealizedPL,
      ),
      realizedPL: stats.values.fold<double>(
        0.0,
        (double sum, CoinStats s) => sum + s.realizedPL,
      ),
    );
  }

  bool _wouldCreateInvalidPosition(Movement candidate, {int? replaceIndex}) {
    final List<Movement> testList = <Movement>[..._movements];

    if (replaceIndex != null &&
        replaceIndex >= 0 &&
        replaceIndex < testList.length) {
      testList[replaceIndex] = candidate;
    } else {
      testList.add(candidate);
    }

    final Map<String, double> balances = <String, double>{
      for (final String coin in _coins) coin: 0.0,
    };

    final List<MapEntry<int, Movement>> indexed =
        testList.asMap().entries.toList()
          ..sort((MapEntry<int, Movement> a, MapEntry<int, Movement> b) {
            final int dateCompare = a.value.date.compareTo(b.value.date);
            if (dateCompare != 0) return dateCompare;
            return a.key.compareTo(b.key);
          });

    for (final MapEntry<int, Movement> entry in indexed) {
      final Movement movement = entry.value;
      final double current = balances[movement.coin] ?? 0.0;

      switch (movement.type) {
        case MovementType.buy:
        case MovementType.transferIn:
          balances[movement.coin] = current + movement.quantity;
          break;

        case MovementType.sell:
        case MovementType.transferOut:
          if (movement.quantity > current + 0.0000000001) return true;
          balances[movement.coin] = current - movement.quantity;
          break;
      }
    }

    return false;
  }

  void _changeVisualMode(AppVisualMode value) {
    setState(() => _visualMode = value);
    _saveData();
  }

  void _changeThemeStyle(AppThemeStyle value) {
    setState(() => _themeStyle = value);
    _saveData();
  }

  void _changeVisiblePositions(VisiblePositions value) {
    setState(() => _visiblePositions = value);
    _saveData();
  }

  void _changePositionSortMode(PositionSortMode value) {
    setState(() => _positionSortMode = value);
    _saveData();
  }

  void _changeSnapshotAutomationMode(SnapshotAutomationMode value) {
    setState(() => _snapshotAutomationMode = value);
    _saveData();
  }

  void _changeSnapshotRetention(SnapshotRetention value) {
    setState(() => _snapshotRetention = value);
    _enforceSnapshotRetention();
    _saveSnapshots();
    _saveData();
  }

  void _openSimulationMode(SimulationMode mode) {
    setState(() {
      _requestedSimulationMode = mode;
      _simulationOpenNonce++;
      _currentIndex = 0;
    });
  }

  Future<void> _showSellFeeDialog(BuildContext pageContext) async {
    final TextEditingController controller = TextEditingController(
      text: compact(_sellFeePercent),
    );

    await showDialog<void>(
      context: pageContext,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Comisión de salida'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Porcentaje',
            helperText: 'Ejemplo: 1.5',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final double? value = double.tryParse(controller.text.trim());
              if (value == null || value < 0 || value >= 100) return;

              setState(() => _sellFeePercent = value);
              _saveData();
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showEditPriceDialog(BuildContext pageContext, String coin) {
    final TextEditingController controller = TextEditingController(
      text: compact(_currentPrices[coin] ?? 0.0),
    );

    showDialog<void>(
      context: pageContext,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Precio actual de $coin'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Precio MXN',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final double? value = double.tryParse(controller.text.trim());
              if (value == null || value < 0) return;

              _currentPrices[coin] = value;
              final PriceCache priceCache = await _priceService
                  .saveManualPrices(
                    await SharedPreferences.getInstance(),
                    _currentPrices,
                  );
              if (!dialogContext.mounted) return;
              await _evaluatePriceAlerts(
                await SharedPreferences.getInstance(),
              );
              if (mounted) {
                setState(() => _applyPriceCache(priceCache));
              }
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddMovementSheet(
    BuildContext pageContext, {
    Movement? existing,
    int? index,
  }) {
    MovementType selectedType = existing?.type ?? MovementType.buy;
    String selectedCoin = existing?.coin ?? _coins.first;
    DateTime selectedDate = existing?.date ?? DateTime.now();

    final TextEditingController qtyController = TextEditingController(
      text: existing == null ? '' : compact(existing.quantity),
    );
    final TextEditingController priceController = TextEditingController(
      text: existing == null ? '' : compact(existing.unitPrice),
    );
    final TextEditingController feeController = TextEditingController(
      text: existing == null ? '0' : compact(existing.fee),
    );
    final TextEditingController sourceController = TextEditingController(
      text: existing?.source ?? '',
    );
    final TextEditingController walletController = TextEditingController(
      text: existing?.wallet ?? '',
    );
    final TextEditingController networkController = TextEditingController(
      text: existing?.network ?? '',
    );
    final TextEditingController noteController = TextEditingController(
      text: existing?.note ?? '',
    );

    return showModalBottomSheet<void>(
      context: pageContext,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder:
              (
                BuildContext context,
                void Function(void Function()) setModalState,
              ) {
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    16 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SheetHeader(
                          title: existing == null
                              ? 'Nuevo movimiento'
                              : 'Editar movimiento',
                          onClose: () => Navigator.of(sheetContext).pop(),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<MovementType>(
                          initialValue: selectedType,
                          decoration: const InputDecoration(
                            labelText: 'Tipo',
                            border: OutlineInputBorder(),
                          ),
                          items: MovementType.values
                              .map(
                                (MovementType type) =>
                                    DropdownMenuItem<MovementType>(
                                      value: type,
                                      child: Text(type.label),
                                    ),
                              )
                              .toList(),
                          onChanged: (MovementType? value) {
                            if (value != null) {
                              setModalState(() => selectedType = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedCoin,
                          decoration: const InputDecoration(
                            labelText: 'Moneda',
                            border: OutlineInputBorder(),
                          ),
                          items: _coins
                              .map(
                                (String coin) => DropdownMenuItem<String>(
                                  value: coin,
                                  child: Text(coin),
                                ),
                              )
                              .toList(),
                          onChanged: (String? value) {
                            if (value != null) {
                              setModalState(() => selectedCoin = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2010),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setModalState(() => selectedDate = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text('Fecha: ${shortDate(selectedDate)}'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: qtyController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Cantidad cripto',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: priceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Precio unitario MXN',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: feeController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Comisión MXN',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: sourceController,
                          decoration: const InputDecoration(
                            labelText: 'Origen',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: walletController,
                          decoration: const InputDecoration(
                            labelText: 'Cartera',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: networkController,
                          decoration: const InputDecoration(
                            labelText: 'Red',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: noteController,
                          decoration: const InputDecoration(
                            labelText: 'Nota',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () {
                              final double? quantity = double.tryParse(
                                qtyController.text.trim(),
                              );
                              final double? unitPrice = double.tryParse(
                                priceController.text.trim(),
                              );
                              final double fee =
                                  double.tryParse(feeController.text.trim()) ??
                                  0.0;

                              if (quantity == null || quantity <= 0) {
                                _snack(pageContext, 'Pon una cantidad válida');
                                return;
                              }

                              if (unitPrice == null || unitPrice < 0) {
                                _snack(pageContext, 'Pon un precio válido');
                                return;
                              }

                              if (fee < 0) {
                                _snack(
                                  pageContext,
                                  'La comisión no puede ser negativa',
                                );
                                return;
                              }

                              final Movement movement = Movement(
                                type: selectedType,
                                coin: selectedCoin,
                                date: selectedDate,
                                quantity: quantity,
                                unitPrice: unitPrice,
                                fee: fee,
                                source: sourceController.text.trim(),
                                wallet: walletController.text.trim(),
                                network: networkController.text.trim(),
                                note: noteController.text.trim(),
                              );

                              if (_wouldCreateInvalidPosition(
                                movement,
                                replaceIndex: existing == null ? null : index,
                              )) {
                                _snack(
                                  pageContext,
                                  'Ese movimiento dejaría la posición en negativo',
                                );
                                return;
                              }

                              setState(() {
                                if (existing != null &&
                                    index != null &&
                                    index >= 0 &&
                                    index < _movements.length) {
                                  _movements[index] = movement;
                                } else {
                                  _movements.add(movement);
                                }
                              });

                              _saveMovementAndMaybeSnapshot(
                                SnapshotTrigger.movementChange,
                              );
                              Navigator.of(sheetContext).pop();
                            },
                            icon: Icon(
                              existing == null
                                  ? Icons.add
                                  : Icons.save_outlined,
                            ),
                            label: Text(
                              existing == null
                                  ? 'Guardar movimiento'
                                  : 'Guardar cambios',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
        );
      },
    );
  }

  void _showCoinDetails(BuildContext pageContext, CoinStats stats) {
    final CoinAudit audit = _auditCoin(stats.coin);

    showModalBottomSheet<void>(
      context: pageContext,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.84,
        minChildSize: 0.45,
        maxChildSize: 0.96,
        builder: (BuildContext context, ScrollController controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SheetHeader(
              title: 'Detalles de ${stats.coin}',
              onClose: () => Navigator.of(sheetContext).pop(),
            ),
            const SizedBox(height: 12),
            CardPanel(
              title: 'Lectura simple',
              subtitle: 'Datos principales sin saturar la pantalla.',
              child: Column(
                children: <Widget>[
                  InfoLine('Cantidad', crypto(stats.quantity)),
                  InfoLine('Invertido actual', money(stats.costBase)),
                  InfoLine(
                    'Valor de cartera',
                    money(stats.currentValue),
                    emphasized: true,
                  ),
                  InfoLine(
                    'P&L no realizado',
                    money(stats.unrealizedPL),
                    valueColor: pnlColor(stats.unrealizedPL),
                    emphasized: true,
                  ),
                  InfoLine(
                    'Precio para recuperar',
                    money(stats.netBreakEvenPrice(_sellFeePercent)),
                  ),
                ],
              ),
            ),
            CardPanel(
              title: 'Auditoría',
              subtitle: 'Desglose para revisar de dónde salen los números.',
              child: Column(
                children: <Widget>[
                  InfoLine('Compras acumuladas', money(audit.buys)),
                  InfoLine('Ventas acumuladas', money(audit.sells)),
                  InfoLine('Entradas acumuladas', money(audit.transferIns)),
                  InfoLine('Salidas acumuladas', money(audit.transferOuts)),
                  InfoLine('Comisiones acumuladas', money(audit.fees)),
                  InfoLine('Promedio histórico actual', money(stats.avgPrice)),
                  InfoLine(
                    'P&L realizado',
                    money(stats.realizedPL),
                    valueColor: pnlColor(stats.realizedPL),
                  ),
                ],
              ),
            ),
            CardPanel(
              title: 'Fórmulas claras',
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Promedio = invertido actual / cantidad actual'),
                  SizedBox(height: 6),
                  Text('P&L no realizado = valor de cartera - invertido actual'),
                  SizedBox(height: 6),
                  Text(
                    'Precio para recuperar = promedio / (1 - comisión de salida)',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSnapshot(BuildContext pageContext) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);
    final PortfolioSnapshot snapshot = _buildCurrentSnapshot();

    setState(() => _insertSnapshot(snapshot));

    await _saveSnapshots();

    if (mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Instantánea guardada')),
      );
    }
  }

  void _showSnapshots(BuildContext pageContext) {
    showModalBottomSheet<void>(
      context: pageContext,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        minChildSize: 0.45,
        maxChildSize: 0.96,
        builder: (BuildContext context, ScrollController controller) =>
            StatefulBuilder(
              builder:
                  (
                    BuildContext context,
                    void Function(void Function()) setModalState,
                  ) {
                    return ListView(
                      controller: controller,
                      padding: const EdgeInsets.all(16),
                      children: <Widget>[
                        SheetHeader(
                          title: 'Instantáneas',
                          onClose: () => Navigator.of(sheetContext).pop(),
                        ),
                        const SizedBox(height: 12),
                        if (_snapshots.isEmpty)
                          const EmptyState(
                            icon: Icons.photo_library_outlined,
                            title: 'Sin instantáneas',
                            subtitle:
                                'Guarda una instantánea de cartera desde Gráficas.',
                          )
                        else ...<Widget>[
                          SnapshotTrendPanel(snapshots: _snapshots),
                          ..._snapshots.map(
                            (PortfolioSnapshot snapshot) => CardPanel(
                              title: longDate(snapshot.createdAt),
                              trailing: IconButton(
                                tooltip: 'Borrar instantánea',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  setState(
                                    () => _snapshots.removeWhere(
                                      (PortfolioSnapshot s) =>
                                          s.id == snapshot.id,
                                    ),
                                  );
                                  await _saveSnapshots();
                                  setModalState(() {});
                                },
                              ),
                              child: Column(
                                children: <Widget>[
                                  InfoLine('Fecha', longDate(snapshot.createdAt)),
                                  InfoLine(
                                    'Valor de cartera',
                                    money(snapshot.totalCurrentValue),
                                  ),
                                  InfoLine(
                                    'P&L no realizado',
                                    money(snapshot.totalUnrealizedPL),
                                    valueColor: pnlColor(
                                      snapshot.totalUnrealizedPL,
                                    ),
                                    emphasized: true,
                                  ),
                                  InfoLine(
                                    'P&L realizado',
                                    money(snapshot.totalRealizedPL),
                                    valueColor: pnlColor(
                                      snapshot.totalRealizedPL,
                                    ),
                                  ),
                                  InfoLine(
                                    'Inversión total',
                                    money(snapshot.totalCostBase),
                                  ),
                                  InfoLine(
                                    'Moneda dominante',
                                    snapshot.dominantCoinLabel,
                                  ),
                                  InfoLine(
                                    'Movimientos',
                                    snapshot.movementCount.toString(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
            ),
      ),
    );
  }

  String _buildBackupJson() {
    final Map<String, dynamic> backup = <String, dynamic>{
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': <String, double>{'sellFeePercent': _sellFeePercent},
      'currentPrices': _currentPrices,
      'movements': _movements.map((Movement m) => m.toJson()).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  String _buildMovementsCsv() {
    final List<List<Object?>> rows = <List<Object?>>[
      <Object?>[
        'fecha',
        'tipo',
        'tipo_raw',
        'cripto',
        'cantidad',
        'precio_unitario_mxn',
        'comision_mxn',
        'total_bruto_mxn',
        'origen',
        'cartera',
        'red',
        'nota',
      ],
      ..._movements.map((Movement m) {
        return <Object?>[
          isoDate(m.date),
          m.type.label,
          m.type.name,
          m.coin,
          fixed(m.quantity, 8),
          fixed(m.unitPrice, 2),
          fixed(m.fee, 2),
          fixed(m.quantity * m.unitPrice, 2),
          m.source,
          m.wallet,
          m.network,
          m.note,
        ];
      }),
    ];

    return rows
        .map((List<Object?> row) => row.map(csvEscape).join(','))
        .join('\n');
  }

  String _buildSummaryCsv() {
    final Map<String, CoinStats> stats = _computeStats();

    final List<List<Object?>> rows = <List<Object?>>[
      <Object?>[
        'cripto',
        'cantidad_actual',
        'invertido_actual_mxn',
        'precio_promedio_mxn',
        'precio_actual_mxn',
        'valor_actual_mxn',
        'resultado_actual_mxn',
        'resultado_vendido_mxn',
        'precio_para_recuperar_mxn',
        'comisiones_acumuladas_mxn',
      ],
      ..._coins.map((String coin) {
        final CoinStats s = stats[coin]!;
        return <Object?>[
          s.coin,
          fixed(s.quantity, 8),
          fixed(s.costBase, 2),
          fixed(s.avgPrice, 2),
          fixed(s.currentPrice, 2),
          fixed(s.currentValue, 2),
          fixed(s.unrealizedPL, 2),
          fixed(s.realizedPL, 2),
          fixed(s.netBreakEvenPrice(_sellFeePercent), 2),
          fixed(s.feesPaid, 2),
        ];
      }),
    ];

    return rows
        .map((List<Object?> row) => row.map(csvEscape).join(','))
        .join('\n');
  }

  String _buildSnapshotsCsv() {
    final List<List<Object?>> rows = <List<Object?>>[
      <Object?>[
        'snapshot_id',
        'fecha',
        'invertido_total_mxn',
        'valor_actual_total_mxn',
        'resultado_actual_mxn',
        'resultado_vendido_mxn',
        'movimientos',
        'cripto',
        'cantidad',
        'invertido_mxn',
        'promedio_mxn',
        'valor_actual_mxn',
        'resultado_actual_moneda_mxn',
        'resultado_vendido_moneda_mxn',
      ],
    ];

    for (final PortfolioSnapshot snapshot in _snapshots) {
      if (snapshot.coins.isEmpty) {
        rows.add(<Object?>[
          snapshot.id,
          snapshot.createdAt.toIso8601String(),
          fixed(snapshot.totalCostBase, 2),
          fixed(snapshot.totalCurrentValue, 2),
          fixed(snapshot.totalUnrealizedPL, 2),
          fixed(snapshot.totalRealizedPL, 2),
          snapshot.movementCount,
          '',
          '',
          '',
          '',
          '',
          '',
          '',
        ]);
      } else {
        for (final CoinSnapshot coin in snapshot.coins) {
          rows.add(<Object?>[
            snapshot.id,
            snapshot.createdAt.toIso8601String(),
            fixed(snapshot.totalCostBase, 2),
            fixed(snapshot.totalCurrentValue, 2),
            fixed(snapshot.totalUnrealizedPL, 2),
            fixed(snapshot.totalRealizedPL, 2),
            snapshot.movementCount,
            coin.coin,
            fixed(coin.quantity, 8),
            fixed(coin.costBase, 2),
            fixed(coin.avgPrice, 2),
            fixed(coin.currentValue, 2),
            fixed(coin.unrealizedPL, 2),
            fixed(coin.realizedPL, 2),
          ]);
        }
      }
    }

    return rows
        .map((List<Object?> row) => row.map(csvEscape).join(','))
        .join('\n');
  }

  Uint8List _buildXlsxBytes() {
    final Map<String, CoinStats> stats = _computeStats();
    final xl.Excel excel = xl.Excel.createExcel();

    final xl.Sheet history = excel['Historial'];
    _appendExcelRow(history, <Object?>[
      'Fecha',
      'Tipo',
      'Tipo raw',
      'Cripto',
      'Cantidad',
      'Precio unitario MXN',
      'Comisión MXN',
      'Total bruto MXN',
      'Origen',
      'Cartera',
      'Red',
      'Nota',
    ]);

    for (final Movement movement in _movements) {
      _appendExcelRow(history, <Object?>[
        isoDate(movement.date),
        movement.type.label,
        movement.type.name,
        movement.coin,
        movement.quantity,
        movement.unitPrice,
        movement.fee,
        movement.quantity * movement.unitPrice,
        movement.source,
        movement.wallet,
        movement.network,
        movement.note,
      ]);
    }

    final xl.Sheet summary = excel['Resumen'];
    _appendExcelRow(summary, <Object?>[
      'Cripto',
      'Cantidad actual',
      'Invertido actual MXN',
      'Precio promedio MXN',
      'Precio actual MXN',
      'Valor actual MXN',
      'Resultado actual MXN',
      'Resultado vendido MXN',
      'Precio para recuperar MXN',
      'Comisiones acumuladas MXN',
    ]);

    for (final String coin in _coins) {
      final CoinStats stat = stats[coin]!;
      _appendExcelRow(summary, <Object?>[
        stat.coin,
        stat.quantity,
        stat.costBase,
        stat.avgPrice,
        stat.currentPrice,
        stat.currentValue,
        stat.unrealizedPL,
        stat.realizedPL,
        stat.netBreakEvenPrice(_sellFeePercent),
        stat.feesPaid,
      ]);
    }

    final xl.Sheet snapshots = excel['Snapshots'];
    _appendExcelRow(snapshots, <Object?>[
      'Snapshot ID',
      'Fecha',
      'Invertido total MXN',
      'Valor actual total MXN',
      'Resultado actual MXN',
      'Resultado vendido MXN',
      'Movimientos',
      'Cripto',
      'Cantidad',
      'Invertido MXN',
      'Promedio MXN',
      'Valor actual MXN',
      'Resultado actual moneda MXN',
      'Resultado vendido moneda MXN',
    ]);

    for (final PortfolioSnapshot snapshot in _snapshots) {
      if (snapshot.coins.isEmpty) {
        _appendExcelRow(snapshots, <Object?>[
          snapshot.id,
          snapshot.createdAt.toIso8601String(),
          snapshot.totalCostBase,
          snapshot.totalCurrentValue,
          snapshot.totalUnrealizedPL,
          snapshot.totalRealizedPL,
          snapshot.movementCount,
          '',
          '',
          '',
          '',
          '',
          '',
          '',
        ]);
      } else {
        for (final CoinSnapshot coin in snapshot.coins) {
          _appendExcelRow(snapshots, <Object?>[
            snapshot.id,
            snapshot.createdAt.toIso8601String(),
            snapshot.totalCostBase,
            snapshot.totalCurrentValue,
            snapshot.totalUnrealizedPL,
            snapshot.totalRealizedPL,
            snapshot.movementCount,
            coin.coin,
            coin.quantity,
            coin.costBase,
            coin.avgPrice,
            coin.currentValue,
            coin.unrealizedPL,
            coin.realizedPL,
          ]);
        }
      }
    }

    excel.setDefaultSheet('Resumen');
    final List<int>? bytes = excel.encode();
    if (bytes == null) throw StateError('No se pudo crear el XLSX');
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> _buildPdfBytes() async {
    final Map<String, CoinStats> stats = _computeStats();
    final PortfolioTotals totals = _totals(stats);

    final pw.Document pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(margin: pw.EdgeInsets.all(28)),
        build: (pw.Context context) => <pw.Widget>[
          pw.Text(
            'CriptoControlMx - Reporte básico',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Generado: ${DateTime.now().toIso8601String()}'),
          pw.Text('Comisión de salida: ${pct(_sellFeePercent)}'),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            headers: <String>['Concepto', 'Monto'],
            data: <List<String>>[
              <String>['Invertido actual', money(totals.costBase)],
              <String>['Valor de cartera', money(totals.currentValue)],
              <String>['P&L no realizado', money(totals.unrealizedPL)],
              <String>['P&L realizado', money(totals.realizedPL)],
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'Resumen por moneda',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            headers: <String>[
              'Cripto',
              'Cantidad',
              'Invertido',
              'Valor de cartera',
              'Resultado',
              'Recuperar',
            ],
            data: _coins.map((String coin) {
              final CoinStats s = stats[coin]!;
              return <String>[
                s.coin,
                crypto(s.quantity),
                money(s.costBase),
                money(s.currentValue),
                money(s.unrealizedPL),
                money(s.netBreakEvenPrice(_sellFeePercent)),
              ];
            }).toList(),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  Future<void> _shareDataFile({
    required ScaffoldMessengerState messenger,
    required String fileName,
    required String mimeType,
    required List<int> bytes,
    required String successMessage,
  }) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile.fromData(
              Uint8List.fromList(bytes),
              mimeType: mimeType,
              name: fileName,
            ),
          ],
          fileNameOverrides: <String>[fileName],
          text: 'CriptoControlMx',
        ),
      );

      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo exportar el archivo')),
        );
      }
    }
  }

  Future<void> _exportMovementsCsv(BuildContext pageContext) async {
    await _shareDataFile(
      messenger: ScaffoldMessenger.of(pageContext),
      fileName: 'criptocontrolmx_historial.csv',
      mimeType: 'text/csv',
      bytes: utf8.encode('\ufeff${_buildMovementsCsv()}'),
      successMessage: 'Historial CSV listo',
    );
  }

  Future<void> _exportSummaryCsv(BuildContext pageContext) async {
    await _shareDataFile(
      messenger: ScaffoldMessenger.of(pageContext),
      fileName: 'criptocontrolmx_resumen.csv',
      mimeType: 'text/csv',
      bytes: utf8.encode('\ufeff${_buildSummaryCsv()}'),
      successMessage: 'Resumen CSV listo',
    );
  }

  Future<void> _exportSnapshotsCsv(BuildContext pageContext) async {
    await _shareDataFile(
      messenger: ScaffoldMessenger.of(pageContext),
      fileName: 'criptocontrolmx_snapshots.csv',
      mimeType: 'text/csv',
      bytes: utf8.encode('\ufeff${_buildSnapshotsCsv()}'),
      successMessage: 'Instantáneas CSV listas',
    );
  }

  Future<void> _exportXlsx(BuildContext pageContext) async {
    await _shareDataFile(
      messenger: ScaffoldMessenger.of(pageContext),
      fileName: 'criptocontrolmx_reporte.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      bytes: _buildXlsxBytes(),
      successMessage: 'XLSX listo',
    );
  }

  Future<void> _exportPdf(BuildContext pageContext) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);
    final Uint8List bytes = await _buildPdfBytes();
    if (!mounted) return;

    await _shareDataFile(
      messenger: messenger,
      fileName: 'criptocontrolmx_reporte.pdf',
      mimeType: 'application/pdf',
      bytes: bytes,
      successMessage: 'Reporte PDF listo',
    );
  }

  Future<void> _exportBackup(BuildContext pageContext) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);
    await Clipboard.setData(ClipboardData(text: _buildBackupJson()));
    if (mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Respaldo JSON copiado')),
      );
    }
  }

  Future<void> _applyBackupJson(String rawJson) async {
    final dynamic decoded = jsonDecode(rawJson.trim());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException();
    }

    final dynamic movementsRaw = decoded['movements'];
    final dynamic pricesRaw = decoded['currentPrices'];
    final dynamic settingsRaw = decoded['settings'];

    if (movementsRaw is! List || pricesRaw is! Map) {
      throw const FormatException();
    }

    final List<Movement> imported = movementsRaw
        .map(
          (dynamic e) => Movement.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
    final Map<String, dynamic> pricesMap = Map<String, dynamic>.from(pricesRaw);

    setState(() {
      _movements
        ..clear()
        ..addAll(imported);

      for (final String coin in _coins) {
        _currentPrices[coin] = numberFromJson(pricesMap[coin]);
      }

      if (settingsRaw is Map && settingsRaw['sellFeePercent'] is num) {
        _sellFeePercent = (settingsRaw['sellFeePercent'] as num).toDouble();
      }
    });

    await _saveData();
  }

  Future<void> _importBackup(BuildContext pageContext) async {
    final TextEditingController controller = TextEditingController();

    await showDialog<void>(
      context: pageContext,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Importar respaldo JSON'),
        content: TextField(
          controller: controller,
          minLines: 8,
          maxLines: 14,
          decoration: const InputDecoration(
            hintText: 'Pega aquí tu respaldo',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final NavigatorState navigator = Navigator.of(dialogContext);
              final ScaffoldMessengerState messenger = ScaffoldMessenger.of(
                pageContext,
              );
              try {
                await _applyBackupJson(controller.text);

                if (!mounted) return;
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Respaldo importado')),
                );
              } catch (_) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('JSON inválido o incompleto')),
                );
              }
            },
            child: const Text('Importar'),
          ),
        ],
      ),
    );
  }

  Future<void> _importBackupFile(BuildContext pageContext) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);

    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['json'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final PlatformFile file = result.files.single;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) throw const FormatException();

      await _applyBackupJson(utf8.decode(bytes));
      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(content: Text('Respaldo importado: ${file.name}')),
      );
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo importar el archivo JSON')),
        );
      }
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, CoinStats> stats = _computeStats();
    final PortfolioTotals totals = _totals(stats);

    final AppPalette palette = _themeStyle.palette;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CriptoControlMx',
      themeMode: _visualMode.themeMode,
      theme: buildPremiumTheme(palette, Brightness.light),
      darkTheme: buildPremiumTheme(palette, Brightness.dark),
      home: Builder(
        builder: (BuildContext pageContext) {
          void openMorePage(
            String title,
            Widget Function(VoidCallback refresh) childBuilder,
          ) {
            Navigator.of(pageContext).push(
              MaterialPageRoute<void>(
                builder: (_) => StatefulBuilder(
                  builder: (
                    BuildContext routeContext,
                    void Function(void Function()) routeSetState,
                  ) {
                    void refresh() => routeSetState(() {});
                    return Scaffold(
                      appBar: AppBar(title: Text(title)),
                      body: childBuilder(refresh),
                    );
                  },
                ),
              ),
            );
          }

          void openAlertsTab() {
            Navigator.of(pageContext).maybePop();
            setState(() => _currentIndex = 3);
          }

          Widget buildChartsTab({VoidCallback? refresh}) => ChartsTab(
            stats: stats,
            totals: totals,
            snapshots: _snapshots,
            onSaveSnapshot: () {
              _saveSnapshot(pageContext).then((_) => refresh?.call());
            },
            onViewSnapshots: () => _showSnapshots(pageContext),
          );

          Widget buildMovementsTab() => MovementsTab(
            movements: _movements,
            coins: _coins,
            onAdd: () => _showAddMovementSheet(pageContext),
            onEdit: (Movement movement) => _showAddMovementSheet(
              pageContext,
              existing: movement,
              index: _movements.indexOf(movement),
            ),
            onDelete: (Movement movement) {
              setState(() => _movements.remove(movement));
              _saveMovementAndMaybeSnapshot(SnapshotTrigger.movementChange);
            },
          );

          Widget buildSettingsTab({
            VoidCallback? refresh,
            SettingsView view = SettingsView.all,
          }) => SettingsTab(
            view: view,
            visualMode: _visualMode,
            themeStyle: _themeStyle,
            visiblePositions: _visiblePositions,
            positionSortMode: _positionSortMode,
            snapshotAutomationMode: _snapshotAutomationMode,
            snapshotRetention: _snapshotRetention,
            sellFeePercent: _sellFeePercent,
            snapshotCount: _snapshots.length,
            onVisualModeChanged: (AppVisualMode value) {
              _changeVisualMode(value);
              refresh?.call();
            },
            onThemeStyleChanged: (AppThemeStyle value) {
              _changeThemeStyle(value);
              refresh?.call();
            },
            onVisiblePositionsChanged: (VisiblePositions value) {
              _changeVisiblePositions(value);
              refresh?.call();
            },
            onPositionSortModeChanged: (PositionSortMode value) {
              _changePositionSortMode(value);
              refresh?.call();
            },
            onSnapshotAutomationModeChanged: (SnapshotAutomationMode value) {
              _changeSnapshotAutomationMode(value);
              refresh?.call();
            },
            onSnapshotRetentionChanged: (SnapshotRetention value) {
              _changeSnapshotRetention(value);
              refresh?.call();
            },
            onEditSellFee: () => _showSellFeeDialog(pageContext),
            onOpenAlerts: openAlertsTab,
            automaticLocalAlertsEnabled: _automaticLocalAlertsEnabled,
            automaticLocalAlertsIntervalMinutes:
                _automaticLocalAlertsIntervalMinutes,
            notificationsAllowed: _notificationsAllowed,
            onAutomaticLocalAlertsChanged: (bool enabled) {
              _toggleAutomaticLocalAlerts(pageContext, enabled)
                  .then((_) => refresh?.call());
            },
            onAutomaticLocalAlertIntervalChanged: (int minutes) {
              _changeAutomaticLocalAlertInterval(minutes)
                  .then((_) => refresh?.call());
            },
            onSaveSnapshot: () {
              _saveSnapshot(pageContext).then((_) => refresh?.call());
            },
            onViewSnapshots: () => _showSnapshots(pageContext),
            onExportSnapshotsCsv: () => _exportSnapshotsCsv(pageContext),
            onExportXlsx: () => _exportXlsx(pageContext),
            onExportPdf: () => _exportPdf(pageContext),
            onExportBackup: () => _exportBackup(pageContext),
          );

          final List<Widget> pages = <Widget>[
            SimulationTab(
              key: ValueKey<String>(
                '${_requestedSimulationMode.name}-$_simulationOpenNonce',
              ),
              coins: _coins,
              stats: stats,
              defaultFeePercent: _sellFeePercent == 0 ? 1.5 : _sellFeePercent,
              targetExitFeePercent: _sellFeePercent,
              initialMode: _requestedSimulationMode,
            ),
            SummaryTab(
              stats: stats,
              totals: totals,
              sellFeePercent: _sellFeePercent,
              visiblePositions: _visiblePositions,
              positionSortMode: _positionSortMode,
              latestSnapshot: _snapshots.isEmpty ? null : _snapshots.first,
              onDetails: (CoinStats s) => _showCoinDetails(pageContext, s),
              onSaveSnapshot: () => _saveSnapshot(pageContext),
              onViewSnapshots: () => _showSnapshots(pageContext),
              onViewSnapshotEvolution: () =>
                  openMorePage(
                    'Gráficas',
                    (VoidCallback refresh) =>
                        buildChartsTab(refresh: refresh),
                  ),
            ),
            CoinsTab(
              coins: _coins,
              stats: stats,
              sellFeePercent: _sellFeePercent,
              onEditPrice: (String coin) =>
                  _showEditPriceDialog(pageContext, coin),
              onDetails: (CoinStats s) => _showCoinDetails(pageContext, s),
            ),
            AlertsTab(
              coins: _coins,
              stats: stats,
              priceAlertsEnabled: _priceAlertsEnabled,
              priceAlertThresholdPercent: _priceAlertThresholdPercent,
              priceAlertReferences: _priceAlertReferences,
              recoveryAlertsEnabled: _recoveryAlertsEnabled,
              recoveryAlertThresholdPoints: _recoveryAlertThresholdPoints,
              recoveryAlertReferences: _recoveryAlertReferences,
              sellFeePercent: _sellFeePercent,
              notificationsAllowed: _notificationsAllowed,
              automaticLocalAlertsEnabled: _automaticLocalAlertsEnabled,
              automaticLocalAlertsIntervalMinutes:
                  _automaticLocalAlertsIntervalMinutes,
              pricesUpdatedAt: _pricesUpdatedAt,
              isRefreshingPrices: _isRefreshingPrices,
              onRefreshPrices: () => _refreshPricesNow(pageContext),
              onPriceAlertsChanged: (bool enabled) =>
                  _togglePriceAlerts(pageContext, enabled),
              onEditPriceAlertThreshold: () =>
                  _showPriceAlertThresholdDialog(pageContext),
              onResetPriceAlertReferences: () =>
                  _resetPriceAlertReferences(pageContext),
              onRecoveryAlertsChanged: (bool enabled) =>
                  _toggleRecoveryAlerts(pageContext, enabled),
              onEditRecoveryAlertThreshold: () =>
                  _showRecoveryAlertThresholdDialog(pageContext),
              onResetRecoveryAlertReferences: () =>
                  _resetRecoveryAlertReferences(pageContext),
              onAutomaticLocalAlertsChanged: (bool enabled) =>
                  _toggleAutomaticLocalAlerts(pageContext, enabled),
              onAutomaticLocalAlertIntervalChanged:
                  _changeAutomaticLocalAlertInterval,
            ),
            MoreTab(
              totals: totals,
              pricesUpdatedAt: _pricesUpdatedAt,
              visualMode: _visualMode,
              themeStyle: _themeStyle,
              movementCount: _movements.length,
              snapshotCount: _snapshots.length,
              chartDataCount: stats.values
                  .where((CoinStats stat) => stat.currentValue > 0)
                  .length,
              onOpenCharts: () => openMorePage(
                'Gráficas',
                (VoidCallback refresh) => buildChartsTab(refresh: refresh),
              ),
              onOpenMovements: () => openMorePage(
                'Historial de movimientos',
                (_) => buildMovementsTab(),
              ),
              onOpenThemeSettings: () => openMorePage(
                'Tema',
                (VoidCallback refresh) => buildSettingsTab(
                  refresh: refresh,
                  view: SettingsView.theme,
                ),
              ),
              onOpenPortfolioSettings: () => openMorePage(
                'Resumen de cartera',
                (VoidCallback refresh) => buildSettingsTab(
                  refresh: refresh,
                  view: SettingsView.portfolio,
                ),
              ),
              onOpenAlerts: openAlertsTab,
              onExportMovementsCsv: () => _exportMovementsCsv(pageContext),
              onExportSummaryCsv: () => _exportSummaryCsv(pageContext),
              onExportSnapshotsCsv: () => _exportSnapshotsCsv(pageContext),
              onExportXlsx: () => _exportXlsx(pageContext),
              onExportPdf: () => _exportPdf(pageContext),
              onExportBackup: () => _exportBackup(pageContext),
              onImportBackup: () => _importBackup(pageContext),
              onImportBackupFile: () => _importBackupFile(pageContext),
              onSaveSnapshot: () => _saveSnapshot(pageContext),
              onViewSnapshots: () => _showSnapshots(pageContext),
              onResetPriceAlertReferences: () =>
                  _resetPriceAlertReferences(pageContext),
            ),
          ];

          return Scaffold(
            appBar: AppBar(
              title: const Text('CriptoControlMx'),
              actions: <Widget>[
                IconButton(
                  tooltip: 'Actualizar precios',
                  onPressed: _isRefreshingPrices
                      ? null
                      : () => _refreshPricesNow(pageContext),
                  icon: _isRefreshingPrices
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                ),
                IconButton(
                  tooltip: 'Nuevo movimiento',
                  onPressed: () => _showAddMovementSheet(pageContext),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            body: IndexedStack(index: _currentIndex, children: pages),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (int index) {
                setState(() => _currentIndex = index);
              },
              destinations: const <NavigationDestination>[
                NavigationDestination(icon: Icon(Icons.tune), label: 'Simular'),
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  label: 'Resumen',
                ),
                NavigationDestination(
                  icon: Icon(Icons.currency_bitcoin),
                  label: 'Monedas',
                ),
                NavigationDestination(
                  icon: Icon(Icons.notifications_active_outlined),
                  label: 'Alertas',
                ),
                NavigationDestination(
                  icon: Icon(Icons.more_horiz),
                  label: 'Más',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class SummaryTab extends StatelessWidget {
  final Map<String, CoinStats> stats;
  final PortfolioTotals totals;
  final double sellFeePercent;
  final VisiblePositions visiblePositions;
  final PositionSortMode positionSortMode;
  final PortfolioSnapshot? latestSnapshot;
  final void Function(CoinStats stats) onDetails;
  final VoidCallback onSaveSnapshot;
  final VoidCallback onViewSnapshots;
  final VoidCallback onViewSnapshotEvolution;

  const SummaryTab({
    super.key,
    required this.stats,
    required this.totals,
    required this.sellFeePercent,
    required this.visiblePositions,
    required this.positionSortMode,
    required this.latestSnapshot,
    required this.onDetails,
    required this.onSaveSnapshot,
    required this.onViewSnapshots,
    required this.onViewSnapshotEvolution,
  });

  List<Widget> _buildVisiblePositionChildren({
    required List<CoinStats> active,
    required List<CoinStats> visibleActive,
    required double sellFeePercent,
    required PositionSortMode positionSortMode,
    required void Function(CoinStats stats) onDetails,
  }) {
    if (active.isEmpty) {
      return <Widget>[
        const EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Sin posiciones abiertas',
          subtitle: 'Agrega un movimiento para empezar.',
        ),
      ];
    }

    final List<Widget> children = visibleActive
        .map<Widget>(
          (CoinStats s) => CleanCoinCard(
            stats: s,
            sellFeePercent: sellFeePercent,
            onDetails: () => onDetails(s),
          ),
        )
        .toList();

    final int hiddenCount = active.length - visibleActive.length;
    if (hiddenCount > 0) {
      children.add(
        PremiumInfoPanel(
          icon: Icons.visibility_off_outlined,
          title: '$hiddenCount posiciones ocultas',
          subtitle: 'Cambia el límite en Más > Portafolio.',
          badge: positionSortMode.label,
        ),
      );
    }

    return children;
  }

  @override
  Widget build(BuildContext context) {
    final List<CoinStats> active = sortedPositions(
      stats.values.where((CoinStats s) => s.quantity > 0),
      positionSortMode,
      sellFeePercent,
    );
    final int? visibleLimit = visiblePositions.limit;
    final List<CoinStats> visibleActive = visibleLimit == null
        ? active
        : active.take(visibleLimit).toList();
    final CoinStats? leader = active.isEmpty ? null : active.first;
    final CoinStats? weakest = active.isEmpty
        ? null
        : active.reduce(
            (CoinStats a, CoinStats b) =>
                a.unrealizedPL <= b.unrealizedPL ? a : b,
          );
    final int recovered = active
        .where((CoinStats s) => s.isAtOrAboveNetBreakEven(sellFeePercent))
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: <Widget>[
        PremiumDashboardHero(
          title: 'Resumen ejecutivo',
          subtitle: leader == null
              ? 'Panorama limpio para activar decisiones de cartera.'
              : '${leader.coin} lidera la cartera por valor actual.',
          icon: Icons.space_dashboard_outlined,
          metrics: <PremiumMetricData>[
            PremiumMetricData(
              label: 'Valor de cartera',
              value: moneyShort(totals.currentValue),
              icon: Icons.account_balance_wallet_outlined,
            ),
            PremiumMetricData(
              label: 'P&L no realizado',
              value: moneyShort(totals.unrealizedPL),
              color: pnlColor(totals.unrealizedPL),
              icon: totals.unrealizedPL >= 0
                  ? Icons.trending_up
                  : Icons.trending_down,
            ),
            PremiumMetricData(
              label: 'P&L realizado',
              value: moneyShort(totals.realizedPL),
              color: pnlColor(totals.realizedPL),
              icon: Icons.payments_outlined,
            ),
            PremiumMetricData(
              label: 'Mayor posición',
              value: leader?.coin ?? '—',
              icon: Icons.military_tech_outlined,
            ),
          ],
        ),
        const SizedBox(height: 18),
        LatestSnapshotCard(
          snapshot: latestSnapshot,
          onSaveSnapshot: onSaveSnapshot,
          onViewSnapshots: onViewSnapshots,
          onViewEvolution: onViewSnapshotEvolution,
        ),
        const SizedBox(height: 10),
        _CommandSection(
          title: 'Panorama',
          children: <Widget>[
            PremiumMetricCard(
              label: 'Invertido',
              value: money(totals.costBase),
              icon: Icons.savings_outlined,
            ),
            PremiumMetricCard(
              label: 'Posiciones arriba del equilibrio',
              value: '$recovered / ${active.length}',
              icon: Icons.verified_outlined,
              color: Colors.green,
            ),
          ],
        ),
        _CommandSection(
          title: 'Foco inmediato',
          children: <Widget>[
            PremiumInfoPanel(
              icon: Icons.leaderboard_outlined,
              title: 'Mayor posición',
              subtitle: leader == null
                  ? 'Sin posiciones abiertas'
                  : '${leader.coin} · ${money(leader.currentValue)}',
              badge: leader == null ? 'Pendiente' : 'Dominante',
            ),
            PremiumInfoPanel(
              icon: Icons.warning_amber_rounded,
              title: 'Resultado a vigilar',
              subtitle: weakest == null
                  ? 'Sin pérdidas abiertas'
                  : '${weakest.coin} · ${money(weakest.unrealizedPL)}',
              badge: weakest == null
                  ? 'Normal'
                  : _positionStatusLabel(weakest, sellFeePercent),
              badgeColor: weakest == null
                  ? Colors.green
                  : pnlColor(weakest.unrealizedPL),
            ),
          ],
        ),
        _CommandSection(
          title: 'Posiciones visibles · ${visiblePositions.label} · ${positionSortMode.label}',
          children: _buildVisiblePositionChildren(
            active: active,
            visibleActive: visibleActive,
            sellFeePercent: sellFeePercent,
            positionSortMode: positionSortMode,
            onDetails: onDetails,
          ),
        ),
      ],
    );
  }
}

class LatestSnapshotCard extends StatelessWidget {
  final PortfolioSnapshot? snapshot;
  final VoidCallback onSaveSnapshot;
  final VoidCallback onViewSnapshots;
  final VoidCallback onViewEvolution;

  const LatestSnapshotCard({
    super.key,
    required this.snapshot,
    required this.onSaveSnapshot,
    required this.onViewSnapshots,
    required this.onViewEvolution,
  });

  @override
  Widget build(BuildContext context) {
    final PortfolioSnapshot? current = snapshot;
    return CardPanel(
      title: 'Última instantánea',
      subtitle: current == null
          ? 'Sin instantánea guardada todavía. Gestiona instantáneas desde Gráficas.'
          : 'Guardado el ${longDate(current.createdAt)}.',
      child: current == null
          ? const Text(
              'Resumen muestra solo la última instantánea. Para guardar, revisar '
              'o administrar el histórico, entra a Gráficas.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                InfoLine('Fecha', longDate(current.createdAt)),
                InfoLine('Valor de cartera', money(current.totalCurrentValue)),
                InfoLine(
                  'P&L no realizado',
                  money(current.totalUnrealizedPL),
                  valueColor: pnlColor(current.totalUnrealizedPL),
                  emphasized: true,
                ),
                InfoLine(
                  'P&L realizado',
                  money(current.totalRealizedPL),
                  valueColor: pnlColor(current.totalRealizedPL),
                ),
                InfoLine('Inversión total', money(current.totalCostBase)),
                InfoLine('Moneda dominante', current.dominantCoinLabel),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onViewEvolution,
                    icon: const Icon(Icons.show_chart),
                    label: const Text('Ver evolución en Gráficas'),
                  ),
                ),
              ],
            ),
    );
  }
}


class CoinLogo extends StatelessWidget {
  final String coin;
  final double size;

  const CoinLogo({super.key, required this.coin, this.size = 42});

  static const Set<String> _localIcons = <String>{
    'BTC',
    'ETH',
    'LINK',
    'LTC',
    'UNI',
  };

  @override
  Widget build(BuildContext context) {
    final String normalized = coin.toUpperCase();
    final String asset = 'assets/crypto/${normalized.toLowerCase()}.svg';
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.primaryContainer.withValues(alpha: 0.74),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: _localIcons.contains(normalized)
          ? ClipOval(
              child: SvgPicture.asset(
                asset,
                width: size * 0.72,
                height: size * 0.72,
                fit: BoxFit.contain,
                placeholderBuilder: (_) => _CoinLogoFallback(
                  coin: normalized,
                  size: size,
                ),
                errorBuilder: (_, _, _) => _CoinLogoFallback(
                  coin: normalized,
                  size: size,
                ),
              ),
            )
          : _CoinLogoFallback(coin: normalized, size: size),
    );
  }
}

class _CoinLogoFallback extends StatelessWidget {
  final String coin;
  final double size;

  const _CoinLogoFallback({required this.coin, required this.size});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        coin,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: math.max(10, size * 0.24),
        ),
      ),
    );
  }
}

class CleanCoinCard extends StatelessWidget {
  final CoinStats stats;
  final double sellFeePercent;
  final VoidCallback onDetails;

  const CleanCoinCard({
    super.key,
    required this.stats,
    required this.sellFeePercent,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final bool isRecovered = stats.isAtOrAboveNetBreakEven(sellFeePercent);
    final String distance = stats.quantity <= 0 || isRecovered
        ? '0.00%'
        : pct(stats.percentToNetBreakEven(sellFeePercent));

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CoinLogo(coin: stats.coin, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        money(stats.currentValue),
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '${crypto(stats.quantity)} · BE ${money(stats.netBreakEvenPrice(sellFeePercent))}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: isRecovered
                      ? 'Arriba del equilibrio'
                      : _positionStatusLabel(stats, sellFeePercent),
                  positive: isRecovered,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                MiniMetric(label: 'Resultado', value: money(stats.unrealizedPL), color: pnlColor(stats.unrealizedPL)),
                MiniMetric(label: 'Falta', value: distance),
                MiniMetric(label: 'Promedio', value: money(stats.avgPrice)),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: onDetails,
                icon: const Icon(Icons.info_outline),
                label: const Text('Detalles'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MovementsTab extends StatefulWidget {
  final List<Movement> movements;
  final List<String> coins;
  final Future<void> Function() onAdd;
  final Future<void> Function(Movement movement) onEdit;
  final void Function(Movement movement) onDelete;

  const MovementsTab({
    super.key,
    required this.movements,
    required this.coins,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<MovementsTab> createState() => _MovementsTabState();
}

class _MovementsTabState extends State<MovementsTab> {
  String _coinFilter = 'TODAS';
  String _typeFilter = 'TODOS';
  final TextEditingController _searchController = TextEditingController();
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _confirmDeleteMovement(
    BuildContext context,
    Movement movement,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Borrar movimiento'),
        content: Text(
          '¿Quieres borrar el movimiento de ${movement.coin} del '
          '${shortDate(movement.date)}? Esta acción recalculará el portafolio.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Borrar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      widget.onDelete(movement);
      if (mounted) setState(() {});
    }
  }

  Future<void> _addMovement() async {
    await widget.onAdd();
    if (mounted) setState(() {});
  }

  Future<void> _editMovement(Movement movement) async {
    await widget.onEdit(movement);
    if (mounted) setState(() {});
  }

  void _showMovementDetails(BuildContext context, Movement movement) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewPaddingOf(context).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Detalle de movimiento',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              InfoLine('Moneda', movement.coin),
              InfoLine('Tipo', movement.type.label),
              InfoLine('Fecha', shortDate(movement.date)),
              InfoLine('Cantidad', crypto(movement.quantity)),
              InfoLine('Precio', money(movement.unitPrice)),
              InfoLine('Comisión', money(movement.fee)),
              InfoLine(
                'Total',
                money(movement.quantity * movement.unitPrice),
                emphasized: true,
              ),
              if (movement.source.isNotEmpty)
                InfoLine('Origen', movement.source),
              if (movement.wallet.isNotEmpty)
                InfoLine('Cartera', movement.wallet),
              if (movement.network.isNotEmpty)
                InfoLine('Red', movement.network),
              if (movement.note.isNotEmpty) InfoLine('Nota', movement.note),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _editMovement(movement);
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _confirmDeleteMovement(context, movement);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Borrar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String query = _searchController.text.trim().toLowerCase();
    final List<Movement> filtered = widget.movements.where((Movement m) {
      final bool coinOk = _coinFilter == 'TODAS' || m.coin == _coinFilter;
      final bool typeOk = _typeFilter == 'TODOS' || m.type.name == _typeFilter;
      final bool fromOk =
          _fromDate == null || !m.date.isBefore(dateOnly(_fromDate!));
      final bool toOk =
          _toDate == null || m.date.isBefore(dateOnly(_toDate!).add(days1));
      final bool textOk =
          query.isEmpty ||
          <String>[
            m.coin,
            m.type.label,
            m.type.shortLabel,
            m.source,
            m.wallet,
            m.network,
            m.note,
          ].any((String value) => value.toLowerCase().contains(query));

      return coinOk && typeOk && fromOk && toOk && textOk;
    }).toList()..sort((Movement a, Movement b) => b.date.compareTo(a.date));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _coinFilter,
                decoration: const InputDecoration(
                  labelText: 'Moneda',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: 'TODAS',
                    child: Text('Todas'),
                  ),
                  ...widget.coins.map(
                    (String c) =>
                        DropdownMenuItem<String>(value: c, child: Text(c)),
                  ),
                ],
                onChanged: (String? value) {
                  setState(() => _coinFilter = value ?? 'TODAS');
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _typeFilter,
                decoration: const InputDecoration(
                  labelText: 'Tipo',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: 'TODOS',
                    child: Text('Todos'),
                  ),
                  ...MovementType.values.map(
                    (MovementType t) => DropdownMenuItem<String>(
                      value: t.name,
                      child: Text(t.shortLabel),
                    ),
                  ),
                ],
                onChanged: (String? value) {
                  setState(() => _typeFilter = value ?? 'TODOS');
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Buscar',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: () async {
                final DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: _fromDate ?? DateTime.now(),
                  firstDate: DateTime(2010),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() => _fromDate = picked);
                }
              },
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(
                _fromDate == null ? 'Desde' : 'Desde ${shortDate(_fromDate!)}',
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: _toDate ?? _fromDate ?? DateTime.now(),
                  firstDate: DateTime(2010),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() => _toDate = picked);
                }
              },
              icon: const Icon(Icons.event_available_outlined),
              label: Text(
                _toDate == null ? 'Hasta' : 'Hasta ${shortDate(_toDate!)}',
              ),
            ),
            if (_fromDate != null || _toDate != null || query.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _fromDate = null;
                    _toDate = null;
                  });
                },
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Limpiar'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _addMovement,
            icon: const Icon(Icons.add),
            label: const Text('Agregar movimiento'),
          ),
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Sin movimientos',
            subtitle: 'No hay registros con esos filtros.',
          )
        else
          ...filtered.map(
            (Movement m) => CardPanel(
              title: '${m.coin} · ${m.type.shortLabel}',
              subtitle: shortDate(m.date),
              onTap: () => _showMovementDetails(context, m),
              trailing: PopupMenuButton<String>(
                onSelected: (String value) {
                  if (value == 'details') _showMovementDetails(context, m);
                  if (value == 'edit') _editMovement(m);
                  if (value == 'delete') _confirmDeleteMovement(context, m);
                },
                itemBuilder: (BuildContext context) =>
                    const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'details',
                        child: Text('Ver detalle'),
                      ),
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: Text('Editar'),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('Borrar'),
                      ),
                    ],
              ),
              child: Column(
                children: <Widget>[
                  InfoLine('Cantidad', crypto(m.quantity)),
                  InfoLine('Precio', money(m.unitPrice)),
                  InfoLine('Comisión', money(m.fee)),
                  InfoLine(
                    'Total',
                    money(m.quantity * m.unitPrice),
                    emphasized: true,
                  ),
                  if (m.source.isNotEmpty) InfoLine('Origen', m.source),
                  if (m.wallet.isNotEmpty) InfoLine('Cartera', m.wallet),
                  if (m.network.isNotEmpty) InfoLine('Red', m.network),
                  if (m.note.isNotEmpty) InfoLine('Nota', m.note),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class SimulationTab extends StatefulWidget {
  final List<String> coins;
  final Map<String, CoinStats> stats;
  final double defaultFeePercent;
  final double targetExitFeePercent;
  final SimulationMode initialMode;

  const SimulationTab({
    super.key,
    required this.coins,
    required this.stats,
    required this.defaultFeePercent,
    required this.targetExitFeePercent,
    this.initialMode = SimulationMode.operation,
  });

  @override
  State<SimulationTab> createState() => _SimulationTabState();
}

class _SimulationTabState extends State<SimulationTab> {
  SimulationMode _mode = SimulationMode.operation;
  OperationSimulationMode _operationMode = OperationSimulationMode.buy;

  String _buyCoin = 'UNI';
  final TextEditingController _buyGrossAmountController = TextEditingController(
    text: '3000',
  );
  final TextEditingController _buyPriceController = TextEditingController();
  final TextEditingController _buyFeeController = TextEditingController(
    text: '1.5',
  );
  final TextEditingController _buySellFeeController = TextEditingController(
    text: '1.5',
  );

  String _sellCoin = 'LINK';
  SimulationSellMethod _sellMethod = SimulationSellMethod.percent;
  final TextEditingController _sellPriceController = TextEditingController();
  final TextEditingController _sellFeeController = TextEditingController(
    text: '1.5',
  );
  final TextEditingController _sellPercentController = TextEditingController(
    text: '50',
  );
  final TextEditingController _sellQuantityController = TextEditingController();
  final TextEditingController _sellGrossController = TextEditingController(
    text: '1000',
  );

  String _rotationOriginCoin = 'LINK';
  String _rotationTargetCoin = 'BTC';
  SimulationRotationMethod _rotationMethod = SimulationRotationMethod.percent;
  final TextEditingController _rotationOriginPriceController =
      TextEditingController();
  final TextEditingController _rotationTargetPriceController =
      TextEditingController();
  final TextEditingController _rotationSellFeeController =
      TextEditingController(text: '1.5');
  final TextEditingController _rotationBuyFeeController = TextEditingController(
    text: '1.5',
  );
  final TextEditingController _rotationPercentController =
      TextEditingController(text: '100');
  final TextEditingController _rotationQuantityController =
      TextEditingController();
  final TextEditingController _rotationGrossController = TextEditingController(
    text: '1000',
  );

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  void didUpdateWidget(covariant SimulationTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialMode != oldWidget.initialMode) {
      _mode = widget.initialMode;
    }
  }

  @override
  void dispose() {
    _buyGrossAmountController.dispose();
    _buyPriceController.dispose();
    _buyFeeController.dispose();
    _buySellFeeController.dispose();
    _sellPriceController.dispose();
    _sellFeeController.dispose();
    _sellPercentController.dispose();
    _sellQuantityController.dispose();
    _sellGrossController.dispose();
    _rotationOriginPriceController.dispose();
    _rotationTargetPriceController.dispose();
    _rotationSellFeeController.dispose();
    _rotationBuyFeeController.dispose();
    _rotationPercentController.dispose();
    _rotationQuantityController.dispose();
    _rotationGrossController.dispose();
    super.dispose();
  }


  String get _modeLabel => switch (_mode) {
    SimulationMode.operation => _operationMode == OperationSimulationMode.buy
        ? 'Operación · Compra'
        : 'Operación · Venta',
    SimulationMode.rotation => 'Rotación',
  };

  String get _simulationPairLabel => switch (_mode) {
    SimulationMode.operation => _operationMode == OperationSimulationMode.buy
        ? _buyCoin
        : _sellCoin,
    SimulationMode.rotation => '$_rotationOriginCoin → $_rotationTargetCoin',
  };

  String get _activeFeeLabel => switch (_mode) {
    SimulationMode.operation => _operationMode == OperationSimulationMode.buy
        ? '${_buyFeeController.text.trim()}% / ${_buySellFeeController.text.trim()}%'
        : '${_sellFeeController.text.trim()}%',
    SimulationMode.rotation => '${_rotationSellFeeController.text.trim()}% / ${_rotationBuyFeeController.text.trim()}%',
  };

  String get _simulationScenarioLabel => switch (_mode) {
    SimulationMode.operation => _operationMode == OperationSimulationMode.buy
        ? moneyShort(_parseInput(_buyGrossAmountController))
        : _sellMethod == SimulationSellMethod.percent
            ? '${_sellPercentController.text.trim()}% posición'
            : _sellMethod == SimulationSellMethod.quantity
                ? '${_sellQuantityController.text.trim()} cripto'
                : moneyShort(_parseInput(_sellGrossController)),
    SimulationMode.rotation => _rotationMethod == SimulationRotationMethod.percent
        ? '${_rotationPercentController.text.trim()}% origen'
        : _rotationMethod == SimulationRotationMethod.quantity
            ? '${_rotationQuantityController.text.trim()} cripto'
            : moneyShort(_parseInput(_rotationGrossController)),
  };

  @override
  Widget build(BuildContext context) {
    if (widget.coins.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.tune_outlined,
          title: 'Sin monedas configuradas',
          subtitle: 'Agrega monedas para simular escenarios tácticos.',
        ),
      );
    }

    _ensureSelectedCoins();
    final CoinStats buyStats = _statsFor(_buyCoin);
    final CoinStats sellStats = _statsFor(_sellCoin);
    final CoinStats rotationOriginStats = _statsFor(_rotationOriginCoin);
    final CoinStats rotationTargetStats = _statsFor(_rotationTargetCoin);

    _seedPriceIfEmpty(_buyPriceController, buyStats.currentPrice);
    _seedPriceIfEmpty(_sellPriceController, sellStats.currentPrice);
    _seedPriceIfEmpty(
      _rotationOriginPriceController,
      rotationOriginStats.currentPrice,
    );
    _seedPriceIfEmpty(
      _rotationTargetPriceController,
      rotationTargetStats.currentPrice,
    );

    final BuySimulationResult buyResult = _calculateBuy(buyStats);
    final SellSimulationResult sellResult = _calculateSell(sellStats);
    final RotationSimulationResult rotationResult = _calculateRotation(
      rotationOriginStats,
      rotationTargetStats,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: <Widget>[
        PremiumDashboardHero(
          title: 'Simulación táctica',
          subtitle: 'Prueba compra, venta o rotación sin alterar tu cartera real',
          icon: Icons.tune_outlined,
          metrics: <PremiumMetricData>[
            PremiumMetricData(
              label: 'Modo activo',
              value: _modeLabel,
              icon: Icons.bolt_outlined,
            ),
            PremiumMetricData(
              label: 'Moneda / par',
              value: _simulationPairLabel,
              icon: Icons.token_outlined,
            ),
            PremiumMetricData(
              label: 'Comisión usada',
              value: _activeFeeLabel,
              icon: Icons.percent_outlined,
            ),
            PremiumMetricData(
              label: 'Escenario',
              value: _simulationScenarioLabel,
              icon: Icons.auto_graph_outlined,
            ),
          ],
        ),
        const SizedBox(height: 14),
        PremiumSegmentShell(
          child: SegmentedButton<SimulationMode>(
            segments: const <ButtonSegment<SimulationMode>>[
              ButtonSegment<SimulationMode>(
                value: SimulationMode.operation,
                label: Text('Operación'),
                icon: Icon(Icons.calculate_outlined),
              ),
              ButtonSegment<SimulationMode>(
                value: SimulationMode.rotation,
                label: Text('Rotar'),
                icon: Icon(Icons.sync_alt),
              ),
            ],
            selected: <SimulationMode>{_mode},
            onSelectionChanged: (Set<SimulationMode> value) {
              setState(() => _mode = value.first);
            },
          ),
        ),
        if (_mode == SimulationMode.operation) ...<Widget>[
          const SizedBox(height: 10),
          PremiumSegmentShell(
            child: SegmentedButton<OperationSimulationMode>(
              segments: const <ButtonSegment<OperationSimulationMode>>[
                ButtonSegment<OperationSimulationMode>(
                  value: OperationSimulationMode.buy,
                  label: Text('Compra'),
                  icon: Icon(Icons.add_circle_outline),
                ),
                ButtonSegment<OperationSimulationMode>(
                  value: OperationSimulationMode.sell,
                  label: Text('Venta'),
                  icon: Icon(Icons.remove_circle_outline),
                ),
              ],
              selected: <OperationSimulationMode>{_operationMode},
              onSelectionChanged: (Set<OperationSimulationMode> value) {
                setState(() => _operationMode = value.first);
              },
            ),
          ),
        ],
        const SizedBox(height: 14),
        ...switch (_mode) {
          SimulationMode.operation => _operationMode == OperationSimulationMode.buy
              ? _buildBuyMode(buyStats, buyResult)
              : _buildSellMode(sellStats, sellResult),
          SimulationMode.rotation => _buildRotationMode(
            rotationOriginStats,
            rotationTargetStats,
            rotationResult,
          ),
        },
      ],
    );
  }

  List<Widget> _buildBuyMode(CoinStats stats, BuySimulationResult result) {
    return <Widget>[
      CardPanel(
        title: 'Datos de entrada',
        subtitle:
            'Ajusta entradas para simular compra sin mover fondos reales.',
        child: Column(
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: _buyCoin,
              decoration: const InputDecoration(
                labelText: 'Moneda',
                border: OutlineInputBorder(),
              ),
              items: widget.coins
                  .map(
                    (String coin) => DropdownMenuItem<String>(
                      value: coin,
                      child: Text(coin),
                    ),
                  )
                  .toList(),
              onChanged: (String? value) {
                setState(() {
                  _buyCoin = value ?? _buyCoin;
                  _setPriceFromCoin(_buyPriceController, _buyCoin);
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _buyGrossAmountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Monto bruto MXN',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final double amount in _quickAmountValues)
                  ActionChip(
                    label: Text(moneyShort(amount)),
                    onPressed: () {
                      setState(
                        () => _buyGrossAmountController.text = compact(amount),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _buyPriceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Precio de compra MXN',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _buyFeeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Comisión compra %',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _buySellFeeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Comisión venta %',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            InfoLine('Cantidad actual', crypto(stats.quantity)),
            InfoLine('Costo base actual', money(stats.costBase)),
            InfoLine('Precio actual', money(stats.currentPrice)),
          ],
        ),
      ),
      CardPanel(
        title: 'Resultado esperado',
        subtitle: result.valid
            ? 'Proyección de compra, no movimiento real.'
            : result.invalidReason,
        child: result.valid
            ? Column(
                children: <Widget>[
                  InfoLine(
                    'Cantidad estimada comprada',
                    crypto(result.quantityBought),
                  ),
                  InfoLine('Comisión estimada', money(result.buyCommission)),
                  InfoLine('Capital neto usado', money(result.netBuyCapital)),
                  InfoLine(
                    'Cantidad total después',
                    crypto(result.quantityAfter),
                    emphasized: true,
                  ),
                  InfoLine('Costo base después', money(result.costBaseAfter)),
                  InfoLine('Promedio actual', money(result.avgCurrent)),
                  InfoLine(
                    'Promedio después',
                    money(result.avgAfter),
                    emphasized: true,
                  ),
                  InfoLine(
                    'Diferencia de promedio',
                    _moneyAndPercent(
                      result.avgDifferenceMxn,
                      result.avgDifferencePct,
                    ),
                  ),
                  InfoLine(
                    'Break even neto después',
                    money(result.breakEvenNetAfter),
                    emphasized: true,
                  ),
                  InfoLine(
                    'Distancia al break even neto',
                    _percentOrNa(result.distanceToBreakEvenPct),
                    valueColor: result.distanceToBreakEvenPct == null
                        ? null
                        : pnlColor(-result.distanceToBreakEvenPct!),
                  ),
                ],
              )
            : const SizedBox.shrink(),
      ),
      CardPanel(
        title: 'Impacto táctico',
        subtitle: result.valid
            ? 'Lectura compacta del escenario de entrada.'
            : result.invalidReason,
        child: result.valid
            ? Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  MiniMetric(label: 'Cantidad estimada', value: crypto(result.quantityBought)),
                  MiniMetric(label: 'Costo después', value: money(result.costBaseAfter)),
                  MiniMetric(label: 'Break even', value: money(result.breakEvenNetAfter)),
                  MiniMetric(label: 'Comisión total', value: money(result.buyCommission)),
                ],
              )
            : const SizedBox.shrink(),
      ),
    ];
  }

  List<Widget> _buildSellMode(CoinStats stats, SellSimulationResult result) {
    return <Widget>[
      CardPanel(
        title: 'Datos de entrada',
        subtitle:
            'Simula salida parcial o total sin registrar movimiento real.',
        child: Column(
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: _sellCoin,
              decoration: const InputDecoration(
                labelText: 'Moneda',
                border: OutlineInputBorder(),
              ),
              items: widget.coins
                  .map(
                    (String coin) => DropdownMenuItem<String>(
                      value: coin,
                      child: Text(coin),
                    ),
                  )
                  .toList(),
              onChanged: (String? value) {
                setState(() {
                  _sellCoin = value ?? _sellCoin;
                  _setPriceFromCoin(_sellPriceController, _sellCoin);
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sellPriceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Precio de venta MXN',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sellFeeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Comisión venta %',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<SimulationSellMethod>(
              segments: const <ButtonSegment<SimulationSellMethod>>[
                ButtonSegment<SimulationSellMethod>(
                  value: SimulationSellMethod.percent,
                  label: Text('% posición'),
                ),
                ButtonSegment<SimulationSellMethod>(
                  value: SimulationSellMethod.quantity,
                  label: Text('Cantidad'),
                ),
                ButtonSegment<SimulationSellMethod>(
                  value: SimulationSellMethod.grossAmount,
                  label: Text('Monto MXN'),
                ),
              ],
              selected: <SimulationSellMethod>{_sellMethod},
              onSelectionChanged: (Set<SimulationSellMethod> value) {
                setState(() => _sellMethod = value.first);
              },
            ),
            const SizedBox(height: 12),
            if (_sellMethod == SimulationSellMethod.percent) ...<Widget>[
              TextField(
                controller: _sellPercentController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Porcentaje de posición %',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final double value in _quickPercentValues)
                    ActionChip(
                      label: Text(pct(value)),
                      onPressed: () {
                        setState(
                          () => _sellPercentController.text = compact(value),
                        );
                      },
                    ),
                ],
              ),
            ],
            if (_sellMethod == SimulationSellMethod.quantity)
              TextField(
                controller: _sellQuantityController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Cantidad cripto',
                  border: OutlineInputBorder(),
                ),
              ),
            if (_sellMethod == SimulationSellMethod.grossAmount)
              TextField(
                controller: _sellGrossController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Monto bruto MXN',
                  border: OutlineInputBorder(),
                ),
              ),
            const SizedBox(height: 10),
            InfoLine('Cantidad disponible', crypto(stats.quantity)),
            InfoLine('Costo base actual', money(stats.costBase)),
            InfoLine('Promedio actual', money(stats.avgPrice)),
          ],
        ),
      ),
      CardPanel(
        title: 'Resultado esperado',
        subtitle: result.valid
            ? 'Proyección de venta, no movimiento real.'
            : result.invalidReason,
        child: result.valid
            ? Column(
                children: <Widget>[
                  InfoLine(
                    'Cantidad a vender',
                    crypto(result.quantitySold),
                    emphasized: true,
                  ),
                  InfoLine('Venta bruta', money(result.grossSale)),
                  InfoLine('Comisión', money(result.sellCommission)),
                  InfoLine('Neto recibido', money(result.netReceived)),
                  InfoLine(
                    'Costo promedio removido',
                    money(result.removedAverageCost),
                  ),
                  InfoLine(
                    'P&L realizado estimado',
                    money(result.realizedPLEstimate),
                    valueColor: pnlColor(result.realizedPLEstimate),
                    emphasized: true,
                  ),
                  InfoLine(
                    'Cantidad restante',
                    crypto(result.quantityRemaining),
                  ),
                  InfoLine(
                    'Costo base restante',
                    money(result.costBaseRemaining),
                  ),
                  InfoLine('Promedio restante', money(result.avgRemaining)),
                  if (result.warnings.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    ...result.warnings.map(_warningLine),
                  ],
                ],
              )
            : const SizedBox.shrink(),
      ),
      CardPanel(
        title: 'Impacto táctico',
        subtitle: result.valid
            ? 'Salida neta y efecto realizado del escenario.'
            : result.invalidReason,
        child: result.valid
            ? Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  MiniMetric(label: 'Neto recibido', value: money(result.netReceived)),
                  MiniMetric(
                    label: 'P&L realizado',
                    value: money(result.realizedPLEstimate),
                    color: pnlColor(result.realizedPLEstimate),
                  ),
                  MiniMetric(label: 'Cantidad restante', value: crypto(result.quantityRemaining)),
                  MiniMetric(label: 'Comisión total', value: money(result.sellCommission)),
                ],
              )
            : const SizedBox.shrink(),
      ),
    ];
  }

  List<Widget> _buildRotationMode(
    CoinStats originStats,
    CoinStats targetStats,
    RotationSimulationResult result,
  ) {
    return <Widget>[
      CardPanel(
        title: 'Datos de entrada',
        subtitle: 'Modela venta de origen y compra de destino.',
        child: Column(
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: _rotationOriginCoin,
              decoration: const InputDecoration(
                labelText: 'Moneda origen',
                border: OutlineInputBorder(),
              ),
              items: widget.coins
                  .map(
                    (String coin) => DropdownMenuItem<String>(
                      value: coin,
                      child: Text(coin),
                    ),
                  )
                  .toList(),
              onChanged: (String? value) {
                setState(() {
                  _rotationOriginCoin = value ?? _rotationOriginCoin;
                  _setPriceFromCoin(
                    _rotationOriginPriceController,
                    _rotationOriginCoin,
                  );
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _rotationTargetCoin,
              decoration: const InputDecoration(
                labelText: 'Moneda destino',
                border: OutlineInputBorder(),
              ),
              items: widget.coins
                  .map(
                    (String coin) => DropdownMenuItem<String>(
                      value: coin,
                      child: Text(coin),
                    ),
                  )
                  .toList(),
              onChanged: (String? value) {
                setState(() {
                  _rotationTargetCoin = value ?? _rotationTargetCoin;
                  _setPriceFromCoin(
                    _rotationTargetPriceController,
                    _rotationTargetCoin,
                  );
                });
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: () {
                    setState(() {
                      _rotationOriginCoin = 'LINK';
                      _rotationTargetCoin = 'BTC';
                      _setPriceFromCoin(
                        _rotationOriginPriceController,
                        _rotationOriginCoin,
                      );
                      _setPriceFromCoin(
                        _rotationTargetPriceController,
                        _rotationTargetCoin,
                      );
                    });
                  },
                  child: const Text('LINK → BTC'),
                ),
                FilledButton.tonal(
                  onPressed: () {
                    setState(() {
                      _rotationOriginCoin = 'UNI';
                      _rotationTargetCoin = 'BTC';
                      _setPriceFromCoin(
                        _rotationOriginPriceController,
                        _rotationOriginCoin,
                      );
                      _setPriceFromCoin(
                        _rotationTargetPriceController,
                        _rotationTargetCoin,
                      );
                    });
                  },
                  child: const Text('UNI → BTC'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rotationOriginPriceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Precio $_rotationOriginCoin MXN',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rotationTargetPriceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Precio $_rotationTargetCoin MXN',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rotationSellFeeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Comisión venta $_rotationOriginCoin %',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rotationBuyFeeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Comisión compra $_rotationTargetCoin %',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<SimulationRotationMethod>(
              segments: const <ButtonSegment<SimulationRotationMethod>>[
                ButtonSegment<SimulationRotationMethod>(
                  value: SimulationRotationMethod.percent,
                  label: Text('% origen'),
                ),
                ButtonSegment<SimulationRotationMethod>(
                  value: SimulationRotationMethod.quantity,
                  label: Text('Cantidad'),
                ),
                ButtonSegment<SimulationRotationMethod>(
                  value: SimulationRotationMethod.grossAmount,
                  label: Text('Monto MXN'),
                ),
              ],
              selected: <SimulationRotationMethod>{_rotationMethod},
              onSelectionChanged: (Set<SimulationRotationMethod> value) {
                setState(() => _rotationMethod = value.first);
              },
            ),
            const SizedBox(height: 12),
            if (_rotationMethod ==
                SimulationRotationMethod.percent) ...<Widget>[
              TextField(
                controller: _rotationPercentController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Porcentaje $_rotationOriginCoin %',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final double value in _quickPercentValues)
                    ActionChip(
                      label: Text(pct(value)),
                      onPressed: () {
                        setState(
                          () =>
                              _rotationPercentController.text = compact(value),
                        );
                      },
                    ),
                ],
              ),
            ],
            if (_rotationMethod == SimulationRotationMethod.quantity)
              TextField(
                controller: _rotationQuantityController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Cantidad $_rotationOriginCoin',
                  border: const OutlineInputBorder(),
                ),
              ),
            if (_rotationMethod == SimulationRotationMethod.grossAmount)
              TextField(
                controller: _rotationGrossController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Monto bruto MXN',
                  border: OutlineInputBorder(),
                ),
              ),
            const SizedBox(height: 10),
            InfoLine(
              '$_rotationOriginCoin disponible',
              crypto(originStats.quantity),
            ),
            InfoLine(
              '$_rotationTargetCoin actual',
              crypto(targetStats.quantity),
            ),
          ],
        ),
      ),
      CardPanel(
        title: 'Resumen de rotación',
        subtitle: result.valid
            ? 'Ruta: $_rotationOriginCoin → $_rotationTargetCoin'
            : result.invalidReason,
        child: result.valid
            ? Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  MiniMetric(
                    label: 'Ruta',
                    value: '$_rotationOriginCoin → $_rotationTargetCoin',
                  ),
                  MiniMetric(
                    label: 'Pérdida realizada estimada',
                    value: money(result.originRealizedPLEstimate),
                    color: pnlColor(result.originRealizedPLEstimate),
                  ),
                  MiniMetric(
                    label: 'Comisiones totales',
                    value: money(result.totalCommissions),
                  ),
                  MiniMetric(
                    label: '$_rotationTargetCoin comprado',
                    value: crypto(result.targetQuantityBought),
                  ),
                  MiniMetric(
                    label: '$_rotationTargetCoin después',
                    value: crypto(result.targetBalanceAfter),
                  ),
                  MiniMetric(
                    label: 'Promedio $_rotationTargetCoin antes',
                    value: money(result.targetAvgBefore),
                  ),
                  MiniMetric(
                    label: 'Promedio $_rotationTargetCoin después',
                    value: money(result.targetAvgAfter),
                  ),
                  MiniMetric(
                    label: 'Break even $_rotationTargetCoin después',
                    value: money(result.targetBreakEvenAfter),
                  ),
                  MiniMetric(
                    label: 'Faltante a break even',
                    value: _percentOrNa(result.targetDistanceToBreakEvenPct),
                    color: result.targetDistanceToBreakEvenPct == null
                        ? null
                        : pnlColor(-result.targetDistanceToBreakEvenPct!),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (result.warnings.isNotEmpty) ...<Widget>[
                    ...result.warnings.map(_warningLine),
                  ],
                ],
              ),
      ),
      CardPanel(
        title: 'Impacto táctico',
        subtitle: result.valid
            ? 'Proyección de rotación, no movimiento real.'
            : result.invalidReason,
        child: result.valid
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Venta simulada de $_rotationOriginCoin',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  InfoLine(
                    '$_rotationOriginCoin vendido',
                    crypto(result.originQuantitySold),
                  ),
                  InfoLine(
                    'Venta bruta $_rotationOriginCoin',
                    money(result.originGrossSale),
                  ),
                  InfoLine(
                    'Comisión venta $_rotationOriginCoin',
                    money(result.originSellCommission),
                  ),
                  InfoLine('Neto disponible', money(result.netAvailable)),
                  InfoLine(
                    'Costo base removido $_rotationOriginCoin',
                    money(result.originRemovedAverageCost),
                  ),
                  InfoLine(
                    'Promedio $_rotationOriginCoin removido',
                    '\$${result.originRemovedAveragePrice.toStringAsFixed(2)}'
                    '/$_rotationOriginCoin',
                  ),
                  InfoLine(
                    'P&L realizado estimado',
                    money(result.originRealizedPLEstimate),
                    valueColor: pnlColor(result.originRealizedPLEstimate),
                    emphasized: true,
                  ),
                  InfoLine(
                    '$_rotationOriginCoin restante',
                    crypto(result.originQuantityRemaining),
                  ),
                  InfoLine(
                    'Costo base restante $_rotationOriginCoin',
                    money(result.originCostBaseRemaining),
                  ),
                  InfoLine(
                    'Promedio restante $_rotationOriginCoin',
                    money(result.originAvgRemaining),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Compra simulada de $_rotationTargetCoin',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  InfoLine(
                    'Comisión compra $_rotationTargetCoin',
                    money(result.targetBuyCommission),
                  ),
                  InfoLine(
                    'Capital convertido $_rotationTargetCoin',
                    money(result.targetConvertedCapital),
                  ),
                  InfoLine(
                    '$_rotationTargetCoin comprado',
                    crypto(result.targetQuantityBought),
                  ),
                  InfoLine(
                    '$_rotationTargetCoin después',
                    crypto(result.targetBalanceAfter),
                  ),
                  InfoLine(
                    'Promedio $_rotationTargetCoin antes',
                    money(result.targetAvgBefore),
                  ),
                  InfoLine(
                    'Promedio $_rotationTargetCoin después',
                    money(result.targetAvgAfter),
                    emphasized: true,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Resultado de rotación',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  InfoLine(
                    'Costo base $_rotationTargetCoin después',
                    money(result.targetCostBaseAfter),
                  ),
                  InfoLine(
                    'Break even $_rotationTargetCoin después',
                    money(result.targetBreakEvenAfter),
                  ),
                  InfoLine(
                    'Faltante a break even',
                    _percentOrNa(result.targetDistanceToBreakEvenPct),
                    valueColor: result.targetDistanceToBreakEvenPct == null
                        ? null
                        : pnlColor(-result.targetDistanceToBreakEvenPct!),
                  ),
                  InfoLine(
                    'Comisiones totales',
                    money(result.totalCommissions),
                    emphasized: true,
                  ),
                  if (result.warnings.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    ...result.warnings.map(_warningLine),
                  ],
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (result.warnings.isNotEmpty) ...<Widget>[
                    ...result.warnings.map(_warningLine),
                  ],
                ],
              ),
      ),
    ];
  }

  BuySimulationResult _calculateBuy(CoinStats stats) {
    final double grossAmount = _parseInput(_buyGrossAmountController);
    final double buyPrice = _parseInput(_buyPriceController);
    final double buyFeePercent = _parseInput(_buyFeeController);
    final double sellFeePercent = _parseInput(_buySellFeeController);

    if (grossAmount <= 0) {
      return BuySimulationResult.invalid(
        'Ingresa un monto bruto MXN mayor a 0.',
      );
    }

    if (buyPrice <= 0) {
      return BuySimulationResult.invalid(
        'Ingresa un precio de compra MXN mayor a 0.',
      );
    }

    if (buyFeePercent < 0 || sellFeePercent < 0 || sellFeePercent >= 100) {
      return BuySimulationResult.invalid(
        'Verifica comisiones válidas (0 a 99.99%).',
      );
    }

    final double buyCommission = grossAmount * buyFeePercent / 100;
    final double netBuyCapital = grossAmount - buyCommission;
    final double quantityBought = netBuyCapital / buyPrice;
    final double quantityAfter = stats.quantity + quantityBought;
    final double costBaseAfter = stats.costBase + grossAmount;
    final double avgCurrent = stats.quantity > 0
        ? stats.costBase / stats.quantity
        : 0.0;
    final double avgAfter = quantityAfter > 0
        ? costBaseAfter / quantityAfter
        : 0.0;
    final double avgDifferenceMxn = avgAfter - avgCurrent;
    final double? avgDifferencePct = avgCurrent > 0
        ? ((avgDifferenceMxn / avgCurrent) * 100)
        : null;
    final double breakEvenNetAfter = avgAfter / (1 - (sellFeePercent / 100));
    final double? distanceToBreakEvenPct = stats.currentPrice > 0
        ? (((breakEvenNetAfter - stats.currentPrice) / stats.currentPrice) *
              100)
        : null;

    return BuySimulationResult(
      valid: true,
      invalidReason: '',
      quantityBought: quantityBought,
      buyCommission: buyCommission,
      netBuyCapital: netBuyCapital,
      quantityAfter: quantityAfter,
      costBaseAfter: costBaseAfter,
      avgCurrent: avgCurrent,
      avgAfter: avgAfter,
      avgDifferenceMxn: avgDifferenceMxn,
      avgDifferencePct: avgDifferencePct,
      breakEvenNetAfter: breakEvenNetAfter,
      distanceToBreakEvenPct: distanceToBreakEvenPct,
    );
  }

  SellSimulationResult _calculateSell(CoinStats stats) {
    final double sellPrice = _parseInput(_sellPriceController);
    final double sellFeePercent = _parseInput(_sellFeeController);

    if (sellPrice <= 0) {
      return SellSimulationResult.invalid(
        'Ingresa un precio de venta MXN mayor a 0.',
      );
    }

    if (sellFeePercent < 0 || sellFeePercent >= 100) {
      return SellSimulationResult.invalid(
        'Ingresa una comisión de venta válida (0 a 99.99%).',
      );
    }

    double requestedQuantity = 0.0;
    if (_sellMethod == SimulationSellMethod.percent) {
      final double percent = _parseInput(_sellPercentController);
      if (percent <= 0) {
        return SellSimulationResult.invalid(
          'Ingresa un porcentaje de posición mayor a 0.',
        );
      }
      requestedQuantity = stats.quantity * (percent / 100);
    } else if (_sellMethod == SimulationSellMethod.quantity) {
      requestedQuantity = _parseInput(_sellQuantityController);
      if (requestedQuantity <= 0) {
        return SellSimulationResult.invalid(
          'Ingresa una cantidad cripto mayor a 0.',
        );
      }
    } else {
      final double grossAmount = _parseInput(_sellGrossController);
      if (grossAmount <= 0) {
        return SellSimulationResult.invalid(
          'Ingresa un monto bruto MXN mayor a 0.',
        );
      }
      requestedQuantity = grossAmount / sellPrice;
    }

    final List<String> warnings = <String>[];
    if (requestedQuantity > stats.quantity) {
      warnings.add('Advertencia: intenta vender más de lo disponible.');
    }

    final double quantitySold = math.min(requestedQuantity, stats.quantity);
    if (quantitySold <= 0) {
      return SellSimulationResult.invalid(
        'No hay cantidad disponible para vender.',
      );
    }

    final double grossSale = quantitySold * sellPrice;
    final double sellCommission = grossSale * sellFeePercent / 100;
    final double netReceived = grossSale - sellCommission;
    final double avgCurrent = stats.quantity > 0
        ? stats.costBase / stats.quantity
        : 0.0;
    final double removedAverageCost = avgCurrent * quantitySold;
    final double realizedPLEstimate = netReceived - removedAverageCost;
    double quantityRemaining = stats.quantity - quantitySold;
    double costBaseRemaining = stats.costBase - removedAverageCost;

    if (quantityRemaining.abs() < 0.0000000001) {
      quantityRemaining = 0.0;
      costBaseRemaining = 0.0;
    }
    if (costBaseRemaining.abs() < 0.00000001) costBaseRemaining = 0.0;

    final double avgRemaining = quantityRemaining > 0
        ? costBaseRemaining / quantityRemaining
        : 0.0;

    if (realizedPLEstimate < 0) {
      warnings.add('Advertencia: esta venta cristaliza pérdida estimada.');
    }

    return SellSimulationResult(
      valid: true,
      invalidReason: '',
      warnings: warnings,
      quantitySold: quantitySold,
      grossSale: grossSale,
      sellCommission: sellCommission,
      netReceived: netReceived,
      removedAverageCost: removedAverageCost,
      realizedPLEstimate: realizedPLEstimate,
      quantityRemaining: quantityRemaining,
      costBaseRemaining: costBaseRemaining,
      avgRemaining: avgRemaining,
    );
  }

  RotationSimulationResult _calculateRotation(
    CoinStats originStats,
    CoinStats targetStats,
  ) {
    final List<String> warnings = <String>[];
    final double originPrice = _parseInput(_rotationOriginPriceController);
    final double targetPrice = _parseInput(_rotationTargetPriceController);
    final double sellFeePercent = _parseInput(_rotationSellFeeController);
    final double buyFeePercent = _parseInput(_rotationBuyFeeController);
    final double targetExitFeePercent = widget.targetExitFeePercent;

    if (_rotationOriginCoin == _rotationTargetCoin) {
      warnings.add('Advertencia: origen y destino son iguales.');
    }
    if (originPrice <= 0 || targetPrice <= 0) {
      warnings.add('Advertencia: falta precio origen/destino.');
    }
    if (sellFeePercent < 0 || sellFeePercent >= 100) {
      return RotationSimulationResult.invalid(
        'Ingresa una comisión de venta origen válida (0 a 99.99%).',
        warnings,
      );
    }
    if (buyFeePercent < 0 || buyFeePercent >= 100) {
      return RotationSimulationResult.invalid(
        'Ingresa una comisión de compra destino válida (0 a 99.99%).',
        warnings,
      );
    }
    if (targetExitFeePercent < 0 || targetExitFeePercent >= 100) {
      return RotationSimulationResult.invalid(
        'Configura una comisión de salida destino válida (0 a 99.99%).',
        warnings,
      );
    }

    if (_rotationOriginCoin == _rotationTargetCoin) {
      return RotationSimulationResult.invalid(
        'Elige monedas distintas para rotación.',
        warnings,
      );
    }
    if (originPrice <= 0 || targetPrice <= 0) {
      return RotationSimulationResult.invalid(
        'Se requiere precio origen y destino mayor a 0.',
        warnings,
      );
    }

    double requestedOriginQuantity = 0.0;
    if (_rotationMethod == SimulationRotationMethod.percent) {
      final double percent = _parseInput(_rotationPercentController);
      if (percent <= 0) {
        return RotationSimulationResult.invalid(
          'Ingresa un porcentaje de origen mayor a 0.',
          warnings,
        );
      }
      requestedOriginQuantity = originStats.quantity * (percent / 100);
    } else if (_rotationMethod == SimulationRotationMethod.quantity) {
      requestedOriginQuantity = _parseInput(_rotationQuantityController);
      if (requestedOriginQuantity <= 0) {
        return RotationSimulationResult.invalid(
          'Ingresa una cantidad cripto origen mayor a 0.',
          warnings,
        );
      }
    } else {
      final double grossAmount = _parseInput(_rotationGrossController);
      if (grossAmount <= 0) {
        return RotationSimulationResult.invalid(
          'Ingresa un monto bruto MXN mayor a 0.',
          warnings,
        );
      }
      requestedOriginQuantity = grossAmount / originPrice;
    }

    if (requestedOriginQuantity > originStats.quantity) {
      warnings.add('Advertencia: intenta rotar más de lo disponible.');
    }

    final double originQuantitySold = math.min(
      requestedOriginQuantity,
      originStats.quantity,
    );
    if (originQuantitySold <= 0) {
      return RotationSimulationResult.invalid(
        'No hay cantidad disponible en moneda origen para rotar.',
        warnings,
      );
    }

    final double originGrossSale = originQuantitySold * originPrice;
    final double originSellCommission = originGrossSale * sellFeePercent / 100;
    final double netAvailable = originGrossSale - originSellCommission;
    final double originAvgCurrent = originStats.quantity > 0
        ? originStats.costBase / originStats.quantity
        : 0.0;
    final double originRemovedAverageCost =
        originAvgCurrent * originQuantitySold;
    final double originRemovedAveragePrice = originQuantitySold > 0
        ? originRemovedAverageCost / originQuantitySold
        : 0.0;
    final double originRealizedPLEstimate =
        netAvailable - originRemovedAverageCost;
    double originQuantityRemaining = originStats.quantity - originQuantitySold;
    double originCostBaseRemaining =
        originStats.costBase - originRemovedAverageCost;

    if (originQuantityRemaining.abs() < 0.0000000001) {
      originQuantityRemaining = 0.0;
      originCostBaseRemaining = 0.0;
    }
    if (originCostBaseRemaining.abs() < 0.00000001) {
      originCostBaseRemaining = 0.0;
    }

    final double originAvgRemaining = originQuantityRemaining > 0
        ? originCostBaseRemaining / originQuantityRemaining
        : 0.0;

    final double targetBuyCommission = netAvailable * buyFeePercent / 100;
    final double targetConvertedCapital = netAvailable - targetBuyCommission;
    final double targetQuantityBought = targetConvertedCapital / targetPrice;
    final double targetBalanceAfter =
        targetStats.quantity + targetQuantityBought;
    final double targetCostBaseAfter = targetStats.costBase + netAvailable;
    final double targetAvgBefore = targetStats.quantity > 0
        ? targetStats.costBase / targetStats.quantity
        : 0.0;
    final double targetAvgAfter = targetBalanceAfter > 0
        ? targetCostBaseAfter / targetBalanceAfter
        : 0.0;
    final double targetBreakEvenAfter =
        targetAvgAfter / (1 - (targetExitFeePercent / 100));
    final double? targetDistanceToBreakEvenPct = targetPrice > 0
        ? ((targetBreakEvenAfter - targetPrice) / targetPrice) * 100
        : null;
    final double totalCommissions = originSellCommission + targetBuyCommission;

    if (originRealizedPLEstimate < 0) {
      warnings.add('Advertencia: esta rotación cristaliza pérdida estimada.');
    }

    return RotationSimulationResult(
      valid: true,
      invalidReason: '',
      warnings: warnings,
      originQuantitySold: originQuantitySold,
      originGrossSale: originGrossSale,
      originSellCommission: originSellCommission,
      netAvailable: netAvailable,
      originRemovedAverageCost: originRemovedAverageCost,
      originRemovedAveragePrice: originRemovedAveragePrice,
      originRealizedPLEstimate: originRealizedPLEstimate,
      originQuantityRemaining: originQuantityRemaining,
      originCostBaseRemaining: originCostBaseRemaining,
      originAvgRemaining: originAvgRemaining,
      targetBuyCommission: targetBuyCommission,
      targetConvertedCapital: targetConvertedCapital,
      targetQuantityBought: targetQuantityBought,
      targetBalanceAfter: targetBalanceAfter,
      targetCostBaseAfter: targetCostBaseAfter,
      targetAvgBefore: targetAvgBefore,
      targetAvgAfter: targetAvgAfter,
      targetBreakEvenAfter: targetBreakEvenAfter,
      targetDistanceToBreakEvenPct: targetDistanceToBreakEvenPct,
      totalCommissions: totalCommissions,
    );
  }

  CoinStats _statsFor(String coin) =>
      widget.stats[coin] ?? CoinStats(coin: coin);

  double _parseInput(TextEditingController controller) {
    final String raw = controller.text.trim().replaceAll(',', '');
    return double.tryParse(raw) ?? 0.0;
  }

  void _seedPriceIfEmpty(TextEditingController controller, double price) {
    if (controller.text.trim().isNotEmpty || price <= 0) return;
    controller.text = compact(price);
  }

  void _setPriceFromCoin(TextEditingController controller, String coin) {
    final double price = _statsFor(coin).currentPrice;
    controller.text = price > 0 ? compact(price) : '';
  }

  void _ensureSelectedCoins() {
    if (widget.coins.isEmpty) return;
    if (!widget.coins.contains(_buyCoin)) _buyCoin = widget.coins.first;
    if (!widget.coins.contains(_sellCoin)) _sellCoin = widget.coins.first;
    if (!widget.coins.contains(_rotationOriginCoin)) {
      _rotationOriginCoin = widget.coins.first;
    }
    if (!widget.coins.contains(_rotationTargetCoin)) {
      _rotationTargetCoin = widget.coins.first;
    }
  }

  String _percentOrNa(double? value) {
    if (value == null) return 'N/A';
    return pct(value);
  }

  String _moneyAndPercent(double value, double? percentValue) {
    if (percentValue == null) return '${money(value)} (N/A)';
    return '${money(value)} (${pct(percentValue)})';
  }

  Widget _warningLine(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.amber.shade900,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static const List<double> _quickAmountValues = <double>[
    500,
    1000,
    3000,
    5000,
    8000,
    15000,
  ];

  static const List<double> _quickPercentValues = <double>[25, 50, 75, 100];
}

class BuySimulationResult {
  final bool valid;
  final String invalidReason;
  final double quantityBought;
  final double buyCommission;
  final double netBuyCapital;
  final double quantityAfter;
  final double costBaseAfter;
  final double avgCurrent;
  final double avgAfter;
  final double avgDifferenceMxn;
  final double? avgDifferencePct;
  final double breakEvenNetAfter;
  final double? distanceToBreakEvenPct;

  BuySimulationResult({
    required this.valid,
    required this.invalidReason,
    required this.quantityBought,
    required this.buyCommission,
    required this.netBuyCapital,
    required this.quantityAfter,
    required this.costBaseAfter,
    required this.avgCurrent,
    required this.avgAfter,
    required this.avgDifferenceMxn,
    required this.avgDifferencePct,
    required this.breakEvenNetAfter,
    required this.distanceToBreakEvenPct,
  });

  factory BuySimulationResult.invalid(String reason) => BuySimulationResult(
    valid: false,
    invalidReason: reason,
    quantityBought: 0.0,
    buyCommission: 0.0,
    netBuyCapital: 0.0,
    quantityAfter: 0.0,
    costBaseAfter: 0.0,
    avgCurrent: 0.0,
    avgAfter: 0.0,
    avgDifferenceMxn: 0.0,
    avgDifferencePct: null,
    breakEvenNetAfter: 0.0,
    distanceToBreakEvenPct: null,
  );
}

class SellSimulationResult {
  final bool valid;
  final String invalidReason;
  final List<String> warnings;
  final double quantitySold;
  final double grossSale;
  final double sellCommission;
  final double netReceived;
  final double removedAverageCost;
  final double realizedPLEstimate;
  final double quantityRemaining;
  final double costBaseRemaining;
  final double avgRemaining;

  SellSimulationResult({
    required this.valid,
    required this.invalidReason,
    required this.warnings,
    required this.quantitySold,
    required this.grossSale,
    required this.sellCommission,
    required this.netReceived,
    required this.removedAverageCost,
    required this.realizedPLEstimate,
    required this.quantityRemaining,
    required this.costBaseRemaining,
    required this.avgRemaining,
  });

  factory SellSimulationResult.invalid(String reason) => SellSimulationResult(
    valid: false,
    invalidReason: reason,
    warnings: const <String>[],
    quantitySold: 0.0,
    grossSale: 0.0,
    sellCommission: 0.0,
    netReceived: 0.0,
    removedAverageCost: 0.0,
    realizedPLEstimate: 0.0,
    quantityRemaining: 0.0,
    costBaseRemaining: 0.0,
    avgRemaining: 0.0,
  );
}

class RotationSimulationResult {
  final bool valid;
  final String invalidReason;
  final List<String> warnings;
  final double originQuantitySold;
  final double originGrossSale;
  final double originSellCommission;
  final double netAvailable;
  final double originRemovedAverageCost;
  final double originRemovedAveragePrice;
  final double originRealizedPLEstimate;
  final double originQuantityRemaining;
  final double originCostBaseRemaining;
  final double originAvgRemaining;
  final double targetBuyCommission;
  final double targetConvertedCapital;
  final double targetQuantityBought;
  final double targetBalanceAfter;
  final double targetCostBaseAfter;
  final double targetAvgBefore;
  final double targetAvgAfter;
  final double targetBreakEvenAfter;
  final double? targetDistanceToBreakEvenPct;
  final double totalCommissions;

  RotationSimulationResult({
    required this.valid,
    required this.invalidReason,
    required this.warnings,
    required this.originQuantitySold,
    required this.originGrossSale,
    required this.originSellCommission,
    required this.netAvailable,
    required this.originRemovedAverageCost,
    required this.originRemovedAveragePrice,
    required this.originRealizedPLEstimate,
    required this.originQuantityRemaining,
    required this.originCostBaseRemaining,
    required this.originAvgRemaining,
    required this.targetBuyCommission,
    required this.targetConvertedCapital,
    required this.targetQuantityBought,
    required this.targetBalanceAfter,
    required this.targetCostBaseAfter,
    required this.targetAvgBefore,
    required this.targetAvgAfter,
    required this.targetBreakEvenAfter,
    required this.targetDistanceToBreakEvenPct,
    required this.totalCommissions,
  });

  factory RotationSimulationResult.invalid(
    String reason,
    List<String> warnings,
  ) => RotationSimulationResult(
    valid: false,
    invalidReason: reason,
    warnings: warnings,
    originQuantitySold: 0.0,
    originGrossSale: 0.0,
    originSellCommission: 0.0,
    netAvailable: 0.0,
    originRemovedAverageCost: 0.0,
    originRemovedAveragePrice: 0.0,
    originRealizedPLEstimate: 0.0,
    originQuantityRemaining: 0.0,
    originCostBaseRemaining: 0.0,
    originAvgRemaining: 0.0,
    targetBuyCommission: 0.0,
    targetConvertedCapital: 0.0,
    targetQuantityBought: 0.0,
    targetBalanceAfter: 0.0,
    targetCostBaseAfter: 0.0,
    targetAvgBefore: 0.0,
    targetAvgAfter: 0.0,
    targetBreakEvenAfter: 0.0,
    targetDistanceToBreakEvenPct: null,
    totalCommissions: 0.0,
  );
}

class CoinsTab extends StatelessWidget {
  final List<String> coins;
  final Map<String, CoinStats> stats;
  final double sellFeePercent;
  final void Function(String coin) onEditPrice;
  final void Function(CoinStats stats) onDetails;

  const CoinsTab({
    super.key,
    required this.coins,
    required this.stats,
    required this.sellFeePercent,
    required this.onEditPrice,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final int activeCount = coins
        .where((String coin) => (stats[coin]?.quantity ?? 0) > 0)
        .length;
    final int pricedCount = coins
        .where((String coin) => (stats[coin]?.currentPrice ?? 0) > 0)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: <Widget>[
        PremiumDashboardHero(
          title: 'Monedas',
          subtitle: 'Precios y lectura general de tus posiciones',
          icon: Icons.token_outlined,
          metrics: <PremiumMetricData>[
            PremiumMetricData(
              label: 'Activas',
              value: '$activeCount / ${coins.length}',
              icon: Icons.account_balance_wallet_outlined,
            ),
            PremiumMetricData(
              label: 'Actualizadas',
              value: '$pricedCount precios',
              icon: Icons.price_check_outlined,
            ),
            PremiumMetricData(
              label: 'Fuente',
              value: 'CoinGecko',
              icon: Icons.cloud_outlined,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _CommandSection(
          title: 'Paneles por moneda',
          children: coins.map((String coin) {
            final CoinStats stat = stats[coin] ?? CoinStats(coin: coin);
            return PremiumCoinCard(
              stat: stat,
              sellFeePercent: sellFeePercent,
              onEditPrice: () => onEditPrice(coin),
              onDetails: () => onDetails(stat),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class PremiumCoinCard extends StatelessWidget {
  final CoinStats stat;
  final double sellFeePercent;
  final VoidCallback onEditPrice;
  final VoidCallback onDetails;

  const PremiumCoinCard({
    super.key,
    required this.stat,
    required this.sellFeePercent,
    required this.onEditPrice,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasPosition = stat.quantity > 0;
    final bool recovered = stat.isAtOrAboveNetBreakEven(sellFeePercent);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CoinLogo(coin: stat.coin, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        hasPosition ? 'Posición abierta' : 'Sin posición',
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        hasPosition
                            ? '${crypto(stat.quantity)} en cartera'
                            : 'Precio listo para seguimiento',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Editar precio',
                  onPressed: onEditPrice,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                MiniMetric(label: 'Precio', value: money(stat.currentPrice)),
                MiniMetric(label: 'Valor actual', value: money(stat.currentValue)),
                MiniMetric(label: 'Resultado', value: money(stat.unrealizedPL), color: pnlColor(stat.unrealizedPL)),
                MiniMetric(label: 'Break even', value: money(stat.netBreakEvenPrice(sellFeePercent))),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                StatusPill(
                  label: hasPosition
                      ? (recovered ? 'Arriba del equilibrio' : 'Vigilar')
                      : 'Limpia',
                  positive: !hasPosition || recovered,
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: onDetails,
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Detalles'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


class AlertsTab extends StatefulWidget {
  final List<String> coins;
  final Map<String, CoinStats> stats;
  final bool priceAlertsEnabled;
  final double priceAlertThresholdPercent;
  final Map<String, double> priceAlertReferences;
  final bool recoveryAlertsEnabled;
  final double recoveryAlertThresholdPoints;
  final Map<String, double> recoveryAlertReferences;
  final double sellFeePercent;
  final bool notificationsAllowed;
  final bool automaticLocalAlertsEnabled;
  final int automaticLocalAlertsIntervalMinutes;
  final DateTime? pricesUpdatedAt;
  final bool isRefreshingPrices;
  final VoidCallback onRefreshPrices;
  final ValueChanged<bool> onPriceAlertsChanged;
  final VoidCallback onEditPriceAlertThreshold;
  final VoidCallback onResetPriceAlertReferences;
  final ValueChanged<bool> onRecoveryAlertsChanged;
  final VoidCallback onEditRecoveryAlertThreshold;
  final VoidCallback onResetRecoveryAlertReferences;
  final ValueChanged<bool> onAutomaticLocalAlertsChanged;
  final ValueChanged<int> onAutomaticLocalAlertIntervalChanged;

  const AlertsTab({
    super.key,
    required this.coins,
    required this.stats,
    required this.priceAlertsEnabled,
    required this.priceAlertThresholdPercent,
    required this.priceAlertReferences,
    required this.recoveryAlertsEnabled,
    required this.recoveryAlertThresholdPoints,
    required this.recoveryAlertReferences,
    required this.sellFeePercent,
    required this.notificationsAllowed,
    required this.automaticLocalAlertsEnabled,
    required this.automaticLocalAlertsIntervalMinutes,
    required this.pricesUpdatedAt,
    required this.isRefreshingPrices,
    required this.onRefreshPrices,
    required this.onPriceAlertsChanged,
    required this.onEditPriceAlertThreshold,
    required this.onResetPriceAlertReferences,
    required this.onRecoveryAlertsChanged,
    required this.onEditRecoveryAlertThreshold,
    required this.onResetRecoveryAlertReferences,
    required this.onAutomaticLocalAlertsChanged,
    required this.onAutomaticLocalAlertIntervalChanged,
  });

  @override
  State<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<AlertsTab> {
  int _segment = 0;
  bool _showCoinsWithoutPosition = false;

  @override
  Widget build(BuildContext context) {
    final int watchedCount = widget.coins
        .where((String coin) => (widget.stats[coin]?.currentPrice ?? 0) > 0)
        .length;
    final String globalState = widget.priceAlertsEnabled || widget.recoveryAlertsEnabled
        ? 'Activas'
        : 'En pausa';
    final String autoState = widget.automaticLocalAlertsEnabled
        ? intervalLabel(widget.automaticLocalAlertsIntervalMinutes)
        : 'Desactivadas';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: <Widget>[
        PremiumDashboardHero(
          title: 'Alertas',
          subtitle: 'Internas al usar la app y automáticas locales en Android',
          icon: Icons.notifications_active_outlined,
          metrics: <PremiumMetricData>[
            PremiumMetricData(
              label: 'Estado global',
              value: globalState,
              icon: Icons.radar_outlined,
              color: globalState == 'Activas' ? Colors.green : null,
            ),
            PremiumMetricData(
              label: 'Umbral mercado',
              value: pct(widget.priceAlertThresholdPercent),
              icon: Icons.percent_outlined,
            ),
            PremiumMetricData(
              label: 'Referencias',
              value: '$watchedCount monedas',
              icon: Icons.track_changes_outlined,
            ),
            PremiumMetricData(
              label: 'Automáticas',
              value: autoState,
              icon: Icons.work_history_outlined,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildAutomaticNotificationsCard(context),
        const SizedBox(height: 14),
        PremiumSegmentShell(
          child: SegmentedButton<int>(
            segments: const <ButtonSegment<int>>[
              ButtonSegment<int>(
                value: 0,
                label: Text('Mercado'),
                icon: Icon(Icons.show_chart),
              ),
              ButtonSegment<int>(
                value: 1,
                label: Text('Recuperación'),
                icon: Icon(Icons.trending_up),
              ),
            ],
            selected: <int>{_segment},
            onSelectionChanged: (Set<int> selected) {
              setState(() => _segment = selected.first);
            },
          ),
        ),
        const SizedBox(height: 14),
        if (_segment == 0)
          _buildMarketSection(context)
        else
          _buildRecoverySection(context),
      ],
    );
  }


  Widget _buildAutomaticNotificationsCard(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return CardPanel(
      title: 'Alertas automáticas locales',
      subtitle: 'Revisión en segundo plano con WorkManager de Android.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            dense: true,
            value: widget.automaticLocalAlertsEnabled,
            onChanged: widget.onAutomaticLocalAlertsChanged,
            title: const Text('Activar revisión automática local'),
            subtitle: Text(
              widget.notificationsAllowed
                  ? 'Usa las mismas alertas de mercado y recuperación.'
                  : 'Falta permiso de notificaciones de Android.',
            ),
            contentPadding: EdgeInsets.zero,
          ),
          const Text(
            'Las alertas internas se revisan al abrir la app o actualizar precios. '
            'Las alertas automáticas locales dependen de Android, batería, '
            'permisos y conexión. Pueden no ser exactas al minuto.',
          ),
          const SizedBox(height: 8),
          Text(
            'Android puede agrupar o retrasar revisiones para ahorrar batería.',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Text('Intervalo', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PriceAlertService.automaticIntervalOptions.map((int minutes) {
              return ChoiceChip(
                selected: widget.automaticLocalAlertsIntervalMinutes == minutes,
                label: Text(intervalLabel(minutes)),
                onSelected: (_) => widget.onAutomaticLocalAlertIntervalChanged(minutes),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMarketSection(BuildContext context) {
    final List<String> watchedCoins = widget.coins
        .where((String coin) => (widget.stats[coin]?.currentPrice ?? 0) > 0)
        .toList();

    return Column(
      children: <Widget>[
        CardPanel(
          title: 'Alertas internas de mercado',
          subtitle: '${pct(widget.priceAlertThresholdPercent)} · ${priceUpdatedLabel(widget.pricesUpdatedAt)}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SwitchListTile(
                dense: true,
                value: widget.priceAlertsEnabled,
                onChanged: widget.onPriceAlertsChanged,
                title: const Text('Activar mercado'),
                contentPadding: EdgeInsets.zero,
              ),
              if (widget.priceAlertsEnabled && !widget.notificationsAllowed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Falta permiso de notificaciones.',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              InfoLine('Umbral actual', pct(widget.priceAlertThresholdPercent)),
              InfoLine('Monitoreo', '${watchedCoins.length} monedas monitoreadas'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: widget.isRefreshingPrices ? null : widget.onRefreshPrices,
                    icon: widget.isRefreshingPrices
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: Text(widget.isRefreshingPrices ? 'Actualizando' : 'Precios'),
                  ),
                  FilledButton.tonal(
                    onPressed: widget.onEditPriceAlertThreshold,
                    child: const Text('Editar umbral'),
                  ),
                  FilledButton.tonal(
                    onPressed: widget.onResetPriceAlertReferences,
                    child: const Text('Reiniciar referencias'),
                  ),
                ],
              ),
            ],
          ),
        ),
        CardPanel(
          title: 'Monedas',
          subtitle: watchedCoins.isEmpty ? 'Sin precios cargados.' : '${watchedCoins.length} monedas monitoreadas',
          child: Column(
            children: widget.coins.map((String coin) {
              final CoinStats stat = widget.stats[coin] ?? CoinStats(coin: coin);
              final double reference = widget.priceAlertReferences[coin] ?? 0.0;
              final double variation = reference <= 0
                  ? 0.0
                  : ((stat.currentPrice - reference) / reference) * 100;
              final bool triggered = reference > 0 &&
                  variation.abs() >= widget.priceAlertThresholdPercent;

              return AlertCoinRow(
                coin: coin,
                currentPrice: stat.currentPrice,
                referencePrice: reference,
                variationPercent: variation,
                triggered: triggered,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRecoverySection(BuildContext context) {
    final List<String> coinsToShow = widget.coins.where((String coin) {
      if (_showCoinsWithoutPosition) {
        return true;
      }
      final CoinStats stat = widget.stats[coin] ?? CoinStats(coin: coin);
      return stat.quantity > 0;
    }).toList();

    return Column(
      children: <Widget>[
        CardPanel(
          title: 'Alertas internas de recuperación',
          subtitle: 'Avance hacia break even.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SwitchListTile(
                dense: true,
                value: widget.recoveryAlertsEnabled,
                onChanged: widget.onRecoveryAlertsChanged,
                title: const Text('Activar recuperación'),
                subtitle: const Text('Basado en tu posición neta.'),
                contentPadding: EdgeInsets.zero,
              ),
              InfoLine(
                'Umbral actual',
                '${widget.recoveryAlertThresholdPoints.toStringAsFixed(2)} pts',
              ),
              const Text('Avance hacia break even por P&L no realizado.'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.tonal(
                    onPressed: widget.onEditRecoveryAlertThreshold,
                    child: const Text('Editar umbral'),
                  ),
                  FilledButton.tonal(
                    onPressed: widget.onResetRecoveryAlertReferences,
                    child: const Text('Reiniciar referencias'),
                  ),
                ],
              ),
            ],
          ),
        ),
        CardPanel(
          title: 'P&L por moneda',
          subtitle: '${coinsToShow.length} monedas visibles',
          child: Column(
            children: <Widget>[
              SwitchListTile(
                dense: true,
                value: _showCoinsWithoutPosition,
                onChanged: (bool value) {
                  setState(() => _showCoinsWithoutPosition = value);
                },
                title: const Text('Mostrar monedas sin posición'),
                contentPadding: EdgeInsets.zero,
              ),
              if (coinsToShow.isEmpty)
                const EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Sin posiciones abiertas',
                  subtitle: 'Activa el switch para ver monedas sin posición.',
                )
              else
                ...coinsToShow.map((String coin) {
                  final CoinStats stat = widget.stats[coin] ?? CoinStats(coin: coin);
                  final RecoveryAlertPosition position = RecoveryAlertPosition(
                    quantity: stat.quantity,
                    investmentNet: stat.costBase,
                    currentPrice: stat.currentPrice,
                    sellFeePercent: widget.sellFeePercent,
                  );
                  final double? reference = widget.recoveryAlertReferences[coin];
                  final double delta = reference == null
                      ? 0.0
                      : position.pnlPercent - reference;
                  final bool triggered = reference != null &&
                      delta.abs() >= widget.recoveryAlertThresholdPoints;

                  return RecoveryAlertCoinRow(
                    coin: coin,
                    position: position,
                    referencePnlPercent: reference,
                    deltaPoints: delta,
                    triggered: triggered,
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}

class AlertCoinRow extends StatelessWidget {
  final String coin;
  final double currentPrice;
  final double referencePrice;
  final double variationPercent;
  final bool triggered;

  const AlertCoinRow({
    super.key,
    required this.coin,
    required this.currentPrice,
    required this.referencePrice,
    required this.variationPercent,
    required this.triggered,
  });

  @override
  Widget build(BuildContext context) {
    final String variationText = referencePrice <= 0
        ? 'Sin ref'
        : '${variationPercent >= 0 ? '+' : ''}${variationPercent.toStringAsFixed(2)}%';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        children: <Widget>[
          CoinLogo(coin: coin, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  money(currentPrice),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  'Ref ${money(referencePrice)} · Δ $variationText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          StatusPill(label: triggered ? 'Revisar' : 'Normal', positive: !triggered),
        ],
      ),
    );
  }
}

class RecoveryAlertCoinRow extends StatelessWidget {
  final String coin;
  final RecoveryAlertPosition position;
  final double? referencePnlPercent;
  final double deltaPoints;
  final bool triggered;

  const RecoveryAlertCoinRow({
    super.key,
    required this.coin,
    required this.position,
    required this.referencePnlPercent,
    required this.deltaPoints,
    required this.triggered,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasPosition = position.hasPosition;
    final String pnlText = hasPosition ? pct(position.pnlPercent) : 'Sin posición';
    final String referenceText = referencePnlPercent == null
        ? 'Sin ref'
        : pct(referencePnlPercent!);
    final String deltaText = referencePnlPercent == null
        ? 'Sin ref'
        : '${deltaPoints >= 0 ? '+' : ''}${deltaPoints.toStringAsFixed(2)} pts';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CoinLogo(coin: coin, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  pnlText,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: hasPosition ? pnlColor(position.unrealizedPnl) : null,
                  ),
                ),
              ),
              StatusPill(label: triggered ? 'Revisar' : 'Normal', positive: !triggered),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              MiniMetric(
                label: 'P&L no realizado',
                value: hasPosition ? money(position.unrealizedPnl) : 'Sin posición',
                color: hasPosition ? pnlColor(position.unrealizedPnl) : null,
              ),
              MiniMetric(label: 'Referencia', value: referenceText),
              MiniMetric(label: 'Delta', value: deltaText),
              MiniMetric(
                label: 'Falta BE',
                value: position.missingToBreakEven > 0
                    ? money(position.missingToBreakEven)
                    : 'Listo',
              ),
            ],
          ),
        ],
      ),
    );
  }
}



String _btcDominance(Map<String, CoinStats> stats, PortfolioTotals totals) {
  if (totals.currentValue <= 0) return '—';
  final double btcValue = stats['BTC']?.currentValue ?? 0;
  return pct((btcValue / totals.currentValue) * 100);
}


enum SnapshotMetric {
  portfolioValue,
  invested,
  unrealizedPnl,
  realizedPnl,
  btcDominance,
}

extension SnapshotMetricDetails on SnapshotMetric {
  String get label {
    switch (this) {
      case SnapshotMetric.portfolioValue:
        return 'Valor de cartera';
      case SnapshotMetric.invested:
        return 'Invertido';
      case SnapshotMetric.unrealizedPnl:
        return 'P&L no realizado';
      case SnapshotMetric.realizedPnl:
        return 'P&L realizado';
      case SnapshotMetric.btcDominance:
        return 'Dominancia BTC';
    }
  }

  IconData get icon {
    switch (this) {
      case SnapshotMetric.portfolioValue:
        return Icons.account_balance_wallet_outlined;
      case SnapshotMetric.invested:
        return Icons.savings_outlined;
      case SnapshotMetric.unrealizedPnl:
        return Icons.trending_up;
      case SnapshotMetric.realizedPnl:
        return Icons.sell_outlined;
      case SnapshotMetric.btcDominance:
        return Icons.currency_bitcoin;
    }
  }

  double valueFor(PortfolioSnapshot snapshot) {
    switch (this) {
      case SnapshotMetric.portfolioValue:
        return snapshot.totalCurrentValue;
      case SnapshotMetric.invested:
        return snapshot.totalCostBase;
      case SnapshotMetric.unrealizedPnl:
        return snapshot.totalUnrealizedPL;
      case SnapshotMetric.realizedPnl:
        return snapshot.totalRealizedPL;
      case SnapshotMetric.btcDominance:
        return snapshot.btcDominancePercent;
    }
  }

  String format(double value) {
    switch (this) {
      case SnapshotMetric.btcDominance:
        return pct(value);
      case SnapshotMetric.portfolioValue:
      case SnapshotMetric.invested:
      case SnapshotMetric.unrealizedPnl:
      case SnapshotMetric.realizedPnl:
        return money(value);
    }
  }

  String shortFormat(double value) {
    switch (this) {
      case SnapshotMetric.btcDominance:
        return pct(value);
      case SnapshotMetric.portfolioValue:
      case SnapshotMetric.invested:
      case SnapshotMetric.unrealizedPnl:
      case SnapshotMetric.realizedPnl:
        return moneyShort(value);
    }
  }
}

class SnapshotRangeOption {
  final String label;
  final int? days;

  const SnapshotRangeOption(this.label, this.days);
}

class AnalyticsControlPanel extends StatefulWidget {
  final List<PortfolioSnapshot> snapshots;

  const AnalyticsControlPanel({super.key, required this.snapshots});

  @override
  State<AnalyticsControlPanel> createState() => _AnalyticsControlPanelState();
}

class _AnalyticsControlPanelState extends State<AnalyticsControlPanel> {
  static const List<SnapshotRangeOption> _ranges = <SnapshotRangeOption>[
    SnapshotRangeOption('7D', 7),
    SnapshotRangeOption('30D', 30),
    SnapshotRangeOption('90D', 90),
    SnapshotRangeOption('Todo', null),
  ];

  SnapshotRangeOption _range = _ranges[1];
  SnapshotMetric _metric = SnapshotMetric.portfolioValue;

  List<PortfolioSnapshot> _filteredSnapshots() {
    final List<PortfolioSnapshot> ordered = widget.snapshots.toList()
      ..sort(
        (PortfolioSnapshot a, PortfolioSnapshot b) =>
            a.createdAt.compareTo(b.createdAt),
      );

    if (_range.days == null || ordered.isEmpty) return ordered;

    final DateTime latest = ordered.last.createdAt;
    final DateTime from = latest.subtract(Duration(days: _range.days!));
    return ordered
        .where((PortfolioSnapshot snapshot) => !snapshot.createdAt.isBefore(from))
        .toList();
  }

  Color _metricColor(BuildContext context, List<PortfolioSnapshot> filtered) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    switch (_metric) {
      case SnapshotMetric.portfolioValue:
        return colors.primary;
      case SnapshotMetric.invested:
        return colors.tertiary;
      case SnapshotMetric.unrealizedPnl:
        final double value = filtered.isEmpty ? 0 : _metric.valueFor(filtered.last);
        return pnlColor(value);
      case SnapshotMetric.realizedPnl:
        return colors.secondary;
      case SnapshotMetric.btcDominance:
        return const Color(0xFFF7931A);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<PortfolioSnapshot> filtered = _filteredSnapshots();
    final Color metricColor = _metricColor(context, filtered);
    final double? latestValue = filtered.isEmpty ? null : _metric.valueFor(filtered.last);
    final double? firstValue = filtered.isEmpty ? null : _metric.valueFor(filtered.first);
    final double? delta = latestValue == null || firstValue == null
        ? null
        : latestValue - firstValue;

    return CardPanel(
      title: 'Evolución por instantáneas',
      subtitle: 'Filtro temporal y métrica principal con línea y puntos.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _ranges.map((SnapshotRangeOption range) {
              return ChoiceChip(
                selected: _range == range,
                label: Text(range.label),
                onSelected: (_) => setState(() => _range = range),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<SnapshotMetric>(
            value: _metric,
            decoration: const InputDecoration(
              labelText: 'Métrica',
              border: OutlineInputBorder(),
            ),
            items: SnapshotMetric.values
                .map(
                  (SnapshotMetric metric) => DropdownMenuItem<SnapshotMetric>(
                    value: metric,
                    child: Text(metric.label),
                  ),
                )
                .toList(),
            onChanged: (SnapshotMetric? value) {
              if (value != null) setState(() => _metric = value);
            },
          ),
          const SizedBox(height: 14),
          if (filtered.length < 2)
            EmptyState(
              icon: Icons.show_chart_outlined,
              title: filtered.isEmpty
                  ? 'Sin instantáneas para graficar'
                  : 'Hace falta otra instantánea',
              subtitle: filtered.isEmpty
                  ? 'Guarda al menos dos instantáneas para ver una línea histórica.'
                  : 'Con una sola instantánea se muestra el dato, pero se '
                      'necesita otra para conectar puntos.',
            )
          else ...<Widget>[
            SnapshotLineChart(
              snapshots: filtered,
              height: 240,
              includeZero: _metric != SnapshotMetric.btcDominance,
              series: <SnapshotChartSeries>[
                SnapshotChartSeries(
                  label: _metric.label,
                  color: metricColor,
                  values: filtered
                      .map((PortfolioSnapshot s) => _metric.valueFor(s))
                      .toList(),
                  valueFormatter: (double value) => _metric.shortFormat(value),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ChartLegendDot(label: _metric.label, color: metricColor),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              MiniMetric(
                label: 'Último dato',
                value: latestValue == null ? '—' : _metric.format(latestValue),
                color: _metric == SnapshotMetric.unrealizedPnl && latestValue != null
                    ? pnlColor(latestValue)
                    : null,
              ),
              MiniMetric(
                label: 'Cambio del periodo',
                value: delta == null ? '—' : _metric.format(delta),
                color: delta == null ? null : pnlColor(delta),
              ),
              MiniMetric(
                label: 'Instantáneas filtradas',
                value: filtered.length.toString(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ChartsTab extends StatelessWidget {
  final Map<String, CoinStats> stats;
  final PortfolioTotals totals;
  final List<PortfolioSnapshot> snapshots;
  final VoidCallback onSaveSnapshot;
  final VoidCallback onViewSnapshots;

  const ChartsTab({
    super.key,
    required this.stats,
    required this.totals,
    required this.snapshots,
    required this.onSaveSnapshot,
    required this.onViewSnapshots,
  });

  @override
  Widget build(BuildContext context) {
    final List<CoinStats> active = stats.values
        .where((CoinStats s) => s.currentValue > 0)
        .toList()
      ..sort(
        (CoinStats a, CoinStats b) => b.currentValue.compareTo(a.currentValue),
      );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Text(
          'Gráficas',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Analítica limpia con filtros de tiempo, métricas semánticas e instantáneas.',
        ),
        const SizedBox(height: 12),
        AnalyticsControlPanel(snapshots: snapshots),
        const SizedBox(height: 12),
        _CommandSection(
          title: 'Indicadores',
          children: <Widget>[
            PremiumMetricCard(
              label: 'Valor de cartera',
              value: moneyShort(totals.currentValue),
              icon: Icons.account_balance_wallet_outlined,
            ),
            PremiumMetricCard(
              label: 'Invertido',
              value: moneyShort(totals.costBase),
              icon: Icons.savings_outlined,
            ),
            PremiumMetricCard(
              label: 'P&L no realizado',
              value: moneyShort(totals.unrealizedPL),
              icon: Icons.trending_up,
              color: pnlColor(totals.unrealizedPL),
            ),
            PremiumMetricCard(
              label: 'Dominancia BTC',
              value: _btcDominance(stats, totals),
              icon: Icons.currency_bitcoin,
            ),
          ],
        ),
        CardPanel(
          title: 'Distribución actual',
          subtitle: totals.currentValue <= 0
              ? 'Sin valor cargado para graficar.'
              : 'Valor total: ${money(totals.currentValue)}',
          child: active.isEmpty
              ? const EmptyState(
                  icon: Icons.pie_chart_outline,
                  title: 'Sin datos para graficar',
                  subtitle: 'Carga precios y movimientos para activar una '
                      'lectura visual premium.',
                )
              : Column(
                  children: active.map((CoinStats stat) {
                    final double share = totals.currentValue <= 0
                        ? 0.0
                        : stat.currentValue / totals.currentValue;
                    return AllocationBar(
                      label: stat.coin,
                      value: money(stat.currentValue),
                      share: share,
                      result: stat.unrealizedPL,
                    );
                  }).toList(),
                ),
        ),
        CardPanel(
          title: 'P&L no realizado por moneda',
          subtitle: 'Barras semánticas: ganancias verdes, pérdidas rojas.',
          child: active.isEmpty
              ? const Text('Sin posiciones abiertas.')
              : Column(
                  children: active.map((CoinStats stat) {
                    final double maxAbs = active.fold<double>(
                      1,
                      (double maxValue, CoinStats item) =>
                          math.max(maxValue, item.unrealizedPL.abs()),
                    );
                    return ResultBar(
                      label: stat.coin,
                      amount: stat.unrealizedPL,
                      intensity: stat.unrealizedPL.abs() / maxAbs,
                    );
                  }).toList(),
                ),
        ),
        if (snapshots.isEmpty)
          CardPanel(
            title: 'Histórico de instantáneas',
            subtitle: 'Guarda instantáneas para activar líneas de tendencia.',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: onSaveSnapshot,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Guardar instantánea'),
                ),
                FilledButton.tonal(
                  onPressed: onViewSnapshots,
                  child: const Text('Ver instantáneas'),
                ),
              ],
            ),
          )
        else ...<Widget>[
          SnapshotTrendPanel(snapshots: snapshots),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: onViewSnapshots,
              child: const Text('Administrar instantáneas'),
            ),
          ),
        ],
      ],
    );
  }
}

class AllocationBar extends StatelessWidget {
  final String label;
  final String value;
  final double share;
  final double result;

  const AllocationBar({
    super.key,
    required this.label,
    required this.value,
    required this.share,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
              Text('${pct(share * 100)} · $value'),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: share.clamp(0.0, 1.0),
            minHeight: 10,
            color: pnlColor(result),
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ],
      ),
    );
  }
}

class ResultBar extends StatelessWidget {
  final String label;
  final double amount;
  final double intensity;

  const ResultBar({
    super.key,
    required this.label,
    required this.amount,
    required this.intensity,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          SizedBox(width: 48, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(
            child: LinearProgressIndicator(
              value: intensity.clamp(0.0, 1.0),
              minHeight: 10,
              color: pnlColor(amount),
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 104,
            child: Text(
              money(amount),
              textAlign: TextAlign.right,
              style: TextStyle(color: pnlColor(amount), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class MoreTab extends StatelessWidget {
  final PortfolioTotals totals;
  final DateTime? pricesUpdatedAt;
  final AppVisualMode visualMode;
  final AppThemeStyle themeStyle;
  final int movementCount;
  final int snapshotCount;
  final int chartDataCount;
  final VoidCallback onOpenCharts;
  final VoidCallback onOpenMovements;
  final VoidCallback onOpenThemeSettings;
  final VoidCallback onOpenPortfolioSettings;
  final VoidCallback onOpenAlerts;
  final VoidCallback onExportMovementsCsv;
  final VoidCallback onExportSummaryCsv;
  final VoidCallback onExportSnapshotsCsv;
  final VoidCallback onExportXlsx;
  final VoidCallback onExportPdf;
  final VoidCallback onExportBackup;
  final VoidCallback onImportBackup;
  final VoidCallback onImportBackupFile;
  final VoidCallback onSaveSnapshot;
  final VoidCallback onViewSnapshots;
  final VoidCallback onResetPriceAlertReferences;

  const MoreTab({
    super.key,
    required this.totals,
    required this.pricesUpdatedAt,
    required this.visualMode,
    required this.themeStyle,
    required this.movementCount,
    required this.snapshotCount,
    required this.chartDataCount,
    required this.onOpenCharts,
    required this.onOpenMovements,
    required this.onOpenThemeSettings,
    required this.onOpenPortfolioSettings,
    required this.onOpenAlerts,
    required this.onExportMovementsCsv,
    required this.onExportSummaryCsv,
    required this.onExportSnapshotsCsv,
    required this.onExportXlsx,
    required this.onExportPdf,
    required this.onExportBackup,
    required this.onImportBackup,
    required this.onImportBackupFile,
    required this.onSaveSnapshot,
    required this.onViewSnapshots,
    required this.onResetPriceAlertReferences,
  });

  static const String _priceSource = 'CoinGecko';

  @override
  Widget build(BuildContext context) {
    final Color semanticPnl = pnlColor(totals.unrealizedPL);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: <Widget>[
        _CommandCenterHeader(
          totals: totals,
          pnlColor: semanticPnl,
          pricesUpdatedAt: pricesUpdatedAt,
          priceSource: _priceSource,
        ),
        const SizedBox(height: 18),
        _CommandSection(
          title: 'Cuenta y respaldo',
          children: <Widget>[
            _CommandCard(
              icon: Icons.account_circle_outlined,
              title: 'Cuenta',
              subtitle: 'Próximamente: sincronización y respaldo en la nube',
              badge: 'Local',
              onTap: () => _showAccountPlaceholder(context),
            ),
            _CommandCard(
              icon: Icons.backup_outlined,
              title: 'Copia de seguridad',
              subtitle: 'Copiar JSON completo sin cambiar estructura',
              onTap: onExportBackup,
            ),
            _CommandCard(
              icon: Icons.receipt_long_outlined,
              title: 'Historial de movimientos',
              subtitle: movementCount == 1
                  ? '1 movimiento registrado para auditoría, edición y borrado'
                  : '$movementCount movimientos registrados para auditoría, '
                      'edición y borrado',
              badge: 'Clave',
              onTap: onOpenMovements,
            ),
            _CommandCard(
              icon: Icons.table_chart_outlined,
              title: 'Exportaciones',
              subtitle: 'CSV, JSON, PDF y XLSX cuando están soportados',
              badge: 'Reportes',
              onTap: () => _showDataActions(context),
            ),
            _CommandCard(
              icon: Icons.upload_file_outlined,
              title: 'Importar respaldo',
              subtitle: 'Pegar JSON o cargar archivo local',
              onTap: () => _showImportActions(context),
            ),
          ],
        ),
        _CommandSection(
          title: 'Apariencia global',
          children: <Widget>[
            _CommandCard(
              icon: Icons.palette_outlined,
              title: 'Tema',
              subtitle: 'Modo ${visualMode.label} · ${themeStyle.label}',
              onTap: onOpenThemeSettings,
            ),
          ],
        ),
        _CommandSection(
          title: 'Portafolio',
          children: <Widget>[
            _CommandCard(
              icon: Icons.view_agenda_outlined,
              title: 'Resumen de cartera',
              subtitle: 'Posiciones visibles y orden del portafolio',
              onTap: onOpenPortfolioSettings,
            ),
            _CommandCard(
              icon: Icons.visibility_outlined,
              title: 'Monedas monitoreadas',
              subtitle: 'BTC, ETH, LINK, LTC y UNI con logos locales',
              badge: '5',
              onTap: onOpenPortfolioSettings,
            ),
          ],
        ),
        _CommandSection(
          title: 'Herramientas',
          children: <Widget>[
            _CommandCard(
              icon: Icons.health_and_safety_outlined,
              title: 'Diagnóstico',
              subtitle: 'Datos locales, instantáneas y fuente de precios',
              badge: pricesUpdatedAt == null ? 'Pendiente' : 'OK',
              onTap: () => _showDiagnostics(context),
            ),
          ],
        ),
      ],
    );
  }

  void _showAccountPlaceholder(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: SafeArea(
          top: false,
          child: EmptyState(
            icon: Icons.cloud_sync_outlined,
            title: 'Cuenta local',
            subtitle: 'Próximamente: sincronización y respaldo en la nube. '
                'No se agregó Firebase en esta versión.',
          ),
        ),
      ),
    );
  }

  void _showDataActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _CommandActionSheet(
        title: 'Exportaciones',
        actions: <_SheetAction>[
          _SheetAction(
            icon: Icons.receipt_long_outlined,
            title: 'CSV historial',
            subtitle: 'Movimientos registrados',
            onTap: onExportMovementsCsv,
          ),
          _SheetAction(
            icon: Icons.summarize_outlined,
            title: 'CSV resumen',
            subtitle: 'Cartera actual',
            onTap: onExportSummaryCsv,
          ),
          _SheetAction(
            icon: Icons.photo_library_outlined,
            title: 'CSV instantáneas',
            subtitle: 'Evolución guardada',
            onTap: onExportSnapshotsCsv,
          ),
          _SheetAction(
            icon: Icons.data_object_outlined,
            title: 'JSON respaldo',
            subtitle: 'Copia completa compatible',
            onTap: onExportBackup,
          ),
          _SheetAction(
            icon: Icons.picture_as_pdf_outlined,
            title: 'PDF reporte',
            subtitle: 'Reporte existente',
            onTap: onExportPdf,
          ),
          _SheetAction(
            icon: Icons.table_chart_outlined,
            title: 'XLSX reporte',
            subtitle: 'Libro de cálculo existente',
            onTap: onExportXlsx,
          ),
        ],
      ),
    );
  }

  void _showImportActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _CommandActionSheet(
        title: 'Importar respaldo',
        actions: <_SheetAction>[
          _SheetAction(
            icon: Icons.content_paste_outlined,
            title: 'Pegar JSON',
            subtitle: 'Importar desde portapapeles o texto',
            onTap: onImportBackup,
          ),
          _SheetAction(
            icon: Icons.upload_file_outlined,
            title: 'Importar archivo',
            subtitle: 'Seleccionar respaldo JSON',
            onTap: onImportBackupFile,
          ),
        ],
      ),
    );
  }

  void _showDiagnostics(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewPaddingOf(context).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Diagnóstico',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              InfoLine('Movimientos locales', movementCount.toString()),
              InfoLine('Instantáneas', snapshotCount.toString()),
              InfoLine('Monedas con valor', chartDataCount.toString()),
              InfoLine('Fuente de precios', _priceSource),
              InfoLine('Última actualización', priceUpdatedLabel(pricesUpdatedAt)),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: onResetPriceAlertReferences,
                icon: const Icon(Icons.restart_alt_outlined),
                label: const Text('Reiniciar referencias de alertas'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandCenterHeader extends StatelessWidget {
  final PortfolioTotals totals;
  final Color pnlColor;
  final DateTime? pricesUpdatedAt;
  final String priceSource;

  const _CommandCenterHeader({
    required this.totals,
    required this.pnlColor,
    required this.pricesUpdatedAt,
    required this.priceSource,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colors.primaryContainer.withValues(alpha: 0.92),
            colors.surfaceContainerHighest.withValues(alpha: 0.88),
          ],
        ),
        border: Border.all(color: colors.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Centro de control',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Herramientas, datos y configuración',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.dashboard_customize_outlined,
                color: colors.primary,
                size: 30,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _HeaderMetric(
                label: 'Cartera',
                value: moneyShort(totals.currentValue),
                icon: Icons.account_balance_wallet_outlined,
              ),
              _HeaderMetric(
                label: 'P&L no realizado',
                value: moneyShort(totals.unrealizedPL),
                color: pnlColor,
                icon: totals.unrealizedPL >= 0
                    ? Icons.trending_up
                    : Icons.trending_down,
              ),
              _HeaderMetric(
                label: 'Precios',
                value: priceUpdatedLabel(pricesUpdatedAt),
                icon: Icons.schedule_outlined,
              ),
              _HeaderMetric(
                label: 'Fuente',
                value: priceSource,
                icon: Icons.cloud_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const _HeaderMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minWidth: 142, maxWidth: 190),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: colors.surface.withValues(alpha: 0.62),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: color ?? colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _CommandSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool twoColumns = constraints.maxWidth >= 560;
              final double spacing = twoColumns ? 12 : 0;
              final double itemWidth = twoColumns
                  ? (constraints.maxWidth - spacing) / 2
                  : constraints.maxWidth;

              return Wrap(
                spacing: spacing,
                runSpacing: 12,
                children: children
                    .map(
                      (Widget child) => SizedBox(
                        width: itemWidth,
                        child: child,
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CommandCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final bool loading;
  final String? emptyTitle;
  final String? emptySubtitle;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final VoidCallback? onTap;

  const _CommandCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.loading = false,
    this.emptyTitle,
    this.emptySubtitle,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.onTap,
  });

  bool get _hasEmptyState => emptyTitle != null && emptySubtitle != null;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: colors.primary.withValues(alpha: 0.12),
                    ),
                    child: loading
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(icon, color: colors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (badge != null) ...<Widget>[
                              const SizedBox(width: 6),
                              _MiniBadge(label: badge!),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right,
                    color: colors.onSurfaceVariant.withValues(alpha: 0.72),
                  ),
                ],
              ),
              if (_hasEmptyState) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(icon, size: 22, color: colors.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              emptyTitle!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              emptySubtitle!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (emptyActionLabel != null && onEmptyAction != null)
                        TextButton(
                          onPressed: onEmptyAction,
                          child: Text(emptyActionLabel!),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String label;

  const _MiniBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: colors.primary.withValues(alpha: 0.12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SheetAction {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SheetAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

class _CommandActionSheet extends StatelessWidget {
  final String title;
  final List<_SheetAction> actions;

  const _CommandActionSheet({required this.title, required this.actions});

  @override
  Widget build(BuildContext context) {
    final double bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 20;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.7,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: actions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int index) {
                  final _SheetAction action = actions[index];
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: Icon(action.icon),
                      title: Text(action.title),
                      subtitle: Text(action.subtitle),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: action.onTap != null,
                      onTap: action.onTap == null
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              action.onTap!();
                            },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum SettingsView { all, theme, portfolio }

class SettingsTab extends StatelessWidget {
  final SettingsView view;
  final AppVisualMode visualMode;
  final AppThemeStyle themeStyle;
  final VisiblePositions visiblePositions;
  final PositionSortMode positionSortMode;
  final SnapshotAutomationMode snapshotAutomationMode;
  final SnapshotRetention snapshotRetention;
  final double sellFeePercent;
  final int snapshotCount;
  final bool automaticLocalAlertsEnabled;
  final int automaticLocalAlertsIntervalMinutes;
  final bool notificationsAllowed;
  final ValueChanged<AppVisualMode> onVisualModeChanged;
  final ValueChanged<AppThemeStyle> onThemeStyleChanged;
  final ValueChanged<VisiblePositions> onVisiblePositionsChanged;
  final ValueChanged<PositionSortMode> onPositionSortModeChanged;
  final ValueChanged<SnapshotAutomationMode> onSnapshotAutomationModeChanged;
  final ValueChanged<SnapshotRetention> onSnapshotRetentionChanged;
  final VoidCallback onEditSellFee;
  final VoidCallback onOpenAlerts;
  final ValueChanged<bool> onAutomaticLocalAlertsChanged;
  final ValueChanged<int> onAutomaticLocalAlertIntervalChanged;
  final VoidCallback onSaveSnapshot;
  final VoidCallback onViewSnapshots;
  final VoidCallback onExportSnapshotsCsv;
  final VoidCallback onExportXlsx;
  final VoidCallback onExportPdf;
  final VoidCallback onExportBackup;

  const SettingsTab({
    super.key,
    this.view = SettingsView.all,
    required this.visualMode,
    required this.themeStyle,
    required this.visiblePositions,
    required this.positionSortMode,
    required this.snapshotAutomationMode,
    required this.snapshotRetention,
    required this.sellFeePercent,
    required this.snapshotCount,
    required this.automaticLocalAlertsEnabled,
    required this.automaticLocalAlertsIntervalMinutes,
    required this.notificationsAllowed,
    required this.onVisualModeChanged,
    required this.onThemeStyleChanged,
    required this.onVisiblePositionsChanged,
    required this.onPositionSortModeChanged,
    required this.onSnapshotAutomationModeChanged,
    required this.onSnapshotRetentionChanged,
    required this.onEditSellFee,
    required this.onOpenAlerts,
    required this.onAutomaticLocalAlertsChanged,
    required this.onAutomaticLocalAlertIntervalChanged,
    required this.onSaveSnapshot,
    required this.onViewSnapshots,
    required this.onExportSnapshotsCsv,
    required this.onExportXlsx,
    required this.onExportPdf,
    required this.onExportBackup,
  });

  @override
  Widget build(BuildContext context) {
    final bool showTheme =
        view == SettingsView.all || view == SettingsView.theme;
    final bool showPortfolio =
        view == SettingsView.all || view == SettingsView.portfolio;
    final bool showAdvanced = view == SettingsView.all;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        if (showTheme)
          CardPanel(
            title: 'Tema',
          subtitle: 'Paletas premium completas, sin alterar colores '
              'semánticos financieros.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Modo visual',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<AppVisualMode>(
                segments: AppVisualMode.values
                    .map(
                      (AppVisualMode mode) => ButtonSegment<AppVisualMode>(
                        value: mode,
                        label: Text(mode.label),
                      ),
                    )
                    .toList(),
                selected: <AppVisualMode>{visualMode},
                onSelectionChanged: (Set<AppVisualMode> value) {
                  onVisualModeChanged(value.first);
                },
              ),
              const SizedBox(height: 18),
              Text(
                'Estilo visual',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 10),
              ...AppThemeStyle.values.map(
                (AppThemeStyle option) => _ThemePaletteTile(
                  option: option,
                  selected: themeStyle == option,
                  onTap: () => onThemeStyleChanged(option),
                ),
              ),
            ],
          ),
        ),
        if (showPortfolio)
          CardPanel(
            title: 'Resumen de cartera',
          subtitle: 'Configura cuántas posiciones aparecen en resumen y '
              'cómo se ordenan.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Posiciones visibles',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: VisiblePositions.values.map(
                  (VisiblePositions option) {
                    return ChoiceChip(
                      selected: visiblePositions == option,
                      label: Text(option.label),
                      onSelected: (_) => onVisiblePositionsChanged(option),
                    );
                  },
                ).toList(),
              ),
              const SizedBox(height: 16),
              Text('Orden', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ...PositionSortMode.values.map(
                (PositionSortMode option) => RadioListTile<PositionSortMode>(
                  contentPadding: EdgeInsets.zero,
                  value: option,
                  groupValue: positionSortMode,
                  title: Text(option.label),
                  onChanged: (PositionSortMode? value) {
                    if (value != null) onPositionSortModeChanged(value);
                  },
                ),
              ),
            ],
          ),
        ),
        if (showAdvanced)
          CardPanel(
            title: 'Cálculo',
          subtitle: 'Comisión de salida actual: ${pct(sellFeePercent)}',
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              onPressed: onEditSellFee,
              child: const Text('Editar comisión'),
            ),
          ),
        ),
        if (showAdvanced)
          CardPanel(
            title: 'Instantáneas',
          subtitle: 'Instantáneas guardadas: $snapshotCount. Configura automatización y retención.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Automatización',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              ...SnapshotAutomationMode.values.map(
                (SnapshotAutomationMode option) =>
                    RadioListTile<SnapshotAutomationMode>(
                  contentPadding: EdgeInsets.zero,
                  value: option,
                  groupValue: snapshotAutomationMode,
                  title: Text(option.label),
                  onChanged: (SnapshotAutomationMode? value) {
                    if (value != null) onSnapshotAutomationModeChanged(value);
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text('Retención', style: Theme.of(context).textTheme.titleSmall),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: SnapshotRetention.values.map(
                  (SnapshotRetention option) {
                    return ChoiceChip(
                      selected: snapshotRetention == option,
                      label: Text(option.label),
                      onSelected: (_) => onSnapshotRetentionChanged(option),
                    );
                  },
                ).toList(),
              ),
              const SizedBox(height: 14),
              Text(
                'La creación y revisión de instantáneas vive en Gráficas. '
                'Aquí solo se configura automatización y retención.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (showAdvanced)
          CardPanel(
            title: 'Notificaciones',
          subtitle: 'Configura comportamiento; la gestión completa vive en Alertas.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Alertas internas: al abrir app / actualizar precios.'),
              const SizedBox(height: 8),
              SwitchListTile(
                dense: true,
                value: automaticLocalAlertsEnabled,
                onChanged: onAutomaticLocalAlertsChanged,
                title: const Text('Alertas automáticas locales'),
                subtitle: Text(
                  notificationsAllowed
                      ? 'Revisión en segundo plano de Android.'
                      : 'Permiso pendiente o denegado en Android.',
                ),
                contentPadding: EdgeInsets.zero,
              ),
              const Text(
                'Android puede agrupar o retrasar revisiones para ahorrar batería. '
                'No son notificaciones push en la nube.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: PriceAlertService.automaticIntervalOptions.map((int minutes) {
                  return ChoiceChip(
                    selected: automaticLocalAlertsIntervalMinutes == minutes,
                    label: Text(intervalLabel(minutes)),
                    onSelected: (_) => onAutomaticLocalAlertIntervalChanged(minutes),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: onOpenAlerts,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Ir a Alertas'),
              ),
            ],
          ),
        ),
        if (showAdvanced)
          CardPanel(
            title: 'Respaldo',
          subtitle: 'Cuenta local. Próximamente: sincronización y respaldo en la nube.',
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: onExportBackup,
              icon: const Icon(Icons.data_object_outlined),
              label: const Text('Copiar JSON de respaldo'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ThemePaletteTile extends StatelessWidget {
  final AppThemeStyle option;
  final bool selected;
  final VoidCallback onTap;

  const _ThemePaletteTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = option.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? palette.primarySoft.withValues(alpha: 0.75)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? palette.primary : Theme.of(context).colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(option.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(option.description),
                  ],
                ),
              ),
              Row(
                children: <Color>[
                  palette.background,
                  palette.surfaceAlt,
                  palette.primary,
                  palette.positive,
                  palette.negative,
                  palette.warning,
                ]
                    .map(
                      (Color color) => Container(
                        width: 18,
                        height: 18,
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.border),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SnapshotTrendPanel extends StatelessWidget {
  final List<PortfolioSnapshot> snapshots;

  const SnapshotTrendPanel({super.key, required this.snapshots});

  @override
  Widget build(BuildContext context) {
    final List<PortfolioSnapshot> ordered = snapshots.toList()
      ..sort(
        (PortfolioSnapshot a, PortfolioSnapshot b) =>
            a.createdAt.compareTo(b.createdAt),
      );
    final ColorScheme colors = Theme.of(context).colorScheme;
    final PortfolioSnapshot first = ordered.first;
    final PortfolioSnapshot latest = ordered.last;
    final double valueChange =
        latest.totalCurrentValue - first.totalCurrentValue;
    final double plChange = latest.totalUnrealizedPL - first.totalUnrealizedPL;

    return CardPanel(
      title: 'Evolución por instantáneas',
      subtitle: ordered.length < 2
          ? 'Guarda otra instantánea para ver líneas comparativas.'
          : '${ordered.length} instantáneas entre '
              '${shortDate(first.createdAt)} y ${shortDate(latest.createdAt)}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (ordered.length >= 2) ...<Widget>[
            SnapshotLineChart(
              snapshots: ordered,
              height: 220,
              includeZero: true,
              series: <SnapshotChartSeries>[
                SnapshotChartSeries(
                  label: 'Valor de cartera',
                  color: colors.primary,
                  values: ordered
                      .map((PortfolioSnapshot s) => s.totalCurrentValue)
                      .toList(),
                ),
                SnapshotChartSeries(
                  label: 'Invertido',
                  color: colors.tertiary,
                  values: ordered
                      .map((PortfolioSnapshot s) => s.totalCostBase)
                      .toList(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SnapshotLineChart(
              snapshots: ordered,
              height: 180,
              includeZero: true,
              series: <SnapshotChartSeries>[
                SnapshotChartSeries(
                  label: 'P&L no realizado',
                  color: pnlColor(latest.totalUnrealizedPL),
                  values: ordered
                      .map((PortfolioSnapshot s) => s.totalUnrealizedPL)
                      .toList(),
                ),
                SnapshotChartSeries(
                  label: 'P&L realizado',
                  color: colors.secondary,
                  values: ordered
                      .map((PortfolioSnapshot s) => s.totalRealizedPL)
                      .toList(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SnapshotLineChart(
              snapshots: ordered,
              height: 170,
              includeZero: false,
              series: <SnapshotChartSeries>[
                SnapshotChartSeries(
                  label: 'Dominancia BTC',
                  color: const Color(0xFFF7931A),
                  values: ordered
                      .map((PortfolioSnapshot s) => s.btcDominancePercent)
                      .toList(),
                  valueFormatter: pct,
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ChartLegendDot(label: 'Valor de cartera', color: colors.primary),
              ChartLegendDot(label: 'Invertido', color: colors.tertiary),
              ChartLegendDot(
                label: 'P&L no realizado',
                color: pnlColor(latest.totalUnrealizedPL),
              ),
              ChartLegendDot(
                label: 'P&L realizado',
                color: colors.secondary,
              ),
              const ChartLegendDot(
                label: 'Dominancia BTC',
                color: Color(0xFFF7931A),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InfoLine(
            'Cambio en valor',
            money(valueChange),
            valueColor: pnlColor(valueChange),
            emphasized: true,
          ),
          InfoLine(
            'Cambio en P&L no realizado',
            money(plChange),
            valueColor: pnlColor(plChange),
          ),
          InfoLine('Último valor de cartera', money(latest.totalCurrentValue)),
        ],
      ),
    );
  }
}

class SnapshotLineChart extends StatelessWidget {
  final List<PortfolioSnapshot> snapshots;
  final List<SnapshotChartSeries> series;
  final double height;
  final bool includeZero;

  const SnapshotLineChart({
    super.key,
    required this.snapshots,
    required this.series,
    required this.height,
    required this.includeZero,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: SnapshotLineChartPainter(
          snapshots: snapshots,
          series: series,
          includeZero: includeZero,
          axisColor: Theme.of(context).colorScheme.outlineVariant,
          labelColor: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class SnapshotChartSeries {
  final String label;
  final Color color;
  final List<double> values;
  final String Function(double value)? valueFormatter;

  const SnapshotChartSeries({
    required this.label,
    required this.color,
    required this.values,
    this.valueFormatter,
  });
}

class SnapshotLineChartPainter extends CustomPainter {
  final List<PortfolioSnapshot> snapshots;
  final List<SnapshotChartSeries> series;
  final bool includeZero;
  final Color axisColor;
  final Color labelColor;

  SnapshotLineChartPainter({
    required this.snapshots,
    required this.series,
    required this.includeZero,
    required this.axisColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (snapshots.isEmpty || series.isEmpty) return;

    final Rect chart = Rect.fromLTWH(
      54,
      12,
      math.max(1, size.width - 66),
      math.max(1, size.height - 42),
    );

    final Iterable<double> allValues = series.expand(
      (SnapshotChartSeries s) => s.values,
    );
    double minValue = allValues.reduce(math.min);
    double maxValue = allValues.reduce(math.max);
    if (includeZero) {
      minValue = math.min(minValue, 0);
      maxValue = math.max(maxValue, 0);
    }

    if ((maxValue - minValue).abs() < 0.000001) {
      final double pad = math.max(1, maxValue.abs() * 0.1);
      minValue -= pad;
      maxValue += pad;
    }

    final Paint gridPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final double y = chart.top + chart.height * i / 4;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);

      final double value = maxValue - ((maxValue - minValue) * i / 4);
      final String label = series.length == 1 && series.first.valueFormatter != null
          ? series.first.valueFormatter!(value)
          : moneyShort(value);
      _drawLabel(canvas, label, Offset(0, y - 8), labelColor);
    }

    final int pointCount = snapshots.length;
    double xFor(int index) => pointCount == 1
        ? chart.center.dx
        : chart.left + chart.width * index / (pointCount - 1);
    double yFor(double value) =>
        chart.bottom -
        ((value - minValue) / (maxValue - minValue)).clamp(0.0, 1.0) *
            chart.height;

    for (final SnapshotChartSeries item in series) {
      if (item.values.length != pointCount) continue;

      final Path path = Path();
      for (int i = 0; i < pointCount; i++) {
        final Offset point = Offset(xFor(i), yFor(item.values[i]));
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }

      final Paint linePaint = Paint()
        ..color = item.color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, linePaint);

      final Paint dotPaint = Paint()..color = item.color;
      for (int i = 0; i < pointCount; i++) {
        canvas.drawCircle(Offset(xFor(i), yFor(item.values[i])), 3.5, dotPaint);
      }
    }

    _drawLabel(
      canvas,
      shortDate(snapshots.first.createdAt),
      Offset(chart.left, chart.bottom + 10),
      labelColor,
    );
    _drawLabel(
      canvas,
      shortDate(snapshots.last.createdAt),
      Offset(chart.right - 82, chart.bottom + 10),
      labelColor,
    );
  }

  void _drawLabel(Canvas canvas, String text, Offset offset, Color color) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 90);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant SnapshotLineChartPainter oldDelegate) {
    return oldDelegate.snapshots != snapshots ||
        oldDelegate.series != series ||
        oldDelegate.axisColor != axisColor ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.includeZero != includeZero;
  }
}

class ChartLegendDot extends StatelessWidget {
  final String label;
  final Color color;

  const ChartLegendDot({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}


String _positionStatusLabel(CoinStats stats, double sellFeePercent) {
  if (stats.quantity <= 0) return 'Sin posición';
  if (stats.isAtOrAboveNetBreakEven(sellFeePercent)) return 'Arriba del equilibrio';
  final double distance = stats.percentToNetBreakEven(sellFeePercent);
  if (stats.unrealizedPL < 0 && distance > 25) return 'Fuerte pérdida';
  if (distance > 10) return 'Debajo del equilibrio';
  return 'Vigilar';
}

class PremiumMetricData {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const PremiumMetricData({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });
}

class PremiumDashboardHero extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<PremiumMetricData> metrics;

  const PremiumDashboardHero({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colors.primaryContainer.withValues(alpha: 0.92),
            colors.surfaceContainerHighest.withValues(alpha: 0.88),
          ],
        ),
        border: Border.all(color: colors.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              Icon(icon, color: colors.primary, size: 30),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: metrics
                .map(
                  (PremiumMetricData metric) => _HeaderMetric(
                    label: metric.label,
                    value: metric.value,
                    icon: metric.icon,
                    color: metric.color,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class PremiumSegmentShell extends StatelessWidget {
  final Widget child;

  const PremiumSegmentShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Center(child: child),
    );
  }
}

class PremiumMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const PremiumMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(icon, color: color ?? Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(fontWeight: FontWeight.w900, color: color),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PremiumInfoPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final Color? badgeColor;

  const PremiumInfoPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (badge != null)
              StatusPill(label: badge!, positive: (badgeColor ?? Colors.green) == Colors.green),
          ],
        ),
      ),
    );
  }
}

class MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const MiniMetric({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 126, maxWidth: 180),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w900, color: color),
          ),
        ],
      ),
    );
  }
}

class CardPanel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTap;

  const CardPanel({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: onTap == null ? Clip.none : Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

class SheetHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;

  const SheetHeader({super.key, required this.title, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
      ],
    );
  }
}

class MetricTile extends StatelessWidget {
  final String title;
  final String value;
  final Color? valueColor;

  const MetricTile({
    super.key,
    required this.title,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: valueColor),
          ),
        ],
      ),
    );
  }
}

class SimpleValue extends StatelessWidget {
  final String title;
  final String value;
  final Color? color;

  const SimpleValue({
    super.key,
    required this.title,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}

class InfoLine extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;
  final Color? valueColor;

  const InfoLine(
    this.label,
    this.value, {
    super.key,
    this.emphasized = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(flex: 5, child: Text(label)),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: emphasized ? FontWeight.w700 : FontWeight.w400,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String label;
  final bool positive;

  const StatusPill({super.key, required this.label, required this.positive});

  @override
  Widget build(BuildContext context) {
    final MaterialColor color = positive ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.bold, color: color.shade700),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 44),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}


List<CoinStats> sortedPositions(
  Iterable<CoinStats> positions,
  PositionSortMode mode,
  double sellFeePercent,
) {
  final List<CoinStats> sorted = positions.toList();
  switch (mode) {
    case PositionSortMode.largestValue:
      sorted.sort(
        (CoinStats a, CoinStats b) => b.currentValue.compareTo(a.currentValue),
      );
      break;
    case PositionSortMode.largestLoss:
      sorted.sort(
        (CoinStats a, CoinStats b) => a.unrealizedPL.compareTo(b.unrealizedPL),
      );
      break;
    case PositionSortMode.closestBreakEven:
      sorted.sort((CoinStats a, CoinStats b) {
        final double da = (a.percentToNetBreakEven(sellFeePercent)).abs();
        final double db = (b.percentToNetBreakEven(sellFeePercent)).abs();
        return da.compareTo(db);
      });
      break;
    case PositionSortMode.manual:
      sorted.sort((CoinStats a, CoinStats b) => a.coin.compareTo(b.coin));
      break;
  }
  return sorted;
}

ThemeData buildPremiumTheme(AppPalette palette, Brightness brightness) {
  final ColorScheme scheme = palette.toColorScheme(brightness);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    cardTheme: CardThemeData(
      elevation: 0,
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: palette.border.withValues(alpha: 0.55)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background,
      foregroundColor: palette.textMain,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.surface,
      indicatorColor: palette.primarySoft,
      labelTextStyle: WidgetStateProperty.all(
        TextStyle(color: palette.textMain, fontWeight: FontWeight.w700),
      ),
    ),
    dividerColor: palette.border,
    chipTheme: ChipThemeData(
      backgroundColor: palette.surfaceAlt,
      selectedColor: palette.primarySoft,
      side: BorderSide(color: palette.border),
      labelStyle: TextStyle(color: palette.textMain),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: palette.border),
      ),
    ),
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
          bodyColor: palette.textMain,
          displayColor: palette.textMain,
        ),
  );
}

enum AppVisualMode { system, light, dark }

extension AppVisualModeLabel on AppVisualMode {
  String get label {
    switch (this) {
      case AppVisualMode.system:
        return 'Auto';
      case AppVisualMode.light:
        return 'Claro';
      case AppVisualMode.dark:
        return 'Oscuro';
    }
  }

  ThemeMode get themeMode {
    switch (this) {
      case AppVisualMode.system:
        return ThemeMode.system;
      case AppVisualMode.light:
        return ThemeMode.light;
      case AppVisualMode.dark:
        return ThemeMode.dark;
    }
  }
}

AppVisualMode appVisualModeFromName(String? value) {
  for (final AppVisualMode mode in AppVisualMode.values) {
    if (mode.name == value) return mode;
  }
  return AppVisualMode.system;
}

class AppPalette {
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color primary;
  final Color primarySoft;
  final Color border;
  final Color positive;
  final Color negative;
  final Color warning;
  final Color textMain;
  final Color textMuted;

  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.primary,
    required this.primarySoft,
    required this.border,
    required this.positive,
    required this.negative,
    required this.warning,
    required this.textMain,
    required this.textMuted,
  });

  ColorScheme toColorScheme(Brightness brightness) =>
      ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
        primary: primary,
        onPrimary: _bestOnColor(primary),
        primaryContainer: primarySoft,
        onPrimaryContainer: textMain,
        secondary: positive,
        onSecondary: _bestOnColor(positive),
        secondaryContainer: positive.withValues(alpha: 0.18),
        onSecondaryContainer: textMain,
        tertiary: warning,
        onTertiary: _bestOnColor(warning),
        tertiaryContainer: warning.withValues(alpha: 0.20),
        onTertiaryContainer: textMain,
        error: negative,
        onError: _bestOnColor(negative),
        errorContainer: negative.withValues(alpha: 0.18),
        onErrorContainer: textMain,
        surface: surface,
        onSurface: textMain,
        surfaceContainerHighest: surfaceAlt,
        onSurfaceVariant: textMuted,
        outline: border,
        outlineVariant: border.withValues(alpha: 0.55),
        shadow: Colors.black,
        scrim: Colors.black,
        inverseSurface: textMain,
        onInverseSurface: surface,
        inversePrimary: primarySoft,
      );

}

Color _bestOnColor(Color color) {
  return color.computeLuminance() > 0.45 ? Colors.black : Colors.white;
}

enum AppThemeStyle {
  proDark,
  graphite,
  institutionalBlue,
  bitcoinDark,
  terminalGreen,
  highContrast,
}

extension AppThemeStyleDetails on AppThemeStyle {
  String get label {
    switch (this) {
      case AppThemeStyle.proDark:
        return 'Pro oscuro';
      case AppThemeStyle.graphite:
        return 'Grafito';
      case AppThemeStyle.institutionalBlue:
        return 'Azul institucional';
      case AppThemeStyle.bitcoinDark:
        return 'Bitcoin dark';
      case AppThemeStyle.terminalGreen:
        return 'Verde terminal';
      case AppThemeStyle.highContrast:
        return 'Alto contraste';
    }
  }

  String get description {
    switch (this) {
      case AppThemeStyle.proDark:
        return 'Negro profundo con acentos violeta premium.';
      case AppThemeStyle.graphite:
        return 'Neutros sobrios para lectura prolongada.';
      case AppThemeStyle.institutionalBlue:
        return 'Azules financieros con contraste limpio.';
      case AppThemeStyle.bitcoinDark:
        return 'Carbón y naranja BTC en paleta completa.';
      case AppThemeStyle.terminalGreen:
        return 'Oscuro técnico con energía terminal.';
      case AppThemeStyle.highContrast:
        return 'Máxima legibilidad y bordes marcados.';
    }
  }

  AppPalette get palette {
    switch (this) {
      case AppThemeStyle.proDark:
        return const AppPalette(
          background: Color(0xFF090B12),
          surface: Color(0xFF111520),
          surfaceAlt: Color(0xFF1B2233),
          primary: Color(0xFF9B8CFF),
          primarySoft: Color(0xFF28234F),
          border: Color(0xFF30384C),
          positive: Color(0xFF22C55E),
          negative: Color(0xFFEF4444),
          warning: Color(0xFFF59E0B),
          textMain: Color(0xFFF8FAFC),
          textMuted: Color(0xFF94A3B8),
        );
      case AppThemeStyle.graphite:
        return const AppPalette(
          background: Color(0xFF111315),
          surface: Color(0xFF1B1F23),
          surfaceAlt: Color(0xFF272C31),
          primary: Color(0xFFCBD5E1),
          primarySoft: Color(0xFF334155),
          border: Color(0xFF3B424A),
          positive: Color(0xFF16A34A),
          negative: Color(0xFFDC2626),
          warning: Color(0xFFD97706),
          textMain: Color(0xFFF1F5F9),
          textMuted: Color(0xFFA1A1AA),
        );
      case AppThemeStyle.institutionalBlue:
        return const AppPalette(
          background: Color(0xFF07111F),
          surface: Color(0xFF0E1B2E),
          surfaceAlt: Color(0xFF162A46),
          primary: Color(0xFF60A5FA),
          primarySoft: Color(0xFF12345C),
          border: Color(0xFF25496F),
          positive: Color(0xFF10B981),
          negative: Color(0xFFF43F5E),
          warning: Color(0xFFFBBF24),
          textMain: Color(0xFFF8FAFC),
          textMuted: Color(0xFF93A8C2),
        );
      case AppThemeStyle.bitcoinDark:
        return const AppPalette(
          background: Color(0xFF0D0A06),
          surface: Color(0xFF17110A),
          surfaceAlt: Color(0xFF2A1B0D),
          primary: Color(0xFFF7931A),
          primarySoft: Color(0xFF3A220C),
          border: Color(0xFF5C3A16),
          positive: Color(0xFF22C55E),
          negative: Color(0xFFEF4444),
          warning: Color(0xFFF59E0B),
          textMain: Color(0xFFFFFBEB),
          textMuted: Color(0xFFD6B98A),
        );
      case AppThemeStyle.terminalGreen:
        return const AppPalette(
          background: Color(0xFF020A06),
          surface: Color(0xFF07140D),
          surfaceAlt: Color(0xFF0E2618),
          primary: Color(0xFF39FF88),
          primarySoft: Color(0xFF073D20),
          border: Color(0xFF176B3A),
          positive: Color(0xFF22C55E),
          negative: Color(0xFFF87171),
          warning: Color(0xFFFACC15),
          textMain: Color(0xFFEFFFF5),
          textMuted: Color(0xFF88B99C),
        );
      case AppThemeStyle.highContrast:
        return const AppPalette(
          background: Color(0xFF000000),
          surface: Color(0xFF0B0B0B),
          surfaceAlt: Color(0xFF1F1F1F),
          primary: Color(0xFFFFFFFF),
          primarySoft: Color(0xFF2C2C2C),
          border: Color(0xFFFFFFFF),
          positive: Color(0xFF00E676),
          negative: Color(0xFFFF1744),
          warning: Color(0xFFFFD600),
          textMain: Color(0xFFFFFFFF),
          textMuted: Color(0xFFE0E0E0),
        );
    }
  }
}

AppThemeStyle appThemeStyleFromName(String? value) {
  switch (value) {
    case 'green':
      return AppThemeStyle.terminalGreen;
    case 'blue':
      return AppThemeStyle.institutionalBlue;
    case 'orange':
    case 'bitcoin':
      return AppThemeStyle.bitcoinDark;
    case 'grey':
      return AppThemeStyle.graphite;
  }
  for (final AppThemeStyle style in AppThemeStyle.values) {
    if (style.name == value) return style;
  }
  return AppThemeStyle.proDark;
}

enum VisiblePositions { one, two, three, five, all }

extension VisiblePositionsDetails on VisiblePositions {
  String get label {
    switch (this) {
      case VisiblePositions.one:
        return '1';
      case VisiblePositions.two:
        return '2';
      case VisiblePositions.three:
        return '3';
      case VisiblePositions.five:
        return '5';
      case VisiblePositions.all:
        return 'Todas';
    }
  }

  int? get limit {
    switch (this) {
      case VisiblePositions.one:
        return 1;
      case VisiblePositions.two:
        return 2;
      case VisiblePositions.three:
        return 3;
      case VisiblePositions.five:
        return 5;
      case VisiblePositions.all:
        return null;
    }
  }
}

VisiblePositions visiblePositionsFromName(String? value) {
  for (final VisiblePositions option in VisiblePositions.values) {
    if (option.name == value) return option;
  }
  return VisiblePositions.three;
}

enum PositionSortMode { largestValue, largestLoss, closestBreakEven, manual }

extension PositionSortModeDetails on PositionSortMode {
  String get label {
    switch (this) {
      case PositionSortMode.largestValue:
        return 'Mayor valor';
      case PositionSortMode.largestLoss:
        return 'Mayor pérdida';
      case PositionSortMode.closestBreakEven:
        return 'Más cerca del equilibrio';
      case PositionSortMode.manual:
        return 'Manual';
    }
  }
}

PositionSortMode positionSortModeFromName(String? value) {
  for (final PositionSortMode mode in PositionSortMode.values) {
    if (mode.name == value) return mode;
  }
  return PositionSortMode.largestValue;
}

enum SnapshotTrigger { appOpen, priceUpdate, movementChange, daily }

enum SnapshotAutomationMode {
  manual,
  appOpen24h,
  afterPriceUpdate,
  afterMovementChange,
  daily,
}

extension SnapshotAutomationModeDetails on SnapshotAutomationMode {
  String get label {
    switch (this) {
      case SnapshotAutomationMode.manual:
        return 'Solo manual';
      case SnapshotAutomationMode.appOpen24h:
        return 'Al abrir si pasaron 24h';
      case SnapshotAutomationMode.afterPriceUpdate:
        return 'Después de actualizar precios';
      case SnapshotAutomationMode.afterMovementChange:
        return 'Después de cambiar movimientos';
      case SnapshotAutomationMode.daily:
        return 'Diario';
    }
  }

  bool shouldCapture(
    SnapshotTrigger trigger,
    List<PortfolioSnapshot> snapshots,
  ) {
    final DateTime? latest = snapshots.isEmpty
        ? null
        : snapshots.first.createdAt;
    final bool olderThan24h = latest == null ||
        DateTime.now().difference(latest) >= const Duration(hours: 24);
    switch (this) {
      case SnapshotAutomationMode.manual:
        return false;
      case SnapshotAutomationMode.appOpen24h:
        return trigger == SnapshotTrigger.appOpen && olderThan24h;
      case SnapshotAutomationMode.afterPriceUpdate:
        return trigger == SnapshotTrigger.priceUpdate;
      case SnapshotAutomationMode.afterMovementChange:
        return trigger == SnapshotTrigger.movementChange;
      case SnapshotAutomationMode.daily:
        return olderThan24h &&
            (trigger == SnapshotTrigger.appOpen ||
                trigger == SnapshotTrigger.daily);
    }
  }
}

SnapshotAutomationMode snapshotAutomationModeFromName(String? value) {
  for (final SnapshotAutomationMode mode in SnapshotAutomationMode.values) {
    if (mode.name == value) return mode;
  }
  return SnapshotAutomationMode.manual;
}

enum SnapshotRetention { last30, last90, unlimited }

extension SnapshotRetentionDetails on SnapshotRetention {
  String get label {
    switch (this) {
      case SnapshotRetention.last30:
        return 'Últimos 30';
      case SnapshotRetention.last90:
        return 'Últimos 90';
      case SnapshotRetention.unlimited:
        return 'Ilimitado';
    }
  }

  int? get limit {
    switch (this) {
      case SnapshotRetention.last30:
        return 30;
      case SnapshotRetention.last90:
        return 90;
      case SnapshotRetention.unlimited:
        return null;
    }
  }
}

SnapshotRetention snapshotRetentionFromName(String? value) {
  for (final SnapshotRetention retention in SnapshotRetention.values) {
    if (retention.name == value) return retention;
  }
  return SnapshotRetention.last30;
}
enum MovementType { buy, sell, transferIn, transferOut }

enum SimulationMode { operation, rotation }

enum OperationSimulationMode { buy, sell }

enum SimulationSellMethod { percent, quantity, grossAmount }

enum SimulationRotationMethod { percent, quantity, grossAmount }

extension MovementLabel on MovementType {
  String get label {
    switch (this) {
      case MovementType.buy:
        return 'Compra';
      case MovementType.sell:
        return 'Venta';
      case MovementType.transferIn:
        return 'Transferencia recibida';
      case MovementType.transferOut:
        return 'Transferencia enviada';
    }
  }

  String get shortLabel {
    switch (this) {
      case MovementType.buy:
        return 'Compra';
      case MovementType.sell:
        return 'Venta';
      case MovementType.transferIn:
        return 'Entrada';
      case MovementType.transferOut:
        return 'Salida';
    }
  }
}

MovementType movementTypeFromAny(dynamic value) {
  final String raw = value?.toString().trim().toLowerCase() ?? '';

  if (raw == 'buy' || raw == 'compra' || raw == 'comprar') {
    return MovementType.buy;
  }

  if (raw == 'sell' || raw == 'venta' || raw == 'vender') {
    return MovementType.sell;
  }

  if (raw == 'transferin' ||
      raw == 'transfer_in' ||
      raw == 'transferenciaentrada' ||
      raw == 'transferencia_entrada' ||
      raw == 'transferencia recibida' ||
      raw == 'recibida' ||
      raw == 'entrada') {
    return MovementType.transferIn;
  }

  if (raw == 'transferout' ||
      raw == 'transfer_out' ||
      raw == 'transferenciasalida' ||
      raw == 'transferencia_salida' ||
      raw == 'transferencia enviada' ||
      raw == 'enviada' ||
      raw == 'salida') {
    return MovementType.transferOut;
  }

  return MovementType.buy;
}

class Movement {
  final MovementType type;
  final String coin;
  final DateTime date;
  final double quantity;
  final double unitPrice;
  final double fee;
  final String source;
  final String wallet;
  final String network;
  final String note;

  Movement({
    required this.type,
    required this.coin,
    required this.date,
    required this.quantity,
    required this.unitPrice,
    required this.fee,
    this.source = '',
    this.wallet = '',
    this.network = '',
    required this.note,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type.name,
    'coin': coin,
    'date': date.toIso8601String(),
    'quantity': quantity,
    'unitPrice': unitPrice,
    'fee': fee,
    'source': source,
    'wallet': wallet,
    'network': network,
    'note': note,
  };

  factory Movement.fromJson(Map<String, dynamic> json) {
    return Movement(
      type: movementTypeFromAny(json['type']),
      coin: (json['coin'] ?? json['crypto'] ?? 'BTC').toString().toUpperCase(),
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      quantity: numberFromJson(json['quantity']),
      unitPrice: numberFromJson(json['unitPrice'] ?? json['unit_price']),
      fee: numberFromJson(json['fee'] ?? json['commission']),
      source: textFromJson(json['source'] ?? json['origin'] ?? json['origen']),
      wallet: textFromJson(json['wallet'] ?? json['cartera']),
      network: textFromJson(json['network'] ?? json['red']),
      note: json['note']?.toString() ?? '',
    );
  }
}

class CoinStats {
  final String coin;
  double quantity;
  double costBase;
  double currentPrice;
  double realizedPL;
  double feesPaid;

  CoinStats({
    required this.coin,
    this.quantity = 0.0,
    this.costBase = 0.0,
    this.currentPrice = 0.0,
    this.realizedPL = 0.0,
    this.feesPaid = 0.0,
  });

  double get avgPrice => quantity > 0 ? costBase / quantity : 0.0;
  double get currentValue => quantity * currentPrice;
  double get unrealizedPL => currentValue - costBase;

  double netBreakEvenPrice(double sellFeePercent) {
    if (quantity <= 0) return 0.0;
    final double multiplier = 1 - (sellFeePercent / 100);
    if (multiplier <= 0) return 0.0;
    return avgPrice / multiplier;
  }

  double targetNetExitPrice(double sellFeePercent, double targetPercent) {
    if (quantity <= 0) return 0.0;
    final double multiplier = 1 - (sellFeePercent / 100);
    if (multiplier <= 0) return 0.0;
    return (costBase * (1 + targetPercent / 100)) / (quantity * multiplier);
  }

  double percentToNetBreakEven(double sellFeePercent) {
    if (quantity <= 0 || currentPrice <= 0) return 0.0;
    final double target = netBreakEvenPrice(sellFeePercent);
    if (target <= 0) return 0.0;
    return ((target / currentPrice) - 1) * 100;
  }

  bool isAtOrAboveNetBreakEven(double sellFeePercent) {
    if (quantity <= 0) return true;
    return currentPrice >= netBreakEvenPrice(sellFeePercent);
  }
}

class CoinAudit {
  final double buys;
  final double sells;
  final double transferIns;
  final double transferOuts;
  final double fees;

  CoinAudit({
    required this.buys,
    required this.sells,
    required this.transferIns,
    required this.transferOuts,
    required this.fees,
  });
}

class PortfolioTotals {
  final double costBase;
  final double currentValue;
  final double unrealizedPL;
  final double realizedPL;

  PortfolioTotals({
    required this.costBase,
    required this.currentValue,
    required this.unrealizedPL,
    required this.realizedPL,
  });
}

class CoinSnapshot {
  final String coin;
  final double quantity;
  final double costBase;
  final double avgPrice;
  final double currentValue;
  final double unrealizedPL;
  final double realizedPL;

  CoinSnapshot({
    required this.coin,
    required this.quantity,
    required this.costBase,
    required this.avgPrice,
    required this.currentValue,
    required this.unrealizedPL,
    required this.realizedPL,
  });

  factory CoinSnapshot.fromStats(CoinStats stats) => CoinSnapshot(
    coin: stats.coin,
    quantity: stats.quantity,
    costBase: stats.costBase,
    avgPrice: stats.avgPrice,
    currentValue: stats.currentValue,
    unrealizedPL: stats.unrealizedPL,
    realizedPL: stats.realizedPL,
  );

  factory CoinSnapshot.fromJson(Map<String, dynamic> json) => CoinSnapshot(
    coin: json['coin'] as String,
    quantity: (json['quantity'] as num).toDouble(),
    costBase: (json['costBase'] as num).toDouble(),
    avgPrice: (json['avgPrice'] as num).toDouble(),
    currentValue: (json['currentValue'] as num).toDouble(),
    unrealizedPL: (json['unrealizedPL'] as num).toDouble(),
    realizedPL: (json['realizedPL'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'coin': coin,
    'quantity': quantity,
    'costBase': costBase,
    'avgPrice': avgPrice,
    'currentValue': currentValue,
    'unrealizedPL': unrealizedPL,
    'realizedPL': realizedPL,
  };
}

class PortfolioSnapshot {
  final String id;
  final DateTime createdAt;
  final double totalCostBase;
  final double totalCurrentValue;
  final double totalUnrealizedPL;
  final double totalRealizedPL;
  final int movementCount;
  final List<CoinSnapshot> coins;

  PortfolioSnapshot({
    required this.id,
    required this.createdAt,
    required this.totalCostBase,
    required this.totalCurrentValue,
    required this.totalUnrealizedPL,
    required this.totalRealizedPL,
    required this.movementCount,
    required this.coins,
  });

  String get dominantCoinLabel {
    final List<CoinSnapshot> active = coins
        .where((CoinSnapshot coin) => coin.currentValue > 0)
        .toList()
      ..sort(
        (CoinSnapshot a, CoinSnapshot b) =>
            b.currentValue.compareTo(a.currentValue),
      );
    if (active.isEmpty) return 'Sin posición dominante';
    final CoinSnapshot leader = active.first;
    final double share = totalCurrentValue <= 0
        ? 0.0
        : (leader.currentValue / totalCurrentValue) * 100;
    return '${leader.coin} · ${pct(share)}';
  }


  double get btcDominancePercent {
    if (totalCurrentValue <= 0) return 0.0;
    final double btcValue = coins
        .where((CoinSnapshot coin) => coin.coin.toUpperCase() == 'BTC')
        .fold<double>(0.0, (double total, CoinSnapshot coin) => total + coin.currentValue);
    return (btcValue / totalCurrentValue) * 100;
  }

  factory PortfolioSnapshot.fromJson(Map<String, dynamic> json) {
    return PortfolioSnapshot(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      totalCostBase: (json['totalCostBase'] as num).toDouble(),
      totalCurrentValue: (json['totalCurrentValue'] as num).toDouble(),
      totalUnrealizedPL: (json['totalUnrealizedPL'] as num).toDouble(),
      totalRealizedPL: (json['totalRealizedPL'] as num).toDouble(),
      movementCount: json['movementCount'] as int,
      coins: (json['coins'] as List<dynamic>)
          .map(
            (dynamic e) =>
                CoinSnapshot.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'totalCostBase': totalCostBase,
    'totalCurrentValue': totalCurrentValue,
    'totalUnrealizedPL': totalUnrealizedPL,
    'totalRealizedPL': totalRealizedPL,
    'movementCount': movementCount,
    'coins': coins.map((CoinSnapshot c) => c.toJson()).toList(),
  };
}

double numberFromJson(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

String textFromJson(dynamic value) => value?.toString().trim() ?? '';

DateTime dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

const Duration days1 = Duration(days: 1);

String money(double value) => '\$${value.toStringAsFixed(2)} MXN';

String moneyShort(double value) => '\$${value.toStringAsFixed(0)}';

String crypto(double value) => value.toStringAsFixed(8);

String pct(double value) => '${value.toStringAsFixed(2)}%';

String intervalLabel(int minutes) {
  switch (minutes) {
    case 15:
      return '15 min';
    case 30:
      return '30 min';
    case 60:
      return '1 h';
    case 360:
      return '6 h';
    case 1440:
      return 'Diario';
  }
  return '$minutes min';
}

String fixed(double value, int decimals) => value.toStringAsFixed(decimals);

String compact(double value) {
  final String text = value.toStringAsFixed(8);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

String shortDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String longDate(DateTime date) {
  return '${shortDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String priceUpdatedLabel(DateTime? updatedAt) {
  if (updatedAt == null) return 'Sin actualización registrada';

  final Duration age = DateTime.now().difference(updatedAt);
  if (age.inMinutes < 1) return 'Actualizado hace menos de 1 min';
  if (age.inHours < 1) {
    return 'Actualizado hace ${age.inMinutes} min';
  }
  if (age.inDays < 1) {
    return 'Actualizado hace ${age.inHours} h';
  }

  return 'Actualizado ${longDate(updatedAt)}';
}

String isoDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String csvEscape(Object? value) {
  final String text = value?.toString() ?? '';
  final bool needsEscape =
      text.contains(',') || text.contains('"') || text.contains('\n');
  final String escaped = text.replaceAll('"', '""');
  return needsEscape ? '"$escaped"' : escaped;
}

void _appendExcelRow(xl.Sheet sheet, List<Object?> values) {
  sheet.appendRow(values.map(toExcelValue).toList());
}

xl.CellValue? toExcelValue(Object? value) {
  if (value is int) return xl.IntCellValue(value);
  if (value is double) return xl.DoubleCellValue(value);
  return xl.TextCellValue(value?.toString() ?? '');
}

Color pnlColor(double value) {
  if (value > 0) return const Color(0xFF16A34A);
  if (value < 0) return const Color(0xFFDC2626);
  return Colors.grey.shade700;
}
