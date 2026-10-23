import '../domain/wallet.dart';
import '../projection/ledger_projection.dart';

final class LegacyCoinStatsData {
  const LegacyCoinStatsData({
    required this.coin,
    required this.quantity,
    required this.custodyQuantity,
    required this.unknownQuantity,
    required this.completeness,
    required this.costBase,
    required this.realizedProfit,
  });

  final String coin;

  /// Quantity whose cost basis is known and can support performance metrics.
  final double quantity;
  final double custodyQuantity;
  final double unknownQuantity;
  final AccountingCompleteness completeness;
  final double costBase;
  final double realizedProfit;

  bool get hasDefinitivePerformance =>
      completeness == AccountingCompleteness.complete;
}

final class LegacyPortfolioTotalsData {
  const LegacyPortfolioTotalsData({
    required this.costBase,
    required this.currentValue,
    required this.realizedProfit,
    required this.completeness,
  });

  final double costBase;
  final double currentValue;
  final double realizedProfit;
  final AccountingCompleteness completeness;

  bool get hasDefinitivePerformance =>
      completeness == AccountingCompleteness.complete;

  double get knownCurrentValue => currentValue;
  double get knownUnrealizedProfit => knownCurrentValue - costBase;
  double get knownRealizedProfit => realizedProfit;
  double? get definitiveUnrealizedProfit =>
      hasDefinitivePerformance ? knownUnrealizedProfit : null;
}

final class LegacyCoinAuditData {
  const LegacyCoinAuditData({
    required this.coin,
    required this.reconciledCostBase,
  });

  final String coin;
  final double reconciledCostBase;
}

final class LegacyFinancialAdapter {
  const LegacyFinancialAdapter();

  Map<String, LegacyCoinStatsData> coinStats(
    LedgerProjection projection,
    Map<String, double> currentPrices,
  ) {
    final assets = <String>{
      ...projection.positions.keys.map((key) => key.asset),
      ...currentPrices.keys.map((asset) => asset.toUpperCase()),
    };
    return <String, LegacyCoinStatsData>{
      for (final asset in assets)
        asset: _coinStats(
          asset,
          projection.positions.values.where(
            (position) => position.key.asset == asset,
          ),
        ),
    };
  }

  Map<String, LegacyCoinAuditData> audits(LedgerProjection projection) {
    final stats = coinStats(projection, const <String, double>{});
    return <String, LegacyCoinAuditData>{
      for (final entry in stats.entries)
        entry.key: LegacyCoinAuditData(
          coin: entry.key,
          reconciledCostBase: entry.value.costBase,
        ),
    };
  }

  LegacyPortfolioTotalsData totals(
    LedgerProjection projection,
    Map<String, double> currentPrices,
  ) {
    final normalizedPrices = <String, double>{
      for (final entry in currentPrices.entries)
        entry.key.toUpperCase(): entry.value,
    };
    final stats = coinStats(projection, normalizedPrices);
    return LegacyPortfolioTotalsData(
      costBase: stats.values.fold<double>(
        0,
        (total, value) => total + value.costBase,
      ),
      currentValue: stats.values.fold<double>(
        0,
        (total, value) =>
            total + value.quantity * (normalizedPrices[value.coin] ?? 0),
      ),
      realizedProfit: stats.values.fold<double>(
        0,
        (total, value) => total + value.realizedProfit,
      ),
      completeness: _aggregateCompleteness(
        stats.values.map((value) => value.completeness),
      ),
    );
  }
}

LegacyCoinStatsData _coinStats(
  String asset,
  Iterable<WalletAssetProjection> positions,
) {
  final materialized = positions.toList(growable: false);
  return LegacyCoinStatsData(
    coin: asset,
    quantity: _sum(
      materialized.map(
        (position) => position.performance.knownQuantity.toJson(),
      ),
    ),
    custodyQuantity: _sum(
      materialized.map(
        (position) => position.custody.reconciledQuantity.toJson(),
      ),
    ),
    unknownQuantity: _sum(
      materialized.map(
        (position) => position.completeness.unknownQuantity.toJson(),
      ),
    ),
    completeness: _aggregateCompleteness(
      materialized.map((position) => position.completeness.state),
    ),
    costBase: _sum(
      materialized.map(
        (position) => position.performance.knownCostBasis.toJson(),
      ),
    ),
    realizedProfit: _sum(
      materialized.map(
        (position) => position.performance.realizedPnlKnown.toJson(),
      ),
    ),
  );
}

AccountingCompleteness _aggregateCompleteness(
  Iterable<AccountingCompleteness> states,
) {
  final values = states.toSet();
  if (values.contains(AccountingCompleteness.unassignedLegacy)) {
    return AccountingCompleteness.unassignedLegacy;
  }
  if (values.contains(AccountingCompleteness.pendingAssignment)) {
    return AccountingCompleteness.pendingAssignment;
  }
  if (values.contains(AccountingCompleteness.partiallyKnown)) {
    return AccountingCompleteness.partiallyKnown;
  }
  return AccountingCompleteness.complete;
}

double _sum(Iterable<String> values) =>
    values.fold<double>(0, (total, value) => total + double.parse(value));
