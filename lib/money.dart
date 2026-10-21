import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

/// Display currency (spec §4.9, added 0.1.8).
///
/// Every value in the app is computed in USD — prices, totals, alarm
/// thresholds. This converts for DISPLAY ONLY, at the rate the backend serves
/// from its daily feed (`GET /v1/fx`). Nothing downstream of a conversion is
/// ever fed back into a calculation, so a stale or missing rate can change
/// what a number looks like but never what it means.
///
/// If rates cannot be fetched the app stays in USD rather than guessing.
class Money {
  /// Currencies offered in Settings, in the order shown. Symbol is what the
  /// user expects to see, not necessarily the ISO sign.
  static const currencies = <MoneyCurrency>[
    MoneyCurrency('USD', r'$', 'US Dollar'),
    MoneyCurrency('EUR', '€', 'Euro'),
    MoneyCurrency('GBP', '£', 'British Pound'),
    MoneyCurrency('JPY', '¥', 'Japanese Yen', decimals: 0),
    MoneyCurrency('CHF', 'CHF ', 'Swiss Franc'),
    MoneyCurrency('CAD', r'CA$', 'Canadian Dollar'),
    MoneyCurrency('AUD', r'A$', 'Australian Dollar'),
    MoneyCurrency('NZD', r'NZ$', 'New Zealand Dollar'),
    MoneyCurrency('CNY', '¥', 'Chinese Yuan'),
    MoneyCurrency('HKD', r'HK$', 'Hong Kong Dollar'),
    MoneyCurrency('SGD', r'S$', 'Singapore Dollar'),
    MoneyCurrency('INR', '₹', 'Indian Rupee'),
    MoneyCurrency('KRW', '₩', 'South Korean Won', decimals: 0),
    MoneyCurrency('TWD', r'NT$', 'New Taiwan Dollar'),
    MoneyCurrency('BRL', r'R$', 'Brazilian Real'),
    MoneyCurrency('MXN', r'MX$', 'Mexican Peso'),
    MoneyCurrency('ARS', r'AR$', 'Argentine Peso', decimals: 0),
    MoneyCurrency('CLP', r'CL$', 'Chilean Peso', decimals: 0),
    MoneyCurrency('COP', r'CO$', 'Colombian Peso', decimals: 0),
    MoneyCurrency('SEK', 'kr ', 'Swedish Krona'),
    MoneyCurrency('NOK', 'kr ', 'Norwegian Krone'),
    MoneyCurrency('DKK', 'kr ', 'Danish Krone'),
    MoneyCurrency('PLN', 'zł ', 'Polish Zloty'),
    MoneyCurrency('CZK', 'Kč ', 'Czech Koruna'),
    MoneyCurrency('HUF', 'Ft ', 'Hungarian Forint', decimals: 0),
    MoneyCurrency('RON', 'lei ', 'Romanian Leu'),
    MoneyCurrency('TRY', '₺', 'Turkish Lira'),
    MoneyCurrency('ZAR', 'R ', 'South African Rand'),
    MoneyCurrency('NGN', '₦', 'Nigerian Naira', decimals: 0),
    MoneyCurrency('EGP', 'E£', 'Egyptian Pound'),
    MoneyCurrency('AED', 'AED ', 'UAE Dirham'),
    MoneyCurrency('SAR', 'SAR ', 'Saudi Riyal'),
    MoneyCurrency('ILS', '₪', 'Israeli Shekel'),
    MoneyCurrency('THB', '฿', 'Thai Baht'),
    MoneyCurrency('PHP', '₱', 'Philippine Peso'),
    MoneyCurrency('IDR', 'Rp ', 'Indonesian Rupiah', decimals: 0),
    MoneyCurrency('MYR', 'RM ', 'Malaysian Ringgit'),
    MoneyCurrency('VND', '₫', 'Vietnamese Dong', decimals: 0),
    MoneyCurrency('PKR', 'Rs ', 'Pakistani Rupee', decimals: 0),
    MoneyCurrency('BDT', '৳', 'Bangladeshi Taka'),
  ];

  /// Bumped whenever the chosen currency or the rate table changes. Widgets
  /// that show money listen to this and rebuild.
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static String _code = 'USD';

  /// The chosen currency code.
  static String get code => _code;

  /// USD -> code multipliers. Populated from the on-disk cache at launch and
  /// then refreshed from `/v1/fx`.
  static Map<String, double> _rates = const {};
  static bool _loaded = false;
  /// Set once the first rate fetch has finished, successfully or not.
  /// Before that we must not render a number in the wrong currency.
  static bool _firstLoadDone = false;

  /// When the rate table we are holding was published by the backend, and when
  /// we last managed to fetch it. Both null until a fetch or a cache restore
  /// succeeds.
  static DateTime? _asOf;
  static DateTime? _fetchedAt;

  /// Why the last fetch failed, for Settings to display. 0.1.10: every FX
  /// failure used to be swallowed by `catch (_)`, so a user reporting "euro
  /// shows dollars" gave us nothing to act on.
  static String? _lastError;

