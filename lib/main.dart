import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const CriptoControlApp());
}

class CriptoControlApp extends StatefulWidget {
  const CriptoControlApp({super.key});

  @override
  State<CriptoControlApp> createState() => _CriptoControlAppState();
}

class _CriptoControlAppState extends State<CriptoControlApp> {
  final List<String> _coins = ['BTC', 'ETH', 'LINK', 'LTC', 'UNI'];

  final List<Movement> _movements = [];

  final Map<String, double> _currentPrices = {
    'BTC': 0,
    'ETH': 0,
    'LINK': 0,
    'LTC': 0,
    'UNI': 0,
  };

  static const _movementsKey = 'movements_json';
  static const _pricesKey = 'prices_json';
  static const _sellFeePercentKey = 'sell_fee_percent';

  int _currentIndex = 0;
  double _sellFeePercent = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();

    final movementsJson = jsonEncode(
      _movements.map((m) => m.toJson()).toList(),
    );
    final pricesJson = jsonEncode(_currentPrices);

    await prefs.setString(_movementsKey, movementsJson);
    await prefs.setString(_pricesKey, pricesJson);
    await prefs.setDouble(_sellFeePercentKey, _sellFeePercent);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final movementsRaw = prefs.getString(_movementsKey);
    final pricesRaw = prefs.getString(_pricesKey);

    if (movementsRaw != null) {
      final decoded = jsonDecode(movementsRaw) as List<dynamic>;
      _movements
        ..clear()
        ..addAll(
          decoded.map((e) => Movement.fromJson(Map<String, dynamic>.from(e))),
        );
    }

    if (pricesRaw != null) {
      final decoded = Map<String, dynamic>.from(jsonDecode(pricesRaw));
      decoded.forEach((key, value) {
        _currentPrices[key] = (value as num).toDouble();
      });
    }

    _sellFeePercent = prefs.getDouble(_sellFeePercentKey) ?? 0;

