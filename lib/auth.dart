import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'supabase_config.dart';

/// Email + 6-digit-code sign-in against Supabase auth (GoTrue) REST.
/// No SDK dependency, no deep links — a code the user types beats a
/// magic link on desktop and in store review. Session lives in memory
/// for now; persistence arrives with the settings screen.
class Session {
  final String accessToken, refreshToken, userId, email;
  const Session(this.accessToken, this.refreshToken, this.userId, this.email);
}

class KeyviewAuth {
  static final ValueNotifier<Session?> session = ValueNotifier(null);
  static bool get signedIn => session.value != null;

  static Map<String, String> get _headers => {
        'apikey': SupabaseConfig.anonKey,
        'content-type': 'application/json',
      };

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
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final user = j['user'] as Map<String, dynamic>? ?? {};
        session.value = Session(
          j['access_token'] as String? ?? '',
          j['refresh_token'] as String? ?? '',
          user['id'] as String? ?? '',
          user['email'] as String? ?? email,
        );
        return null;
      }
      return _errorFrom(r.body);
    } catch (_) {
      return 'Network error — try again.';
    }
  }

  static void signOut() => session.value = null;

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
