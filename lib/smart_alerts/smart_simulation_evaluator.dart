import 'simulation_snapshot.dart';

enum SmartEvaluationStatus { favorable, notFavorable, missingData }

class SmartEvaluation {
  const SmartEvaluation({
    required this.status,
    required this.currentValue,
    required this.targetValue,
    required this.netAfterFees,
    required this.totalCommissions,
    required this.currentPrices,
    required this.reason,
  });

  const SmartEvaluation.missing(this.reason)
    : status = SmartEvaluationStatus.missingData,
      currentValue = 0,
      targetValue = 0,
      netAfterFees = 0,
      totalCommissions = 0,
      currentPrices = const <String, double>{};

  final SmartEvaluationStatus status;
  final double currentValue;
  final double targetValue;
  final double netAfterFees;
  final double totalCommissions;
  final Map<String, double> currentPrices;
  final String reason;

  bool get isFavorable => status == SmartEvaluationStatus.favorable;
}

class SmartSimulationEvaluator {
  const SmartSimulationEvaluator();

  static const double epsilon = 1e-9;

  static bool _positiveFinite(double value) => value.isFinite && value > 0;

  static bool _nonNegativeFinite(double value) => value.isFinite && value >= 0;

  static bool _validFee(double fee) => fee.isFinite && fee >= 0 && fee < 100;

  static bool _meets(double current, double target) =>
      current >= target * (1 - epsilon);

  SmartEvaluation evaluate(
    SimulationSnapshot snapshot,
    Map<String, double> prices,
  ) {
    for (final String coin in snapshot.coins) {
      final double? price = prices[coin];
      if (price == null || !_positiveFinite(price)) {
        return SmartEvaluation.missing(
          'Falta cotización actual válida de $coin.',
        );
      }
    }

    return switch (snapshot) {
      BuySimulationSnapshot() => _buy(snapshot, prices),
      SellSimulationSnapshot() => _sell(snapshot, prices),
      RotationSimulationSnapshot() => _rotation(snapshot, prices),
    };
  }

  SmartEvaluation _buy(BuySimulationSnapshot s, Map<String, double> prices) {
    if (!_positiveFinite(s.grossAmount) ||
        !_validFee(s.buyFeePercent) ||
        !_positiveFinite(s.simPrice) ||
        !_positiveFinite(s.targetQuantity)) {
      return const SmartEvaluation.missing(
        'Parámetros de compra incompletos o inválidos.',
      );
    }

    final double price = prices[s.coin]!;
    final double commission = s.grossAmount * s.buyFeePercent / 100;
    final double net = s.grossAmount - commission;
    final double quantity = net / price;

    if (!_nonNegativeFinite(commission) ||
        !_positiveFinite(net) ||
        !_positiveFinite(quantity)) {
      return const SmartEvaluation.missing(
        'Resultado de compra fuera de rango numérico.',
      );
    }

    final bool ok = _meets(quantity, s.targetQuantity);

    return SmartEvaluation(
      status: ok
          ? SmartEvaluationStatus.favorable
          : SmartEvaluationStatus.notFavorable,
      currentValue: quantity,
      targetValue: s.targetQuantity,
      netAfterFees: net,
      totalCommissions: commission,
      currentPrices: <String, double>{s.coin: price},
      reason: ok
          ? 'Con el mismo capital obtienes igual o más ${s.coin} que en tu simulación.'
          : 'Hoy obtendrías menos ${s.coin} que el objetivo de la simulación.',
    );
  }

  SmartEvaluation _sell(SellSimulationSnapshot s, Map<String, double> prices) {
    if (!_positiveFinite(s.quantity) ||
        !_validFee(s.sellFeePercent) ||
        !_positiveFinite(s.simPrice) ||
        !_positiveFinite(s.targetNetReceived)) {
      return const SmartEvaluation.missing(
        'Parámetros de venta incompletos o inválidos.',
      );
    }

    final double price = prices[s.coin]!;
    final double gross = s.quantity * price;
    final double commission = gross * s.sellFeePercent / 100;
    final double net = gross - commission;

    if (!_positiveFinite(gross) ||
        !_nonNegativeFinite(commission) ||
        !_positiveFinite(net)) {
      return const SmartEvaluation.missing(
        'Resultado de venta fuera de rango numérico.',
      );
    }

    final bool ok = _meets(net, s.targetNetReceived);

    return SmartEvaluation(
      status: ok
          ? SmartEvaluationStatus.favorable
          : SmartEvaluationStatus.notFavorable,
      currentValue: net,
      targetValue: s.targetNetReceived,
      netAfterFees: net,
      totalCommissions: commission,
      currentPrices: <String, double>{s.coin: price},
      reason: ok
          ? 'Vender la misma cantidad hoy deja igual o más MXN netos que tu simulación.'
          : 'Hoy recibirías menos MXN netos que el objetivo de la simulación.',
    );
  }

  SmartEvaluation _rotation(
    RotationSimulationSnapshot s,
    Map<String, double> prices,
  ) {
    if (s.originCoin == s.targetCoin ||
        !_positiveFinite(s.originQuantity) ||
        !_validFee(s.sellFeePercent) ||
        !_validFee(s.buyFeePercent) ||
        !_positiveFinite(s.simOriginPrice) ||
        !_positiveFinite(s.simTargetPrice) ||
        !_positiveFinite(s.targetQuantity)) {
      return const SmartEvaluation.missing(
        'Parámetros de rotación incompletos o inválidos.',
      );
    }

    final double originPrice = prices[s.originCoin]!;
    final double targetPrice = prices[s.targetCoin]!;

    final double originGross = s.originQuantity * originPrice;
    final double sellCommission = originGross * s.sellFeePercent / 100;
    final double netAvailable = originGross - sellCommission;
    final double buyCommission = netAvailable * s.buyFeePercent / 100;
    final double converted = netAvailable - buyCommission;
    final double bought = converted / targetPrice;
    final double totalCommissions = sellCommission + buyCommission;

    if (!_positiveFinite(originGross) ||
        !_nonNegativeFinite(sellCommission) ||
        !_positiveFinite(netAvailable) ||
        !_nonNegativeFinite(buyCommission) ||
        !_positiveFinite(converted) ||
        !_positiveFinite(bought) ||
        !_nonNegativeFinite(totalCommissions)) {
      return const SmartEvaluation.missing(
        'Resultado de rotación fuera de rango numérico.',
      );
    }

    final bool ok = _meets(bought, s.targetQuantity);

    return SmartEvaluation(
      status: ok
          ? SmartEvaluationStatus.favorable
          : SmartEvaluationStatus.notFavorable,
      currentValue: bought,
      targetValue: s.targetQuantity,
      netAfterFees: converted,
      totalCommissions: totalCommissions,
      currentPrices: <String, double>{
        s.originCoin: originPrice,
        s.targetCoin: targetPrice,
      },
      reason: ok
          ? 'La relación ${s.originCoin}/${s.targetCoin} permite obtener igual o más ${s.targetCoin} que tu simulación.'
          : 'La relación ${s.originCoin}/${s.targetCoin} hoy da menos ${s.targetCoin} que el objetivo.',
    );
  }
}
