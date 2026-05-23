import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main_v2_step3.dart' show CardPanel, SheetHeader, InfoLine;

void main() => runApp(const CriptoControlApp());

class CriptoControlApp extends StatefulWidget {
  const CriptoControlApp({super.key});

  @override
  State<CriptoControlApp> createState() => _CriptoControlAppState();
}

class _CriptoControlAppState extends State<CriptoControlApp> {
  static const List<String> coins = <String>[
    'BTC',
    'ETH',
    'LINK',
    'LTC',
    'UNI',
  ];
  static const String movementsKey = 'movements_json';
  static const String pricesKey = 'prices_json';
  static const String sellFeeKey = 'sell_fee_percent';
  static const String snapshotsKey = 'portfolio_snapshots_v23_json';
  static const String darkModeKey = 'dark_mode_v24';

  final List<Movement> movements = <Movement>[];
  final List<PortfolioSnapshot> snapshots = <PortfolioSnapshot>[];
  final Map<String, double> currentPrices = <String, double>{
    'BTC': 0.0,
    'ETH': 0.0,
    'LINK': 0.0,
    'LTC': 0.0,
    'UNI': 0.0,
  };

  int currentIndex = 0;
  double sellFeePercent = 0.0;
  bool darkMode = false;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final String? rawMovements = prefs.getString(movementsKey);
    if (rawMovements != null && rawMovements.trim().isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(rawMovements);
        if (decoded is List) {
          movements
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

    final String? rawPrices = prefs.getString(pricesKey);
    if (rawPrices != null && rawPrices.trim().isNotEmpty) {
      try {
        final Map<String, dynamic> decoded = Map<String, dynamic>.from(
          jsonDecode(rawPrices) as Map,
        );
        for (final String coin in coins) {
          final dynamic value = decoded[coin];
          if (value is num) currentPrices[coin] = value.toDouble();
        }
      } catch (_) {}
    }

    final String? rawSnapshots = prefs.getString(snapshotsKey);
    if (rawSnapshots != null && rawSnapshots.trim().isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(rawSnapshots);
        if (decoded is List) {
          snapshots
            ..clear()
            ..addAll(
              decoded.map(
                (dynamic e) => PortfolioSnapshot.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              ),
            );
          snapshots.sort(
            (PortfolioSnapshot a, PortfolioSnapshot b) =>
                b.createdAt.compareTo(a.createdAt),
          );
        }
      } catch (_) {}
    }

    sellFeePercent = prefs.getDouble(sellFeeKey) ?? 0.0;
    darkMode = prefs.getBool(darkModeKey) ?? false;
    if (mounted) setState(() {});
  }