  static const _prefKey = 'display_currency';
  static const _ratesKey = 'fx_rates_v1';
  static const _asOfKey = 'fx_as_of_v1';
  static const _fetchedKey = 'fx_fetched_at_v1';

  /// A cached table older than this is still used — a two-day-old euro rate is
  /// a far better answer than refusing to convert — but it is labelled stale.
  static const staleAfter = Duration(hours: 36);

  static MoneyCurrency get current => currencies
      .firstWhere((c) => c.code == _code, orElse: () => currencies.first);

  /// True when a non-USD currency is selected, the rate fetch has finished,
  /// and there is still no rate from any source — live or cached — so the UI
  /// can say the figures are in USD instead of lying about them.
  static bool get rateMissing =>
      _code != 'USD' && _firstLoadDone && !_rates.containsKey(_code);

  /// True while a non-USD currency is selected but no rate for it is known
  /// yet. With the on-disk cache restored at launch this window is now empty
  /// for anyone who has ever had rates, which is the actual fix for "when I
  /// select euro the total still populates in dollars".
  static bool get awaitingRate =>
      _code != 'USD' && !_firstLoadDone && !_rates.containsKey(_code);

  /// Converting at a rate we could not refresh today. The figure is honest but
  /// dated, and the UI says so rather than silently falling back to dollars.
  static bool get ratesStale {
    final f = _fetchedAt;
    if (f == null || !_rates.containsKey(_code) || _code == 'USD') return false;
    return DateTime.now().difference(f) > staleAfter;
  }

  static DateTime? get ratesAsOf => _asOf;
  static String? get lastError => _lastError;

