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

  /// USD -> code multipliers, empty until /v1/fx answers.
  static Map<String, double> _rates = const {};
  static bool _loaded = false;
  /// Set once the first rate fetch has finished, successfully or not.
  /// Before that we must not render a number in the wrong currency.
  static bool _firstLoadDone = false;

  static const _prefKey = 'display_currency';

  static MoneyCurrency get current => currencies
      .firstWhere((c) => c.code == _code, orElse: () => currencies.first);

  /// True when a non-USD currency is selected, the rate fetch has finished,
  /// and there is still no rate — so the UI can say the figures are in USD
  /// instead of lying about them.
  static bool get rateMissing =>
      _code != 'USD' && _firstLoadDone && !_rates.containsKey(_code);

  /// True while a non-USD currency is selected but its rate has not arrived
  /// yet. 0.1.9: money renders a placeholder for this brief window instead of
  /// printing a dollar figure under a euro setting — the defect behind "when
  /// I select euro the total still populates in dollars". The window is one
  /// HTTP round trip at launch, and screens rebuild on [version].
  static bool get awaitingRate =>
      _code != 'USD' && !_firstLoadDone && !_rates.containsKey(_code);

  /// Restores the saved choice and refreshes rates. Safe to call more than
  /// once; never throws.
  static Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString(_prefKey);
      if (saved != null && currencies.any((c) => c.code == saved)) {
        _code = saved;
        version.value++;
      }
    } catch (_) {/* a missing preference just means USD */}
    await refreshRates();
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

  static Future<void> refreshRates() async {
    if (KeyviewApi.base.isEmpty) {
      // No backend to ask: the waiting window is over before it began.
      _firstLoadDone = true;
      version.value++;
      return;
    }
    try {
      final r = await http
          .get(Uri.parse('${KeyviewApi.base}/v1/fx'))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final raw = (j['rates'] as Map?) ?? {};
      final parsed = <String, double>{};
      raw.forEach((k, v) {
        final d = v is num ? v.toDouble() : double.tryParse('$v');
        if (d != null && d > 0) parsed['$k'] = d;
      });
      if (parsed.isNotEmpty) {
        _rates = parsed;
        _loaded = true;
      }
    } catch (_) {/* stay in USD */} finally {
      // Whatever happened, the waiting window is over: either we have rates
      // or we fall back to USD and say so. Already-built screens pick this up.
      _firstLoadDone = true;
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
