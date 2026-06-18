import 'portfolio_math.dart';
import 'portfolio_models.dart';

class PortfolioState {
  final Map<String, CoinStats> stats;
  final PortfolioTotals totals;

  const PortfolioState({required this.stats, required this.totals});

  factory PortfolioState.fromInputs({
    required List<String> coins,
    required List<Movement> movements,
    required Map<String, double> currentPrices,
  }) {
    final Map<String, CoinStats> stats = PortfolioMath.computeStats(
      coins: coins,
      movements: movements,
      currentPrices: currentPrices,
    );

    return PortfolioState(
      stats: stats,
      totals: PortfolioMath.totals(stats),
    );
  }
}
