import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';

import '../accounting/domain/accounting_movement.dart';
import '../accounting/persistence/accounting_document.dart';
import '../accounting/projection/ledger_projection.dart';

/// Cliente aislado para el analista conversacional. No modifica ni persiste
/// movimientos, saldos, precios o proyecciones.
final class PortfolioAiService {
  PortfolioAiService({
    FirebaseAuth? auth,
    HttpClient? httpClient,
    this.endpoint = 'https://us-central1-control-cripto-mx.cloudfunctions.net/analyzePortfolio',
  }) : _auth = auth ?? FirebaseAuth.instance,
       _httpClient = httpClient ?? HttpClient();

  final FirebaseAuth _auth;
  final HttpClient _httpClient;
  final String endpoint;

  Future<PortfolioAiAnswer> ask({
    required String question,
    required AccountingDocument accounting,
    required LedgerProjection projection,
    required Map<String, double> currentPrices,
    required DateTime? pricesUpdatedAt,
    required Map<String, String> priceModes,
  }) async {
    final normalizedQuestion = question.trim();
    if (normalizedQuestion.isEmpty || normalizedQuestion.length > 8000) {
      throw ArgumentError('La pregunta debe contener entre 1 y 8000 caracteres.');
    }
    final user = _auth.currentUser;
    if (user == null) throw StateError('Debes iniciar sesión para consultar tu cartera.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) throw StateError('No se pudo validar la sesión.');
    final requestId = _requestId();
    final context = _buildContext(
      accounting: accounting,
      projection: projection,
      currentPrices: currentPrices,
      pricesUpdatedAt: pricesUpdatedAt,
      priceModes: priceModes,
    );
    final payload = jsonEncode({
      'question': normalizedQuestion,
      'requestId': requestId,
      'portfolioContext': context,
    });
    final request = await _httpClient.postUrl(Uri.parse(endpoint));
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..contentType = ContentType.json
      ..set(HttpHeaders.acceptHeader, 'application/json');
    request.write(payload);
    final response = await request.close().timeout(const Duration(seconds: 110));
    final body = await utf8.decoder.bind(response).join();
    final decoded = jsonDecode(body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map ? decoded['message']?.toString() : null;
      throw PortfolioAiException(message ?? 'Error al consultar CriptoControl AI.', response.statusCode);
    }
    if (decoded is! Map || decoded['answer'] is! String) {
      throw const PortfolioAiException('Respuesta inválida del analista.', 502);
    }
    return PortfolioAiAnswer(
      answer: decoded['answer'] as String,
      requestId: decoded['requestId']?.toString() ?? requestId,
      remaining: (decoded['quota'] is Map ? (decoded['quota'] as Map)['remaining'] : null) as int?,
      model: (decoded['meta'] is Map ? (decoded['meta'] as Map)['model'] : null)?.toString(),
    );
  }

  Map<String, Object?> _buildContext({
    required AccountingDocument accounting,
    required LedgerProjection projection,
    required Map<String, double> currentPrices,
    required DateTime? pricesUpdatedAt,
    required Map<String, String> priceModes,
  }) {
    final walletNames = <String, String>{
      for (var i = 0; i < accounting.wallets.length; i++)
        accounting.wallets[i].id: accounting.wallets[i].name,
    };
    final positions = projection.positions.values.map(position => {
      'wallet': walletNames[position.key.walletId] ?? position.key.walletId.startsWith('virtual:') ? 'Sin asignar / pendiente' : 'Cartera',
      'asset': position.key.asset,
      'custodyQuantity': position.custody.reconciledQuantity.toJson(),
      'knownQuantity': position.performance.knownQuantity.toJson(),
      'unknownQuantity': position.completeness.unknownQuantity.toJson(),
      'knownCostBasis': position.performance.knownCostBasis.toJson(),
      'averageCost': position.performance.averageCost.toJson(),
      'realizedPnlKnown': position.performance.realizedPnlKnown.toJson(),
      'unrealizedPnlKnown': position.performance.unrealizedPnlKnown.toJson(),
      'marketValue': position.custodyMarketValue.toJson(),
      'knownPositionMarketValue': position.knownPositionMarketValue.toJson(),
      'completeness': position.completeness.state.name,
      'reconciliationDifference': position.reconciliationDifference.toJson(),
      'custodyDeficit': position.custodyDeficit.toJson(),
    }).toList(growable: false);
    final movements = accounting.movements.map((AccountingMovement movement) {
      final json = movement.toJson();
      json.remove('externalRecipientName');
      json.remove('sourceWalletId');
      json.remove('destinationWalletId');
      json.remove('adjustmentWalletId');
      json['sourceWallet'] = walletNames[movement.sourceWalletId] ?? (movement.sourceWalletId == null ? null : 'Cartera');
      json['destinationWallet'] = walletNames[movement.destinationWalletId] ?? (movement.destinationWalletId == null ? null : 'Cartera');
      json['adjustmentWallet'] = walletNames[movement.adjustmentWalletId] ?? (movement.adjustmentWalletId == null ? null : 'Cartera');
      return json;
    }).toList(growable: false);
    return {
      'schemaVersion': 1,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'accountingUpdatedAt': accounting.updatedAt.toUtc().toIso8601String(),
      'baseCurrency': 'MXN',
      'wallets': accounting.wallets.map((wallet) => {
        'name': wallet.name,
        'provider': wallet.provider,
        'status': wallet.status.name,
      }).toList(growable: false),
      'positions': positions,
      'totals': {
        'custodyMarketValue': projection.totals.custodyMarketValue.toJson(),
        'knownPositionMarketValue': projection.totals.knownPositionMarketValue.toJson(),
        'knownCostBasis': projection.totals.knownCostBasis.toJson(),
        'realizedPnlKnown': projection.totals.realizedPnlKnown.toJson(),
        'unrealizedPnlKnown': projection.totals.unrealizedPnlKnown.toJson(),
        'fiatCostEffect': projection.totals.fiatCostEffect.toJson(),
      },
      'prices': {
        for (final entry in currentPrices.entries)
          entry.key: {
            'mxn': entry.value,
            'mode': priceModes[entry.key] ?? 'automatic',
          },
      },
      'pricesUpdatedAt': pricesUpdatedAt?.toUtc().toIso8601String(),
      'migrationProgress': {
        'assigned': projection.migrationProgress.assigned,
        'total': projection.migrationProgress.total,
      },
      'issues': projection.issues.map(issue => {
        'code': issue.code.name,
        'description': issue.message.replaceAll(RegExp(r'[0-9a-fA-F-]{20,}'), '[id]'),
      }).toList(growable: false),
      'sales': projection.sales.map(sale => {
        'movementId': sale.movementId,
        'status': sale.status.name,
        'quantity': sale.totalQuantity.toJson(),
        'knownQuantity': sale.knownQuantity.toJson(),
        'demonstratedCostBasis': sale.demonstratedCostBasis.toJson(),
        'knownProceeds': sale.knownProceeds.toJson(),
        'allocatedKnownFiatFee': sale.allocatedKnownFiatFee.toJson(),
        'realizedPnlKnown': sale.realizedPnlKnown.toJson(),
        'pendingCostQuantity': sale.pendingCostQuantity.toJson(),
      }).toList(growable: false),
      'movements': movements,
    };
  }

  String _requestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  void close() => _httpClient.close(force: true);
}

final class PortfolioAiAnswer {
  const PortfolioAiAnswer({required this.answer, required this.requestId, this.remaining, this.model});
  final String answer;
  final String requestId;
  final int? remaining;
  final String? model;
}

final class PortfolioAiException implements Exception {
  const PortfolioAiException(this.message, this.statusCode);
  final String message;
  final int statusCode;
  @override
  String toString() => message;
}
