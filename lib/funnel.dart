import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'brand.dart';

/// Funnel touchpoints + privacy-respecting analytics (spec §4.8, §18).
///
/// KŌINIkeyview earns nothing directly (§20.1). Its whole job is to send
/// engaged people to the rest of the Koini family, so these handoffs and the
/// counters behind them are the actual measure of success (§1.3).
///
/// Since 0.1.6 the roster is LIVE: the backend reads apps.koini.io and turns
/// every product card there into a promo (GET /v1/promos), so editing that
/// page edits the ads — no app release. A small built-in fallback keeps the
/// slot working offline or if the catalog is ever unreachable.
///
/// Analytics are AGGREGATE COUNTERS ONLY — an event name and nothing else.
/// No user id, no address, no device id, no advertising identifier. That is
/// what the published privacy policy promises, so it is enforced here in code
/// rather than left to discipline.
class Funnel {
  static const koiniswap = FunnelDestination(
    id: 'koiniswap',
    label: 'Swap on Koiniswap',
    blurb: 'Trade this token without leaving the Koini family.',
    url: 'https://koiniswap.com',
    icon: Icons.swap_horiz_rounded,
  );

  static const koini = FunnelDestination(
    id: 'koini',
    label: 'Trade on KŌINI',
    blurb: 'Full order book and deeper liquidity.',
    url: 'https://koini.io',
    icon: Icons.candlestick_chart_rounded,
  );

  /// Shown until /v1/promos answers, and whenever it cannot.
  static const fallbackPromos = [
    FunnelDestination(
      id: 'koinivpn',
      label: 'KŌINIvpn',
      blurb:
          'Your wallet is public. Your browsing does not have to be — private, encrypted browsing built for crypto.',
      url: 'https://vpn.koini.io',
      icon: Icons.vpn_lock_rounded,
    ),
    FunnelDestination(
      id: 'koinikeystickos',
      label: 'KŌINIkeystickOS',
      blurb: 'Boot a computer from the stick and keep your keys off every screen.',
      url: 'https://keystick.koini.io',
      icon: Icons.usb_rounded,
    ),
    FunnelDestination(
      id: 'koinisend',
      label: 'KŌINIsend',
      blurb: 'The safest way to send crypto — a transfer-only self-custody wallet.',
      url: 'https://send.koini.io',
      icon: Icons.send_rounded,
    ),
    koini,
  ];

  /// Backend icon names → Material icons. Anything unknown gets the generic
  /// outward arrow, so new catalog entries can never break the slot.
  static const _icons = <String, IconData>{
    'vpn_lock': Icons.vpn_lock_rounded,
    'usb': Icons.usb_rounded,
    'swap_horiz': Icons.swap_horiz_rounded,
    'receipt_long': Icons.receipt_long_rounded,
    'menu_book': Icons.menu_book_rounded,
    'edit_note': Icons.edit_note_rounded,
    'alt_route': Icons.alt_route_rounded,
    'send': Icons.send_rounded,
    'visibility': Icons.visibility_rounded,
    'alarm': Icons.alarm_rounded,
    'sell': Icons.sell_rounded,
    'account_balance_wallet': Icons.account_balance_wallet_rounded,
    'candlestick_chart': Icons.candlestick_chart_rounded,
    'casino': Icons.casino_rounded,
    'emergency': Icons.emergency_rounded,
    'storefront': Icons.storefront_rounded,
    'arrow_outward': Icons.arrow_outward_rounded,
  };

  static List<FunnelDestination>? _promoCache;

