import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
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
    await prefs.setString(
      _movementsKey,
      jsonEncode(_movements.map((m) => m.toJson()).toList()),
    );
    await prefs.setString(_pricesKey, jsonEncode(_currentPrices));
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
      for (final entry in decoded.entries) {
        _currentPrices[entry.key] = (entry.value as num).toDouble();
      }
    }

    _sellFeePercent = prefs.getDouble(_sellFeePercentKey) ?? 0;
    if (mounted) setState(() {});
  }

  Map<String, CoinStats> _computeStats() {
    final stats = <String, CoinStats>{
      for (final coin in _coins)
        coin: CoinStats(coin: coin, currentPrice: _currentPrices[coin] ?? 0),
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
          break;
        case MovementType.transferOut:
          final avg = s.quantity > 0 ? s.costBase / s.quantity : 0;
          final qtyToRemove = m.quantity > s.quantity ? s.quantity : m.quantity;
          final removedCost = avg * qtyToRemove;
          s.quantity -= qtyToRemove;
          s.costBase -= removedCost;
          break;
      }

      if (s.quantity.abs() < 0.0000000001) {
        s.quantity = 0;
        s.costBase = 0;
      }
      s.currentPrice = _currentPrices[m.coin] ?? 0;
    }

    for (final coin in _coins) {
      stats[coin]!.currentPrice = _currentPrices[coin] ?? 0;
    }

    return stats;
  }

  bool _wouldCreateInvalidPosition(Movement candidate, {int? replaceIndex}) {
    final testList = [..._movements];

    if (replaceIndex != null && replaceIndex >= 0 && replaceIndex < testList.length) {
      testList[replaceIndex] = candidate;
    } else {
      testList.add(candidate);
    }

    final balances = <String, double>{for (final coin in _coins) coin: 0};
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
          if (m.quantity > current + 0.0000000001) return true;
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
      'settings': {'sellFeePercent': _sellFeePercent},
      'currentPrices': _currentPrices,
      'movements': _movements.map((m) => m.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  String _buildMovementsCsv() {
    final rows = <List<Object?>>[
      [
        'fecha',
        'tipo',
        'tipo_raw',
        'cripto',
        'cantidad',
        'precio_unitario_mxn',
        'fee_mxn',
        'total_bruto_mxn',
        'total_neto_mxn',
        'nota',
      ],
      ..._movements.map((m) {
        final gross = m.quantity * m.unitPrice;
        final net = m.type == MovementType.sell ? gross - m.fee : gross + m.fee;
        return [
          isoDate(m.date),
          m.type.label,
          m.type.name,
          m.coin,
          fixed(m.quantity, 8),
          fixed(m.unitPrice, 2),
          fixed(m.fee, 2),
          fixed(gross, 2),
          fixed(net, 2),
          m.note,
        ];
      }),
    ];
    return rows.map((r) => r.map(csvEscape).join(',')).join('\n');
  }

  String _buildSummaryCsv() {
    final stats = _computeStats();
    final rows = <List<Object?>>[
      [
        'cripto',
        'cantidad_actual',
        'costo_base_mxn',
        'promedio_actual_mxn',
        'break_even_bruto_mxn',
        'break_even_neto_mxn',
        'precio_actual_mxn',
        'valor_actual_mxn',
        'pl_realizado_mxn',
        'pl_no_realizado_mxn',
        'objetivo_neto_5_mxn',
        'objetivo_neto_10_mxn',
        'estado',
      ],
      ..._coins.map((coin) {
        final s = stats[coin]!;
        return [
          s.coin,
          fixed(s.quantity, 8),
          fixed(s.costBase, 2),
          fixed(s.avgPrice, 2),
          fixed(s.breakEvenPrice, 2),
          fixed(s.netBreakEvenPrice(_sellFeePercent), 2),
          fixed(s.currentPrice, 2),
          fixed(s.currentValue, 2),
          fixed(s.realizedPL, 2),
          fixed(s.unrealizedPL, 2),
          fixed(s.targetNetExitPrice(_sellFeePercent, 5), 2),
          fixed(s.targetNetExitPrice(_sellFeePercent, 10), 2),
          statusLabel(s, _sellFeePercent),
        ];
      }),
    ];
    return rows.map((r) => r.map(csvEscape).join(',')).join('\n');
  }

  Uint8List _buildXlsxBytes() {
    final stats = _computeStats();
    final excel = xl.Excel.createExcel();

    final historial = excel['Historial'];
    _appendExcelRow(historial, [
      'Fecha',
      'Tipo',
      'Tipo raw',
      'Cripto',
      'Cantidad',
      'Precio unitario MXN',
      'Fee MXN',
      'Total bruto MXN',
      'Total neto MXN',
      'Nota',
    ]);

    for (final m in _movements) {
      final gross = m.quantity * m.unitPrice;
      final net = m.type == MovementType.sell ? gross - m.fee : gross + m.fee;
      _appendExcelRow(historial, [
        isoDate(m.date),
        m.type.label,
        m.type.name,
        m.coin,
        m.quantity,
        m.unitPrice,
        m.fee,
        gross,
        net,
        m.note,
      ]);
    }

    final resumen = excel['Resumen'];
    _appendExcelRow(resumen, [
      'Cripto',
      'Cantidad actual',
      'Costo base MXN',
      'Promedio actual MXN',
      'BE bruto MXN',
      'BE neto MXN',
      'Precio actual MXN',
      'Valor actual MXN',
      'P/L realizado MXN',
      'P/L no realizado MXN',
      'Objetivo +5% MXN',
      'Objetivo +10% MXN',
      'Estado',
    ]);

    for (final coin in _coins) {
      final s = stats[coin]!;
      _appendExcelRow(resumen, [
        s.coin,
        s.quantity,
        s.costBase,
        s.avgPrice,
        s.breakEvenPrice,
        s.netBreakEvenPrice(_sellFeePercent),
        s.currentPrice,
        s.currentValue,
        s.realizedPL,
        s.unrealizedPL,
        s.targetNetExitPrice(_sellFeePercent, 5),
        s.targetNetExitPrice(_sellFeePercent, 10),
        statusLabel(s, _sellFeePercent),
      ]);
    }

    excel.setDefaultSheet('Resumen');
    final bytes = excel.encode();
    if (bytes == null) throw Exception('No se pudo crear el XLSX');
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> _buildPdfBytes() async {
    final stats = _computeStats();
    final totalCostBase = stats.values.fold<double>(0, (sum, s) => sum + s.costBase);
    final totalCurrentValue = stats.values.fold<double>(0, (sum, s) => sum + s.currentValue);
    final totalUnrealized = stats.values.fold<double>(0, (sum, s) => sum + s.unrealizedPL);
    final totalRealized = stats.values.fold<double>(0, (sum, s) => sum + s.realizedPL);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(margin: pw.EdgeInsets.all(28)),
        build: (context) => [
          pw.Text(
            'CriptoControlMx - Reporte de cartera',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Generado: ${DateTime.now().toIso8601String()}'),
          pw.Text('Comision de salida: ${pct(_sellFeePercent)}'),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            headers: ['Metrica', 'Monto'],
            data: [
              ['Costo base actual', money(totalCostBase)],
              ['Valor actual', money(totalCurrentValue)],
              ['P/L no realizado', money(totalUnrealized)],
              ['P/L realizado', money(totalRealized)],
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
            headers: ['Cripto', 'Cantidad', 'Costo base', 'Valor', 'P/L', 'BE neto', 'Estado'],
            data: _coins.map((coin) {
              final s = stats[coin]!;
              return [
                s.coin,
                fmt(s.quantity),
                money(s.costBase),
                money(s.currentValue),
                money(s.unrealizedPL),
                money(s.netBreakEvenPrice(_sellFeePercent)),
                statusLabel(s, _sellFeePercent),
              ];
            }).toList(),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  void _appendExcelRow(xl.Sheet sheet, List<Object?> values) {
    sheet.appendRow(values.map(toExcelValue).toList());
  }

  Future<void> _shareDataFile({
    required BuildContext pageContext,
    required String fileName,
    required String mimeType,
    required List<int> bytes,
    required String successMessage,
  }) async {
    final messenger = ScaffoldMessenger.of(pageContext);
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(bytes),
              mimeType: mimeType,
              name: fileName,
            ),
          ],
          fileNameOverrides: [fileName],
          text: 'CriptoControlMx',
        ),
      );
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo exportar el archivo')));
    }
  }

  Future<void> _exportMovementsCsv(BuildContext pageContext) async {
    await _shareDataFile(
      pageContext: pageContext,
      fileName: 'criptocontrolmx_historial.csv',
      mimeType: 'text/csv',
      bytes: utf8.encode('\ufeff${_buildMovementsCsv()}'),
      successMessage: 'Historial CSV listo para compartir',
    );
  }

  Future<void> _exportSummaryCsv(BuildContext pageContext) async {
    await _shareDataFile(
      pageContext: pageContext,
      fileName: 'criptocontrolmx_resumen.csv',
      mimeType: 'text/csv',
      bytes: utf8.encode('\ufeff${_buildSummaryCsv()}'),
      successMessage: 'Resumen CSV listo para compartir',
    );
  }

  Future<void> _exportXlsx(BuildContext pageContext) async {
    await _shareDataFile(
      pageContext: pageContext,
      fileName: 'criptocontrolmx_reporte.xlsx',
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      bytes: _buildXlsxBytes(),
      successMessage: 'XLSX listo para compartir',
    );
  }

  Future<void> _exportPdf(BuildContext pageContext) async {
    final bytes = await _buildPdfBytes();
    if (!mounted) return;
    await _shareDataFile(
      pageContext: pageContext,
      fileName: 'criptocontrolmx_reporte.pdf',
      mimeType: 'application/pdf',
      bytes: bytes,
      successMessage: 'PDF listo para compartir',
    );
  }

  Future<void> _exportBackup(BuildContext pageContext) async {
    final backupJson = _buildBackupJson();

    await showDialog<void>(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Respaldo JSON'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(backupJson)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: backupJson));
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(pageContext).showSnackBar(
                const SnackBar(content: Text('Respaldo copiado al portapapeles')),
              );
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
      builder: (dialogContext) => AlertDialog(
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
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final raw = controller.text.trim();
                if (raw.isEmpty) {
                  ScaffoldMessenger.of(pageContext).showSnackBar(
                    const SnackBar(content: Text('Pega un respaldo válido')),
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
                    .map((e) => Movement.fromJson(Map<String, dynamic>.from(e)))
                    .toList();

                final importedPrices = <String, double>{};
                for (final coin in _coins) {
                  final value = pricesRaw[coin];
                  importedPrices[coin] = value == null ? 0 : (value as num).toDouble();
                }

                double importedSellFeePercent = 0;
                if (settingsRaw is Map) {
                  final feeValue = settingsRaw['sellFeePercent'];
                  if (feeValue is num) importedSellFeePercent = feeValue.toDouble();
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
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(pageContext).showSnackBar(
                  const SnackBar(content: Text('Respaldo importado correctamente')),
                );
              } catch (_) {
                ScaffoldMessenger.of(pageContext).showSnackBar(
                  const SnackBar(content: Text('El JSON no es válido o está incompleto')),
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('Borrar todo'),
        content: const Text('¿Seguro que quieres borrar todos los datos?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Borrar todo'),
          ),
        ],
      ),
    );

    if (confirm == true) _clearAll();
  }

  void _deleteMovement(Movement movement) {
    setState(() => _movements.remove(movement));
    _saveData();
  }

  Future<void> _showSellFeeDialog(BuildContext pageContext) async {
    final controller = TextEditingController(text: _sellFeePercent.toString());

    await showDialog<void>(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
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
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
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
    final controller = TextEditingController(text: (_currentPrices[coin] ?? 0).toString());

    showDialog<void>(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
        title: Text('Precio actual de $coin'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Precio en MXN', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null || value < 0) return;
              setState(() => _currentPrices[coin] = value);
              _saveData();
              Navigator.of(dialogContext).pop();
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
    if (picked != null) onPicked(picked);
  }

  void _showAddMovementSheet(BuildContext pageContext, {Movement? existing, int? index}) {
    MovementType selectedType = existing?.type ?? MovementType.buy;
    String selectedCoin = existing?.coin ?? _coins.first;
    DateTime selectedDate = existing?.date ?? DateTime.now();

    final qtyController = TextEditingController(text: existing != null ? fmtCompact(existing.quantity) : '');
    final priceController = TextEditingController(text: existing != null ? fmtCompact(existing.unitPrice) : '');
    final feeController = TextEditingController(text: existing != null ? fmtCompact(existing.fee) : '0');
    final noteController = TextEditingController(text: existing?.note ?? '');

    showModalBottomSheet<void>(
      context: pageContext,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isOut = selectedType == MovementType.sell || selectedType == MovementType.transferOut;
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing != null ? 'Editar movimiento' : 'Agregar movimiento',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<MovementType>(
                      initialValue: selectedType,
                      decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                      items: MovementType.values
                          .map((type) => DropdownMenuItem(value: type, child: Text(type.label)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setModalState(() => selectedType = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCoin,
                      decoration: const InputDecoration(labelText: 'Moneda', border: OutlineInputBorder()),
                      items: _coins.map((coin) => DropdownMenuItem(value: coin, child: Text(coin))).toList(),
                      onChanged: (value) {
                        if (value != null) setModalState(() => selectedCoin = value);
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Cantidad', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: isOut ? 'Precio unitario en MXN (0 si no aplica)' : 'Precio unitario en MXN',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: feeController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Comisión en MXN', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(labelText: 'Nota', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          final quantity = double.tryParse(qtyController.text.trim());
                          final unitPrice = double.tryParse(priceController.text.trim());
                          final fee = double.tryParse(feeController.text.trim()) ?? 0;

                          if (quantity == null || quantity <= 0) {
                            ScaffoldMessenger.of(pageContext).showSnackBar(
                              const SnackBar(content: Text('Pon una cantidad válida')),
                            );
                            return;
                          }
                          if (unitPrice == null || unitPrice < 0) {
                            ScaffoldMessenger.of(pageContext).showSnackBar(
                              const SnackBar(content: Text('Pon un precio válido')),
                            );
                            return;
                          }
                          if (fee < 0) {
                            ScaffoldMessenger.of(pageContext).showSnackBar(
                              const SnackBar(content: Text('La comisión no puede ser negativa')),
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

                          if (_wouldCreateInvalidPosition(updated, replaceIndex: existing != null ? index : null)) {
                            ScaffoldMessenger.of(pageContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Esa ${selectedType.label.toLowerCase()} deja la posición de $selectedCoin en negativo. Revísalo.',
                                ),
                              ),
                            );
                            return;
                          }

                          setState(() {
                            if (existing != null && index != null && index >= 0 && index < _movements.length) {
                              _movements[index] = updated;
                            } else {
                              _movements.add(updated);
                            }
                          });
                          _saveData();
                          Navigator.of(sheetContext).pop();
                        },
                        icon: Icon(existing != null ? Icons.save : Icons.add),
                        label: Text(existing != null ? 'Guardar cambios' : 'Guardar movimiento'),
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
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      home: Builder(
        builder: (pageContext) => Scaffold(
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
              SummaryTab(stats: stats, sellFeePercent: _sellFeePercent),
              MovementsTab(
                movements: _movements,
                coins: _coins,
                onDelete: _deleteMovement,
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
                onExportMovementsCsv: () => _exportMovementsCsv(pageContext),
                onExportSummaryCsv: () => _exportSummaryCsv(pageContext),
                onExportXlsx: () => _exportXlsx(pageContext),
                onExportPdf: () => _exportPdf(pageContext),
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
            onDestinationSelected: (index) => setState(() => _currentIndex = index),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Resumen'),
              NavigationDestination(icon: Icon(Icons.swap_horiz), label: 'Movimientos'),
              NavigationDestination(icon: Icon(Icons.currency_bitcoin), label: 'Monedas'),
              NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Ajustes'),
            ],
          ),
        ),
      ),
    );
  }
}

class SummaryTab extends StatelessWidget {
  final Map<String, CoinStats> stats;
  final double sellFeePercent;

  const SummaryTab({super.key, required this.stats, required this.sellFeePercent});

  @override
  Widget build(BuildContext context) {
    final totalCostBase = stats.values.fold<double>(0, (sum, s) => sum + s.costBase);
    final totalCurrentValue = stats.values.fold<double>(0, (sum, s) => sum + s.currentValue);
    final totalUnrealized = stats.values.fold<double>(0, (sum, s) => sum + s.unrealizedPL);
    final totalRealized = stats.values.fold<double>(0, (sum, s) => sum + s.realizedPL);
    final activeStats = stats.values.where((s) => s.quantity > 0).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cartera total', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    MetricTile(title: 'Costo base', value: money(totalCostBase)),
                    MetricTile(title: 'Valor actual', value: money(totalCurrentValue)),
                    MetricTile(title: 'P/L no realizado', value: money(totalUnrealized), valueColor: pnlColor(totalUnrealized)),
                    MetricTile(title: 'P/L realizado', value: money(totalRealized), valueColor: pnlColor(totalRealized)),
                  ],
                ),
                const Divider(height: 24),
                Text('Monedas activas: ${activeStats.length} · Comisión de salida: ${pct(sellFeePercent)}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Posiciones abiertas', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (activeStats.isEmpty)
          const EmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Sin posiciones abiertas',
            subtitle: 'Agrega una compra o una transferencia recibida para ver tu cartera aquí.',
          )
        else
          ...activeStats.map((s) => CoinSummaryCard(stats: s, sellFeePercent: sellFeePercent)),
      ],
    );
  }
}

class CoinSummaryCard extends StatelessWidget {
  final CoinStats stats;
  final double sellFeePercent;

  const CoinSummaryCard({super.key, required this.stats, required this.sellFeePercent});

  @override
  Widget build(BuildContext context) {
    final s = stats;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(s.coin, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const Spacer(),
                StatusPill(label: statusLabel(s, sellFeePercent), color: statusColor(s, sellFeePercent)),
              ],
            ),
            const SizedBox(height: 10),
            InfoLine('Cantidad', fmt(s.quantity)),
            InfoLine('Costo base', money(s.costBase)),
            InfoLine('Precio actual', money(s.currentPrice)),
            InfoLine('Valor actual', money(s.currentValue), bold: true),
            const Divider(height: 20),
            InfoLine('BE neto', money(s.netBreakEvenPrice(sellFeePercent)), bold: true),
            InfoLine('Objetivo +5%', money(s.targetNetExitPrice(sellFeePercent, 5))),
            InfoLine('Objetivo +10%', money(s.targetNetExitPrice(sellFeePercent, 10))),
            InfoLine('Distancia BE', distanceLabel(s, sellFeePercent)),
            const Divider(height: 20),
            InfoLine('P/L no realizado', money(s.unrealizedPL), bold: true, valueColor: pnlColor(s.unrealizedPL)),
            InfoLine('P/L realizado', money(s.realizedPL), valueColor: pnlColor(s.realizedPL)),
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
  String _selectedType = 'TODOS';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.movements.where((m) {
      final coinMatch = _selectedCoin == 'TODAS' || m.coin == _selectedCoin;
      final typeMatch = _selectedType == 'TODOS' || m.type.name == _selectedType;
      return coinMatch && typeMatch;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedCoin,
                  decoration: const InputDecoration(labelText: 'Moneda', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: 'TODAS', child: Text('Todas')),
                    ...widget.coins.map((coin) => DropdownMenuItem(value: coin, child: Text(coin))),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _selectedCoin = value);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedType,
                  decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: 'TODOS', child: Text('Todos')),
                    ...MovementType.values.map(
                      (type) => DropdownMenuItem(value: type.name, child: Text(type.shortLabel)),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _selectedType = value);
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Sin movimientos',
                  subtitle: 'No hay registros con esos filtros.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final m = filtered[index];
                    final gross = m.quantity * m.unitPrice;
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => widget.onEdit(m),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  MovementChip(type: m.type),
                                  const SizedBox(width: 8),
                                  Text(m.coin, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  const Spacer(),
                                  Text(shortDate(m.date)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              InfoLine('Cantidad', fmt(m.quantity)),
                              InfoLine('Precio unitario', money(m.unitPrice)),
                              InfoLine('Comisión', money(m.fee)),
                              InfoLine('Total bruto', money(gross), bold: true),
                              if (m.note.isNotEmpty) ...[
                                const Divider(height: 18),
                                Text('Nota: ${m.note}'),
                              ],
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
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
                                        builder: (dialogContext) => AlertDialog(
                                          title: const Text('Borrar movimiento'),
                                          content: Text(
                                            '¿Seguro que quieres borrar ${m.type.label.toLowerCase()} de ${m.coin} por ${fmt(m.quantity)}?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(dialogContext).pop(false),
                                              child: const Text('Cancelar'),
                                            ),
                                            FilledButton(
                                              onPressed: () => Navigator.of(dialogContext).pop(true),
                                              child: const Text('Borrar'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) widget.onDelete(m);
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
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
                    Text(coin, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    StatusPill(label: statusLabel(s, sellFeePercent), color: statusColor(s, sellFeePercent)),
                    IconButton(
                      onPressed: () => onEditPrice(coin),
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Editar precio actual',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Posición', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                InfoLine('Cantidad', fmt(s.quantity)),
                InfoLine('Costo base', money(s.costBase)),
                InfoLine('Promedio actual', money(s.avgPrice)),
                InfoLine('Precio actual', money(s.currentPrice)),
                const Divider(height: 20),
                const Text('Estrategia', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                InfoLine('BE bruto', money(s.breakEvenPrice)),
                InfoLine('BE neto', money(s.netBreakEvenPrice(sellFeePercent)), bold: true),
                InfoLine('Objetivo +5%', money(s.targetNetExitPrice(sellFeePercent, 5))),
                InfoLine('Objetivo +10%', money(s.targetNetExitPrice(sellFeePercent, 10))),
                InfoLine('Subida a +5%', s.quantity <= 0 ? '—' : pct(s.upsideToTargetPercent(sellFeePercent, 5))),
                InfoLine('Subida a +10%', s.quantity <= 0 ? '—' : pct(s.upsideToTargetPercent(sellFeePercent, 10))),
                const Divider(height: 20),
                const Text('Resultado', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                InfoLine('Valor actual', money(s.currentValue), bold: true),
                InfoLine('P/L no realizado', money(s.unrealizedPL), bold: true, valueColor: pnlColor(s.unrealizedPL)),
                InfoLine('P/L realizado', money(s.realizedPL), valueColor: pnlColor(s.realizedPL)),
                InfoLine('Distancia BE', distanceLabel(s, sellFeePercent)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class SettingsTab extends StatelessWidget {
  final double sellFeePercent;
  final VoidCallback onEditSellFee;
  final VoidCallback onExportBackup;
  final VoidCallback onImportBackup;
  final VoidCallback onExportMovementsCsv;
  final VoidCallback onExportSummaryCsv;
  final VoidCallback onExportXlsx;
  final VoidCallback onExportPdf;
  final VoidCallback onClearAll;

  const SettingsTab({
    super.key,
    required this.sellFeePercent,
    required this.onEditSellFee,
    required this.onExportBackup,
    required this.onImportBackup,
    required this.onExportMovementsCsv,
    required this.onExportSummaryCsv,
    required this.onExportXlsx,
    required this.onExportPdf,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SettingsCard(
          title: 'Configuración',
          subtitle: 'Comisión de salida actual: ${pct(sellFeePercent)}',
          children: [FilledButton.tonal(onPressed: onEditSellFee, child: const Text('Editar comisión de salida'))],
        ),
        const SizedBox(height: 12),
        SettingsCard(
          title: 'Respaldo JSON',
          subtitle: 'Formato interno compatible con CriptoControlMx.',
          children: [
            FilledButton.tonal(onPressed: onExportBackup, child: const Text('Exportar respaldo JSON')),
            const SizedBox(height: 10),
            FilledButton.tonal(onPressed: onImportBackup, child: const Text('Importar respaldo JSON')),
          ],
        ),
        const SizedBox(height: 12),
        SettingsCard(
          title: 'Exportaciones V2',
          subtitle: 'Archivos para auditoría, Excel, Google Sheets o reporte.',
          children: [
            FilledButton.tonalIcon(
              onPressed: onExportMovementsCsv,
              icon: const Icon(Icons.table_rows_outlined),
              label: const Text('Exportar historial CSV'),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: onExportSummaryCsv,
              icon: const Icon(Icons.summarize_outlined),
              label: const Text('Exportar resumen CSV'),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: onExportXlsx,
              icon: const Icon(Icons.grid_on_outlined),
              label: const Text('Exportar Excel XLSX'),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: onExportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Exportar reporte PDF'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SettingsCard(
          title: 'Peligro',
          subtitle: 'Esto borra movimientos, precios actuales y comisión de salida guardados en el dispositivo.',
          children: [FilledButton.tonal(onPressed: onClearAll, child: const Text('Borrar todo'))],
        ),
      ],
    );
  }
}

class SettingsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const SettingsCard({super.key, required this.title, required this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

enum MovementType { buy, sell, transferIn, transferOut }

extension MovementTypeLabel on MovementType {
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

  IconData get icon {
    switch (this) {
      case MovementType.buy:
        return Icons.add_circle_outline;
      case MovementType.sell:
        return Icons.remove_circle_outline;
      case MovementType.transferIn:
        return Icons.call_received;
      case MovementType.transferOut:
        return Icons.call_made;
    }
  }

  Color get color {
    switch (this) {
      case MovementType.buy:
        return Colors.green.shade700;
      case MovementType.sell:
        return Colors.deepOrange.shade700;
      case MovementType.transferIn:
        return Colors.blue.shade700;
      case MovementType.transferOut:
        return Colors.amber.shade800;
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

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'coin': coin,
        'date': date.toIso8601String(),
        'quantity': quantity,
        'unitPrice': unitPrice,
        'fee': fee,
        'note': note,
      };

  factory Movement.fromJson(Map<String, dynamic> json) => Movement(
        type: MovementType.values.firstWhere((e) => e.name == json['type']),
        coin: json['coin'] as String,
        date: DateTime.parse(json['date'] as String),
        quantity: (json['quantity'] as num).toDouble(),
        unitPrice: (json['unitPrice'] as num).toDouble(),
        fee: (json['fee'] as num).toDouble(),
        note: json['note']?.toString() ?? '',
      );
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
  double get currentValue => quantity * currentPrice;
  double get unrealizedPL => currentValue - costBase;

  double netBreakEvenPrice(double sellFeePercent) {
    if (quantity <= 0) return 0;
    final multiplier = 1 - (sellFeePercent / 100);
    if (multiplier <= 0) return 0;
    return avgPrice / multiplier;
  }

  double targetNetExitPrice(double sellFeePercent, double targetProfitPercent) {
    if (quantity <= 0) return 0;
    final multiplier = 1 - (sellFeePercent / 100);
    if (multiplier <= 0) return 0;
    final targetValue = costBase * (1 + (targetProfitPercent / 100));
    return targetValue / (quantity * multiplier);
  }

  double upsideToTargetPercent(double sellFeePercent, double targetProfitPercent) {
    if (quantity <= 0 || currentPrice <= 0) return 0;
    final target = targetNetExitPrice(sellFeePercent, targetProfitPercent);
    if (target <= 0) return 0;
    return ((target / currentPrice) - 1) * 100;
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

class MetricTile extends StatelessWidget {
  final String title;
  final String value;
  final Color? valueColor;

  const MetricTile({super.key, required this.title, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 155,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: valueColor),
          ),
        ],
      ),
    );
  }
}

class InfoLine extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  const InfoLine(this.label, this.value, {super.key, this.bold = false, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 6, child: Text(label, style: const TextStyle(color: Colors.black87))),
          Expanded(
            flex: 7,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                color: valueColor ?? Colors.black87,
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
  final Color color;

  const StatusPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class MovementChip extends StatelessWidget {
  final MovementType type;

  const MovementChip({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: type.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(type.icon, size: 16, color: type.color),
          const SizedBox(width: 5),
          Text(type.shortLabel, style: TextStyle(color: type.color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyState({super.key, required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: Colors.black45),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

String money(double value) => '\$${value.toStringAsFixed(2)} MXN';
String fmt(double value) => value.toStringAsFixed(8);
String fmtCompact(double value) {
  final text = value.toStringAsFixed(8);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

String pct(double value) => '${value.toStringAsFixed(2)}%';
String fixed(double value, int decimals) => value.toStringAsFixed(decimals);
String shortDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
String isoDate(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String csvEscape(Object? value) {
  final text = value?.toString() ?? '';
  final needsEscape = text.contains(',') || text.contains('"') || text.contains('\n');
  final escaped = text.replaceAll('"', '""');
  return needsEscape ? '"$escaped"' : escaped;
}

xl.CellValue? toExcelValue(Object? value) {
  if (value is int) return xl.IntCellValue(value);
  if (value is double) return xl.DoubleCellValue(value);
  return xl.TextCellValue(value?.toString() ?? '');
}

Color pnlColor(double value) {
  if (value > 0) return Colors.green.shade700;
  if (value < 0) return Colors.red.shade700;
  return Colors.black87;
}

Color statusColor(CoinStats s, double sellFeePercent) {
  if (s.quantity <= 0) return Colors.grey.shade700;
  if (s.isAtOrAboveNetBreakEven(sellFeePercent)) return Colors.green.shade700;
  return Colors.red.shade700;
}

String statusLabel(CoinStats s, double sellFeePercent) {
  if (s.quantity <= 0) return 'Sin posición';
  if (s.isAtOrAboveNetBreakEven(sellFeePercent)) return 'Arriba BE neto';
  return 'Bajo BE neto';
}

String distanceLabel(CoinStats s, double sellFeePercent) {
  if (s.quantity <= 0) return '—';
  if (s.isAtOrAboveNetBreakEven(sellFeePercent)) return '0.00%';
  return pct(s.percentToNetBreakEven(sellFeePercent));
}