  /// Restores the saved choice AND the last known rate table. Local disk only,
  /// so it is safe to await before first paint; the network refresh is fired
  /// off and never blocks the UI.
  static Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString(_prefKey);
      if (saved != null && currencies.any((c) => c.code == saved)) {
        _code = saved;
      }
      _restoreCached(p);
      version.value++;
    } catch (_) {/* a missing preference just means USD */}
    unawaited(refreshRates());
  }

  static void _restoreCached(SharedPreferences p) {
    try {
      final raw = p.getString(_ratesKey);
      if (raw == null) return;
      final parsed = _parseRates(jsonDecode(raw));
      if (parsed.isEmpty) return;
      _rates = parsed;
      _loaded = true;
      final a = p.getString(_asOfKey);
      if (a != null) _asOf = DateTime.tryParse(a);
      final f = p.getInt(_fetchedKey);
      if (f != null) {
        _fetchedAt = DateTime.fromMillisecondsSinceEpoch(f);
      }
    } catch (_) {/* a corrupt cache is simply ignored */}
  }

  static Future<void> _persist(Map<String, double> rates, String? asOf) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_ratesKey, jsonEncode(rates));
      await p.setInt(_fetchedKey, DateTime.now().millisecondsSinceEpoch);
      final parsedAsOf = asOf == null ? null : _parseHttpDate(asOf);
      if (parsedAsOf != null) {
        await p.setString(_asOfKey, parsedAsOf.toIso8601String());
      }
    } catch (_) {/* cache is an optimisation, never a requirement */}
  }

  static Map<String, double> _parseRates(Object? decoded) {
    final out = <String, double>{};
    final raw = decoded is Map
        ? (decoded['rates'] is Map ? decoded['rates'] as Map : decoded)
        : const {};
    raw.forEach((k, v) {
      final d = v is num ? v.toDouble() : double.tryParse('$v');
      if (d != null && d > 0) out['$k'] = d;
    });
    return out;
  }

  /// `/v1/fx` reports `asOf` as an RFC 1123 string ("Wed, 21 Oct 2026 ...").
  static const _months = <String, int>{
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };

  static DateTime? _parseHttpDate(String s) {
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso.toLocal();
    final m = RegExp(r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2})')
        .firstMatch(s);
    if (m == null) return null;
    final mon = _months[m.group(2)!];
    if (mon == null) return null;
    return DateTime.utc(
      int.parse(m.group(3)!), mon, int.parse(m.group(1)!),
      int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6)!),
    ).toLocal();
  }

  static Future<void> setCurrency(String newCode) async {
    if (!currencies.any((c) => c.code == newCode)) return;
    _code = newCode;
    version.value++;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefKey, newCode);
    } catch (_) {/* choice still applies for this run */}
    if (newCode != 'USD' && !_rates.containsKey(newCode)) await refreshRates();
  }

  /// Three attempts with backoff, and a timeout that matches the rest of the
  /// API client. 0.1.10: a single slow or rate-limited response used to leave
  /// the app stuck in dollars for the entire session with nothing logged.
  static const _attempts = 3;
  static const _attemptTimeout = Duration(seconds: 20);
  static bool _inFlight = false;

  static Future<void> refreshRates() async {
    if (_inFlight) return;
    _inFlight = true;
    if (KeyviewApi.base.isEmpty) {
      _lastError = 'No backend configured.';
      _firstLoadDone = true;
      _inFlight = false;
      version.value++;
      return;
    }
    try {
      for (var attempt = 1; attempt <= _attempts; attempt++) {
        try {
          final r = await http
              .get(Uri.parse('${KeyviewApi.base}/v1/fx'))
              .timeout(_attemptTimeout);
          if (r.statusCode != 200) {
            _lastError = 'HTTP ${r.statusCode} from /v1/fx';
          } else {
            final j = jsonDecode(r.body) as Map<String, dynamic>;
            final parsed = _parseRates(j);
            if (parsed.isEmpty) {
              _lastError = '/v1/fx returned no usable rates';
            } else {
              _rates = parsed;
              _loaded = true;
              _lastError = null;
              final asOf = j['asOf'];
              _asOf = asOf is String ? _parseHttpDate(asOf) : null;
              _fetchedAt = DateTime.now();
              await _persist(parsed, asOf is String ? asOf : null);
              return;
            }
          }
        } on TimeoutException {
          _lastError = 'Timed out after ${_attemptTimeout.inSeconds}s';
        } catch (e) {
          _lastError = e.runtimeType.toString();
        }
        if (attempt < _attempts) {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      }
    } finally {
      // Whatever happened, the waiting window is over: we either have rates
      // (fresh or cached) or we fall back to USD and say why.
      _firstLoadDone = true;
      _inFlight = false;
      version.value++;
    }
  }

  static bool get ratesLoaded => _loaded;

  /// Converts a USD amount into the chosen currency, or returns it unchanged
  /// when no rate is known.
  static double convert(double usd) {
    final r = _rates[_code];
    return r == null ? usd : usd * r;
  }

  /// Shown for the one round trip between "EUR selected" and "EUR rate here".
  static const placeholder = '—';

  /// A full currency string for [usd], e.g. "€1,234.56".
  static String format(double usd) {
    if (awaitingRate) return placeholder;
    final c = rateMissing ? currencies.first : current;
    return NumberFormat.currency(symbol: c.symbol, decimalDigits: c.decimals)
        .format(convert(usd));
  }

  /// Like [format] but keeps small values readable instead of collapsing a
  /// fraction of a cent to zero — which is what the EthFan tokens need:
  /// $0.000003965 must not render as "$0.00".
  static String formatPrice(double usd) {
    if (awaitingRate) return placeholder;
    final v = convert(usd);
    final c = rateMissing ? currencies.first : current;
    if (v != 0 && v.abs() < 0.01) {
      return '${c.symbol}${v.toStringAsPrecision(3)}';
    }
    return NumberFormat.currency(symbol: c.symbol, decimalDigits: c.decimals)
        .format(v);
  }

  /// Compact money for tight spots (alarm thresholds): "€1.2k", "$3.4M".
  /// 0.1.9 — alarms.dart printed these with a hardcoded "$" regardless of the
  /// chosen currency.
  static String formatCompact(double usd) {
    if (awaitingRate) return placeholder;
    final v = convert(usd);
    final s = (rateMissing ? currencies.first : current).symbol;
    final a = v.abs();
    if (a >= 1000000) return '$s${(v / 1000000).toStringAsFixed(1)}M';
    if (a >= 1000) {
      return '$s${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
    }
    if (v == v.roundToDouble()) return '$s${v.toStringAsFixed(0)}';
    return '$s${v.toStringAsFixed(2)}';
  }

  // ── Test hooks ────────────────────────────────────────────────────────────
  // Exposed so the currency rules can be tested without a network or a
  // SharedPreferences binding. Not used by the app.

  @visibleForTesting
  static void debugReset() {
    _code = 'USD';
    _rates = const {};
    _loaded = false;
    _firstLoadDone = false;
    _asOf = null;
    _fetchedAt = null;
    _lastError = null;
    _inFlight = false;
    version.value++;
  }

  @visibleForTesting
  static void debugSetCode(String c) {
    if (!currencies.any((x) => x.code == c)) return;
    _code = c;
    version.value++;
  }

  @visibleForTesting
  static void debugSetRates(Map<String, double> r) {
    _rates = {'USD': 1, ...r};
    _loaded = true;
    _firstLoadDone = true;
    _fetchedAt = DateTime.now();
    version.value++;
  }

  /// Simulates the on-disk cache restored at launch with an old timestamp —
  /// the "stale but usable" path.
  @visibleForTesting
  static void debugSetCachedRates(Map<String, double> r, {Duration? age}) {
    _rates = {'USD': 1, ...r};
    _loaded = true;
    _firstLoadDone = true;
    _fetchedAt = DateTime.now().subtract(age ?? const Duration(hours: 48));
    version.value++;
  }

  @visibleForTesting
  static void debugSetError(String? e) {
    _lastError = e;
    version.value++;
  }

  @visibleForTesting
  static void debugFinishFirstLoad() {
    _firstLoadDone = true;
    version.value++;
  }
}

class MoneyCurrency {
  final String code, symbol, name;
  final int decimals;
  const MoneyCurrency(this.code, this.symbol, this.name, {this.decimals = 2});
}
