import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api.dart';
import 'auth.dart';
import 'supabase_config.dart';

/// Device registration + the notifications feed (spec §4.5, §11 "Record").
///
/// The FCM token itself comes from the platform (firebase_messaging on mobile,
/// an OS notifier on desktop). That plugin is added during Phase 3 packaging,
/// so this layer takes a token as input rather than fetching it — which also
/// makes the whole thing testable with no Firebase project attached.
class PushService {
  static const _deviceTable = 'device';
  static const _logTable = 'notification_log';

  /// Platforms the `device` table accepts (schema.sql check constraint).
  static const platforms = {'ios', 'android', 'windows', 'macos'};

  static Map<String, String> _headers(Session s) => {
        'apikey': SupabaseConfig.anonKey,
        'authorization': 'Bearer ${s.accessToken}',
        'content-type': 'application/json',
      };

  /// Save (or refresh) this device's push token.
  ///
  /// Upserts on (user_id, push_token) — the table's unique constraint — so a
  /// re-registration after an app restart updates the row instead of piling up
  /// duplicates that would each get their own copy of every notification.
  static Future<bool> registerDevice(
      Session s, String platform, String pushToken) async {
    if (!platforms.contains(platform) || pushToken.trim().isEmpty) return false;
    try {
      final r = await http
          .post(
            Uri.parse('${SupabaseConfig.url}/rest/v1/$_deviceTable'
                '?on_conflict=user_id,push_token'),
            headers: {
              ..._headers(s),
              'prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: jsonEncode({
              'user_id': s.userId,
              'platform': platform,
              'push_token': pushToken.trim(),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Remove this device's token — on sign-out, or when the user turns
  /// notifications off. Leaving it behind means the backend keeps paying to
  /// push at a device that should be silent.
  static Future<bool> unregisterDevice(Session s, String pushToken) async {
    if (pushToken.trim().isEmpty) return false;
    try {
      final r = await http
          .delete(
              Uri.parse('${SupabaseConfig.url}/rest/v1/$_deviceTable'
                  '?push_token=eq.${Uri.encodeComponent(pushToken.trim())}'),
              headers: _headers(s))
          .timeout(const Duration(seconds: 15));
      return r.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  /// The in-app notifications feed, newest first.
  static Future<List<NotificationEntry>> feed(Session s, {int limit = 100}) async {
    final r = await http
        .get(
            Uri.parse('${SupabaseConfig.url}/rest/v1/$_logTable'
                '?select=id,address,tx_hash,summary,fired_at'
                '&order=fired_at.desc&limit=$limit'),
            headers: _headers(s))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    return (jsonDecode(r.body) as List)
        .map((e) => NotificationEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Ask the backend to start (or stop) watching an address on-chain.
  /// Ref-counting lives server-side; the client just announces intent.
  static Future<bool> setMonitoring(
      Session s, String address, {required bool on}) async {
    try {
      final r = await http
          .post(Uri.parse('${KeyviewApi.base}/v1/monitor'),
              headers: {
                'authorization': 'Bearer ${s.accessToken}',
                'content-type': 'application/json',
              },
              body: jsonEncode({
                'address': address,
                'action': on ? 'register' : 'unregister',
              }))
          .timeout(const Duration(seconds: 20));
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}

class NotificationEntry {
  final String id, address, summary;
  final String? txHash;
  final DateTime? firedAt;

  const NotificationEntry({
    required this.id,
    required this.address,
    required this.summary,
    this.txHash,
    this.firedAt,
  });

  factory NotificationEntry.fromJson(Map<String, dynamic> j) => NotificationEntry(
        id: j['id'] as String? ?? '',
        address: j['address'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        txHash: j['tx_hash'] as String?,
        firedAt: DateTime.tryParse(j['fired_at'] as String? ?? '')?.toLocal(),
      );

  String get shortAddress => address.length > 14
      ? '${address.substring(0, 6)}…${address.substring(address.length - 4)}'
      : address;
}

/// Pure formatting for the feed — testable without a Flutter binding.
class FeedFormat {
  /// "just now" / "12m ago" / "3h ago" / "yesterday" / "Jul 24".
  /// Deliberately coarse: an exact timestamp is noise in a scroll list, and the
  /// transaction itself is one tap away.
  static String relative(DateTime? when, DateTime now) {
    if (when == null) return '';
    final d = now.difference(when);
    if (d.isNegative) return 'just now'; // clock skew — never say "in 3 minutes"
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays == 1) return 'yesterday';
    if (d.inDays < 7) return '${d.inDays}d ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[when.month - 1]} ${when.day}';
  }

  /// Group feed entries under day headings, newest day first.
  static List<FeedSection> groupByDay(
      List<NotificationEntry> items, DateTime now) {
    final out = <FeedSection>[];
    String? currentKey;
    for (final e in items) {
      final w = e.firedAt;
      final key = w == null
          ? 'Earlier'
          : _dayLabel(DateTime(w.year, w.month, w.day),
              DateTime(now.year, now.month, now.day));
      if (key != currentKey) {
        out.add(FeedSection(key, []));
        currentKey = key;
      }
      out.last.entries.add(e);
    }
    return out;
  }

  static String _dayLabel(DateTime day, DateTime today) {
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '$diff days ago';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[day.month - 1]} ${day.day}';
  }
}

class FeedSection {
  final String label;
  final List<NotificationEntry> entries;
  const FeedSection(this.label, this.entries);
}
