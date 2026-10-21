import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;
import 'package:purchases_flutter/purchases_flutter.dart';

import 'api.dart';
import 'auth.dart';

/// SI call alerts (SPEC-KEYVIEW-SI §6) — the one paid thing in the app.
///
/// $14.99/month, 45 agent-minutes a month shared across the KŌINI apps: the
/// COINY voice agent calls you when a big move hits a wallet you alarm, and
/// can answer questions about your holdings on any call.
///
/// Purchases run through RevenueCat (entitlement `si`). The server mirrors the
/// entitlement, so someone who subscribed in another KŌINI app is simply
/// active here — no second purchase, no cross-app sales pitch (Apple 3.1.1).
class SiKeys {
  /// RevenueCat public SDK keys. Empty string = purchases not configured on
  /// this platform (the UI then shows server-side entitlement state only).
  static const apple = String.fromEnvironment('RC_APPLE_KEY', defaultValue: '');
  static const google = String.fromEnvironment('RC_GOOGLE_KEY', defaultValue: '');
}

enum SiStatus { unknown, inactive, active }

class SiService {
  SiService._();

  static final ValueNotifier<SiStatus> status = ValueNotifier(SiStatus.unknown);
  static final ValueNotifier<String?> phone = ValueNotifier(null);
  static bool _configured = false;
  static String? _configuredFor;

  /// True on the two store platforms where the subscription can be bought.
  /// Everywhere else (Windows, Linux, the notarized macOS DMG) the tier still
  /// *works* when granted elsewhere — there is just no purchase button.
  static bool get purchasesSupported {
    if (kIsWeb) return false;
    try {
      if (Platform.isIOS) return SiKeys.apple.isNotEmpty;
      if (Platform.isAndroid) return SiKeys.google.isNotEmpty;
    } catch (_) { /* Platform unavailable → no purchases */ }
    return false;
  }

  static bool get active => status.value == SiStatus.active;

  /// Fire-and-forget at startup and on sign-in change. Never blocks paint,
  /// never throws (same contract as PushPlatform.start()).
  static Future<void> start() async {
    try {
      KeyviewAuth.session.addListener(() { unawaited(refresh()); });
      await refresh();
    } catch (_) { /* fail-soft */ }
  }

  static Future<void> _ensureConfigured(String userId) async {
    if (!purchasesSupported) return;
    try {
      if (!_configured) {
        final key = Platform.isIOS ? SiKeys.apple : SiKeys.google;
        await Purchases.configure(PurchasesConfiguration(key)..appUserID = userId);
        _configured = true;
        _configuredFor = userId;
      } else if (_configuredFor != userId) {
        await Purchases.logIn(userId);
        _configuredFor = userId;
      }
    } catch (_) { /* store outage — server check still runs */ }
  }

  /// Entitlement truth: RevenueCat first (fresh purchases), the backend mirror
  /// second (cross-app grants, and every platform without the SDK).
  static Future<void> refresh() async {
    final s = await KeyviewAuth.ensureFresh() ?? KeyviewAuth.session.value;
    if (s == null) {
      status.value = SiStatus.inactive;
      phone.value = null;
      return;
    }
    var found = false;
    if (purchasesSupported) {
      await _ensureConfigured(s.userId);
      try {
        final info = await Purchases.getCustomerInfo();
        found = info.entitlements.active.containsKey('si');
      } catch (_) { /* fall through to the server */ }
    }
    if (!found) {
      try {
        final r = await http.get(Uri.parse('${KeyviewApi.base}/v1/entitlement'),
            headers: {'authorization': 'Bearer ${s.accessToken}'})
            .timeout(const Duration(seconds: 12));
        if (r.statusCode == 200) {
          found = (jsonDecode(r.body) as Map)['si_active'] == true;
        }
      } catch (_) { /* offline → keep whatever we had */ }
    }
    status.value = found ? SiStatus.active : SiStatus.inactive;
    unawaited(_loadPhone(s));
  }

  // ── purchase ───────────────────────────────────────────────────────────────

