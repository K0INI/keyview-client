import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

import 'auth.dart';
import 'firebase_options.dart';
import 'push.dart';

/// Bridges the platform's FCM token into [PushService].
///
/// [PushService] deliberately takes a token as input rather than fetching one,
/// so that layer stays testable with no Firebase project attached. This file is
/// the missing other half: it obtains the token from the platform and keeps the
/// `device` table in step with the signed-in session.
///
/// Everything here is fail-soft, matching how `SupabaseConfig` degrades: if
/// Firebase is not configured, the plugin is unavailable, or the user declines
/// notifications, the app keeps working exactly as before and alarms simply stay
/// silent. Nothing in this file may prevent the app from starting.
class PushPlatform {
  PushPlatform._();

  static bool _started = false;
  static bool _firebaseReady = false;
  static String? _lastToken;
  static Session? _lastSession;
  static StreamSubscription<String>? _refreshSub;

  /// Only iOS and Android route through FCM. Desktop uses OS-level notifiers
  /// (spec §9) and is intentionally a no-op here.
  static String? get platformName {
    if (kIsWeb) return null;
    try {
      if (Platform.isIOS) return 'ios';
      if (Platform.isAndroid) return 'android';
    } catch (_) {
      // Platform is unavailable on some targets; treat as unsupported.
    }
    return null;
  }

  static bool get supported => platformName != null;

  /// Call once from `main()`, after `KeyviewAuth.restore()`.
  ///
  /// Safe to await or to fire and forget — it never throws.
  static Future<void> start() async {
    if (_started || !supported) return;
    _started = true;

    if (!await _ensureFirebase()) return;

    KeyviewAuth.session.addListener(_onSessionChanged);
    await _sync(KeyviewAuth.session.value);

    try {
      _refreshSub =
          FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        _lastToken = token;
        final s = KeyviewAuth.session.value;
        if (s != null) {
          await PushService.registerDevice(s, platformName!, token);
        }
      });
    } catch (e) {
      debugPrint('[push] token-refresh stream unavailable: $e');
    }
  }

  /// Detach listeners. Only needed in tests.
  static Future<void> stop() async {
    KeyviewAuth.session.removeListener(_onSessionChanged);
    await _refreshSub?.cancel();
    _refreshSub = null;
    _started = false;
  }

  static Future<bool> _ensureFirebase() async {
    if (_firebaseReady) return true;
    try {
      // Options are Dart constants (lib/firebase_options.dart), not the native
      // config files — so init can't fail on a missing Xcode resource membership
      // or an absent Gradle plugin. The native copies in firebase/ remain as
      // backup/documentation.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _firebaseReady = true;
      return true;
    } catch (e) {
      debugPrint('[push] Firebase not configured, push disabled: $e');
      return false;
    }
  }

  static void _onSessionChanged() {
    // ValueNotifier listeners are synchronous; hand off without blocking.
    unawaited(_sync(KeyviewAuth.session.value));
  }

  static Future<void> _sync(Session? session) async {
    if (session == null) {
      await _unregisterLast();
      return;
    }
    _lastSession = session;
    final token = await _token();
    if (token == null) return;
    _lastToken = token;
    await PushService.registerDevice(session, platformName!, token);
  }

  /// Best-effort cleanup on sign-out.
  ///
  /// The DELETE needs a session to authorise it, and `KeyviewAuth.signOut()`
  /// clears the session before we hear about it — so the last known session is
  /// held onto for exactly this. Its access token is usually still inside its
  /// validity window at this point. If it isn't, the row is simply left behind
  /// and refreshed on the next sign-in, which the upsert already handles.
  static Future<void> _unregisterLast() async {
    final s = _lastSession;
    final t = _lastToken;
    _lastSession = null;
    _lastToken = null;
    if (s == null || t == null) return;
    try {
      await PushService.unregisterDevice(s, t);
    } catch (e) {
      debugPrint('[push] unregister failed (harmless): $e');
    }
  }

  static Future<String?> _token() async {
    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission();
      final status = settings.authorizationStatus;
      if (status != AuthorizationStatus.authorized &&
          status != AuthorizationStatus.provisional) {
        debugPrint('[push] notifications not granted: $status');
        return null;
      }

      // On iOS, getToken() returns null until APNs has handed the app its
      // device token. That is asynchronous and usually lands within a second
      // or two of launch, so poll briefly rather than giving up on the race.
      if (Platform.isIOS) {
        for (var i = 0; i < 10; i++) {
          final apns = await messaging.getAPNSToken();
          if (apns != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

      return await messaging.getToken();
    } catch (e) {
      debugPrint('[push] could not obtain FCM token: $e');
      return null;
    }
  }
}
