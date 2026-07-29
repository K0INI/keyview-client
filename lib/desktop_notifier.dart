import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth.dart';
import 'push.dart';

/// Desktop alarm banners (spec §9: desktop uses OS-level notifiers, not APNs).
///
/// While the app is running and a session exists, this polls the notifications
/// feed once a minute and raises a native banner for every entry that fired
/// since the last one seen. The very first pass only records where the feed
/// currently ends, so launching the app never replays history as banners.
///
/// Everything is fail-soft, matching [PushPlatform]: a missing plugin, a
/// declined permission, a signed-out session, or a network error all mean
/// "no banner this minute" — never a crash, never a blocked launch.
class DesktopNotifier {
  DesktopNotifier._();

  static const _pollEvery = Duration(seconds: 60);
  static const _lastSeenKey = 'desktop_notifier_last_seen_ms';
  static const _maxBannersPerTick = 5;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static Timer? _timer;
  static bool _started = false;
  static bool _ready = false;
  static int _notifId = 0;

  /// Banners are a macOS feature for now. Windows gets its own treatment in
  /// the Microsoft Store phase; mobile stays on FCM via [PushPlatform].
  static bool get supported {
    if (kIsWeb) return false;
    try {
      return Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  static Future<void> start() async {
    if (_started || !supported) return;
    _started = true;
    try {
      _ready = await _plugin.initialize(
            const InitializationSettings(
              macOS: DarwinInitializationSettings(
                requestAlertPermission: true,
                requestBadgePermission: false,
                requestSoundPermission: true,
                defaultPresentAlert: true,
                defaultPresentSound: true,
              ),
            ),
          ) ??
          false;
    } catch (_) {
      _ready = false; // plugin unavailable on this build — stay silent
    }
    if (!_ready) return;
    await _tick(seed: true);
    _timer = Timer.periodic(_pollEvery, (_) => _tick());
  }

  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  static Future<void> _tick({bool seed = false}) async {
    try {
      final s = await KeyviewAuth.ensureFresh();
      if (s == null) return; // signed out — nothing to show
      final feed = await PushService.feed(s, limit: 20);
      if (feed.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final lastSeen = prefs.getInt(_lastSeenKey) ?? 0;
      final newestMs = newestFiredMs(feed, fallback: lastSeen);

      if (!seed && lastSeen > 0) {
        for (final e in pickNew(feed, lastSeen, max: _maxBannersPerTick)) {
          await _show(e);
        }
      }
      if (newestMs > lastSeen) await prefs.setInt(_lastSeenKey, newestMs);
    } catch (_) {
      // Network blip, 401 mid-refresh, prefs failure — try again next minute.
    }
  }

  static Future<void> _show(NotificationEntry e) async {
    try {
      await _plugin.show(
        _notifId++ % 1000,
        'KŌINIkeyview',
        e.summary,
        const NotificationDetails(macOS: DarwinNotificationDetails()),
      );
    } catch (_) {
      // A single failed banner must not stop the loop.
    }
  }

  /// Newest fired_at in [feed] as epoch ms; [fallback] when nothing has one.
  /// Pure — unit tested.
  @visibleForTesting
  static int newestFiredMs(List<NotificationEntry> feed, {int fallback = 0}) {
    var newest = fallback;
    for (final e in feed) {
      final ms = e.firedAt?.millisecondsSinceEpoch ?? 0;
      if (ms > newest) newest = ms;
    }
    return newest;
  }

  /// Entries strictly newer than [lastSeenMs], oldest first so the most
  /// recent banner ends up on top, capped at [max]. Pure — unit tested.
  @visibleForTesting
  static List<NotificationEntry> pickNew(
    List<NotificationEntry> feed,
    int lastSeenMs, {
    int max = 5,
  }) {
    final fresh = feed
        .where((e) =>
            (e.firedAt?.millisecondsSinceEpoch ?? 0) > lastSeenMs)
        .toList()
      ..sort((a, b) => (a.firedAt?.millisecondsSinceEpoch ?? 0)
          .compareTo(b.firedAt?.millisecondsSinceEpoch ?? 0));
    return fresh.length <= max ? fresh : fresh.sublist(fresh.length - max);
  }
}
