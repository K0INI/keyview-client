import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth.dart';
import 'supabase_config.dart';

/// Watchlist CRUD straight against Supabase PostgREST — row-level security
/// ("own watched" policy + 50-cap trigger, schema.sql) does the enforcement,
/// so no Worker round-trip is needed.
class WatchedAddress {
  final String id, address, chainKind;
  final String? label;
  const WatchedAddress(this.id, this.address, this.chainKind, this.label);

  factory WatchedAddress.fromJson(Map<String, dynamic> j) => WatchedAddress(
      j['id'] as String? ?? '',
      j['address'] as String? ?? '',
      j['chain_kind'] as String? ?? 'evm',
      j['label'] as String?);
}

class WatchlistService {
  static const _table = 'watched_address';

  static Map<String, String> _headers(Session s) => {
        'apikey': SupabaseConfig.anonKey,
        'authorization': 'Bearer ${s.accessToken}',
        'content-type': 'application/json',
      };

  static Future<List<WatchedAddress>> list(Session s) async {
    final r = await http
        .get(
            Uri.parse('${SupabaseConfig.url}/rest/v1/$_table'
                '?select=id,address,chain_kind,label&order=created_at.desc'),
            headers: _headers(s))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    return (jsonDecode(r.body) as List)
        .map((e) => WatchedAddress.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Null on success, or a friendly error message.
  static Future<String?> add(Session s, String address, {String? label}) async {
    final kind = address.endsWith('.eth') || address.startsWith('0x')
        ? 'evm'
        : 'solana';
    try {
      final r = await http
          .post(Uri.parse('${SupabaseConfig.url}/rest/v1/$_table'),
              headers: _headers(s),
              body: jsonEncode({
                'user_id': s.userId,
                'address': address,
                'chain_kind': kind,
                if (label != null && label.isNotEmpty) 'label': label,
              }))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 201) return null;
      if (r.statusCode == 409) return 'Already on your watchlist.';
      final msg = r.body;
      if (msg.contains('fair-use cap')) {
        return 'Watchlist cap reached (50 addresses).';
      }
      return 'Could not add (HTTP ${r.statusCode}).';
    } catch (_) {
      return 'Network error — try again.';
    }
  }

  static Future<bool> remove(Session s, String id) async {
    try {
      final r = await http
          .delete(Uri.parse('${SupabaseConfig.url}/rest/v1/$_table?id=eq.$id'),
              headers: _headers(s))
          .timeout(const Duration(seconds: 15));
      return r.statusCode == 204;
    } catch (_) {
      return false;
    }
  }
}