    if (mounted) {
      setState(() {});
    }
  }

  Map<String, CoinStats> _computeStats() {
    final stats = <String, CoinStats>{
      for (final coin in _coins)
        coin: CoinStats(
          coin: coin,
          currentPrice: _currentPrices[coin] ?? 0,
        ),
    };

    final indexed = _movements.asMap().entries.toList()
      ..sort((a, b) {
        final dateCompare = a.value.date.compareTo(b.value.date);
        if (dateCompare != 0) return dateCompare;
        return a.key.compareTo(b.key);
      });

    for (final entry in indexed) {
      final m = entry.value;
      final s = stats[m.coin];
      if (s == null) continue;

      switch (m.type) {
        case MovementType.buy:
        case MovementType.transferIn:
          s.quantity += m.quantity;
          s.costBase += (m.quantity * m.unitPrice) + m.fee;
          break;

        case MovementType.sell:
          final avg = s.quantity > 0 ? s.costBase / s.quantity : 0;
          final qtyToRemove = m.quantity > s.quantity ? s.quantity : m.quantity;
          final removedCost = avg * qtyToRemove;
          final proceeds = (m.quantity * m.unitPrice) - m.fee;

          s.realizedPL += proceeds - removedCost;
          s.quantity -= qtyToRemove;
          s.costBase -= removedCost;

          if (s.quantity.abs() < 0.0000000001) {
            s.quantity = 0;
            s.costBase = 0;
          }
          break;

        case MovementType.transferOut:
          final avg = s.quantity > 0 ? s.costBase / s.quantity : 0;
          final qtyToRemove = m.quantity > s.quantity ? s.quantity : m.quantity;
          final removedCost = avg * qtyToRemove;

          s.quantity -= qtyToRemove;
          s.costBase -= removedCost;

          if (s.quantity.abs() < 0.0000000001) {
            s.quantity = 0;
            s.costBase = 0;
          }
          break;
      }

      s.currentPrice = _currentPrices[m.coin] ?? 0;
    }

    for (final coin in _coins) {
      stats[coin]!.currentPrice = _currentPrices[coin] ?? 0;
    }

    return stats;
  }

  bool _wouldCreateInvalidPosition(
    Movement candidate, {
    int? replaceIndex,
  }) {
    final testList = [..._movements];

    if (replaceIndex != null &&
        replaceIndex >= 0 &&
        replaceIndex < testList.length) {
      testList[replaceIndex] = candidate;
    } else {
      testList.add(candidate);
    }

    final balances = <String, double>{
      for (final coin in _coins) coin: 0,
    };

    final indexed = testList.asMap().entries.toList()
      ..sort((a, b) {
        final dateCompare = a.value.date.compareTo(b.value.date);
        if (dateCompare != 0) return dateCompare;
        return a.key.compareTo(b.key);
      });

    for (final entry in indexed) {
      final m = entry.value;
      final current = balances[m.coin] ?? 0;

      switch (m.type) {
        case MovementType.buy:
        case MovementType.transferIn:
          balances[m.coin] = current + m.quantity;
          break;

        case MovementType.sell:
        case MovementType.transferOut:
          if (m.quantity > current + 0.0000000001) {
            return true;
          }
          balances[m.coin] = current - m.quantity;
          break;
      }
    }

    return false;
  }

  String _buildBackupJson() {
    final backup = {
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': {
        'sellFeePercent': _sellFeePercent,
      },
      'currentPrices': _currentPrices,
      'movements': _movements.map((m) => m.toJson()).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  Future<void> _exportBackup(BuildContext pageContext) async {
    final backupJson = _buildBackupJson();

    await showDialog<void>(
      context: pageContext,
      builder: (context) => AlertDialog(
        title: const Text('Respaldo JSON'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(backupJson),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: backupJson));
              if (context.mounted && pageContext.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(pageContext).showSnackBar(
                  const SnackBar(
                    content: Text('Respaldo copiado al portapapeles'),
                  ),
                );
              }
            },
            child: const Text('Copiar'),
          ),
        ],
      ),
    );
  }

  Future<void> _importBackup(BuildContext pageContext) async {
    final controller = TextEditingController();

    await showDialog<void>(
      context: pageContext,
      builder: (context) => AlertDialog(
        title: const Text('Importar respaldo JSON'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 18,
            minLines: 10,
            decoration: const InputDecoration(
              hintText: 'Pega aquí el JSON del respaldo',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final raw = controller.text.trim();
                if (raw.isEmpty) {
                  if (!pageContext.mounted) return;
                  ScaffoldMessenger.of(pageContext).showSnackBar(
                    const SnackBar(
                      content: Text('Pega un respaldo válido'),
                    ),
                  );
                  return;
                }

                final decoded = jsonDecode(raw);

                if (decoded is! Map<String, dynamic>) {
                  throw const FormatException('JSON inválido');
                }

                final movementsRaw = decoded['movements'];
                final pricesRaw = decoded['currentPrices'];
                final settingsRaw = decoded['settings'];

                if (movementsRaw is! List) {
                  throw const FormatException('Falta lista de movimientos');
                }

                if (pricesRaw is! Map) {
                  throw const FormatException('Faltan precios actuales');
                }

                final importedMovements = movementsRaw
                    .map(
                      (e) => Movement.fromJson(Map<String, dynamic>.from(e)),
                    )
                    .toList();

                final importedPrices = <String, double>{};
                for (final coin in _coins) {
                  final value = pricesRaw[coin];
                  importedPrices[coin] =
                      value == null ? 0 : (value as num).toDouble();
                }

                double importedSellFeePercent = 0;
                if (settingsRaw is Map) {
                  final feeValue = settingsRaw['sellFeePercent'];
                  if (feeValue is num) {
                    importedSellFeePercent = feeValue.toDouble();
                  }
                }

                setState(() {
                  _movements
                    ..clear()
                    ..addAll(importedMovements);

                  for (final coin in _coins) {
                    _currentPrices[coin] = importedPrices[coin] ?? 0;
                  }

                  _sellFeePercent = importedSellFeePercent;
                });

                await _saveData();

                if (context.mounted && pageContext.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(pageContext).showSnackBar(
                    const SnackBar(
                      content: Text('Respaldo importado correctamente'),
                    ),
                  );
                }
              } catch (_) {
                if (!pageContext.mounted) return;

                ScaffoldMessenger.of(pageContext).showSnackBar(
                  const SnackBar(
                    content: Text('El JSON no es válido o está incompleto'),
                  ),
                );
              }
            },
            child: const Text('Importar'),
          ),
        ],
      ),
    );
  }

  void _clearAll() {
    setState(() {
      _movements.clear();
      for (final coin in _coins) {
        _currentPrices[coin] = 0;
      }
      _sellFeePercent = 0;
    });
    _saveData();
  }

  Future<void> _confirmClearAll(BuildContext pageContext) async {
    final confirm = await showDialog<bool>(
      context: pageContext,
      builder: (context) => AlertDialog(
        title: const Text('Borrar todo'),
        content: const Text('¿Seguro que quieres borrar todos los datos?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar todo'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _clearAll();
    }
  }

  void _deleteMovement(Movement movement) {
    setState(() {
      _movements.remove(movement);
    });
    _saveData();
  }

  Future<void> _showSellFeeDialog(BuildContext pageContext) async {
    final controller = TextEditingController(
      text: _sellFeePercent.toString(),
    );

    await showDialog<void>(
      context: pageContext,
      builder: (context) => AlertDialog(
        title: const Text('Comisión de salida (%)'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Porcentaje',
            border: OutlineInputBorder(),
            helperText: 'Ejemplo: 1.5',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null || value < 0 || value >= 100) return;

              setState(() {
                _sellFeePercent = value;
              });
              _saveData();
              Navigator.of(context).pop();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showEditPriceDialog(BuildContext pageContext, String coin) {
    final controller = TextEditingController(
      text: (_currentPrices[coin] ?? 0).toString(),
    );

    showDialog<void>(
      context: pageContext,
      builder: (context) => AlertDialog(
        title: Text('Precio actual de $coin'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Precio en MXN',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null || value < 0) return;

              setState(() {
                _currentPrices[coin] = value;
              });
              _saveData();
              Navigator.of(context).pop();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    DateTime initialDate,
    void Function(DateTime) onPicked,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2010),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      onPicked(picked);
    }
  }

  void _showAddMovementSheet(
    BuildContext pageContext, {
    Movement? existing,
    int? index,
  }) {
    MovementType selectedType = existing?.type ?? MovementType.buy;
    String selectedCoin = existing?.coin ?? _coins.first;
    DateTime selectedDate = existing?.date ?? DateTime.now();

    final qtyController = TextEditingController(
      text: existing != null ? fmtCompact(existing.quantity) : '',
    );
    final priceController = TextEditingController(
      text: existing != null ? fmtCompact(existing.unitPrice) : '',
    );
    final feeController = TextEditingController(
      text: existing != null ? fmtCompact(existing.fee) : '0',
    );
    final noteController = TextEditingController(
      text: existing?.note ?? '',
    );

    showModalBottomSheet<void>(
      context: pageContext,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isOut = selectedType == MovementType.sell ||
                selectedType == MovementType.transferOut;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing != null
                          ? 'Editar movimiento'
                          : 'Agregar movimiento',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<MovementType>(
                      initialValue: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        border: OutlineInputBorder(),
                      ),
                      items: MovementType.values
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(type.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
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
                            (coin) => DropdownMenuItem(
                              value: coin,
                              child: Text(coin),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setModalState(() => selectedCoin = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _pickDate(
                        context,
                        selectedDate,
                        (date) => setModalState(() => selectedDate = date),
                      ),
                      icon: const Icon(Icons.calendar_today),
                      label: Text('Fecha: ${shortDate(selectedDate)}'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: qtyController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Cantidad',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: isOut
                            ? 'Precio unitario en MXN (0 si no aplica)'
                            : 'Precio unitario en MXN',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: feeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Comisión en MXN',
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
                          final quantity = double.tryParse(
                            qtyController.text.trim(),
                          );
                          final unitPrice = double.tryParse(
                            priceController.text.trim(),
                          );
                          final fee =
                              double.tryParse(feeController.text.trim()) ?? 0;

                          if (quantity == null || quantity <= 0) {
                            ScaffoldMessenger.of(pageContext).showSnackBar(
                              const SnackBar(
                                content: Text('Pon una cantidad válida'),
                              ),
                            );
                            return;
                          }

                          if (unitPrice == null || unitPrice < 0) {
                            ScaffoldMessenger.of(pageContext).showSnackBar(
                              const SnackBar(
                                content: Text('Pon un precio válido'),
                              ),
                            );
                            return;
                          }

                          if (fee < 0) {
                            ScaffoldMessenger.of(pageContext).showSnackBar(
                              const SnackBar(
                                content: Text('La comisión no puede ser negativa'),
                              ),
                            );
                            return;
                          }

                          final updated = Movement(
                            type: selectedType,
                            coin: selectedCoin,
                            date: selectedDate,
                            quantity: quantity,
                            unitPrice: unitPrice,
                            fee: fee,
                            note: noteController.text.trim(),
                          );

                          if (_wouldCreateInvalidPosition(
                            updated,
                            replaceIndex: existing != null ? index : null,
                          )) {
                            ScaffoldMessenger.of(pageContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Ese ${selectedType.label} deja la posición de $selectedCoin en negativo. Revísalo.',
                                ),
                              ),
                            );
                            return;
                          }

                          setState(() {
                            if (existing != null &&
                                index != null &&
                                index >= 0 &&
                                index < _movements.length) {
                              _movements[index] = updated;
                            } else {
                              _movements.add(updated);
                            }
                          });

                          _saveData();
                          Navigator.of(context).pop();
                        },
                        icon: Icon(existing != null ? Icons.save : Icons.add),
                        label: Text(
                          existing != null
                              ? 'Guardar cambios'
                              : 'Guardar movimiento',
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

  @override
  Widget build(BuildContext context) {
    final stats = _computeStats();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CriptoControlMx',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
      ),
      home: Builder(
        builder: (pageContext) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('CriptoControlMx'),
              actions: [
                IconButton(
                  onPressed: () => _showAddMovementSheet(pageContext),
                  icon: const Icon(Icons.add),
                  tooltip: 'Agregar movimiento',
                ),
              ],
            ),
            body: IndexedStack(
              index: _currentIndex,
              children: [
                SummaryTab(
                  stats: stats,
                  sellFeePercent: _sellFeePercent,
                ),
                MovementsTab(
                  movements: _movements,
                  coins: _coins,
                  onDelete: (movement) => _deleteMovement(movement),
                  onEdit: (movement) => _showAddMovementSheet(
                    pageContext,
                    existing: movement,
                    index: _movements.indexOf(movement),
                  ),
                ),
                CoinsTab(
                  coins: _coins,
                  stats: stats,
                  sellFeePercent: _sellFeePercent,
                  onEditPrice: (coin) => _showEditPriceDialog(pageContext, coin),
                ),
                SettingsTab(
                  sellFeePercent: _sellFeePercent,
                  onEditSellFee: () => _showSellFeeDialog(pageContext),
                  onExportBackup: () => _exportBackup(pageContext),
                  onImportBackup: () => _importBackup(pageContext),
                  onClearAll: () => _confirmClearAll(pageContext),
                ),
              ],
            ),
            floatingActionButton: _currentIndex == 3
                ? null
                : FloatingActionButton.extended(
                    onPressed: () => _showAddMovementSheet(pageContext),
                    icon: const Icon(Icons.add),
                    label: const Text('Movimiento'),
                  ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() => _currentIndex = index);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  label: 'Resumen',
                ),
                NavigationDestination(
                  icon: Icon(Icons.swap_horiz),
                  label: 'Movimientos',
                ),
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
  final double sellFeePercent;

  const SummaryTab({
    super.key,
    required this.stats,
    required this.sellFeePercent,
  });

  @override
  Widget build(BuildContext context) {
    final totalCostBase = stats.values.fold<double>(
      0,
      (sum, s) => sum + s.costBase,
    );
    final totalCurrentValue = stats.values.fold<double>(
      0,
      (sum, s) => sum + s.currentValue,
    );
    final totalUnrealized = stats.values.fold<double>(
      0,
      (sum, s) => sum + s.unrealizedPL,
    );
    final totalRealized = stats.values.fold<double>(
      0,
      (sum, s) => sum + s.realizedPL,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _metricCard('Costo base actual', totalCostBase),
        const SizedBox(height: 12),
        _metricCard('Valor actual', totalCurrentValue),
        const SizedBox(height: 12),
        _metricCard('P/L no realizado', totalUnrealized),
        const SizedBox(height: 12),
        _metricCard('P/L realizado', totalRealized),
        const SizedBox(height: 20),
        const Text(
          'Resumen por moneda',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...stats.values.map(
          (s) => Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.coin,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Cantidad actual: ${fmt(s.quantity)}'),
                  Text('Costo base actual: ${money(s.costBase)}'),
                  Text('Precio promedio actual: ${money(s.avgPrice)}'),
                  Text('Break even bruto: ${money(s.breakEvenPrice)}'),
                  Text(
                    'Break even neto: ${money(s.netBreakEvenPrice(sellFeePercent))}',
                  ),
                  Text('Precio actual: ${money(s.currentPrice)}'),
                  Text('Valor actual: ${money(s.currentValue)}'),
                  Text('P/L no realizado: ${money(s.unrealizedPL)}'),
                  Text('P/L realizado: ${money(s.realizedPL)}'),
                  Text(_statusLine(s, sellFeePercent)),
                  Text(_distanceLine(s, sellFeePercent)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _statusLine(CoinStats s, double sellFeePercent) {
    if (s.quantity <= 0) {
      return 'Estado: sin posición abierta';
    }

    if (s.isAtOrAboveNetBreakEven(sellFeePercent)) {
      return 'Estado: arriba o en break even neto';
    }

    return 'Faltante para break even neto: ${money(s.amountToNetBreakEven(sellFeePercent))}';
  }

  String _distanceLine(CoinStats s, double sellFeePercent) {
    if (s.quantity <= 0) {
      return 'Distancia al break even: —';
    }

    if (s.isAtOrAboveNetBreakEven(sellFeePercent)) {
      return 'Subida necesaria: 0.00%';
    }

    return 'Subida necesaria: ${pct(s.percentToNetBreakEven(sellFeePercent))}';
  }

  Widget _metricCard(String title, double value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            const SizedBox(height: 8),
            Text(
              money(value),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
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
  final void Function(Movement movement) onDelete;
  final void Function(Movement movement) onEdit;

  const MovementsTab({
    super.key,
    required this.movements,
    required this.coins,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  State<MovementsTab> createState() => _MovementsTabState();
}

class _MovementsTabState extends State<MovementsTab> {
  String _selectedCoin = 'TODAS';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.movements.where((m) {
      if (_selectedCoin == 'TODAS') return true;
      return m.coin == _selectedCoin;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: DropdownButtonFormField<String>(
            initialValue: _selectedCoin,
            decoration: const InputDecoration(
              labelText: 'Filtrar por moneda',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(
                value: 'TODAS',
                child: Text('Todas'),
              ),
              ...widget.coins.map(
                (coin) => DropdownMenuItem(
                  value: coin,
                  child: Text(coin),
                ),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedCoin = value);
              }
            },
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Aún no hay movimientos'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final m = filtered[index];

                    return Card(
                      child: ListTile(
                        onTap: () => widget.onEdit(m),
                        title: Text('${m.type.label} · ${m.coin}'),
                        subtitle: Text(
                          '${shortDate(m.date)}\n'
                          'Cantidad: ${fmt(m.quantity)} · Precio: ${money(m.unitPrice)} · Comisión: ${money(m.fee)}'
                          '${m.note.isNotEmpty ? '\nNota: ${m.note}' : ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Editar',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => widget.onEdit(m),
                            ),
                            IconButton(
                              tooltip: 'Borrar',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Borrar movimiento'),
                                    content: Text(
                                      '¿Seguro que quieres borrar ${m.type.label} de ${m.coin} por ${fmt(m.quantity)}?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(false),
                                        child: const Text('Cancelar'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(true),
                                        child: const Text('Borrar'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  widget.onDelete(m);
                                }
                              },
                            ),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class CoinsTab extends StatelessWidget {
  final List<String> coins;
  final Map<String, CoinStats> stats;
  final double sellFeePercent;
  final void Function(String coin) onEditPrice;

  const CoinsTab({
    super.key,
    required this.coins,
    required this.stats,
    required this.sellFeePercent,
    required this.onEditPrice,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: coins.map((coin) {
        final s = stats[coin]!;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      coin,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => onEditPrice(coin),
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Editar precio actual',
                    ),
                  ],
                ),
                Text('Cantidad actual: ${fmt(s.quantity)}'),
                Text('Costo base actual: ${money(s.costBase)}'),
                Text('Precio promedio actual: ${money(s.avgPrice)}'),
                Text('Break even bruto: ${money(s.breakEvenPrice)}'),
                Text(
                  'Break even neto: ${money(s.netBreakEvenPrice(sellFeePercent))}',
                ),
                Text('Precio actual: ${money(s.currentPrice)}'),
                Text('Valor actual: ${money(s.currentValue)}'),
                Text('P/L no realizado: ${money(s.unrealizedPL)}'),
                Text('P/L realizado: ${money(s.realizedPL)}'),
                Text(_statusLine(s)),
                Text(_distanceLine(s)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _statusLine(CoinStats s) {
    if (s.quantity <= 0) {
      return 'Estado: sin posición abierta';
    }

    if (s.isAtOrAboveNetBreakEven(sellFeePercent)) {
      return 'Estado: arriba o en break even neto';
    }

    return 'Faltante para break even neto: ${money(s.amountToNetBreakEven(sellFeePercent))}';
  }

  String _distanceLine(CoinStats s) {
    if (s.quantity <= 0) {
      return 'Distancia al break even: —';
    }

    if (s.isAtOrAboveNetBreakEven(sellFeePercent)) {
      return 'Subida necesaria: 0.00%';
    }

    return 'Subida necesaria: ${pct(s.percentToNetBreakEven(sellFeePercent))}';
  }
}

class SettingsTab extends StatelessWidget {
  final double sellFeePercent;
  final VoidCallback onEditSellFee;
  final VoidCallback onExportBackup;
  final VoidCallback onImportBackup;
  final VoidCallback onClearAll;

  const SettingsTab({
    super.key,
    required this.sellFeePercent,
    required this.onEditSellFee,
    required this.onExportBackup,
    required this.onImportBackup,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Break even neto',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Comisión de salida actual: ${pct(sellFeePercent)}',
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: onEditSellFee,
                  child: const Text('Editar comisión de salida'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Respaldo',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Exporta o importa tu cartera en formato JSON usando copiar y pegar.',
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: onExportBackup,
                  child: const Text('Exportar respaldo JSON'),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: onImportBackup,
                  child: const Text('Importar respaldo JSON'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Peligro',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Esto borra movimientos, precios actuales y comisión de salida guardados en el dispositivo.',
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: onClearAll,
                  child: const Text('Borrar todo'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum MovementType {
  buy,
  sell,
  transferIn,
  transferOut,
}

extension MovementTypeLabel on MovementType {
  String get label {
    switch (this) {
      case MovementType.buy:
        return 'BUY';
      case MovementType.sell:
        return 'SELL';
      case MovementType.transferIn:
        return 'TRANSFER_IN';
      case MovementType.transferOut:
        return 'TRANSFER_OUT';
    }
  }
}

class Movement {
  final MovementType type;
  final String coin;
  final DateTime date;
  final double quantity;
  final double unitPrice;
  final double fee;
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

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'coin': coin,
      'date': date.toIso8601String(),
      'quantity': quantity,
      'unitPrice': unitPrice,
      'fee': fee,
      'note': note,
    };
  }

  factory Movement.fromJson(Map<String, dynamic> json) {
    return Movement(
      type: MovementType.values.firstWhere((e) => e.name == json['type']),
      coin: json['coin'] as String,
      date: DateTime.parse(json['date'] as String),
      quantity: (json['quantity'] as num).toDouble(),
      unitPrice: (json['unitPrice'] as num).toDouble(),
      fee: (json['fee'] as num).toDouble(),
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

  CoinStats({
    required this.coin,
    this.quantity = 0,
    this.costBase = 0,
    this.currentPrice = 0,
    this.realizedPL = 0,
  });

  double get avgPrice => quantity > 0 ? costBase / quantity : 0;

  double get breakEvenPrice => avgPrice;

  double netBreakEvenPrice(double sellFeePercent) {
    if (quantity <= 0) return 0;
    final multiplier = 1 - (sellFeePercent / 100);
    if (multiplier <= 0) return 0;
    return avgPrice / multiplier;
  }

  double get currentValue => quantity * currentPrice;

  double get unrealizedPL => currentValue - costBase;

  double amountToNetBreakEven(double sellFeePercent) {
    if (quantity <= 0) return 0;
    final netCurrentValue = currentValue * (1 - (sellFeePercent / 100));
    final diff = costBase - netCurrentValue;
    return diff > 0 ? diff : 0;
  }

  double percentToNetBreakEven(double sellFeePercent) {
    if (quantity <= 0 || currentPrice <= 0) return 0;
    final target = netBreakEvenPrice(sellFeePercent);
    if (target <= 0) return 0;
    return ((target / currentPrice) - 1) * 100;
  }

  bool isAtOrAboveNetBreakEven(double sellFeePercent) {
    if (quantity <= 0) return true;
    return currentPrice >= netBreakEvenPrice(sellFeePercent);
  }
}

String money(double value) => '\$${value.toStringAsFixed(2)} MXN';

String fmt(double value) => value.toStringAsFixed(8);

String fmtCompact(double value) {
  final text = value.toStringAsFixed(8);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

String pct(double value) => '${value.toStringAsFixed(2)}%';

String shortDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';
}
