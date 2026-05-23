import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class PriceService {
  PriceService({HttpClient? httpClient}) : _httpClient = httpClient;

  static const String pricesKey = 'prices_json';
  static const String pricesUpdatedAtKey = 'prices_updated_at_ms';
  static const Duration cacheTtl = Duration(minutes: 10);

  static const Map<String, String> _coinIds = <String, String>{
    'BTC': 'bitcoin',
    'ETH': 'ethereum',
    'LINK': 'chainlink',
    'LTC': 'litecoin',
    'UNI': 'uniswap',
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
    final Map<String, double> prices = await _fetchMxnPrices();
    final DateTime updatedAt = DateTime.now();

    await prefs.setString(pricesKey, jsonEncode(prices));
    await prefs.setInt(pricesUpdatedAtKey, updatedAt.millisecondsSinceEpoch);

    return PriceCache(prices: prices, updatedAt: updatedAt);
  }

  Future<void> saveManualPrices(
    SharedPreferences prefs,
    Map<String, double> prices,
  ) async {
    final DateTime updatedAt = DateTime.now();

    await prefs.setString(pricesKey, jsonEncode(prices));
    await prefs.setInt(pricesUpdatedAtKey, updatedAt.millisecondsSinceEpoch);
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
      final Map<String, double> prices = _emptyPrices();

      for (final MapEntry<String, String> entry in _coinIds.entries) {
        final dynamic coinData = decoded[entry.value];
        if (coinData is! Map) {
          throw const FormatException('Missing coin price');
        }

        final dynamic mxn = Map<String, dynamic>.from(coinData)['mxn'];
        if (mxn is! num) {
          throw const FormatException('Missing MXN price');
        }

        prices[entry.key] = mxn.toDouble();
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
