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
  final List<String> tags;
  final int sortOrder;

  const WatchedAddress(
    this.id,
    this.address,
    this.chainKind,
    this.label, {
    this.tags = const [],
    this.sortOrder = 0,
  });

  /// What the row should be called in the UI: the user's label if they set one,
  /// otherwise a truncated address.
  String get displayName =>
      (label != null && label!.trim().isNotEmpty) ? label!.trim() : shortAddress;

  String get shortAddress => address.length > 14
      ? '${address.substring(0, 6)}…${address.substring(address.length - 4)}'
      : address;

  factory WatchedAddress.fromJson(Map<String, dynamic> j) => WatchedAddress(
        j['id'] as String? ?? '',
        j['address'] as String? ?? '',
        j['chain_kind'] as String? ?? 'evm',
        j['label'] as String?,
        tags: parseTags(j['tags']),
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );

  /// Postgres `text[]` arrives as a JSON list. Be forgiving: a driver or a
  /// hand-edited row can hand back a single string or nulls inside the list.
  static List<String> parseTags(Object? raw) {
    if (raw is List) {
      return raw
          .map((e) => (e ?? '').toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) return [raw.trim()];
    return const [];
  }

  /// Split a comma-separated tag field into clean, de-duplicated tags.
  /// Case-insensitive de-dup, but the first spelling the user typed is kept.
  static List<String> splitTagInput(String input, {int max = 6}) {
    final seen = <String>{};
    final out = <String>[];
    for (final part in input.split(',')) {
      final t = part.trim();
      if (t.isEmpty) continue;
      if (!seen.add(t.toLowerCase())) continue;
      out.add(t);
      if (out.length >= max) break;
    }
    return out;
  }

  WatchedAddress copyWith({String? label, List<String>? tags, int? sortOrder}) =>
      WatchedAddress(
        id,
        address,
        chainKind,
        label ?? this.label,
        tags: tags ?? this.tags,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

class WatchlistService {
  static const _table = 'watched_address';

  static Map<String, String> _headers(Session s) => {
        'apikey': SupabaseConfig.anonKey,
        'authorization': 'Bearer ${s.accessToken}',
        'content-type': 'application/json',
      };

  static const _select = 'id,address,chain_kind,label,tags,sort_order';

  /// Explicit order first, newest-first as the tiebreak. New rows default to
  /// sort_order 0, so an untouched list still reads newest-first; once the user
  /// drags anything, their order wins.
  static Future<List<WatchedAddress>> list(Session s) async {
    final r = await http
        .get(
            Uri.parse('${SupabaseConfig.url}/rest/v1/$_table'
                '?select=$_select&order=sort_order.asc,created_at.desc'),
            headers: _headers(s))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    return (jsonDecode(r.body) as List)
        .map((e) => WatchedAddress.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Null on success, or a friendly error message.
  static Future<String?> add(Session s, String address,
      {String? label, List<String> tags = const []}) async {
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
                if (label != null && label.trim().isNotEmpty)
                  'label': label.trim(),
                if (tags.isNotEmpty) 'tags': tags,
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

  /// Rename and/or re-tag one entry. Passing an empty label clears it, which is
  /// why `label` is sent even when blank — the row falls back to the address.
  static Future<bool> update(Session s, String id,
      {String? label, List<String>? tags}) async {
    final body = <String, Object?>{};
    if (label != null) body['label'] = label.trim().isEmpty ? null : label.trim();
    if (tags != null) body['tags'] = tags;
    if (body.isEmpty) return true;
    try {
      final r = await http
          .patch(Uri.parse('${SupabaseConfig.url}/rest/v1/$_table?id=eq.$id'),
              headers: _headers(s), body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      return r.statusCode == 204 || r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Persist a whole new ordering in ONE request.
  ///
  /// PostgREST upsert (POST + `resolution=merge-duplicates`) needs every row to
  /// carry the same keys and every NOT NULL column, so user_id/address/
  /// chain_kind ride along. label and tags are included too — omitting them
  /// here would be a silent data-loss bug on the update path.
  static Future<bool> reorder(Session s, List<WatchedAddress> ordered) async {
    if (ordered.isEmpty) return true;
    final payload = <Map<String, Object?>>[];
    for (var i = 0; i < ordered.length; i++) {
      final w = ordered[i];
      payload.add({
        'id': w.id,
        'user_id': s.userId,
        'address': w.address,
        'chain_kind': w.chainKind,
        'label': w.label,
        'tags': w.tags,
        'sort_order': i,
      });
    }
    try {
      final r = await http
          .post(Uri.parse('${SupabaseConfig.url}/rest/v1/$_table'),
              headers: {
                ..._headers(s),
                'prefer': 'resolution=merge-duplicates,return=minimal',
              },
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 20));
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (_) {
      return false;
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

/// Pure list helpers — kept out of the widget so they can be unit-tested
/// without a Flutter binding or a network.
class WatchlistOrdering {
  /// Move [oldIndex] to [newIndex] using ReorderableListView's convention:
  /// when dragging downward the framework reports an index that already counts
  /// the removed row, so it must be decremented first. Getting this wrong is
  /// the classic off-by-one that makes downward drags land one slot short.
  static List<T> move<T>(List<T> items, int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= items.length) return List<T>.from(items);
    final out = List<T>.from(items);
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0) target = 0;
    if (target > out.length - 1) target = out.length - 1;
    final item = out.removeAt(oldIndex);
    out.insert(target, item);
    return out;
  }

  /// Pin to the top: the entry moves to index 0 and everything else shifts down.
  static List<T> pinToTop<T>(List<T> items, int index) => move(items, index, 0);

  /// Every distinct tag across the list, in first-seen order — the grouping
  /// filter's source of truth.
  static List<String> allTags(Iterable<WatchedAddress> items) {
    final seen = <String>{};
    final out = <String>[];
    for (final w in items) {
      for (final t in w.tags) {
        if (seen.add(t.toLowerCase())) out.add(t);
      }
    }
    return out;
  }

  /// Filter by tag, case-insensitively. A null/empty tag means "show all".
  static List<WatchedAddress> filterByTag(
      List<WatchedAddress> items, String? tag) {
    if (tag == null || tag.isEmpty) return items;
    final needle = tag.toLowerCase();
    return items
        .where((w) => w.tags.any((t) => t.toLowerCase() == needle))
        .toList();
  }
}
