import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class PriceService {
  PriceService({HttpClient? httpClient}) : _httpClient = httpClient;

  static const String pricesKey = 'prices_json';
  static const String pricesUpdatedAtKey = 'prices_updated_at_ms';
  static const String priceModesKey = 'price_modes_v1_json';
  static const String manualPricesUpdatedAtKey =
      'manual_prices_updated_at_v1_json';
  static const String automaticMode = 'automatic';
  static const String manualMode = 'manual';
  static const Duration cacheTtl = Duration(minutes: 10);
  static const Map<String, String> _coinIds = <String, String>{
    'BTC': 'bitcoin',
    'ETH': 'ethereum',
    'LINK': 'chainlink',
    'LTC': 'litecoin',
    'UNI': 'uniswap',
    'USDT': 'tether',
    'USDC': 'usd-coin',
    'XRP': 'ripple',
    'SOL': 'solana',
    'ATOM': 'cosmos',
  };

  final HttpClient? _httpClient;

  Future<PriceCache> loadCachedPrices(SharedPreferences prefs) async {
    final Map<String, double> prices = _emptyPrices();
    final String? raw = prefs.getString(pricesKey);

    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final Map<String, dynamic> decoded = Map<String, dynamic>.from(
          jsonDecode(raw) as Map,
        );

        for (final String coin in _coinIds.keys) {
          final dynamic value = decoded[coin];
          if (value is num) prices[coin] = value.toDouble();
        }
      } catch (_) {}
    }

    final int? updatedAtMs = prefs.getInt(pricesUpdatedAtKey);
    return PriceCache(
      prices: prices,
      updatedAt: updatedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
    );
  }

  Future<PriceCache> refreshIfStale(SharedPreferences prefs) async {
    final PriceCache cache = await loadCachedPrices(prefs);
    if (!cache.isStale(cacheTtl)) return cache;

    try {
      return await fetchAndCachePrices(prefs);
    } catch (_) {
      return cache;
    }
  }

  Future<PriceCache> fetchAndCachePrices(SharedPreferences prefs) async {
    final PriceCache cached = await loadCachedPrices(prefs);
    final Map<String, String> priceModes = loadPriceModes(prefs);
    final Map<String, double> freshPrices = await _fetchMxnPrices();
    if (freshPrices.isEmpty) {
      throw const FormatException('No valid coin prices');
    }

    final Map<String, double> prices = Map<String, double>.from(cached.prices);
    for (final MapEntry<String, double> entry in freshPrices.entries) {
      if (priceModes[entry.key] == manualMode) continue;
      prices[entry.key] = entry.value;
    }
    for (final String coin in _coinIds.keys) {
      prices.putIfAbsent(coin, () => 0.0);
    }

    final DateTime updatedAt = DateTime.now();

    await prefs.setString(pricesKey, jsonEncode(prices));
    await prefs.setInt(pricesUpdatedAtKey, updatedAt.millisecondsSinceEpoch);

    return PriceCache(prices: prices, updatedAt: updatedAt);
  }

  Future<PriceCache> saveManualPrices(
    SharedPreferences prefs,
    Map<String, double> prices,
  ) async {
    final DateTime updatedAt = DateTime.now();

    await prefs.setString(pricesKey, jsonEncode(prices));
    await prefs.setInt(pricesUpdatedAtKey, updatedAt.millisecondsSinceEpoch);

    return PriceCache(prices: prices, updatedAt: updatedAt);
  }

  Map<String, String> loadPriceModes(SharedPreferences prefs) {
    final Map<String, String> modes = <String, String>{
      for (final String coin in _coinIds.keys) coin: automaticMode,
    };
    final String? raw = prefs.getString(priceModesKey);
    if (raw == null || raw.trim().isEmpty) return modes;

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map) return modes;
      for (final String coin in _coinIds.keys) {
        final String mode = decoded[coin]?.toString() ?? automaticMode;
        modes[coin] = mode == manualMode ? manualMode : automaticMode;
      }
    } catch (_) {}
    return modes;
  }

  Map<String, int> loadManualPriceUpdatedAtMs(SharedPreferences prefs) {
    final String? raw = prefs.getString(manualPricesUpdatedAtKey);
    if (raw == null || raw.trim().isEmpty) return <String, int>{};

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, int>{};
      final Map<String, int> timestamps = <String, int>{};
      for (final String coin in _coinIds.keys) {
        final dynamic value = decoded[coin];
        if (value is int) {
          timestamps[coin] = value;
        } else if (value is num) {
          timestamps[coin] = value.toInt();
        }
      }
      return timestamps;
    } catch (_) {
      return <String, int>{};
    }
  }

  Future<void> savePriceModes(
    SharedPreferences prefs,
    Map<String, String> modes,
  ) async {
    await prefs.setString(priceModesKey, jsonEncode(<String, String>{
      for (final String coin in _coinIds.keys)
        coin: modes[coin] == manualMode ? manualMode : automaticMode,
    }));
  }

  Future<void> saveManualPriceUpdatedAtMs(
    SharedPreferences prefs,
    Map<String, int> timestamps,
  ) async {
    await prefs.setString(manualPricesUpdatedAtKey, jsonEncode(<String, int>{
      for (final String coin in _coinIds.keys)
        if (timestamps.containsKey(coin)) coin: timestamps[coin]!,
    }));
  }

  Future<Map<String, double>> _fetchMxnPrices() async {
    final Uri uri = Uri.https(
      'api.coingecko.com',
      '/api/v3/simple/price',
      <String, String>{
        'ids': _coinIds.values.join(','),
        'vs_currencies': 'mxn',
      },
    );

    final bool ownsClient = _httpClient == null;
    final HttpClient client = _httpClient ?? HttpClient();

    try {
      final HttpClientRequest request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final String body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const HttpException('CoinGecko price request failed');
      }

      final Map<String, dynamic> decoded = Map<String, dynamic>.from(
        jsonDecode(body) as Map,
      );
      final Map<String, double> prices = <String, double>{};

      for (final MapEntry<String, String> entry in _coinIds.entries) {
        final dynamic coinData = decoded[entry.value];
        if (coinData is! Map) continue;

        final dynamic mxn = Map<String, dynamic>.from(coinData)['mxn'];
        if (mxn is! num) continue;

        prices[entry.key] = mxn.toDouble();
      }

      if (prices.isEmpty) {
        throw const FormatException('No valid coin prices');
      }

      return prices;
    } finally {
      if (ownsClient) client.close(force: true);
    }
  }

  Map<String, double> _emptyPrices() => <String, double>{
    for (final String coin in _coinIds.keys) coin: 0.0,
  };
}

class PriceCache {
  const PriceCache({required this.prices, required this.updatedAt});

  final Map<String, double> prices;
  final DateTime? updatedAt;

  bool isStale(Duration ttl) {
    final DateTime? lastUpdate = updatedAt;
    if (lastUpdate == null) return true;
    return DateTime.now().difference(lastUpdate) > ttl;
  }
}
