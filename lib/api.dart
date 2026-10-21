import 'dart:convert';
import 'package:http/http.dart' as http;

/// Something went wrong talking to the backend. Carries a sentence we are
/// willing to show a user — never a stack trace, never a fabricated number.
class KeyviewApiException implements Exception {
  final String message;
  final int? statusCode;
  const KeyviewApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// Backend client. Points at the keyview-backend Worker.
///
/// 0.1.9: this class NO LONGER invents data. Until now any failure — a
/// timeout, a 500, no network — returned `Portfolio.mock()`, roughly $50,000
/// of imaginary BTC/ETH/BNB/SOL/TSLA, and the Portfolio screen drew it like
/// real holdings behind a 9px "SAMPLE DATA" label. A money app that shows
/// invented money on a bad connection is worse than one that says "I can't
/// reach the server". Failures now throw [KeyviewApiException] and every
/// screen renders an honest error with a retry. Mock data survives only
/// behind `--dart-define=KEYVIEW_MOCK=true`, for offline UI work.
class KeyviewApi {
  /// Live Worker URL; override with --dart-define=KEYVIEW_API=... if needed.
  static const String base = String.fromEnvironment('KEYVIEW_API',
      defaultValue: 'https://keyview-api.yellow-violet-ced0.workers.dev');

  /// Opt-in sample data for offline UI work. Never on in a shipped build.
  static const bool allowMock =
      bool.fromEnvironment('KEYVIEW_MOCK', defaultValue: false);

  static const _offline =
      "Couldn't reach the price service. Check your connection and try again.";

  static Never _fail(String message, {int? statusCode}) =>
      throw KeyviewApiException(message, statusCode: statusCode);

  static Future<Portfolio> portfolio(String address) async {
    if (base.isEmpty) {
      if (allowMock) return Portfolio.mock(address);
      _fail('No backend configured.');
    }
    try {
      final r = await http
          .get(Uri.parse('$base/v1/portfolio/$address'))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        if (allowMock) return Portfolio.mock(address);
        _fail(
            r.statusCode == 503
                ? 'Price data is temporarily unavailable.'
                : "Couldn't load this wallet (error ${r.statusCode}).",
            statusCode: r.statusCode);
      }
      return Portfolio.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    } on KeyviewApiException {
      rethrow;
    } catch (_) {
      if (allowMock) return Portfolio.mock(address);
      _fail(_offline);
    }
  }

