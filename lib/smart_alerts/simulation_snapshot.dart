/// Par├ímetros econ├│micos reales capturados al guardar una simulaci├│n.
///
/// Se guardan dentro del registro de `saved_simulations_v1_json` en la clave
/// `smartParams`. Los objetivos (`target*`) son los resultados calculados por
/// el simulador original (`_calculateBuy`, `_calculateSell`,
/// `_calculateRotation`) y nunca se modifican despu├⌐s.
sealed class SimulationSnapshot {
  const SimulationSnapshot();

  static const int schemaVersion = 1;

  String get kind;
  Set<String> get coins;
  Map<String, Object> toJson();

  static SimulationSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, dynamic> json = Map<String, dynamic>.from(raw);
    double? d(String key) {
      final dynamic value = json[key];
      if (value is num) return value.toDouble();
      return double.tryParse('${value ?? ''}');
    }

    String? s(String key) {
      final String value = (json[key] ?? '').toString().trim().toUpperCase();
      return value.isEmpty ? null : value;
    }

    switch (json['kind']) {
      case 'buy':
        final String? coin = s('coin');
        final double? gross = d('grossAmount');
        final double? fee = d('buyFeePercent');
        final double? price = d('simPrice');
        final double? target = d('targetQuantity');
        if (coin == null || gross == null || fee == null || price == null ||
            target == null) {
          return null;
        }
        return BuySimulationSnapshot(
          coin: coin,
          grossAmount: gross,
          buyFeePercent: fee,
          simPrice: price,
          targetQuantity: target,
        );
      case 'sell':
        final String? coin = s('coin');
        final double? quantity = d('quantity');
        final double? fee = d('sellFeePercent');
        final double? price = d('simPrice');
        final double? target = d('targetNetReceived');
        if (coin == null || quantity == null || fee == null || price == null ||
            target == null) {
          return null;
        }
        return SellSimulationSnapshot(
          coin: coin,
          quantity: quantity,
          sellFeePercent: fee,
          simPrice: price,
          targetNetReceived: target,
        );
      case 'rotation':
        final String? origin = s('originCoin');
        final String? target = s('targetCoin');
        final double? quantity = d('originQuantity');
        final double? sellFee = d('sellFeePercent');
        final double? buyFee = d('buyFeePercent');
        final double? originPrice = d('simOriginPrice');
        final double? targetPrice = d('simTargetPrice');
        final double? targetQuantity = d('targetQuantity');
        if (origin == null || target == null || quantity == null ||
            sellFee == null || buyFee == null || originPrice == null ||
            targetPrice == null || targetQuantity == null) {
          return null;
        }
        return RotationSimulationSnapshot(
          originCoin: origin,
          targetCoin: target,
          originQuantity: quantity,
          sellFeePercent: sellFee,
          buyFeePercent: buyFee,
          simOriginPrice: originPrice,
          simTargetPrice: targetPrice,
          targetQuantity: targetQuantity,
        );
    }
    return null;
  }
}

class BuySimulationSnapshot extends SimulationSnapshot {
  const BuySimulationSnapshot({
    required this.coin,
    required this.grossAmount,
    required this.buyFeePercent,
    required this.simPrice,
    required this.targetQuantity,
  });

  final String coin;
  final double grossAmount;
  final double buyFeePercent;
  final double simPrice;

  /// `quantityBought` del simulador original.
  final double targetQuantity;

  @override
  String get kind => 'buy';
  @override
  Set<String> get coins => <String>{coin};

  @override
  Map<String, Object> toJson() => <String, Object>{
    'version': SimulationSnapshot.schemaVersion,
    'kind': kind,
    'coin': coin,
    'grossAmount': grossAmount,
    'buyFeePercent': buyFeePercent,
    'simPrice': simPrice,
    'targetQuantity': targetQuantity,
  };
}

class SellSimulationSnapshot extends SimulationSnapshot {
  const SellSimulationSnapshot({
    required this.coin,
    required this.quantity,
    required this.sellFeePercent,
    required this.simPrice,
    required this.targetNetReceived,
  });

  final String coin;

  /// `quantitySold` del simulador original.
  final double quantity;
  final double sellFeePercent;
  final double simPrice;

  /// `netReceived` del simulador original.
  final double targetNetReceived;

  @override
  String get kind => 'sell';
  @override
  Set<String> get coins => <String>{coin};

  @override
  Map<String, Object> toJson() => <String, Object>{
    'version': SimulationSnapshot.schemaVersion,
    'kind': kind,
    'coin': coin,
    'quantity': quantity,
    'sellFeePercent': sellFeePercent,
    'simPrice': simPrice,
    'targetNetReceived': targetNetReceived,
  };
}

class RotationSimulationSnapshot extends SimulationSnapshot {
  const RotationSimulationSnapshot({
    required this.originCoin,
    required this.targetCoin,
    required this.originQuantity,
    required this.sellFeePercent,
    required this.buyFeePercent,
    required this.simOriginPrice,
    required this.simTargetPrice,
    required this.targetQuantity,
  });

  final String originCoin;
  final String targetCoin;

  /// `originQuantitySold` del simulador original.
  final double originQuantity;
  final double sellFeePercent;
  final double buyFeePercent;
  final double simOriginPrice;
  final double simTargetPrice;

  /// `targetQuantityBought` del simulador original.
  final double targetQuantity;

  @override
  String get kind => 'rotation';
  @override
  Set<String> get coins => <String>{originCoin, targetCoin};

  @override
  Map<String, Object> toJson() => <String, Object>{
    'version': SimulationSnapshot.schemaVersion,
    'kind': kind,
    'originCoin': originCoin,
    'targetCoin': targetCoin,
    'originQuantity': originQuantity,
    'sellFeePercent': sellFeePercent,
    'buyFeePercent': buyFeePercent,
    'simOriginPrice': simOriginPrice,
    'simTargetPrice': simTargetPrice,
    'targetQuantity': targetQuantity,
  };
}
