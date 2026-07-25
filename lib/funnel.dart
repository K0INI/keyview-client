import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api.dart';
import 'brand.dart';

/// Funnel touchpoints + privacy-respecting analytics (spec §4.8, §18).
///
/// KŌINIkeyview earns nothing directly (§20.1). Its whole job is to send
/// engaged people to the rest of the Koini family, so these handoffs and the
/// counters behind them are the actual measure of success (§1.3).
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

  static const networth = FunnelDestination(
    id: 'networth',
    label: 'Hide your traffic with NetWorth',
    blurb:
        'Your wallet is public. Your browsing does not have to be — NetWorth is the family VPN.',
    url: 'https://networthvpn.com',
    icon: Icons.vpn_lock_rounded,
  );

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
    // The only extra dimension permitted is which Koini destination was tapped,
    // and only from the fixed set of destination ids.
    final dest = destination != null && _destIds.contains(destination)
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

  static const _destIds = {'koiniswap', 'koini', 'networth'};

  /// Destinations offered on a token view, in priority order.
  static const forToken = [koiniswap, koini];
}

class FunnelDestination {
  final String id, label, blurb, url;
  final IconData icon;
  const FunnelDestination({
    required this.id,
    required this.label,
    required this.blurb,
    required this.url,
    required this.icon,
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