  /// Combined totals for a whole watchlist in ONE request (backend 0.1.9).
  ///
  /// Returns address (lowercased) → total USD, with null meaning "we could
  /// not price this wallet". A null is shown as unavailable; it is never
  /// treated as zero, because a zero would quietly shrink the headline total.
  static Future<Map<String, double?>> totals(List<String> addresses) async {
    if (base.isEmpty || addresses.isEmpty) return const {};
    final r = await http
        .post(Uri.parse('$base/v1/portfolios'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'addresses': addresses}))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) {
      _fail("Couldn't load your watchlist totals.", statusCode: r.statusCode);
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final out = <String, double?>{};
    for (final e in (j['results'] as List? ?? [])) {
      if (e is! Map<String, dynamic>) continue;
      final a = (e['address'] as String? ?? '').toLowerCase();
      if (a.isEmpty) continue;
      out[a] = e['status'] == 'ok' ? (e['totalUsd'] as num?)?.toDouble() : null;
    }
    return out;
  }

  static Future<History> history(String address) async {
    if (base.isEmpty) {
      if (allowMock) return History.mock(address);
      _fail('No backend configured.');
    }
    try {
      final r = await http
          .get(Uri.parse('$base/v1/history/$address'))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        if (allowMock) return History.mock(address);
        _fail("Couldn't load activity (error ${r.statusCode}).",
            statusCode: r.statusCode);
      }
      return History.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    } on KeyviewApiException {
      rethrow;
    } catch (_) {
      if (allowMock) return History.mock(address);
      _fail(_offline);
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
  // Accuracy layer (spec §21): where the price came from and how much to
  // trust it. Older backends omit these; defaults keep every row "ok".
  final String priceStatus; // ok | unreliable | unpriced
  final double priceConfidence;
  final List<String> priceSources;
  final double? liquidityUsd;
  final String? priceReason;
  final String? logoUrl;
  /// 0.1.9 — size risk, disclosed alongside a good price rather than
  /// suppressing it: "thin-for-size" or "thin-market", or null.
  final String? exitRisk;
  final String? exitNote;
  /// 0.1.9 — true when the price is a labelled last-known-good figure
  /// because every live source failed this minute.
  final bool priceStale;
  final DateTime? priceAsOf;
  const Holding(this.symbol, this.name, this.chain, this.amount, this.priceUsd,
      this.change24h,
      {this.contract,
      this.priceStatus = 'ok',
      this.priceConfidence = 1,
      this.priceSources = const [],
      this.liquidityUsd,
      this.priceReason,
      this.logoUrl,
      this.exitRisk,
      this.exitNote,
      this.priceStale = false,
      this.priceAsOf});
  double get valueUsd => amount * priceUsd;
  bool get reliable => priceStatus == 'ok';

  factory Holding.fromJson(Map<String, dynamic> j) => Holding(
      j['symbol'] as String? ?? '?',
      j['name'] as String? ?? '',
      j['chain'] as String? ?? '',
      (j['amount'] as num?)?.toDouble() ?? 0,
      (j['priceUsd'] as num?)?.toDouble() ?? 0,
      (j['change24h'] as num?)?.toDouble() ?? 0,
      contract: j['contract'] as String?,
      priceStatus: j['priceStatus'] as String? ?? 'ok',
      priceConfidence: (j['priceConfidence'] as num?)?.toDouble() ?? 1,
      priceSources: ((j['priceSources'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      liquidityUsd: (j['liquidityUsd'] as num?)?.toDouble(),
      priceReason: j['priceReason'] as String?,
      logoUrl: j['logoUrl'] as String?,
      exitRisk: j['exitRisk'] as String?,
      exitNote: j['exitNote'] as String?,
      priceStale: j['priceStale'] == true,
      priceAsOf: DateTime.tryParse(j['priceAsOf'] as String? ?? '')?.toLocal());
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
  /// Real positions we refuse to put a number on (spec §21): shown in their
  /// own section with the reason, never counted in [totalUsd].
  final List<Holding> unpriced;
  final DateTime? pricedAt;
  final bool isMock;
  const Portfolio(this.address, this.holdings,
      {this.unpriced = const [], this.pricedAt, this.isMock = false});
  double get totalUsd =>
      holdings.fold(0, (s, h) => h.reliable ? s + h.valueUsd : s);

  factory Portfolio.fromJson(Map<String, dynamic> j) => Portfolio(
      j['address'] as String? ?? '',
      ((j['holdings'] as List?) ?? [])
          .map((e) => Holding.fromJson(e as Map<String, dynamic>))
          .toList(),
      unpriced: ((j['unpriced'] as List?) ?? [])
          .map((e) => Holding.fromJson(e as Map<String, dynamic>))
          .toList(),
      pricedAt: DateTime.tryParse(j['pricedAt'] as String? ?? '')?.toLocal());

  factory Portfolio.mock(String address) => Portfolio(address, const [
        Holding('BTC', 'Bitcoin', 'bitcoin', 0.42, 68420.00, 2.1),
        Holding('ETH', 'Ethereum', 'ethereum', 4.10, 3560.18, 3.4),
        Holding('BNB', 'BNB', 'bnb', 3.20, 604.22, 1.2),
        Holding('SOL', 'Solana', 'solana', 9.50, 172.45, 5.8),
        Holding('TSLA', 'Tesla (Stock Token)', 'robinhood', 2.00, 405.53, -0.8),
      ], isMock: true);
}
