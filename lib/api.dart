import 'dart:convert';
import 'package:http/http.dart' as http;

/// Backend client. Points at the keyview-backend Worker.
/// With no backend configured (or on any failure in debug), returns mock data
/// so the app runs with ZERO accounts or keys — flip [base] when deployed.
class KeyviewApi {
  /// Set after `wrangler deploy`, e.g. https://keyview-api.<account>.workers.dev
  static const String base =
      String.fromEnvironment('KEYVIEW_API', defaultValue: '');

  static Future<Portfolio> portfolio(String address) async {
    if (base.isEmpty) return Portfolio.mock(address);
    try {
      final r = await http
          .get(Uri.parse('$base/v1/portfolio/$address'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      return Portfolio.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    } catch (_) {
      return Portfolio.mock(address);
    }
  }

  static final _evm = RegExp(r'^0x[0-9a-fA-F]{40}$');
  static final _sol = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$');
  static bool isValidAddress(String a) =>
      _evm.hasMatch(a) || _sol.hasMatch(a) || a.endsWith('.eth');
}

class Holding {
  final String symbol, name, chain;
  final double amount, priceUsd, change24h;
  const Holding(this.symbol, this.name, this.chain, this.amount, this.priceUsd,
      this.change24h);
  double get valueUsd => amount * priceUsd;

  factory Holding.fromJson(Map<String, dynamic> j) => Holding(
      j['symbol'] as String? ?? '?',
      j['name'] as String? ?? '',
      j['chain'] as String? ?? '',
      (j['amount'] as num?)?.toDouble() ?? 0,
      (j['priceUsd'] as num?)?.toDouble() ?? 0,
      (j['change24h'] as num?)?.toDouble() ?? 0);
}

class Portfolio {
  final String address;
  final List<Holding> holdings;
  final bool isMock;
  const Portfolio(this.address, this.holdings, {this.isMock = false});
  double get totalUsd => holdings.fold(0, (s, h) => s + h.valueUsd);

  factory Portfolio.fromJson(Map<String, dynamic> j) => Portfolio(
      j['address'] as String? ?? '',
      ((j['holdings'] as List?) ?? [])
          .map((e) => Holding.fromJson(e as Map<String, dynamic>))
          .toList());

  factory Portfolio.mock(String address) => Portfolio(address, const [
        Holding('BTC', 'Bitcoin', 'bitcoin', 0.42, 68420.00, 2.1),
        Holding('ETH', 'Ethereum', 'ethereum', 4.10, 3560.18, 3.4),
        Holding('BNB', 'BNB', 'bnb', 3.20, 604.22, 1.2),
        Holding('SOL', 'Solana', 'solana', 9.50, 172.45, 5.8),
        Holding('TSLA', 'Tesla (Stock Token)', 'robinhood', 2.00, 405.53, -0.8),
      ], isMock: true);
}