  /// The monthly offering's price string ("$14.99/month"), or null offline.
  static Future<Package?> monthlyPackage() async {
    if (!purchasesSupported) return null;
    try {
      final offerings = await Purchases.getOfferings();
      final o = offerings.current;
      return o?.monthly ?? (o != null && o.availablePackages.isNotEmpty ? o.availablePackages.first : null);
    } catch (_) {
      return null;
    }
  }

  /// Returns null on success, a short human message otherwise.
  static Future<String?> buy(Package p) async {
    try {
      await Purchases.purchasePackage(p);
      await refresh();
      return active ? null : 'Purchase did not complete.';
    } on PlatformException catch (e) {
      // The SDK surfaces store errors as PlatformExceptions with a coded detail.
      if (PurchasesErrorHelper.getErrorCode(e) ==
          PurchasesErrorCode.purchaseCancelledError) {
        return null; // their choice, not an error
      }
      return e.message ?? 'Purchase failed.';
    } catch (_) {
      return 'Purchase failed — try again.';
    }
  }

  static Future<String?> restore() async {
    if (!purchasesSupported) return 'Restore is available on iPhone and Android.';
    try {
      await Purchases.restorePurchases();
      await refresh();
      return active ? null : 'No SI subscription found on this store account.';
    } catch (_) {
      return 'Could not reach the store — try again.';
    }
  }

  // ── phone verification (backend /v1/phone, SPEC §4.1) ─────────────────────

  static Map<String, String> _auth(Session s) => {
        'authorization': 'Bearer ${s.accessToken}',
        'content-type': 'application/json',
      };

  static Future<void> _loadPhone(Session s) async {
    try {
      final r = await http.get(Uri.parse('${KeyviewApi.base}/v1/phone'),
          headers: _auth(s)).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        phone.value = (jsonDecode(r.body) as Map)['phone'] as String?;
      }
    } catch (_) { /* leave as-is */ }
  }

  /// Returns null on success, a short human message otherwise.
  static Future<String?> sendCode(String rawPhone) async {
    final s = await KeyviewAuth.ensureFresh() ?? KeyviewAuth.session.value;
    if (s == null) return 'Please sign in first.';
    try {
      final r = await http
          .post(Uri.parse('${KeyviewApi.base}/v1/phone/start'),
              headers: _auth(s), body: jsonEncode({'phone': rawPhone}))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) return null;
      final err = _err(r.body);
      if (r.statusCode == 409) return 'That number is verified on another account.';
      if (r.statusCode == 429) return err ?? 'Too many codes — try again later.';
      if (r.statusCode == 400) return 'That does not look like a phone number.';
      return err ?? 'Could not send the code (HTTP ${r.statusCode}).';
    } catch (_) {
      return 'Network error — try again.';
    }
  }

  static Future<String?> verifyCode(String rawPhone, String code) async {
    final s = await KeyviewAuth.ensureFresh() ?? KeyviewAuth.session.value;
    if (s == null) return 'Please sign in first.';
    try {
      final r = await http
          .post(Uri.parse('${KeyviewApi.base}/v1/phone/verify'),
              headers: _auth(s), body: jsonEncode({'phone': rawPhone, 'code': code}))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        phone.value = (jsonDecode(r.body) as Map)['phone'] as String?;
        return null;
      }
      if (r.statusCode == 401) return 'Wrong code.';
      return _err(r.body) ?? 'Could not verify (HTTP ${r.statusCode}).';
    } catch (_) {
      return 'Network error — try again.';
    }
  }

  static Future<bool> removePhone() async {
    final s = await KeyviewAuth.ensureFresh() ?? KeyviewAuth.session.value;
    if (s == null) return false;
    try {
      final r = await http.delete(Uri.parse('${KeyviewApi.base}/v1/phone'),
          headers: _auth(s)).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        phone.value = null;
        return true;
      }
    } catch (_) { /* fall through */ }
    return false;
  }

  static String? _err(String body) {
    try {
      final e = (jsonDecode(body) as Map)['error'];
      return e is String && e.isNotEmpty ? e[0].toUpperCase() + e.substring(1) : null;
    } catch (_) {
      return null;
    }
  }
}
