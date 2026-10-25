class PortfolioDashboardData {
  const PortfolioDashboardData({
    required this.totalValueMxn,
    required this.investedMxn,
    required this.unrealizedPnlMxn,
    required this.unrealizedPnlPercent,
    required this.assets,
  });

  final double totalValueMxn;
  final double investedMxn;
  final double unrealizedPnlMxn;
  final double unrealizedPnlPercent;
  final List<PortfolioDashboardAsset> assets;
}

class PortfolioDashboardAsset {
  const PortfolioDashboardAsset({
    required this.symbol,
    required this.name,
    required this.quantity,
    required this.valueMxn,
    required this.pnlMxn,
    required this.pnlPercent,
  });

  final String symbol;
  final String name;
  final double quantity;
  final double valueMxn;
  final double pnlMxn;
  final double pnlPercent;
}
