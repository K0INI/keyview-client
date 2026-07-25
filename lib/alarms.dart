import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth.dart';
import 'supabase_config.dart';

/// Alarm settings for one watched address (spec §4.5, defaults §20.5).
///
/// Field names and JSON shapes mirror `alarm` in schema.sql exactly, because
/// the backend pipeline (keyview-backend/src/alarms.ts) reads these rows
/// directly. Renaming anything here silently breaks notification delivery.
class Alarm {
  static const dirAll = 'all';
  static const dirIn = 'in';
  static const dirOut = 'out';

  /// The spec's one-tap night preset (§20.5).
  static const defaultQuietPreset = '22:00-07:00';

  final String? id;
  final String watchedAddressId;
  final String direction;
  final double? valueThresholdUsd;
  final String tokenFilter;
  final bool spamFilter;
  final bool enabled;
  final bool batchingEnabled;
  final int batchingWindowMin;
  final bool loneEventImmediate;
  final bool quietHoursEnabled;
  final String quietPreset;
  final int tzOffsetMin;

  const Alarm({
    this.id,
    required this.watchedAddressId,
    this.direction = dirAll,
    this.valueThresholdUsd,
    this.tokenFilter = 'all',
    this.spamFilter = true,
    this.enabled = true,
    this.batchingEnabled = true,
    this.batchingWindowMin = 10,
    this.loneEventImmediate = true,
    this.quietHoursEnabled = false,
    this.quietPreset = defaultQuietPreset,
    this.tzOffsetMin = 0,
  });

  /// The locked defaults from spec §20.5: batching on with a 10-minute digest
  /// window, a lone event still fires immediately, spam filter on, direction
  /// all, no value threshold, quiet hours off with the 22:00–07:00 preset ready.
  factory Alarm.withDefaults(String watchedAddressId, {int tzOffsetMin = 0}) =>
      Alarm(watchedAddressId: watchedAddressId, tzOffsetMin: tzOffsetMin);

  factory Alarm.fromJson(Map<String, dynamic> j) {
    final b = _asMap(j['batching']);
    final q = _asMap(j['quiet_hours']);
    return Alarm(
      id: j['id'] as String?,
      watchedAddressId: j['watched_address_id'] as String? ?? '',
      direction: _validDirection(j['direction'] as String?),
      valueThresholdUsd: (j['value_threshold_usd'] as num?)?.toDouble(),
      tokenFilter: (j['token_filter'] as String?)?.trim().isNotEmpty == true
          ? (j['token_filter'] as String).trim()
          : 'all',
      spamFilter: j['spam_filter'] != false,
      enabled: j['enabled'] != false,
      batchingEnabled: b['enabled'] != false,
      batchingWindowMin: (b['window_min'] as num?)?.toInt() ?? 10,
      loneEventImmediate: b['lone_event_immediate'] != false,
      quietHoursEnabled: q['enabled'] == true,
      quietPreset: (q['preset'] as String?) ?? defaultQuietPreset,
      tzOffsetMin: (q['tz_offset_min'] as num?)?.toInt() ?? 0,
    );
  }

  /// jsonb columns can come back as a Map or, from some drivers, a JSON string.
  static Map<String, dynamic> _asMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) return d.map((k, v) => MapEntry(k.toString(), v));
      } catch (_) { /* fall through to empty */ }
    }
    return const {};
  }

  static String _validDirection(String? d) =>
      (d == dirIn || d == dirOut) ? d! : dirAll;

  Map<String, Object?> toJson() => {
        'watched_address_id': watchedAddressId,
        'direction': direction,
        'value_threshold_usd': valueThresholdUsd,
        'token_filter': tokenFilter,
        'spam_filter': spamFilter,
        'enabled': enabled,
        'batching': {
          'enabled': batchingEnabled,
          'window_min': batchingWindowMin,
          'lone_event_immediate': loneEventImmediate,
        },
        'quiet_hours': {
          'enabled': quietHoursEnabled,
          'preset': quietPreset,
          'tz_offset_min': tzOffsetMin,
        },
      };

  Alarm copyWith({
    String? direction,
    double? valueThresholdUsd,
    bool clearThreshold = false,
    String? tokenFilter,
    bool? spamFilter,
    bool? enabled,
    bool? batchingEnabled,
    int? batchingWindowMin,
    bool? loneEventImmediate,
    bool? quietHoursEnabled,
    String? quietPreset,
    int? tzOffsetMin,
  }) =>
      Alarm(
        id: id,
        watchedAddressId: watchedAddressId,
        direction: direction ?? this.direction,
        valueThresholdUsd:
            clearThreshold ? null : (valueThresholdUsd ?? this.valueThresholdUsd),
        tokenFilter: tokenFilter ?? this.tokenFilter,
        spamFilter: spamFilter ?? this.spamFilter,
        enabled: enabled ?? this.enabled,
        batchingEnabled: batchingEnabled ?? this.batchingEnabled,
        batchingWindowMin: batchingWindowMin ?? this.batchingWindowMin,
        loneEventImmediate: loneEventImmediate ?? this.loneEventImmediate,
        quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
        quietPreset: quietPreset ?? this.quietPreset,
        tzOffsetMin: tzOffsetMin ?? this.tzOffsetMin,
      );

  /// One-line plain-English description of what this alarm will do.
  /// Shown under the address so the settings never have to be decoded.
  String get summary {
    if (!enabled) return 'Alarm off';
    final parts = <String>[];
    if (direction == dirIn) {
      parts.add('Incoming only');
    } else if (direction == dirOut) {
      parts.add('Outgoing only');
    } else {
      parts.add('All activity');
    }
    if (valueThresholdUsd != null) {
      parts.add('over ${AlarmFormat.usd(valueThresholdUsd!)}');
    }
    if (tokenFilter != 'all') parts.add('· $tokenFilter');
    if (batchingEnabled) parts.add('· grouped every ${batchingWindowMin}m');
    if (quietHoursEnabled) parts.add('· quiet $quietPreset');
    return parts.join(' ');
  }
}