  Future<void> saveData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      movementsKey,
      jsonEncode(movements.map((Movement e) => e.toJson()).toList()),
    );
    await prefs.setString(pricesKey, jsonEncode(currentPrices));
    await prefs.setDouble(sellFeeKey, sellFeePercent);
    await prefs.setBool(darkModeKey, darkMode);
  }

  Future<void> saveSnapshots() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      snapshotsKey,
      jsonEncode(snapshots.map((PortfolioSnapshot e) => e.toJson()).toList()),
    );
  }

  Map<String, CoinStats> computeStats() {
    final Map<String, CoinStats> stats = <String, CoinStats>{
      for (final String coin in coins)
        coin: CoinStats(coin: coin, currentPrice: currentPrices[coin] ?? 0.0),
    };

    final List<MapEntry<int, Movement>> ordered =
        movements.asMap().entries.toList()
          ..sort((MapEntry<int, Movement> a, MapEntry<int, Movement> b) {
            final int dc = a.value.date.compareTo(b.value.date);
            return dc != 0 ? dc : a.key.compareTo(b.key);
          });

    for (final MapEntry<int, Movement> entry in ordered) {
      final Movement m = entry.value;
      final CoinStats? s = stats[m.coin];
      if (s == null) continue;

      switch (m.type) {
        case MovementType.buy:
        case MovementType.transferIn:
          s.quantity += m.quantity;
          s.costBase += (m.quantity * m.unitPrice) + m.fee;
          s.feesPaid += m.fee;
          break;
        case MovementType.sell:
          final double avg = s.quantity > 0 ? s.costBase / s.quantity : 0.0;
          final double qty = m.quantity > s.quantity ? s.quantity : m.quantity;
          final double removedCost = avg * qty;
          final double proceeds = (m.quantity * m.unitPrice) - m.fee;
          s.realizedPL += proceeds - removedCost;
          s.quantity -= qty;
          s.costBase -= removedCost;
          s.feesPaid += m.fee;
          break;
        case MovementType.transferOut:
          final double avg = s.quantity > 0 ? s.costBase / s.quantity : 0.0;
          final double qty = m.quantity > s.quantity ? s.quantity : m.quantity;
          final double removedCost = avg * qty;
          s.quantity -= qty;
          s.costBase -= removedCost;
          s.feesPaid += m.fee;
          break;
      }

      if (s.quantity.abs() < 0.0000000001) {
        s.quantity = 0.0;
        s.costBase = 0.0;
      }
      if (s.costBase.abs() < 0.00000001) s.costBase = 0.0;
    }

    for (final String coin in coins) {
      stats[coin]!.currentPrice = currentPrices[coin] ?? 0.0;
    }
    return stats;
  }

  PortfolioTotals totalsOf(Map<String, CoinStats> stats) => PortfolioTotals(
    costBase: stats.values.fold<double>(
      0.0,
      (double p, CoinStats e) => p + e.costBase,
    ),
    currentValue: stats.values.fold<double>(
      0.0,
      (double p, CoinStats e) => p + e.currentValue,
    ),
    unrealizedPL: stats.values.fold<double>(
      0.0,
      (double p, CoinStats e) => p + e.unrealizedPL,
    ),
    realizedPL: stats.values.fold<double>(
      0.0,
      (double p, CoinStats e) => p + e.realizedPL,
    ),
    feesPaid: stats.values.fold<double>(
      0.0,
      (double p, CoinStats e) => p + e.feesPaid,
    ),
  );

  CoinAudit auditCoin(String coin) {
    double buys = 0, sells = 0, transferIns = 0, transferOuts = 0, fees = 0;
    for (final Movement m in movements.where((Movement e) => e.coin == coin)) {
      final double total = m.quantity * m.unitPrice;
      fees += m.fee;
      switch (m.type) {
        case MovementType.buy:
          buys += total + m.fee;
          break;
        case MovementType.sell:
          sells += total - m.fee;
          break;
        case MovementType.transferIn:
          transferIns += total + m.fee;
          break;
        case MovementType.transferOut:
          transferOuts += total + m.fee;
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

  bool wouldCreateInvalidPosition(Movement candidate, {int? replaceIndex}) {
    final List<Movement> test = <Movement>[...movements];
    if (replaceIndex != null &&
        replaceIndex >= 0 &&
        replaceIndex < test.length) {
      test[replaceIndex] = candidate;
    } else {
      test.add(candidate);
    }

    final Map<String, double> balances = <String, double>{
      for (final String coin in coins) coin: 0.0,
    };
    final List<MapEntry<int, Movement>> ordered = test.asMap().entries.toList()
      ..sort((MapEntry<int, Movement> a, MapEntry<int, Movement> b) {
        final int dc = a.value.date.compareTo(b.value.date);
        return dc != 0 ? dc : a.key.compareTo(b.key);
      });

    for (final MapEntry<int, Movement> entry in ordered) {
      final Movement m = entry.value;
      final double current = balances[m.coin] ?? 0.0;
      switch (m.type) {
        case MovementType.buy:
        case MovementType.transferIn:
          balances[m.coin] = current + m.quantity;
          break;
        case MovementType.sell:
        case MovementType.transferOut:
          if (m.quantity > current + 0.0000000001) return true;
          balances[m.coin] = current - m.quantity;
          break;
      }
    }
    return false;
  }

  Future<void> toggleDarkMode(bool value) async {
    setState(() => darkMode = value);
    await saveData();
  }

  void snack(BuildContext context, String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> showSellFeeDialog(BuildContext context) async {
    final TextEditingController c = TextEditingController(
      text: compact(sellFeePercent),
    );
    await showDialog<void>(
      context: context,
      builder: (BuildContext d) => AlertDialog(
        title: const Text('ComisiÃ³n de salida'),
        content: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Porcentaje',
            helperText: 'Ejemplo: 1.5',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(d).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final double? value = double.tryParse(c.text.trim());
              if (value == null || value < 0 || value >= 100) return;
              setState(() => sellFeePercent = value);
              saveData();
              Navigator.of(d).pop();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void showEditPriceDialog(BuildContext context, String coin) {
    final TextEditingController c = TextEditingController(
      text: compact(currentPrices[coin] ?? 0),
    );
    showDialog<void>(
      context: context,
      builder: (BuildContext d) => AlertDialog(
        title: Text('Precio actual de $coin'),
        content: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Precio MXN',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(d).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final double? value = double.tryParse(c.text.trim());
              if (value == null || value < 0) return;
              setState(() => currentPrices[coin] = value);
              saveData();
              Navigator.of(d).pop();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void showMovementSheet(
    BuildContext context, {
    Movement? existing,
    int? index,
  }) {
    MovementType selectedType = existing?.type ?? MovementType.buy;
    String selectedCoin = existing?.coin ?? coins.first;
    DateTime selectedDate = existing?.date ?? DateTime.now();
    final TextEditingController qty = TextEditingController(
      text: existing == null ? '' : compact(existing.quantity),
    );
    final TextEditingController price = TextEditingController(
      text: existing == null ? '' : compact(existing.unitPrice),
    );
    final TextEditingController fee = TextEditingController(
      text: existing == null ? '0' : compact(existing.fee),
    );
    final TextEditingController note = TextEditingController(
      text: existing?.note ?? '',
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheet) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setModal) =>
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(ctx).viewInsets.bottom,
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
                      onClose: () => Navigator.of(sheet).pop(),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<MovementType>(
                      value: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        border: OutlineInputBorder(),
                      ),
                      items: MovementType.values
                          .map(
                            (MovementType t) => DropdownMenuItem<MovementType>(
                              value: t,
                              child: Text(t.label),
                            ),
                          )
                          .toList(),
                      onChanged: (MovementType? v) {
                        if (v != null) setModal(() => selectedType = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedCoin,
                      decoration: const InputDecoration(
                        labelText: 'Moneda',
                        border: OutlineInputBorder(),
                      ),
                      items: coins
                          .map(
                            (String c) => DropdownMenuItem<String>(
                              value: c,
                              child: Text(c),
                            ),
                          )
                          .toList(),
                      onChanged: (String? v) {
                        if (v != null) setModal(() => selectedCoin = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final DateTime? picked = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDate,
                          firstDate: DateTime(2010),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null)
                          setModal(() => selectedDate = picked);
                      },
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text('Fecha: ${shortDate(selectedDate)}'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: qty,
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
                      controller: price,
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
                      controller: fee,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'ComisiÃ³n MXN',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: note,
                      decoration: const InputDecoration(
                        labelText: 'Nota',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: Icon(
                          existing == null ? Icons.add : Icons.save_outlined,
                        ),
                        label: Text(
                          existing == null
                              ? 'Guardar movimiento'
                              : 'Guardar cambios',
                        ),
                        onPressed: () {
                          final double? q = double.tryParse(qty.text.trim());
                          final double? p = double.tryParse(price.text.trim());
                          final double f =
                              double.tryParse(fee.text.trim()) ?? 0.0;
                          if (q == null || q <= 0)
                            return snack(context, 'Pon una cantidad vÃ¡lida');
                          if (p == null || p < 0)
                            return snack(context, 'Pon un precio vÃ¡lido');
                          if (f < 0)
                            return snack(
                              context,
                              'La comisiÃ³n no puede ser negativa',
                            );
                          final Movement m = Movement(
                            type: selectedType,
                            coin: selectedCoin,
                            date: selectedDate,
                            quantity: q,
                            unitPrice: p,
                            fee: f,
                            note: note.text.trim(),
                          );
                          if (wouldCreateInvalidPosition(
                            m,
                            replaceIndex: existing == null ? null : index,
                          ))
                            return snack(
                              context,
                              'Ese movimiento dejarÃ­a la posiciÃ³n en negativo',
                            );
                          setState(() {
                            if (existing != null &&
                                index != null &&
                                index >= 0 &&
                                index < movements.length) {
                              movements[index] = m;
                            } else {
                              movements.add(m);
                            }
                          });
                          saveData();
                          Navigator.of(sheet).pop();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  void showCoinDetails(BuildContext context, CoinStats s) {
    final CoinAudit audit = auditCoin(s.coin);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        minChildSize: 0.45,
        maxChildSize: 0.96,
        builder: (BuildContext ctx, ScrollController sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SheetHeader(
              title: 'Detalles de ${s.coin}',
              onClose: () => Navigator.of(sheet).pop(),
            ),
            const SizedBox(height: 12),
            CardPanel(
              title: 'PosiciÃ³n actual',
              subtitle: 'Lectura completa por moneda.',
              child: Column(
                children: <Widget>[
                  InfoLine('Cantidad', crypto(s.quantity)),
                  InfoLine('Invertido actual', money(s.costBase)),
                  InfoLine('Precio promedio', money(s.avgPrice)),
                  InfoLine('Precio actual', money(s.currentPrice)),
                  InfoLine(
                    'Valor actual',
                    money(s.currentValue),
                    emphasized: true,
                  ),
                  InfoLine(
                    'Ganancia/PÃ©rdida actual',
                    money(s.unrealizedPL),
                    valueColor: pnlColor(s.unrealizedPL),
                    emphasized: true,
                  ),
                  InfoLine(
                    'Ganancia/PÃ©rdida vendida',
                    money(s.realizedPL),
                    valueColor: pnlColor(s.realizedPL),
                  ),
                  InfoLine(
                    'Precio para recuperar',
                    money(s.netBreakEvenPrice(sellFeePercent)),
                  ),
                  InfoLine(
                    'Distancia a recuperar',
                    s.quantity <= 0 || s.isAtOrAboveNetBreakEven(sellFeePercent)
                        ? '0.00%'
                        : pct(s.percentToNetBreakEven(sellFeePercent)),
                  ),
                  InfoLine(
                    'Objetivo +5%',
                    money(s.targetNetExitPrice(sellFeePercent, 5)),
                  ),
                  InfoLine(
                    'Objetivo +10%',
                    money(s.targetNetExitPrice(sellFeePercent, 10)),
                  ),
                ],
              ),
            ),
            CardPanel(
              title: 'AuditorÃ­a',
              subtitle: 'Desglose de movimientos.',
              child: Column(
                children: <Widget>[
                  InfoLine('Compras acumuladas', money(audit.buys)),
                  InfoLine('Ventas acumuladas', money(audit.sells)),
                  InfoLine('Entradas acumuladas', money(audit.transferIns)),
                  InfoLine('Salidas acumuladas', money(audit.transferOuts)),
                  InfoLine('Comisiones acumuladas', money(audit.fees)),
                  const Divider(),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Promedio = invertido actual / cantidad actual',
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Resultado actual = valor actual - invertido actual',
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Precio para recuperar = promedio / (1 - comisiÃ³n de salida)',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> saveSnapshot(BuildContext context) async {
    final Map<String, CoinStats> stats = computeStats();
    final PortfolioTotals totals = totalsOf(stats);
    final PortfolioSnapshot snapshot = PortfolioSnapshot(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      totalCostBase: totals.costBase,
      totalCurrentValue: totals.currentValue,
      totalUnrealizedPL: totals.unrealizedPL,
      totalRealizedPL: totals.realizedPL,
      movementCount: movements.length,
      coins: coins
          .map((String coin) => CoinSnapshot.fromStats(stats[coin]!))
          .toList(),
    );
    setState(() {
      snapshots.insert(0, snapshot);
      snapshots.sort(
        (PortfolioSnapshot a, PortfolioSnapshot b) =>
            b.createdAt.compareTo(a.createdAt),
      );
    });
    await saveSnapshots();
    if (mounted) snack(context, 'Snapshot guardado');
  }

  void showSnapshots(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        minChildSize: 0.45,
        maxChildSize: 0.96,
        builder: (BuildContext ctx, ScrollController sc) => StatefulBuilder(
          builder:
              (BuildContext ctx, void Function(void Function()) setModal) =>
                  ListView(
                    controller: sc,
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      SheetHeader(
                        title: 'Snapshots',
                        onClose: () => Navigator.of(sheet).pop(),
                      ),
                      const SizedBox(height: 12),
                      if (snapshots.isEmpty)
                        const EmptyState(
                          icon: Icons.photo_library_outlined,
                          title: 'Sin snapshots',
                          subtitle: 'Guarda una foto de cartera desde Ajustes.',
                        )
                      else
                        ...snapshots.map(
                          (PortfolioSnapshot s) => CardPanel(
                            title: longDate(s.createdAt),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                setState(
                                  () => snapshots.removeWhere(
                                    (PortfolioSnapshot item) => item.id == s.id,
                                  ),
                                );
                                await saveSnapshots();
                                setModal(() {});
                              },
                            ),
                            child: Column(
                              children: <Widget>[
                                InfoLine('Invertido', money(s.totalCostBase)),
                                InfoLine(
                                  'Valor actual',
                                  money(s.totalCurrentValue),
                                ),
                                InfoLine(
                                  'Resultado actual',
                                  money(s.totalUnrealizedPL),
                                  valueColor: pnlColor(s.totalUnrealizedPL),
                                  emphasized: true,
                                ),
                                InfoLine(
                                  'Resultado vendido',
                                  money(s.totalRealizedPL),
                                  valueColor: pnlColor(s.totalRealizedPL),
                                ),
                                InfoLine(
                                  'Movimientos',
                                  s.movementCount.toString(),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
        ),
      ),
    );
  }

  String backupJson() =>
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'settings': <String, double>{'sellFeePercent': sellFeePercent},
        'currentPrices': currentPrices,
        'movements': movements.map((Movement m) => m.toJson()).toList(),
      });

  String movementsCsv() {
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
        'nota',
      ],
      ...movements.map(
        (Movement m) => <Object?>[
          isoDate(m.date),
          m.type.label,
          m.type.name,
          m.coin,
          fixed(m.quantity, 8),
          fixed(m.unitPrice, 2),
          fixed(m.fee, 2),
          fixed(m.quantity * m.unitPrice, 2),
          m.note,
        ],
      ),
    ];
    return rows
        .map((List<Object?> row) => row.map(csvEscape).join(','))
        .join('\n');
  }

  String summaryCsv() {
    final Map<String, CoinStats> stats = computeStats();
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
      ...coins.map((String coin) {
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
          fixed(s.netBreakEvenPrice(sellFeePercent), 2),
          fixed(s.feesPaid, 2),
        ];
      }),
    ];
    return rows
        .map((List<Object?> row) => row.map(csvEscape).join(','))
        .join('\n');
  }

  String snapshotsCsv() {
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
    for (final PortfolioSnapshot s in snapshots) {
      for (final CoinSnapshot c in s.coins) {
        rows.add(<Object?>[
          s.id,
          s.createdAt.toIso8601String(),
          fixed(s.totalCostBase, 2),
          fixed(s.totalCurrentValue, 2),
          fixed(s.totalUnrealizedPL, 2),
          fixed(s.totalRealizedPL, 2),
          s.movementCount,
          c.coin,
          fixed(c.quantity, 8),
          fixed(c.costBase, 2),
          fixed(c.avgPrice, 2),
          fixed(c.currentValue, 2),
          fixed(c.unrealizedPL, 2),
          fixed(c.realizedPL, 2),
        ]);
      }
    }
    return rows
        .map((List<Object?> row) => row.map(csvEscape).join(','))
        .join('\n');
  }

  Future<Uint8List> pdfBytes() async {
    final Map<String, CoinStats> stats = computeStats();
    final PortfolioTotals totals = totalsOf(stats);
    final pw.Document pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(margin: pw.EdgeInsets.all(28)),
        build: (pw.Context context) => <pw.Widget>[
          pw.Text(
            'CriptoControlMx - Reporte',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Generado: ${DateTime.now().toIso8601String()}'),
          pw.Text('ComisiÃ³n de salida: ${pct(sellFeePercent)}'),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            headers: <String>['Concepto', 'Monto'],
            data: <List<String>>[
              <String>['Invertido actual', money(totals.costBase)],
              <String>['Valor actual', money(totals.currentValue)],
              <String>['Resultado actual', money(totals.unrealizedPL)],
              <String>['Resultado vendido', money(totals.realizedPL)],
              <String>['Comisiones acumuladas', money(totals.feesPaid)],
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
              'Promedio',
              'Valor',
              'Resultado',
              'Recuperar',
            ],
            data: coins.map((String coin) {
              final CoinStats s = stats[coin]!;
              return <String>[
                s.coin,
                crypto(s.quantity),
                money(s.costBase),
                money(s.avgPrice),
                money(s.currentValue),
                money(s.unrealizedPL),
                money(s.netBreakEvenPrice(sellFeePercent)),
              ];
            }).toList(),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  Future<void> shareFile(
    BuildContext context,
    String fileName,
    String mimeType,
    List<int> bytes,
    String ok,
  ) async {
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
      if (mounted) snack(context, ok);
    } catch (_) {
      if (mounted) snack(context, 'No se pudo exportar el archivo');
    }
  }

  Future<void> importBackup(BuildContext context) async {
    final TextEditingController c = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (BuildContext d) => AlertDialog(
        title: const Text('Importar respaldo JSON'),
        content: TextField(
          controller: c,
          minLines: 8,
          maxLines: 14,
          decoration: const InputDecoration(
            hintText: 'Pega aquÃ­ tu respaldo',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(d).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final dynamic decoded = jsonDecode(c.text.trim());
                if (decoded is! Map<String, dynamic>)
                  throw const FormatException();
                final dynamic rawMovements = decoded['movements'];
                final dynamic rawPrices = decoded['currentPrices'];
                final dynamic rawSettings = decoded['settings'];
                if (rawMovements is! List || rawPrices is! Map)
                  throw const FormatException();
                final List<Movement> imported = rawMovements
                    .map(
                      (dynamic e) => Movement.fromJson(
                        Map<String, dynamic>.from(e as Map),
                      ),
                    )
                    .toList();
                final Map<String, dynamic> prices = Map<String, dynamic>.from(
                  rawPrices,
                );
                setState(() {
                  movements
                    ..clear()
                    ..addAll(imported);
                  for (final String coin in coins) {
                    final dynamic value = prices[coin];
                    currentPrices[coin] = value is num ? value.toDouble() : 0.0;
                  }
                  if (rawSettings is Map &&
                      rawSettings['sellFeePercent'] is num)
                    sellFeePercent = (rawSettings['sellFeePercent'] as num)
                        .toDouble();
                });
                await saveData();
                if (!mounted) return;
                Navigator.of(d).pop();
                snack(context, 'Respaldo importado');
              } catch (_) {
                snack(context, 'JSON invÃ¡lido o incompleto');
              }
            },
            child: const Text('Importar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, CoinStats> stats = computeStats();
    final PortfolioTotals totals = totalsOf(stats);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CriptoControlMx',
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF7FAF2),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
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
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      home: Builder(
        builder: (BuildContext pageContext) {
          final List<Widget> pages = <Widget>[
            SummaryTab(
              stats: stats,
              totals: totals,
              sellFeePercent: sellFeePercent,
              onDetails: (CoinStats s) => showCoinDetails(pageContext, s),
            ),
            MovementsTab(
              movements: movements,
              coins: coins,
              onAdd: () => showMovementSheet(pageContext),
              onEdit: (Movement m) => showMovementSheet(
                pageContext,
                existing: m,
                index: movements.indexOf(m),
              ),
              onDelete: (Movement m) {
                setState(() => movements.remove(m));
                saveData();
              },
            ),
            SimulationTab(
              coins: coins,
              stats: stats,
              currentPrices: currentPrices,
              defaultFeePercent: 1.5,
            ),
            CoinsTab(
              coins: coins,
              stats: stats,
              sellFeePercent: sellFeePercent,
              onEditPrice: (String c) => showEditPriceDialog(pageContext, c),
              onDetails: (CoinStats s) => showCoinDetails(pageContext, s),
            ),
            SettingsTab(
              darkMode: darkMode,
              sellFeePercent: sellFeePercent,
              snapshotCount: snapshots.length,
              onDarkModeChanged: toggleDarkMode,
              onEditSellFee: () => showSellFeeDialog(pageContext),
              onSaveSnapshot: () => saveSnapshot(pageContext),
              onViewSnapshots: () => showSnapshots(pageContext),
              onExportMovementsCsv: () => shareFile(
                pageContext,
                'criptocontrolmx_historial.csv',
                'text/csv',
                utf8.encode('\ufeff${movementsCsv()}'),
                'Historial CSV listo',
              ),
              onExportSummaryCsv: () => shareFile(
                pageContext,
                'criptocontrolmx_resumen.csv',
                'text/csv',
                utf8.encode('\ufeff${summaryCsv()}'),
                'Resumen CSV listo',
              ),
              onExportSnapshotsCsv: () => shareFile(
                pageContext,
                'criptocontrolmx_snapshots.csv',
                'text/csv',
                utf8.encode('\ufeff${snapshotsCsv()}'),
                'Snapshots CSV listo',
              ),
              onExportPdf: () async => shareFile(
                pageContext,
                'criptocontrolmx_reporte.pdf',
                'application/pdf',
                await pdfBytes(),
                'Reporte PDF listo',
              ),
              onExportBackup: () async {
                await Clipboard.setData(ClipboardData(text: backupJson()));
                if (mounted) snack(pageContext, 'Respaldo JSON copiado');
              },
              onImportBackup: () => importBackup(pageContext),
            ),
          ];

          return Scaffold(
            appBar: AppBar(
              title: const Text('CriptoControlMx'),
              actions: <Widget>[
                IconButton(
                  tooltip: 'Nuevo movimiento',
                  onPressed: () => showMovementSheet(pageContext),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            body: IndexedStack(index: currentIndex, children: pages),
            bottomNavigationBar: NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: (int i) =>
                  setState(() => currentIndex = i),
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
        ...coins.map((String coin) {
          final CoinStats stat = stats[coin] ?? CoinStats(coin: coin);

          return CardPanel(
            title: coin,
            subtitle: stat.quantity > 0 ? 'PosiciÃ³n abierta' : 'Sin posiciÃ³n',
            trailing: IconButton(
              tooltip: 'Editar precio',
              onPressed: () => onEditPrice(coin),
              icon: const Icon(Icons.edit_outlined),
            ),
            child: Column(
              children: <Widget>[
                InfoLine('Cantidad', crypto(stat.quantity)),
                InfoLine('Precio actual', money(stat.currentPrice)),
                InfoLine(
                  'Valor actual',
                  money(stat.currentValue),
                  emphasized: true,
                ),
                InfoLine(
                  'Resultado actual',
                  money(stat.unrealizedPL),
                  valueColor: pnlColor(stat.unrealizedPL),
                  emphasized: true,
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
  final ValueChanged<bool> onDarkModeChanged;
  final VoidCallback onEditSellFee;
  final VoidCallback onSaveSnapshot;
  final VoidCallback onViewSnapshots;
  final VoidCallback onExportMovementsCsv;
  final VoidCallback onExportSummaryCsv;
  final VoidCallback onExportSnapshotsCsv;
  final VoidCallback onExportPdf;
  final VoidCallback onExportBackup;
  final VoidCallback onImportBackup;

  const SettingsTab({
    super.key,
    required this.darkMode,
    required this.sellFeePercent,
    required this.snapshotCount,
    required this.onDarkModeChanged,
    required this.onEditSellFee,
    required this.onSaveSnapshot,
    required this.onViewSnapshots,
    required this.onExportMovementsCsv,
    required this.onExportSummaryCsv,
    required this.onExportSnapshotsCsv,
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
          subtitle: 'Modo visual de la app.',
          child: SwitchListTile(
            value: darkMode,
            onChanged: onDarkModeChanged,
            title: const Text('Pantalla oscura'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        CardPanel(
          title: 'CÃ¡lculo',
          subtitle: 'ComisiÃ³n de salida actual: ${pct(sellFeePercent)}',
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              onPressed: onEditSellFee,
              child: const Text('Editar comisiÃ³n'),
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
          subtitle: 'Archivos bÃ¡sicos para auditorÃ­a o respaldo.',
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
            ],
          ),
        ),
        CardPanel(
          title: 'Respaldo JSON',
          subtitle: 'Copia o importa tu respaldo.',
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
    final List<CoinStats> ordered = stats.values.toList()
      ..sort(
        (CoinStats a, CoinStats b) => b.currentValue.compareTo(a.currentValue),
      );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        CardPanel(
          title: 'Resumen general',
          subtitle: 'Cartera completa en MXN.',
          child: Column(
            children: <Widget>[
              InfoLine('Invertido actual', money(totals.costBase)),
              InfoLine(
                'Valor actual',
                money(totals.currentValue),
                emphasized: true,
              ),
              InfoLine(
                'Ganancia/PÃ©rdida actual',
                money(totals.unrealizedPL),
                valueColor: pnlColor(totals.unrealizedPL),
                emphasized: true,
              ),
              InfoLine(
                'Ganancia/PÃ©rdida vendida',
                money(totals.realizedPL),
                valueColor: pnlColor(totals.realizedPL),
              ),
              InfoLine('Comisiones acumuladas', money(totals.feesPaid)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...ordered.map(
          (CoinStats s) => CoinDenseCard(
            stats: s,
            sellFeePercent: sellFeePercent,
            onDetails: () => onDetails(s),
          ),
        ),
      ],
    );
  }
}

class CoinDenseCard extends StatelessWidget {
  final CoinStats stats;
  final double sellFeePercent;
  final VoidCallback onDetails;
  const CoinDenseCard({
    super.key,
    required this.stats,
    required this.sellFeePercent,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final bool recovered = stats.isAtOrAboveNetBreakEven(sellFeePercent);
    return CardPanel(
      title: stats.coin,
      subtitle: stats.quantity > 0 ? 'PosiciÃ³n abierta' : 'Sin posiciÃ³n',
      trailing: IconButton(
        tooltip: 'Ver detalles',
        onPressed: onDetails,
        icon: const Icon(Icons.info_outline),
      ),
      child: Column(
        children: <Widget>[
          InfoLine('Cantidad', crypto(stats.quantity)),
          InfoLine('Invertido', money(stats.costBase)),
          InfoLine('Precio promedio', money(stats.avgPrice)),
          InfoLine('Precio actual', money(stats.currentPrice)),
          InfoLine('Valor actual', money(stats.currentValue), emphasized: true),
          InfoLine(
            'Resultado actual',
            money(stats.unrealizedPL),
            valueColor: pnlColor(stats.unrealizedPL),
            emphasized: true,
          ),
          InfoLine(
            'Resultado vendido',
            money(stats.realizedPL),
            valueColor: pnlColor(stats.realizedPL),
          ),
          InfoLine(
            'Precio para recuperar',
            money(stats.netBreakEvenPrice(sellFeePercent)),
          ),
          InfoLine(
            'Distancia recuperar',
            stats.quantity <= 0 || recovered
                ? '0.00%'
                : pct(stats.percentToNetBreakEven(sellFeePercent)),
          ),
        ],
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
  String coinFilter = 'TODAS';
  String typeFilter = 'TODOS';

  @override
  Widget build(BuildContext context) {
    final List<Movement> filtered =
        widget.movements
            .where(
              (Movement m) =>
                  (coinFilter == 'TODAS' || m.coin == coinFilter) &&
                  (typeFilter == 'TODOS' || m.type.name == typeFilter),
            )
            .toList()
          ..sort((Movement a, Movement b) => b.date.compareTo(a.date));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: DropdownButtonFormField<String>(
                value: coinFilter,
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
                onChanged: (String? v) =>
                    setState(() => coinFilter = v ?? 'TODAS'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: typeFilter,
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
                onChanged: (String? v) =>
                    setState(() => typeFilter = v ?? 'TODOS'),
              ),
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
              title: '${m.coin} Â· ${m.type.shortLabel}',
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
                  InfoLine('ComisiÃ³n', money(m.fee)),
                  InfoLine(
                    'Total bruto',
                    money(m.quantity * m.unitPrice),
                    emphasized: true,
                  ),
                  if (m.note.isNotEmpty) InfoLine('Nota', m.note),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

enum SimulationMode { buySell, rotation }

enum ScenarioType { buy, sell }

enum RotationAmountMode { percentage, quantity, grossMxn }

class RotationResult {
  final bool valid;
  final bool missingOriginPrice;
  final bool missingDestinationPrice;
  final bool wasLimited;
  final double quantitySold;
  final double grossSale;
  final double sellFee;
  final double netSale;
  final double estimatedSellPL;
  final double destinationBought;
  final double buyFee;
  final double capitalMoved;
  final double totalFees;
  final double destinationQtyAfter;
  final double destinationAvgAfter;

  const RotationResult({
    required this.valid,
    this.missingOriginPrice = false,
    this.missingDestinationPrice = false,
    this.wasLimited = false,
    this.quantitySold = 0,
    this.grossSale = 0,
    this.sellFee = 0,
    this.netSale = 0,
    this.estimatedSellPL = 0,
    this.destinationBought = 0,
    this.buyFee = 0,
    this.capitalMoved = 0,
    this.totalFees = 0,
    this.destinationQtyAfter = 0,
    this.destinationAvgAfter = 0,
  });
}

class SimulationTab extends StatefulWidget {
  final List<String> coins;
  final Map<String, CoinStats> stats;
  final Map<String, double> currentPrices;
  final double defaultFeePercent;
  const SimulationTab({
    super.key,
    required this.coins,
    required this.stats,
    required this.currentPrices,
    required this.defaultFeePercent,
  });
  @override
  State<SimulationTab> createState() => _SimulationTabState();
}

class _SimulationTabState extends State<SimulationTab> {
  SimulationMode mode = SimulationMode.buySell;
  String coin = 'LINK';
  ScenarioType scenarioType = ScenarioType.buy;
  final TextEditingController amountController = TextEditingController(
    text: '1000',
  );
  final TextEditingController priceController = TextEditingController();
  final TextEditingController feeController = TextEditingController(
    text: '1.5',
  );

  String originCoin = 'LINK';
  String destinationCoin = 'BTC';
  RotationAmountMode rotationAmountMode = RotationAmountMode.percentage;
  double selectedPercent = 100.0;
  final TextEditingController rotationQtyController = TextEditingController();
  final TextEditingController rotationGrossController = TextEditingController();
  final TextEditingController originPriceController = TextEditingController();
  final TextEditingController destinationPriceController =
      TextEditingController();
  final TextEditingController sellFeeController = TextEditingController(
    text: '1.5',
  );
  final TextEditingController buyFeeController = TextEditingController(
    text: '1.5',
  );

  @override
  void dispose() {
    amountController.dispose();
    priceController.dispose();
    feeController.dispose();
    rotationQtyController.dispose();
    rotationGrossController.dispose();
    originPriceController.dispose();
    destinationPriceController.dispose();
    sellFeeController.dispose();
    buyFeeController.dispose();
    super.dispose();
  }

  void seedRotationPrices() {
    if (originPriceController.text.trim().isEmpty) {
      final double p = widget.currentPrices[originCoin] ?? 0.0;
      if (p > 0) originPriceController.text = compact(p);
    }
    if (destinationPriceController.text.trim().isEmpty) {
      final double p = widget.currentPrices[destinationCoin] ?? 0.0;
      if (p > 0) destinationPriceController.text = compact(p);
    }
  }

  double _inputDouble(TextEditingController controller) {
    return double.tryParse(controller.text.trim().replaceAll(',', '')) ?? 0;
  }

  ScenarioResult calculateScenario(CoinStats s) {
    final double amount = _inputDouble(amountController);
    final double price = _inputDouble(priceController);
    final double feePercent = _inputDouble(
      feeController,
    ).clamp(0, 99).toDouble();

    if (amount <= 0 || price <= 0) {
      return ScenarioResult(
        valid: false,
        quantityAfter: s.quantity,
        costBaseAfter: s.costBase,
        avgAfter: s.avgPrice,
      );
    }

    final double fee = amount * feePercent / 100;

    if (scenarioType == ScenarioType.buy) {
      final double netForCoin = amount - fee;
      final double quantityDelta = netForCoin / price;
      final double quantityAfter = s.quantity + quantityDelta;
      final double costBaseAfter = s.costBase + amount;
      final double avgAfter = quantityAfter > 0
          ? costBaseAfter / quantityAfter
          : 0;

      return ScenarioResult(
        valid: true,
        quantityDelta: quantityDelta,
        fee: fee,
        quantityAfter: quantityAfter,
        costBaseAfter: costBaseAfter,
        avgAfter: avgAfter,
      );
    }

    double quantityDelta = amount / price;
    if (quantityDelta > s.quantity) {
      quantityDelta = s.quantity;
    }

    if (quantityDelta <= 0) {
      return ScenarioResult(
        valid: false,
        quantityAfter: s.quantity,
        costBaseAfter: s.costBase,
        avgAfter: s.avgPrice,
      );
    }

    final double grossSale = quantityDelta * price;
    final double sellFee = grossSale * feePercent / 100;
    final double netSale = grossSale - sellFee;
    final double removedCost = s.avgPrice * quantityDelta;
    final double quantityAfter = s.quantity - quantityDelta;
    final double costBaseAfter = (s.costBase - removedCost)
        .clamp(0, double.infinity)
        .toDouble();
    final double avgAfter = quantityAfter > 0
        ? costBaseAfter / quantityAfter
        : 0;

    return ScenarioResult(
      valid: true,
      quantityDelta: quantityDelta,
      fee: sellFee,
      quantityAfter: quantityAfter,
      costBaseAfter: costBaseAfter,
      avgAfter: avgAfter,
      realizedPLEstimate: netSale - removedCost,
    );
  }

  RotationResult calculateRotation() {
    final CoinStats origin =
        widget.stats[originCoin] ?? CoinStats(coin: originCoin);
    final CoinStats destination =
        widget.stats[destinationCoin] ?? CoinStats(coin: destinationCoin);

    final double originPrice = _inputDouble(originPriceController);
    final double destinationPrice = _inputDouble(destinationPriceController);
    final double sellFeePercentValue = _inputDouble(
      sellFeeController,
    ).clamp(0, 99).toDouble();
    final double buyFeePercentValue = _inputDouble(
      buyFeeController,
    ).clamp(0, 99).toDouble();

    final bool missingOriginPrice = originPrice <= 0;
    final bool missingDestinationPrice = destinationPrice <= 0;

    if (originCoin == destinationCoin ||
        origin.quantity <= 0 ||
        missingOriginPrice ||
        missingDestinationPrice) {
      return RotationResult(
        valid: false,
        missingOriginPrice: missingOriginPrice,
        missingDestinationPrice: missingDestinationPrice,
      );
    }

    double desiredQty;

    switch (rotationAmountMode) {
      case RotationAmountMode.percentage:
        desiredQty = origin.quantity * selectedPercent / 100;
        break;
      case RotationAmountMode.quantity:
        desiredQty = _inputDouble(rotationQtyController);
        break;
      case RotationAmountMode.grossMxn:
        desiredQty = _inputDouble(rotationGrossController) / originPrice;
        break;
    }

    bool wasLimited = false;
    if (desiredQty > origin.quantity) {
      desiredQty = origin.quantity;
      wasLimited = true;
    }

    if (desiredQty <= 0) {
      return RotationResult(
        valid: false,
        missingOriginPrice: missingOriginPrice,
        missingDestinationPrice: missingDestinationPrice,
        wasLimited: wasLimited,
      );
    }

    final double grossSale = desiredQty * originPrice;
    final double sellFee = grossSale * sellFeePercentValue / 100;
    final double netSale = grossSale - sellFee;
    final double removedCost = origin.avgPrice * desiredQty;
    final double estimatedSellPL = netSale - removedCost;

    final double buyFee = netSale * buyFeePercentValue / 100;
    final double capitalMoved = netSale - buyFee;
    final double destinationBought = capitalMoved / destinationPrice;

    final double destinationQtyAfter = destination.quantity + destinationBought;
    final double destinationCostAfter = destination.costBase + netSale;
    final double destinationAvgAfter = destinationQtyAfter > 0
        ? destinationCostAfter / destinationQtyAfter
        : 0;

    return RotationResult(
      valid: true,
      wasLimited: wasLimited,
      quantitySold: desiredQty,
      grossSale: grossSale,
      sellFee: sellFee,
      netSale: netSale,
      estimatedSellPL: estimatedSellPL,
      destinationBought: destinationBought,
      buyFee: buyFee,
      capitalMoved: capitalMoved,
      totalFees: sellFee + buyFee,
      destinationQtyAfter: destinationQtyAfter,
      destinationAvgAfter: destinationAvgAfter,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.coins.contains(coin)) coin = widget.coins.first;
    if (!widget.coins.contains(originCoin)) originCoin = 'LINK';
    if (!widget.coins.contains(destinationCoin)) destinationCoin = 'BTC';
    final CoinStats coinStats = widget.stats[coin] ?? CoinStats(coin: coin);
    if (priceController.text.trim().isEmpty && coinStats.currentPrice > 0)
      priceController.text = compact(coinStats.currentPrice);
    seedRotationPrices();
    final ScenarioResult scenario = calculateScenario(coinStats);
    final RotationResult rotation = calculateRotation();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        CardPanel(
          title: 'SimulaciÃ³n',
          subtitle: 'No modifica tus movimientos reales.',
          child: SegmentedButton<SimulationMode>(
            segments: const <ButtonSegment<SimulationMode>>[
              ButtonSegment<SimulationMode>(
                value: SimulationMode.buySell,
                label: Text('Compra/Venta'),
                icon: Icon(Icons.swap_vert),
              ),
              ButtonSegment<SimulationMode>(
                value: SimulationMode.rotation,
                label: Text('RotaciÃ³n'),
                icon: Icon(Icons.compare_arrows),
              ),
            ],
            selected: <SimulationMode>{mode},
            onSelectionChanged: (Set<SimulationMode> v) =>
                setState(() => mode = v.first),
          ),
        ),
        if (mode == SimulationMode.buySell)
          buildBuySell(coinStats, scenario)
        else
          buildRotation(rotation),
      ],
    );
  }

  Widget buildBuySell(CoinStats s, ScenarioResult result) => Column(
    children: <Widget>[
      CardPanel(
        title: 'Escenario de compra/venta',
        child: Column(
          children: <Widget>[
            DropdownButtonFormField<String>(
              value: coin,
              decoration: const InputDecoration(
                labelText: 'Moneda',
                border: OutlineInputBorder(),
              ),
              items: widget.coins
                  .map(
                    (String item) => DropdownMenuItem<String>(
                      value: item,
                      child: Text(item),
                    ),
                  )
                  .toList(),
              onChanged: (String? v) {
                if (v == null) return;
                setState(() {
                  coin = v;
                  final double p = widget.currentPrices[coin] ?? 0.0;
                  priceController.text = p > 0 ? compact(p) : '';
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
              selected: <ScenarioType>{scenarioType},
              onSelectionChanged: (Set<ScenarioType> v) =>
                  setState(() => scenarioType = v.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: scenarioType == ScenarioType.buy
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
                for (final double v in <double>[
                  500,
                  1000,
                  3000,
                  5000,
                  8000,
                  15000,
                ])
                  ActionChip(
                    label: Text(moneyShort(v)),
                    onPressed: () =>
                        setState(() => amountController.text = compact(v)),
                  ),
                if (scenarioType == ScenarioType.sell)
                  ActionChip(
                    label: const Text('Todo'),
                    onPressed: s.currentPrice <= 0
                        ? null
                        : () => setState(
                            () => amountController.text = compact(
                              s.quantity * s.currentPrice,
                            ),
                          ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
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
              controller: feeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'ComisiÃ³n %',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      CardPanel(
        title: 'Resultado estimado',
        subtitle: result.valid
            ? 'ProyecciÃ³n, no movimiento real.'
            : 'Completa monto y precio.',
        child: result.valid
            ? Column(
                children: <Widget>[
                  InfoLine(
                    scenarioType == ScenarioType.buy
                        ? 'Cantidad estimada'
                        : 'Cantidad a vender',
                    crypto(result.quantityDelta),
                  ),
                  InfoLine('ComisiÃ³n estimada', money(result.fee)),
                  InfoLine(
                    scenarioType == ScenarioType.buy
                        ? 'Cantidad despuÃ©s'
                        : 'Cantidad restante',
                    crypto(result.quantityAfter),
                    emphasized: true,
                  ),
                  InfoLine('Invertido despuÃ©s', money(result.costBaseAfter)),
                  InfoLine(
                    'Promedio despuÃ©s',
                    money(result.avgAfter),
                    emphasized: true,
                  ),
                  if (scenarioType == ScenarioType.sell)
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

  Widget buildRotation(RotationResult r) {
    final CoinStats origin =
        widget.stats[originCoin] ?? CoinStats(coin: originCoin);
    final bool sameCoin = originCoin == destinationCoin;
    return Column(
      children: <Widget>[
        CardPanel(
          title: 'RotaciÃ³n V2.4',
          subtitle: 'Simula vender una moneda para comprar otra.',
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: originCoin,
                      decoration: const InputDecoration(
                        labelText: 'Origen',
                        border: OutlineInputBorder(),
                      ),
                      items: widget.coins
                          .map(
                            (String item) => DropdownMenuItem<String>(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                      onChanged: (String? v) {
                        if (v == null) return;
                        setState(() {
                          originCoin = v;
                          if (originCoin == destinationCoin ||
                              originCoin == 'LINK' ||
                              originCoin == 'UNI')
                            destinationCoin = 'BTC';
                          if (originCoin == destinationCoin)
                            destinationCoin = widget.coins.firstWhere(
                              (String e) => e != originCoin,
                              orElse: () => 'BTC',
                            );
                          originPriceController.text =
                              (widget.currentPrices[originCoin] ?? 0) > 0
                              ? compact(widget.currentPrices[originCoin] ?? 0)
                              : '';
                          destinationPriceController.text =
                              (widget.currentPrices[destinationCoin] ?? 0) > 0
                              ? compact(
                                  widget.currentPrices[destinationCoin] ?? 0,
                                )
                              : '';
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: destinationCoin,
                      decoration: const InputDecoration(
                        labelText: 'Destino',
                        border: OutlineInputBorder(),
                      ),
                      items: widget.coins
                          .map(
                            (String item) => DropdownMenuItem<String>(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                      onChanged: (String? v) {
                        if (v == null) return;
                        setState(() {
                          destinationCoin = v;
                          destinationPriceController.text =
                              (widget.currentPrices[destinationCoin] ?? 0) > 0
                              ? compact(
                                  widget.currentPrices[destinationCoin] ?? 0,
                                )
                              : '';
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<RotationAmountMode>(
                segments: const <ButtonSegment<RotationAmountMode>>[
                  ButtonSegment<RotationAmountMode>(
                    value: RotationAmountMode.percentage,
                    label: Text('%'),
                  ),
                  ButtonSegment<RotationAmountMode>(
                    value: RotationAmountMode.quantity,
                    label: Text('Cantidad'),
                  ),
                  ButtonSegment<RotationAmountMode>(
                    value: RotationAmountMode.grossMxn,
                    label: Text('MXN'),
                  ),
                ],
                selected: <RotationAmountMode>{rotationAmountMode},
                onSelectionChanged: (Set<RotationAmountMode> v) =>
                    setState(() => rotationAmountMode = v.first),
              ),
              const SizedBox(height: 12),
              if (rotationAmountMode == RotationAmountMode.percentage)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final double p in <double>[25, 50, 75, 100])
                      ChoiceChip(
                        label: Text('${p.toStringAsFixed(0)}%'),
                        selected: selectedPercent == p,
                        onSelected: (_) => setState(() => selectedPercent = p),
                      ),
                  ],
                ),
              if (rotationAmountMode == RotationAmountMode.quantity)
                TextField(
                  controller: rotationQtyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Cantidad exacta de origen',
                    border: OutlineInputBorder(),
                  ),
                ),
              if (rotationAmountMode == RotationAmountMode.grossMxn)
                TextField(
                  controller: rotationGrossController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Venta bruta MXN',
                    border: OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: originPriceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Precio venta origen MXN',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sellFeeController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'ComisiÃ³n venta %',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: destinationPriceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Precio compra destino MXN',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: buyFeeController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'ComisiÃ³n compra %',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: null,
                icon: Icon(Icons.lock_outline),
                label: Text(
                  'Crear movimientos desde rotaciÃ³n Â· PrÃ³ximamente',
                ),
              ),
            ],
          ),
        ),
        CardPanel(
          title: 'Resultado de rotaciÃ³n',
          subtitle: 'No modifica tu cartera real.',
          child: Column(
            children: <Widget>[
              if (sameCoin) const WarningBox(text: 'Elige monedas diferentes.'),
              if (origin.quantity <= 0)
                const WarningBox(text: 'No hay saldo para rotar.'),
              if (r.missingOriginPrice)
                const WarningBox(text: 'Falta precio de venta.'),
              if (r.missingDestinationPrice)
                const WarningBox(text: 'Falta precio de compra.'),
              if (r.wasLimited)
                const WarningBox(
                  text: 'La cantidad se limitÃ³ al saldo disponible.',
                ),
              if (r.valid) ...<Widget>[
                InfoLine('VenderÃ­as', '${crypto(r.quantitySold)} $originCoin'),
                InfoLine('Venta bruta', money(r.grossSale)),
                InfoLine('ComisiÃ³n venta', money(r.sellFee)),
                InfoLine(
                  'RecibirÃ­as neto',
                  money(r.netSale),
                  emphasized: true,
                ),
                InfoLine(
                  'Resultado estimado',
                  money(r.estimatedSellPL),
                  valueColor: pnlColor(r.estimatedSellPL),
                  emphasized: true,
                ),
                if (r.estimatedSellPL < 0)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'RotaciÃ³n con pÃ©rdida estimada',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const Divider(),
                InfoLine(
                  'ComprarÃ­as',
                  '${crypto(r.destinationBought)} $destinationCoin',
                ),
                InfoLine('ComisiÃ³n compra', money(r.buyFee)),
                InfoLine('Capital movido', money(r.capitalMoved)),
                InfoLine('Comisiones totales', money(r.totalFees)),
                InfoLine(
                  'Nuevo saldo destino',
                  crypto(r.destinationQtyAfter),
                  emphasized: true,
                ),
                InfoLine(
                  'Nuevo promedio destino',
                  money(r.destinationAvgAfter),
                  emphasized: true,
                ),
                if (destinationCoin == 'BTC') ...<Widget>[
                  const Divider(),
                  InfoLine(
                    'BTC adicional estimado',
                    crypto(r.destinationBought),
                  ),
                  InfoLine('Nuevo saldo BTC', crypto(r.destinationQtyAfter)),
                  InfoLine('Nuevo promedio BTC', money(r.destinationAvgAfter)),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class WarningBox extends StatelessWidget {
  final String text;

  const WarningBox({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.orange.withOpacity(0.12),
        border: Border.all(color: Colors.orange.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.orange.shade800,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Padding(
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

enum MovementType { buy, sell, transferIn, transferOut }

extension MovementLabel on MovementType {
  String get label => switch (this) {
    MovementType.buy => 'Compra',
    MovementType.sell => 'Venta',
    MovementType.transferIn => 'Transferencia recibida',
    MovementType.transferOut => 'Transferencia enviada',
  };
  String get shortLabel => switch (this) {
    MovementType.buy => 'Compra',
    MovementType.sell => 'Venta',
    MovementType.transferIn => 'Entrada',
    MovementType.transferOut => 'Salida',
  };
}

MovementType movementTypeFromAny(dynamic value) {
  final String raw = value?.toString().trim().toLowerCase() ?? '';
  if (raw == 'buy' || raw == 'compra' || raw == 'comprar')
    return MovementType.buy;
  if (raw == 'sell' || raw == 'venta' || raw == 'vender')
    return MovementType.sell;
  if (raw == 'transferin' ||
      raw == 'transfer_in' ||
      raw == 'transferenciaentrada' ||
      raw == 'transferencia_entrada' ||
      raw == 'transferencia recibida' ||
      raw == 'recibida' ||
      raw == 'entrada')
    return MovementType.transferIn;
  if (raw == 'transferout' ||
      raw == 'transfer_out' ||
      raw == 'transferenciasalida' ||
      raw == 'transferencia_salida' ||
      raw == 'transferencia enviada' ||
      raw == 'enviada' ||
      raw == 'salida')
    return MovementType.transferOut;
  return MovementType.buy;
}

class Movement {
  final MovementType type;
  final String coin;
  final DateTime date;
  final double quantity, unitPrice, fee;
  final String note;
  Movement({
    required this.type,
    required this.coin,
    required this.date,
    required this.quantity,
    required this.unitPrice,
    required this.fee,
    required this.note,
  });
  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type.name,
    'coin': coin,
    'date': date.toIso8601String(),
    'quantity': quantity,
    'unitPrice': unitPrice,
    'fee': fee,
    'note': note,
  };
  factory Movement.fromJson(Map<String, dynamic> json) => Movement(
    type: movementTypeFromAny(json['type']),
    coin: (json['coin'] ?? json['crypto'] ?? 'BTC').toString().toUpperCase(),
    date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
    quantity: n(json['quantity']),
    unitPrice: n(json['unitPrice'] ?? json['unit_price'] ?? json['price']),
    fee: n(json['fee'] ?? json['commission'] ?? json['comision']),
    note: json['note']?.toString() ?? '',
  );
}

class CoinStats {
  final String coin;
  double quantity, costBase, currentPrice, realizedPL, feesPaid;
  CoinStats({
    required this.coin,
    this.quantity = 0,
    this.costBase = 0,
    this.currentPrice = 0,
    this.realizedPL = 0,
    this.feesPaid = 0,
  });
  double get avgPrice => quantity > 0 ? costBase / quantity : 0;
  double get currentValue => quantity * currentPrice;
  double get unrealizedPL => currentValue - costBase;
  double netBreakEvenPrice(double feePercent) {
    if (quantity <= 0) return 0;
    final double mult = 1 - feePercent / 100;
    return mult <= 0 ? 0 : avgPrice / mult;
  }

  double targetNetExitPrice(double feePercent, double targetPercent) {
    if (quantity <= 0) return 0;
    final double mult = 1 - feePercent / 100;
    return mult <= 0
        ? 0
        : (costBase * (1 + targetPercent / 100)) / (quantity * mult);
  }

  double percentToNetBreakEven(double feePercent) {
    if (quantity <= 0 || currentPrice <= 0) return 0;
    final double target = netBreakEvenPrice(feePercent);
    return target <= 0 ? 0 : ((target / currentPrice) - 1) * 100;
  }

  bool isAtOrAboveNetBreakEven(double feePercent) =>
      quantity <= 0 || currentPrice >= netBreakEvenPrice(feePercent);
}

class CoinAudit {
  final double buys, sells, transferIns, transferOuts, fees;
  CoinAudit({
    required this.buys,
    required this.sells,
    required this.transferIns,
    required this.transferOuts,
    required this.fees,
  });
}

class PortfolioTotals {
  final double costBase, currentValue, unrealizedPL, realizedPL, feesPaid;
  PortfolioTotals({
    required this.costBase,
    required this.currentValue,
    required this.unrealizedPL,
    required this.realizedPL,
    required this.feesPaid,
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

  const ScenarioResult({
    required this.valid,
    this.quantityDelta = 0,
    this.quantityAfter = 0,
    this.costBaseAfter = 0,
    this.avgAfter = 0,
    this.fee = 0,
    this.realizedPLEstimate = 0,
  });

  factory ScenarioResult.invalid(CoinStats s) {
    return ScenarioResult(
      valid: false,
      quantityDelta: 0,
      quantityAfter: s.quantity,
      costBaseAfter: s.costBase,
      avgAfter: s.avgPrice,
      fee: 0,
      realizedPLEstimate: 0,
    );
  }
}

class CoinSnapshot {
  final String coin;
  final double quantity,
      costBase,
      avgPrice,
      currentValue,
      unrealizedPL,
      realizedPL;
  CoinSnapshot({
    required this.coin,
    required this.quantity,
    required this.costBase,
    required this.avgPrice,
    required this.currentValue,
    required this.unrealizedPL,
    required this.realizedPL,
  });
  factory CoinSnapshot.fromStats(CoinStats s) => CoinSnapshot(
    coin: s.coin,
    quantity: s.quantity,
    costBase: s.costBase,
    avgPrice: s.avgPrice,
    currentValue: s.currentValue,
    unrealizedPL: s.unrealizedPL,
    realizedPL: s.realizedPL,
  );
  factory CoinSnapshot.fromJson(Map<String, dynamic> json) => CoinSnapshot(
    coin: json['coin']?.toString() ?? 'BTC',
    quantity: n(json['quantity']),
    costBase: n(json['costBase']),
    avgPrice: n(json['avgPrice']),
    currentValue: n(json['currentValue']),
    unrealizedPL: n(json['unrealizedPL']),
    realizedPL: n(json['realizedPL']),
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
  final double totalCostBase,
      totalCurrentValue,
      totalUnrealizedPL,
      totalRealizedPL;
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
  factory PortfolioSnapshot.fromJson(
    Map<String, dynamic> json,
  ) => PortfolioSnapshot(
    id:
        json['id']?.toString() ??
        DateTime.now().microsecondsSinceEpoch.toString(),
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
    totalCostBase: n(json['totalCostBase']),
    totalCurrentValue: n(json['totalCurrentValue']),
    totalUnrealizedPL: n(json['totalUnrealizedPL']),
    totalRealizedPL: n(json['totalRealizedPL']),
    movementCount: json['movementCount'] is int
        ? json['movementCount'] as int
        : 0,
    coins: json['coins'] is List
        ? (json['coins'] as List<dynamic>)
              .map(
                (dynamic e) =>
                    CoinSnapshot.fromJson(Map<String, dynamic>.from(e as Map)),
              )
              .toList()
        : <CoinSnapshot>[],
  );
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'totalCostBase': totalCostBase,
    'totalCurrentValue': totalCurrentValue,
    'totalUnrealizedPL': totalUnrealizedPL,
    'totalRealizedPL': totalRealizedPL,
    'movementCount': movementCount,
    'coins': coins.map((CoinSnapshot e) => e.toJson()).toList(),
  };
}

double n(dynamic value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;
String money(double value) => '\$${value.toStringAsFixed(2)} MXN';
String moneyShort(double value) => '\$${value.toStringAsFixed(0)}';
String crypto(double value) => value.toStringAsFixed(8);
String pct(double value) => '${value.toStringAsFixed(2)}%';
String fixed(double value, int decimals) => value.toStringAsFixed(decimals);
String compact(double value) =>
    value.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
String shortDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
String longDate(DateTime d) =>
    '${shortDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String csvEscape(Object? value) {
  final String text = value?.toString() ?? '';
  final String escaped = text.replaceAll('"', '""');
  return text.contains(',') || text.contains('"') || text.contains('\n')
      ? '"$escaped"'
      : escaped;
}

Color pnlColor(double value) => value > 0
    ? Colors.green.shade700
    : value < 0
    ? Colors.red.shade700
    : Colors.grey.shade700;
