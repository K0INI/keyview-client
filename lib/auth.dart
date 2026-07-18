import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_config.dart';

/// Email + 6-digit-code sign-in against Supabase auth (GoTrue) REST.
/// No SDK dependency, no deep links — a code the user types beats a
/// magic link on desktop and in store review. Sessions persist locally
/// (shared_preferences) and refresh themselves before they expire.
class Session {
  final String accessToken, refreshToken, userId, email;
  final int expiresAtMs; // epoch millis; 0 = unknown (treated as stale)
  const Session(this.accessToken, this.refreshToken, this.userId, this.email,
      [this.expiresAtMs = 0]);

  /// True when within 60s of expiry (or expiry is unknown).
  bool get stale =>
      DateTime.now().millisecondsSinceEpoch > expiresAtMs - 60 * 1000;

  Map<String, dynamic> toJson() => {
        'access': accessToken,
        'refresh': refreshToken,
        'uid': userId,
        'email': email,
        'exp': expiresAtMs,
      };

  static Session? fromJson(Map<String, dynamic> j) {
    final access = j['access'] as String? ?? '';
    final refresh = j['refresh'] as String? ?? '';
    if (access.isEmpty || refresh.isEmpty) return null;
    return Session(access, refresh, j['uid'] as String? ?? '',
        j['email'] as String? ?? '', j['exp'] as int? ?? 0);
  }
}

class KeyviewAuth {
  static const _storeKey = 'kv.session.v1';
  static final ValueNotifier<Session?> session = ValueNotifier(null);
  static bool get signedIn => session.value != null;

  static Map<String, String> get _headers => {
        'apikey': SupabaseConfig.anonKey,
        'content-type': 'application/json',
      };

  /// Load the stored session at startup. Local read only — the app opens
  /// instantly; a stale token refreshes in the background.
  static Future<void> restore() async {
    if (!SupabaseConfig.enabled) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storeKey);
      if (raw == null) return;
      final s = Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (s == null) return;
      session.value = s;
      if (s.stale) unawaited(refresh());
    } catch (_) {/* a broken store must never block startup */}
  }

  /// Session with ≥60s of life, refreshing first when needed.
  /// Null = signed out or refresh unavailable right now.
  static Future<Session?> ensureFresh() async {
    final s = session.value;
    if (s == null) return null;
    if (!s.stale) return s;
    return refresh();
  }

  /// Swap the refresh token for a new access token. Signs out when the
  /// server says the grant is gone (revoked / already rotated); keeps the
  /// session on transient network failures.
  static Future<Session?> refresh() async {
    final s = session.value;
    if (s == null) return null;
    try {
      final r = await http
          .post(
              Uri.parse(
                  '${SupabaseConfig.url}/auth/v1/token?grant_type=refresh_token'),
              headers: _headers,
              body: jsonEncode({'refresh_token': s.refreshToken}))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        _store(jsonDecode(r.body) as Map<String, dynamic>,
            fallbackEmail: s.email);
        return session.value;
      }
      if (r.statusCode == 400 || r.statusCode == 401) signOut();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Sends the 6-digit code. Returns null on success, or an error message.
  static Future<String?> sendCode(String email) async {
    if (!SupabaseConfig.enabled) return 'Accounts arrive in Beta.';
    try {
      final r = await http
          .post(Uri.parse('${SupabaseConfig.url}/auth/v1/otp'),
              headers: _headers,
              body: jsonEncode({'email': email, 'create_user': true}))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) return null;
      return _errorFrom(r.body);
    } catch (_) {
      return 'Network error — try again.';
    }
  }

  /// Verifies the code and stores the session. Null on success.
  static Future<String?> verifyCode(String email, String code) async {
    if (!SupabaseConfig.enabled) return 'Accounts arrive in Beta.';
    try {
      final r = await http
          .post(Uri.parse('${SupabaseConfig.url}/auth/v1/verify'),
              headers: _headers,
              body: jsonEncode(
                  {'type': 'email', 'email': email, 'token': code.trim()}))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        _store(jsonDecode(r.body) as Map<String, dynamic>,
            fallbackEmail: email);
        return null;
      }
      return _errorFrom(r.body);
    } catch (_) {
      return 'Network error — try again.';
    }
  }

  static void _store(Map<String, dynamic> j, {required String fallbackEmail}) {
    final user = j['user'] as Map<String, dynamic>? ?? {};
    final ttlS = j['expires_in'] as int? ?? 3600;
    session.value = Session(
      j['access_token'] as String? ?? '',
      j['refresh_token'] as String? ?? '',
      user['id'] as String? ?? '',
      user['email'] as String? ?? fallbackEmail,
      DateTime.now().millisecondsSinceEpoch + ttlS * 1000,
    );
    unawaited(_persist());
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = session.value;
      if (s == null) {
        await prefs.remove(_storeKey);
      } else {
        await prefs.setString(_storeKey, jsonEncode(s.toJson()));
      }
    } catch (_) {/* persistence is best-effort */}
  }

  static void signOut() {
    session.value = null;
    unawaited(_persist());
  }

  static String _errorFrom(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      return (j['msg'] ??
              j['error_description'] ??
              j['message'] ??
              'Something went wrong')
          .toString();
    } catch (_) {
      return 'Something went wrong';
    }
  }
}
