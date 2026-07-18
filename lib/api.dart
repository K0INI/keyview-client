import 'dart:convert';
import 'package:http/http.dart' as http;

/// Backend client. Points at the keyview-backend Worker.
/// With no backend configured (or on any failure in debug), returns mock data
/// so the app runs with ZERO accounts or keys — flip [base] when deployed.
class KeyviewApi {
  /// Live Worker URL; override with --dart-define=KEYVIEW_API=... if needed.
  static const String base = String.fromEnvironment('KEYVIEW_API',
      defaultValue: 'https://keyview-api.yellow-violet-ced0.workers.dev');

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

  static Future<History> history(String address) async {
    if (base.isEmpty) return History.mock(address);
    try {
      final r = await http
          .get(Uri.parse('$base/v1/history/$address'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      return History.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    } catch (_) {
      return History.mock(address);
    }
  }

  static final _evm = RegExp(r'^0x[0-9a-fA-F]{40}$');
  static final _sol = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$');
  static bool isValidAddress(String a) =>
      _evm.hasMatch(a) || _sol.hasMatch(a) || a.endsWith('.eth');

  /// Block-explorer bases, mirroring the backend chain registry (spec §20.6).
  static const Map<String, String> explorers = {
    'ethereum': 'https://etherscan.io',
    'base': 'https://basescan.org',
    'arbitrum': 'https://arbiscan.io',
    'optimism': 'https://optimistic.etherscan.io',
    'polygon': 'https://polygonscan.com',
    'bsc': 'https://bscscan.com',
    'robinhood': 'https://robinhoodchain.blockscout.com',
    'solana': 'https://solscan.io',
  };

  static String? explorerTokenUrl(Holding h) {
    final root = explorers[h.chain];
    if (root == null || h.contract == null) return null;
    return '$root/token/${h.contract}';
  }
}

class Holding {
  final String symbol, name, chain;
  final double amount, priceUsd, change24h;
  final String? contract; // null = native asset
  const Holding(this.symbol, this.name, this.chain, this.amount, this.priceUsd,
      this.change24h,
      {this.contract});
  double get valueUsd => amount * priceUsd;

  factory Holding.fromJson(Map<String, dynamic> j) => Holding(
      j['symbol'] as String? ?? '?',
      j['name'] as String? ?? '',
      j['chain'] as String? ?? '',
      (j['amount'] as num?)?.toDouble() ?? 0,
      (j['priceUsd'] as num?)?.toDouble() ?? 0,
      (j['change24h'] as num?)?.toDouble() ?? 0,
      contract: j['contract'] as String?);
}

class TransferEvent {
  final String chain, hash, direction, asset;
  final double? amount;
  final int timeMs;
  final String? counterparty;
  const TransferEvent(this.chain, this.hash, this.direction, this.asset,
      this.amount, this.timeMs, this.counterparty);

  factory TransferEvent.fromJson(Map<String, dynamic> j) => TransferEvent(
      j['chain'] as String? ?? '',
      j['hash'] as String? ?? '',
      j['direction'] as String? ?? 'activity',
      j['asset'] as String? ?? '',
      (j['amount'] as num?)?.toDouble(),
      (j['timeMs'] as num?)?.toInt() ?? 0,
      j['counterparty'] as String?);
}

class History {
  final String address;
  final List<TransferEvent> events;
  final bool isMock;
  const History(this.address, this.events, {this.isMock = false});

  factory History.fromJson(Map<String, dynamic> j) => History(
      j['address'] as String? ?? '',
      ((j['events'] as List?) ?? [])
          .map((e) => TransferEvent.fromJson(e as Map<String, dynamic>))
          .toList());

  factory History.mock(String address) => History(address, [
        TransferEvent('ethereum', '0xmock1', 'in', 'ETH', 0.5,
            DateTime.now().millisecondsSinceEpoch - 7200000, '0xabc…'),
        TransferEvent('base', '0xmock2', 'out', 'USDC', 120,
            DateTime.now().millisecondsSinceEpoch - 86400000, '0xdef…'),
      ], isMock: true);
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
