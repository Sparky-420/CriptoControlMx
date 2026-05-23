import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/price_service.dart';

void main() {
  runApp(const CriptoControlApp());
}

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

  final List<Movement> _movements = <Movement>[];
  final List<PortfolioSnapshot> _snapshots = <PortfolioSnapshot>[];
  final PriceService _priceService = PriceService();

  final Map<String, double> _currentPrices = <String, double>{
    'BTC': 0.0,
    'ETH': 0.0,
    'LINK': 0.0,
    'LTC': 0.0,
    'UNI': 0.0,
  };

  int _currentIndex = 0;
  double _sellFeePercent = 0.0;
  bool _darkMode = false;
  DateTime? _pricesUpdatedAt;
  bool _isRefreshingPrices = false;

  @override
  void initState() {
    super.initState();
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
    _darkMode = prefs.getBool(_darkModeKey) ?? false;

    if (mounted) setState(() {});

    await _refreshPricesIfNeeded(prefs);
  }

  void _applyPriceCache(PriceCache cache) {
    for (final String coin in _coins) {
      _currentPrices[coin] = cache.prices[coin] ?? 0.0;
    }
    _pricesUpdatedAt = cache.updatedAt;
  }

  Future<void> _refreshPricesIfNeeded(SharedPreferences prefs) async {
    final PriceCache priceCache = await _priceService.refreshIfStale(prefs);
    if (!mounted) return;

    setState(() => _applyPriceCache(priceCache));
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

      setState(() => _applyPriceCache(priceCache));
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
    await prefs.setBool(_darkModeKey, _darkMode);
  }

  Future<void> _saveSnapshots() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _snapshotsKey,
      jsonEncode(_snapshots.map((PortfolioSnapshot s) => s.toJson()).toList()),
    );
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

  void _toggleDarkMode(bool value) {
    setState(() => _darkMode = value);
    _saveData();
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

  void _showAddMovementSheet(
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

    showModalBottomSheet<void>(
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

                              _saveData();
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
                    'Vale hoy',
                    money(stats.currentValue),
                    emphasized: true,
                  ),
                  InfoLine(
                    'Resultado actual',
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
                    'Resultado vendido',
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
                  Text('Resultado actual = vale hoy - invertido actual'),
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
    final Map<String, CoinStats> stats = _computeStats();
    final PortfolioTotals totals = _totals(stats);

    final PortfolioSnapshot snapshot = PortfolioSnapshot(
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

    setState(() {
      _snapshots.insert(0, snapshot);
      _snapshots.sort(
        (PortfolioSnapshot a, PortfolioSnapshot b) =>
            b.createdAt.compareTo(a.createdAt),
      );
    });

    await _saveSnapshots();

    if (mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Snapshot guardado')),
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
                          title: 'Snapshots',
                          onClose: () => Navigator.of(sheetContext).pop(),
                        ),
                        const SizedBox(height: 12),
                        if (_snapshots.isEmpty)
                          const EmptyState(
                            icon: Icons.photo_library_outlined,
                            title: 'Sin snapshots',
                            subtitle:
                                'Guarda una foto de cartera desde Ajustes.',
                          )
                        else
                          ..._snapshots.map(
                            (PortfolioSnapshot snapshot) => CardPanel(
                              title: longDate(snapshot.createdAt),
                              trailing: IconButton(
                                tooltip: 'Borrar snapshot',
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
                                  InfoLine(
                                    'Invertido',
                                    money(snapshot.totalCostBase),
                                  ),
                                  InfoLine(
                                    'Vale hoy',
                                    money(snapshot.totalCurrentValue),
                                  ),
                                  InfoLine(
                                    'Resultado actual',
                                    money(snapshot.totalUnrealizedPL),
                                    valueColor: pnlColor(
                                      snapshot.totalUnrealizedPL,
                                    ),
                                    emphasized: true,
                                  ),
                                  InfoLine(
                                    'Resultado vendido',
                                    money(snapshot.totalRealizedPL),
                                    valueColor: pnlColor(
                                      snapshot.totalRealizedPL,
                                    ),
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
              <String>['Vale hoy', money(totals.currentValue)],
              <String>['Resultado actual', money(totals.unrealizedPL)],
              <String>['Resultado vendido', money(totals.realizedPL)],
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
              'Vale hoy',
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
      successMessage: 'Snapshots CSV listo',
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
                final dynamic decoded = jsonDecode(controller.text.trim());
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
                      (dynamic e) => Movement.fromJson(
                        Map<String, dynamic>.from(e as Map),
                      ),
                    )
                    .toList();

                setState(() {
                  _movements
                    ..clear()
                    ..addAll(imported);

                  final Map<String, dynamic> pricesMap =
                      Map<String, dynamic>.from(pricesRaw);

                  for (final String coin in _coins) {
                    final dynamic value = pricesMap[coin];
                    _currentPrices[coin] = value is num
                        ? value.toDouble()
                        : 0.0;
                  }

                  if (settingsRaw is Map &&
                      settingsRaw['sellFeePercent'] is num) {
                    _sellFeePercent = (settingsRaw['sellFeePercent'] as num)
                        .toDouble();
                  }
                });

                await _saveData();

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

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, CoinStats> stats = _computeStats();
    final PortfolioTotals totals = _totals(stats);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CriptoControlMx',
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF7FAF2),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
        brightness: Brightness.dark,
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      home: Builder(
        builder: (BuildContext pageContext) {
          final List<Widget> pages = <Widget>[
            SummaryTab(
              stats: stats,
              totals: totals,
              sellFeePercent: _sellFeePercent,
              onDetails: (CoinStats s) => _showCoinDetails(pageContext, s),
            ),
            MovementsTab(
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
                _saveData();
              },
            ),
            SimulationTab(coins: _coins, stats: stats, defaultFeePercent: 1.5),
            CoinsTab(
              coins: _coins,
              stats: stats,
              sellFeePercent: _sellFeePercent,
              onEditPrice: (String coin) =>
                  _showEditPriceDialog(pageContext, coin),
              onDetails: (CoinStats s) => _showCoinDetails(pageContext, s),
            ),
            SettingsTab(
              darkMode: _darkMode,
              sellFeePercent: _sellFeePercent,
              snapshotCount: _snapshots.length,
              pricesUpdatedAt: _pricesUpdatedAt,
              isRefreshingPrices: _isRefreshingPrices,
              onDarkModeChanged: _toggleDarkMode,
              onRefreshPrices: () => _refreshPricesNow(pageContext),
              onEditSellFee: () => _showSellFeeDialog(pageContext),
              onSaveSnapshot: () => _saveSnapshot(pageContext),
              onViewSnapshots: () => _showSnapshots(pageContext),
              onExportMovementsCsv: () => _exportMovementsCsv(pageContext),
              onExportSummaryCsv: () => _exportSummaryCsv(pageContext),
              onExportSnapshotsCsv: () => _exportSnapshotsCsv(pageContext),
              onExportXlsx: () => _exportXlsx(pageContext),
              onExportPdf: () => _exportPdf(pageContext),
              onExportBackup: () => _exportBackup(pageContext),
              onImportBackup: () => _importBackup(pageContext),
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
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  label: 'Resumen',
                ),
                NavigationDestination(
                  icon: Icon(Icons.swap_horiz),
                  label: 'Movimientos',
                ),
                NavigationDestination(icon: Icon(Icons.tune), label: 'Simular'),
                NavigationDestination(
                  icon: Icon(Icons.currency_bitcoin),
                  label: 'Monedas',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: 'Ajustes',
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
  final void Function(CoinStats stats) onDetails;

  const SummaryTab({
    super.key,
    required this.stats,
    required this.totals,
    required this.sellFeePercent,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final List<CoinStats> active = stats.values
        .where((CoinStats s) => s.quantity > 0)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        CardPanel(
          title: 'Vista rápida',
          subtitle: 'Lo esencial de tu cartera, sin tecnicismos.',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              MetricTile(title: 'Vale hoy', value: money(totals.currentValue)),
              MetricTile(title: 'Invertido', value: money(totals.costBase)),
              MetricTile(
                title: 'Resultado actual',
                value: money(totals.unrealizedPL),
                valueColor: pnlColor(totals.unrealizedPL),
              ),
              MetricTile(
                title: 'Resultado vendido',
                value: money(totals.realizedPL),
                valueColor: pnlColor(totals.realizedPL),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Posiciones',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (active.isEmpty)
          const EmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Sin posiciones abiertas',
            subtitle: 'Agrega un movimiento para empezar.',
          )
        else
          ...active.map(
            (CoinStats s) => CleanCoinCard(
              stats: s,
              sellFeePercent: sellFeePercent,
              onDetails: () => onDetails(s),
            ),
          ),
      ],
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
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  stats.coin,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                StatusPill(
                  label: isRecovered ? 'Recuperado' : 'Debajo del equilibrio',
                  positive: isRecovered,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text('Vale hoy', style: Theme.of(context).textTheme.bodyMedium),
            Text(
              money(stats.currentValue),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: SimpleValue(
                    title: 'Resultado actual',
                    value: money(stats.unrealizedPL),
                    color: pnlColor(stats.unrealizedPL),
                  ),
                ),
                Expanded(
                  child: SimpleValue(
                    title: 'Falta para recuperar',
                    value: distance,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onDetails,
                icon: const Icon(Icons.info_outline),
                label: const Text('Ver detalles'),
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
  final VoidCallback onAdd;
  final void Function(Movement movement) onEdit;
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
            onPressed: widget.onAdd,
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
              trailing: PopupMenuButton<String>(
                onSelected: (String value) {
                  if (value == 'edit') widget.onEdit(m);
                  if (value == 'delete') widget.onDelete(m);
                },
                itemBuilder: (BuildContext context) =>
                    const <PopupMenuEntry<String>>[
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

  const SimulationTab({
    super.key,
    required this.coins,
    required this.stats,
    required this.defaultFeePercent,
  });

  @override
  State<SimulationTab> createState() => _SimulationTabState();
}

class _SimulationTabState extends State<SimulationTab> {
  String _coin = 'LINK';
  ScenarioType _type = ScenarioType.buy;

  final TextEditingController _amountController = TextEditingController(
    text: '1000',
  );
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _feeController = TextEditingController(
    text: '1.5',
  );

  @override
  void dispose() {
    _amountController.dispose();
    _priceController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.coins.contains(_coin)) _coin = widget.coins.first;

    final CoinStats stats = widget.stats[_coin] ?? CoinStats(coin: _coin);

    if (_priceController.text.isEmpty && stats.currentPrice > 0) {
      _priceController.text = compact(stats.currentPrice);
    }

    final ScenarioResult result = _calculate(stats);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Text(
          'Simulación',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text('Prueba compras o ventas sin alterar tu cartera real.'),
        const SizedBox(height: 16),
        CardPanel(
          title: 'Escenario',
          child: Column(
            children: <Widget>[
              DropdownButtonFormField<String>(
                initialValue: _coin,
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
                    _coin = value ?? _coin;
                    final double price =
                        widget.stats[_coin]?.currentPrice ?? 0.0;
                    _priceController.text = price > 0 ? compact(price) : '';
                  });
                },
              ),
              const SizedBox(height: 12),
              SegmentedButton<ScenarioType>(
                segments: const <ButtonSegment<ScenarioType>>[
                  ButtonSegment<ScenarioType>(
                    value: ScenarioType.buy,
                    label: Text('Comprar'),
                    icon: Icon(Icons.add_circle_outline),
                  ),
                  ButtonSegment<ScenarioType>(
                    value: ScenarioType.sell,
                    label: Text('Vender'),
                    icon: Icon(Icons.remove_circle_outline),
                  ),
                ],
                selected: <ScenarioType>{_type},
                onSelectionChanged: (Set<ScenarioType> value) {
                  setState(() => _type = value.first);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _type == ScenarioType.buy
                      ? 'Monto a invertir MXN'
                      : 'Venta bruta objetivo MXN',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final double value in <double>[
                    500.0,
                    1000.0,
                    3000.0,
                    5000.0,
                    8000.0,
                    15000.0,
                  ])
                    ActionChip(
                      label: Text(moneyShort(value)),
                      onPressed: () {
                        setState(() => _amountController.text = compact(value));
                      },
                    ),
                  if (_type == ScenarioType.sell)
                    ActionChip(
                      label: const Text('Todo'),
                      onPressed: stats.currentPrice <= 0
                          ? null
                          : () {
                              setState(() {
                                _amountController.text = compact(
                                  stats.quantity * stats.currentPrice,
                                );
                              });
                            },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Precio unitario MXN',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _feeController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Comisión %',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        CardPanel(
          title: 'Resultado estimado',
          subtitle: result.valid
              ? 'Proyección, no movimiento real.'
              : 'Completa monto y precio para simular.',
          child: result.valid
              ? Column(
                  children: <Widget>[
                    InfoLine(
                      _type == ScenarioType.buy
                          ? 'Cantidad estimada'
                          : 'Cantidad a vender',
                      crypto(result.quantityDelta),
                    ),
                    InfoLine('Comisión estimada', money(result.fee)),
                    InfoLine(
                      _type == ScenarioType.buy
                          ? 'Cantidad después'
                          : 'Cantidad restante',
                      crypto(result.quantityAfter),
                      emphasized: true,
                    ),
                    InfoLine('Invertido después', money(result.costBaseAfter)),
                    InfoLine(
                      'Promedio después',
                      money(result.avgAfter),
                      emphasized: true,
                    ),
                    if (_type == ScenarioType.sell)
                      InfoLine(
                        'Resultado estimado',
                        money(result.realizedPLEstimate),
                        valueColor: pnlColor(result.realizedPLEstimate),
                        emphasized: true,
                      ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  ScenarioResult _calculate(CoinStats stats) {
    final double amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final double price = double.tryParse(_priceController.text.trim()) ?? 0.0;
    final double feePercent =
        double.tryParse(_feeController.text.trim()) ?? 0.0;

    if (amount <= 0 || price <= 0 || feePercent < 0) {
      return ScenarioResult.invalid(stats);
    }

    if (_type == ScenarioType.buy) {
      final double fee = amount * feePercent / 100;
      final double net = amount - fee;
      final double bought = net > 0 ? net / price : 0.0;
      final double qtyAfter = stats.quantity + bought;
      final double costAfter = stats.costBase + amount;
      final double avgAfter = qtyAfter > 0 ? costAfter / qtyAfter : 0.0;

      return ScenarioResult(
        valid: true,
        quantityDelta: bought,
        quantityAfter: qtyAfter,
        costBaseAfter: costAfter,
        avgAfter: avgAfter,
        fee: fee,
        realizedPLEstimate: 0.0,
      );
    }

    final double wantedQty = amount / price;
    final double sellQty = wantedQty > stats.quantity
        ? stats.quantity
        : wantedQty;
    final double gross = sellQty * price;
    final double fee = gross * feePercent / 100;
    final double net = gross - fee;
    final double removedCost = stats.avgPrice * sellQty;
    final double remainingQty = stats.quantity - sellQty;
    final double remainingCost = stats.costBase - removedCost;
    final double remainingAvg = remainingQty > 0
        ? remainingCost / remainingQty
        : 0.0;

    return ScenarioResult(
      valid: true,
      quantityDelta: sellQty,
      quantityAfter: remainingQty,
      costBaseAfter: remainingCost < 0.00000001 ? 0.0 : remainingCost,
      avgAfter: remainingAvg,
      fee: fee,
      realizedPLEstimate: net - removedCost,
    );
  }
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Text(
          'Monedas',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text('Precios y lectura general por moneda.'),
        const SizedBox(height: 12),
        ...coins.map((String coin) {
          final CoinStats stat = stats[coin] ?? CoinStats(coin: coin);

          return CardPanel(
            title: coin,
            subtitle: stat.quantity > 0 ? 'Posición abierta' : 'Sin posición',
            trailing: IconButton(
              tooltip: 'Editar precio',
              onPressed: () => onEditPrice(coin),
              icon: const Icon(Icons.edit_outlined),
            ),
            child: Column(
              children: <Widget>[
                InfoLine('Precio actual', money(stat.currentPrice)),
                InfoLine(
                  'Vale hoy',
                  money(stat.currentValue),
                  emphasized: true,
                ),
                InfoLine(
                  'Resultado actual',
                  money(stat.unrealizedPL),
                  valueColor: pnlColor(stat.unrealizedPL),
                ),
                InfoLine(
                  'Precio para recuperar',
                  money(stat.netBreakEvenPrice(sellFeePercent)),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: () => onDetails(stat),
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Detalles'),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class SettingsTab extends StatelessWidget {
  final bool darkMode;
  final double sellFeePercent;
  final int snapshotCount;
  final DateTime? pricesUpdatedAt;
  final bool isRefreshingPrices;
  final ValueChanged<bool> onDarkModeChanged;
  final VoidCallback onRefreshPrices;
  final VoidCallback onEditSellFee;
  final VoidCallback onSaveSnapshot;
  final VoidCallback onViewSnapshots;
  final VoidCallback onExportMovementsCsv;
  final VoidCallback onExportSummaryCsv;
  final VoidCallback onExportSnapshotsCsv;
  final VoidCallback onExportXlsx;
  final VoidCallback onExportPdf;
  final VoidCallback onExportBackup;
  final VoidCallback onImportBackup;

  const SettingsTab({
    super.key,
    required this.darkMode,
    required this.sellFeePercent,
    required this.snapshotCount,
    required this.pricesUpdatedAt,
    required this.isRefreshingPrices,
    required this.onDarkModeChanged,
    required this.onRefreshPrices,
    required this.onEditSellFee,
    required this.onSaveSnapshot,
    required this.onViewSnapshots,
    required this.onExportMovementsCsv,
    required this.onExportSummaryCsv,
    required this.onExportSnapshotsCsv,
    required this.onExportXlsx,
    required this.onExportPdf,
    required this.onExportBackup,
    required this.onImportBackup,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        CardPanel(
          title: 'Apariencia',
          subtitle: 'Cambia la app a pantalla oscura cuando quieras.',
          child: SwitchListTile(
            value: darkMode,
            onChanged: onDarkModeChanged,
            title: const Text('Pantalla oscura'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
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
        CardPanel(
          title: 'Precios',
          subtitle: priceUpdatedLabel(pricesUpdatedAt),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: isRefreshingPrices ? null : onRefreshPrices,
              icon: isRefreshingPrices
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(
                isRefreshingPrices ? 'Actualizando' : 'Actualizar ahora',
              ),
            ),
          ),
        ),
        CardPanel(
          title: 'Snapshots',
          subtitle: 'Fotos guardadas: $snapshotCount',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.tonal(
                onPressed: onSaveSnapshot,
                child: const Text('Guardar snapshot'),
              ),
              FilledButton.tonal(
                onPressed: onViewSnapshots,
                child: const Text('Ver snapshots'),
              ),
              FilledButton.tonal(
                onPressed: onExportSnapshotsCsv,
                child: const Text('CSV snapshots'),
              ),
            ],
          ),
        ),
        CardPanel(
          title: 'Exportaciones',
          subtitle: 'Archivos básicos para auditoría o respaldo externo.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.tonal(
                onPressed: onExportMovementsCsv,
                child: const Text('CSV historial'),
              ),
              FilledButton.tonal(
                onPressed: onExportSummaryCsv,
                child: const Text('CSV resumen'),
              ),
              FilledButton.tonal(
                onPressed: onExportPdf,
                child: const Text('PDF reporte'),
              ),
              FilledButton.tonal(
                onPressed: onExportXlsx,
                child: const Text('XLSX reporte'),
              ),
            ],
          ),
        ),
        CardPanel(
          title: 'Respaldo JSON',
          subtitle:
              'Copia o importa tu respaldo sin borrar la estructura actual.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.tonal(
                onPressed: onExportBackup,
                child: const Text('Copiar JSON'),
              ),
              FilledButton.tonal(
                onPressed: onImportBackup,
                child: const Text('Importar JSON'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CardPanel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  const CardPanel({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
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
      ),
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

enum MovementType { buy, sell, transferIn, transferOut }

enum ScenarioType { buy, sell }

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

class ScenarioResult {
  final bool valid;
  final double quantityDelta;
  final double quantityAfter;
  final double costBaseAfter;
  final double avgAfter;
  final double fee;
  final double realizedPLEstimate;

  ScenarioResult({
    required this.valid,
    required this.quantityDelta,
    required this.quantityAfter,
    required this.costBaseAfter,
    required this.avgAfter,
    required this.fee,
    required this.realizedPLEstimate,
  });

  factory ScenarioResult.invalid(CoinStats stats) => ScenarioResult(
    valid: false,
    quantityDelta: 0.0,
    quantityAfter: stats.quantity,
    costBaseAfter: stats.costBase,
    avgAfter: stats.avgPrice,
    fee: 0.0,
    realizedPLEstimate: 0.0,
  );
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
  if (value > 0) return Colors.green.shade700;
  if (value < 0) return Colors.red.shade700;
  return Colors.grey.shade700;
}