/// Pure formatting + parsing helpers, kept separate so they unit-test without
/// a Flutter binding.
class AlarmFormat {
  static String usd(double v) {
    if (v >= 1000000) return '\$${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '\$${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
    if (v == v.roundToDouble()) return '\$${v.toStringAsFixed(0)}';
    return '\$${v.toStringAsFixed(2)}';
  }

  /// Parse the threshold field. Empty means "no threshold" (null), which is the
  /// §20.5 default. Anything unparseable or negative is rejected outright
  /// rather than silently becoming 0 — a 0 threshold would pass everything and
  /// look like the feature is broken.
  static ThresholdResult parseThreshold(String input) {
    final t = input.trim().replaceAll(',', '').replaceAll('\$', '');
    if (t.isEmpty) return const ThresholdResult(value: null, ok: true);
    final v = double.tryParse(t);
    if (v == null) return const ThresholdResult(ok: false, error: 'Enter a number, or leave blank.');
    if (v < 0) return const ThresholdResult(ok: false, error: 'Must be zero or more.');
    if (v == 0) return const ThresholdResult(value: null, ok: true); // 0 == off
    return ThresholdResult(value: v, ok: true);
  }

  /// Normalise the token filter box. Blank or "all" means every token.
  static String parseTokenFilter(String input, {int max = 10}) {
    final t = input.trim();
    if (t.isEmpty || t.toLowerCase() == 'all') return 'all';
    final seen = <String>{};
    final out = <String>[];
    for (final part in t.split(',')) {
      final p = part.trim();
      if (p.isEmpty) continue;
      if (!seen.add(p.toLowerCase())) continue;
      out.add(p);
      if (out.length >= max) break;
    }
    return out.isEmpty ? 'all' : out.join(',');
  }

  /// "22:00-07:00" → "10:00 PM – 7:00 AM" for display.
  static String prettyPreset(String preset) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})$').firstMatch(preset);
    if (m == null) return preset;
    String h12(int h, int mi) {
      final ampm = h < 12 ? 'AM' : 'PM';
      var hh = h % 12;
      if (hh == 0) hh = 12;
      return mi == 0 ? '$hh:00 $ampm' : '$hh:${mi.toString().padLeft(2, '0')} $ampm';
    }
    return '${h12(int.parse(m.group(1)!), int.parse(m.group(2)!))} – '
        '${h12(int.parse(m.group(3)!), int.parse(m.group(4)!))}';
  }

  static String preset(int startHour, int endHour) =>
      '${startHour.toString().padLeft(2, '0')}:00-'
      '${endHour.toString().padLeft(2, '0')}:00';
}

class ThresholdResult {
  final double? value;
  final bool ok;
  final String? error;
  const ThresholdResult({this.value, required this.ok, this.error});
}

class AlarmService {
  static const _table = 'alarm';

  static Map<String, String> _headers(Session s) => {
        'apikey': SupabaseConfig.anonKey,
        'authorization': 'Bearer ${s.accessToken}',
        'content-type': 'application/json',
      };

  static const _select =
      'id,watched_address_id,direction,value_threshold_usd,token_filter,'
      'spam_filter,enabled,batching,quiet_hours';

  /// The alarm for one watched address, or null when none has been set.
  static Future<Alarm?> forAddress(Session s, String watchedAddressId) async {
    final r = await http
        .get(
            Uri.parse('${SupabaseConfig.url}/rest/v1/$_table'
                '?select=$_select&watched_address_id=eq.$watchedAddressId&limit=1'),
            headers: _headers(s))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final rows = jsonDecode(r.body) as List;
    if (rows.isEmpty) return null;
    return Alarm.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Create or update. Returns null on success, or a friendly error message.
  static Future<String?> save(Session s, Alarm a) async {
    try {
      final isUpdate = a.id != null && a.id!.isNotEmpty;
      final uri = isUpdate
          ? Uri.parse('${SupabaseConfig.url}/rest/v1/$_table?id=eq.${a.id}')
          : Uri.parse('${SupabaseConfig.url}/rest/v1/$_table');
      final body = jsonEncode(a.toJson());
      final r = isUpdate
          ? await http
              .patch(uri, headers: _headers(s), body: body)
              .timeout(const Duration(seconds: 15))
          : await http
              .post(uri, headers: _headers(s), body: body)
              .timeout(const Duration(seconds: 15));
      if (r.statusCode >= 200 && r.statusCode < 300) return null;
      if (r.body.contains('fair-use cap')) return 'Alarm cap reached (50).';
      return 'Could not save (HTTP ${r.statusCode}).';
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
