import 'portfolio_models.dart';

class PortfolioMath {
  const PortfolioMath._();

  static Map<String, CoinStats> computeStats({
    required List<String> coins,
    required List<Movement> movements,
    required Map<String, double> currentPrices,
  }) {
    final Map<String, CoinStats> stats = <String, CoinStats>{
      for (final String coin in coins)
        coin: CoinStats(coin: coin, currentPrice: currentPrices[coin] ?? 0.0),
    };

    final List<MapEntry<int, Movement>> indexed =
        movements.asMap().entries.toList()
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

    for (final String coin in coins) {
      stats[coin]!.currentPrice = currentPrices[coin] ?? 0.0;
    }

    return stats;
  }

  static CoinAudit auditCoin({
    required String coin,
    required List<Movement> movements,
  }) {
    double buys = 0.0;
    double sells = 0.0;
    double transferIns = 0.0;
    double transferOuts = 0.0;
    double fees = 0.0;

    for (final Movement movement in movements.where(
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

  static PortfolioTotals totals(Map<String, CoinStats> stats) {
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

  static bool wouldCreateInvalidPosition({
    required List<String> coins,
    required List<Movement> movements,
    required Movement candidate,
    int? replaceIndex,
  }) {
    final List<Movement> testList = <Movement>[...movements];

    if (replaceIndex != null &&
        replaceIndex >= 0 &&
        replaceIndex < testList.length) {
      testList[replaceIndex] = candidate;
    } else {
      testList.add(candidate);
    }

    final Map<String, double> balances = <String, double>{
      for (final String coin in coins) coin: 0.0,
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
}