  /// The live roster, fetched once per app run. Never throws; always returns
  /// at least the fallback list.
  static Future<List<FunnelDestination>> promos() async {
    final cached = _promoCache;
    if (cached != null) return cached;
    try {
      final r = await http
          .get(Uri.parse('${KeyviewApi.base}/v1/promos'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final rows = (body['promos'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map((p) => FunnelDestination(
                  id: (p['id'] ?? '') as String,
                  label: (p['label'] ?? '') as String,
                  blurb: (p['blurb'] ?? '') as String,
                  url: (p['url'] ?? '') as String,
                  icon: _icons[p['icon']] ?? Icons.arrow_outward_rounded,
                  logoUrl: p['logoUrl'] as String?,
                ))
            .where((d) =>
                d.id.isNotEmpty &&
                d.label.isNotEmpty &&
                d.blurb.isNotEmpty &&
                d.url.startsWith('https://'))
            .toList();
        if (rows.isNotEmpty) return _promoCache = rows;
      }
    } catch (_) {
      // The slot must never be a reason the app feels broken.
    }
    return fallbackPromos;
  }

  /// Events the funnel reports. Named up front so an accidental
  /// `track('user_0x1234…')` can never happen — only these strings are sent.
  static const evAppOpen = 'app_open';
  static const evAddressViewed = 'address_viewed';
  static const evWatchAdded = 'watch_added';
  static const evAlarmCreated = 'alarm_created';
  static const evNotificationTapped = 'notification_tapped';
  static const evHandoff = 'handoff';

  static const _allowed = {
    evAppOpen, evAddressViewed, evWatchAdded, evAlarmCreated,
    evNotificationTapped, evHandoff,
  };

  /// Fire-and-forget aggregate counter bump. Never blocks the UI, never throws,
  /// and silently drops anything not on the allow-list.
  static Future<void> track(String event, {String? destination}) async {
    if (!_allowed.contains(event)) return;
    // The only extra dimension permitted is which Koini destination was
    // tapped. Destinations are now the live roster's slugs, so the guard is
    // shape (a short lowercase slug) rather than a fixed list — still never
    // anything user-derived.
    final dest = destination != null && _slug.hasMatch(destination)
        ? destination
        : null;
    try {
      await http
          .post(Uri.parse('${KeyviewApi.base}/v1/event'),
              headers: {'content-type': 'application/json'},
              body: jsonEncode({'event': event, if (dest != null) 'destination': dest}))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Analytics must never be a reason the app feels broken.
    }
  }

  static final _slug = RegExp(r'^[a-z0-9-]{1,24}$');

  /// Destinations offered on a token view, in priority order.
  static const forToken = [koiniswap, koini];
}

class FunnelDestination {
  final String id, label, blurb, url;
  final IconData icon;
  /// The product's real mark (an SVG served by /v1/promos/logo/:id), when the
  /// live catalog has one; the Material icon is the fallback.
  final String? logoUrl;
  const FunnelDestination({
    required this.id,
    required this.label,
    required this.blurb,
    required this.url,
    required this.icon,
    this.logoUrl,
  });
}

/// A single, non-blocking handoff card. Deliberately not a modal, not an
/// interstitial, and never covering content — the spec asks for one quiet slot
/// introduced gradually, not an ad unit.
class FunnelCard extends StatelessWidget {
  final FunnelDestination destination;
  final VoidCallback? onTap;
  const FunnelCard({super.key, required this.destination, this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Funnel.track(Funnel.evHandoff, destination: destination.id);
            // The handoff itself: open the destination in the system browser.
            launchUrl(Uri.parse(destination.url),
                mode: LaunchMode.externalApplication);
            onTap?.call();
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Brand.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Brand.line),
            ),
            child: Row(
              children: [
                if (destination.logoUrl != null)
                  SvgPicture.network(destination.logoUrl!,
                      width: 22,
                      height: 22,
                      placeholderBuilder: (_) =>
                          Icon(destination.icon, size: 19, color: Brand.amber))
                else
                  Icon(destination.icon, size: 19, color: Brand.amber),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(destination.label,
                          style: const TextStyle(
                              color: Brand.warm,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(destination.blurb,
                          style: const TextStyle(
                              color: Brand.warm3, fontSize: 11, height: 1.4)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_outward_rounded,
                    size: 15, color: Brand.warm3),
              ],
            ),
          ),
        ),
      );
}

/// The portfolio slot since 0.1.6: one card at a time from the live roster,
/// cycling with a quiet fade every ten seconds.
class PromoCarousel extends StatefulWidget {
  const PromoCarousel({super.key});

  @override
  State<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<PromoCarousel> {
  List<FunnelDestination> _promos = Funnel.fallbackPromos;
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    Funnel.promos().then((p) {
      if (mounted) setState(() => _promos = p);
    });
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() => _i = (_i + 1) % _promos.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = _promos[_i % _promos.length];
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: FunnelCard(key: ValueKey(d.id), destination: d),
    );
  }
}
