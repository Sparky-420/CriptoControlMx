import '../projection/ledger_projection.dart';

final class LegacyCoinStatsData {
  const LegacyCoinStatsData({
    required this.coin,
    required this.quantity,
    required this.costBase,
    required this.realizedProfit,
  });

  final String coin;
  final double quantity;
  final double costBase;
  final double realizedProfit;
}

final class LegacyPortfolioTotalsData {
  const LegacyPortfolioTotalsData({
    required this.costBase,
    required this.currentValue,
    required this.realizedProfit,
  });

  final double costBase;
  final double currentValue;
  final double realizedProfit;
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
        asset: LegacyCoinStatsData(
          coin: asset,
          quantity: _sum(
            projection.positions.values
                .where((position) => position.key.asset == asset)
                .map(
                  (position) => position.custody.reconciledQuantity.toJson(),
                ),
          ),
          costBase: _sum(
            projection.positions.values
                .where((position) => position.key.asset == asset)
                .map(
                  (position) => position.performance.knownCostBasis.toJson(),
                ),
          ),
          realizedProfit: _sum(
            projection.positions.values
                .where((position) => position.key.asset == asset)
                .map(
                  (position) => position.performance.realizedPnlKnown.toJson(),
                ),
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
    );
  }
}

double _sum(Iterable<String> values) =>
    values.fold<double>(0, (total, value) => total + double.parse(value));
