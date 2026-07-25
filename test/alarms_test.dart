// Alarm model + formatting tests. Pure logic, no network, no Flutter binding.
// The JSON shapes here must stay identical to `alarm` in schema.sql, because
// keyview-backend/src/alarms.ts reads those rows directly.

import 'package:flutter_test/flutter_test.dart';
import 'package:keyview/alarms.dart';

void main() {
  group('spec §20.5 defaults', () {
    final a = Alarm.withDefaults('wa-1');

    test('batching on, 10-minute window, lone events still immediate', () {
      expect(a.batchingEnabled, isTrue);
      expect(a.batchingWindowMin, 10);
      expect(a.loneEventImmediate, isTrue);
    });

    test('spam filter on, direction all, no threshold', () {
      expect(a.spamFilter, isTrue);
      expect(a.direction, Alarm.dirAll);
      expect(a.valueThresholdUsd, isNull);
      expect(a.tokenFilter, 'all');
    });

    test('quiet hours off, but the 22:00–07:00 preset is ready', () {
      expect(a.quietHoursEnabled, isFalse);
      expect(a.quietPreset, '22:00-07:00');
    });

    test('the alarm itself is enabled', () => expect(a.enabled, isTrue));
  });

  group('json round-trip', () {
    test('serialises the exact shape schema.sql expects', () {
      final j = Alarm.withDefaults('wa-1', tzOffsetMin: -300).toJson();
      expect(j['watched_address_id'], 'wa-1');
      expect(j['direction'], 'all');
      expect(j['token_filter'], 'all');
      expect(j['spam_filter'], true);
      final b = j['batching'] as Map;
      expect(b['enabled'], true);
      expect(b['window_min'], 10);
      expect(b['lone_event_immediate'], true);
      final q = j['quiet_hours'] as Map;
      expect(q['enabled'], false);
      expect(q['preset'], '22:00-07:00');
      expect(q['tz_offset_min'], -300);
    });

    test('reads a row back', () {
      final a = Alarm.fromJson({
        'id': 'al-1',
        'watched_address_id': 'wa-9',
        'direction': 'in',
        'value_threshold_usd': 2500,
        'token_filter': 'ETH,USDC',
        'spam_filter': false,
        'enabled': true,
        'batching': {'enabled': false, 'window_min': 30, 'lone_event_immediate': false},
        'quiet_hours': {'enabled': true, 'preset': '23:00-06:00', 'tz_offset_min': 60},
      });
      expect(a.id, 'al-1');
      expect(a.direction, 'in');
      expect(a.valueThresholdUsd, 2500.0);
      expect(a.spamFilter, isFalse);
      expect(a.batchingWindowMin, 30);
      expect(a.quietHoursEnabled, isTrue);
      expect(a.tzOffsetMin, 60);
    });

    test('survives jsonb arriving as a string', () {
      final a = Alarm.fromJson({
        'watched_address_id': 'wa-1',
        'batching': '{"enabled":false,"window_min":15}',
        'quiet_hours': '{"enabled":true,"preset":"21:00-08:00"}',
      });
      expect(a.batchingEnabled, isFalse);
      expect(a.batchingWindowMin, 15);
      expect(a.quietPreset, '21:00-08:00');
    });

    test('missing or junk fields fall back to the safe defaults', () {
      final a = Alarm.fromJson({'watched_address_id': 'wa-1'});
      expect(a.direction, 'all');
      expect(a.batchingWindowMin, 10);
      expect(a.spamFilter, isTrue);
      expect(a.quietPreset, '22:00-07:00');
      // An unknown direction must not reach the backend filter.
      expect(Alarm.fromJson({'direction': 'sideways'}).direction, 'all');
    });
  });

  group('threshold parsing', () {
    test('blank means no threshold — the default', () {
      final r = AlarmFormat.parseThreshold('');
      expect(r.ok, isTrue);
      expect(r.value, isNull);
    });

    test('accepts plain numbers, commas and a dollar sign', () {
      expect(AlarmFormat.parseThreshold('2500').value, 2500);
      expect(AlarmFormat.parseThreshold('2,500').value, 2500);
      expect(AlarmFormat.parseThreshold(r'$2,500.50').value, 2500.50);
    });

    test('zero is treated as off, not as a threshold of zero', () {
      // A literal 0 threshold would pass everything and read as a broken filter.
      final r = AlarmFormat.parseThreshold('0');
      expect(r.ok, isTrue);
      expect(r.value, isNull);
    });

    test('rejects nonsense and negatives instead of coercing', () {
      expect(AlarmFormat.parseThreshold('abc').ok, isFalse);
      expect(AlarmFormat.parseThreshold('-5').ok, isFalse);
      expect(AlarmFormat.parseThreshold('abc').error, isNotNull);
    });
  });

  group('token filter parsing', () {
    test('blank or "all" means every token', () {
      expect(AlarmFormat.parseTokenFilter(''), 'all');
      expect(AlarmFormat.parseTokenFilter('  '), 'all');
      expect(AlarmFormat.parseTokenFilter('All'), 'all');
    });

    test('trims, de-dupes case-insensitively, keeps first spelling', () {
      expect(AlarmFormat.parseTokenFilter(' ETH , usdc, eth '), 'ETH,usdc');
    });

    test('a list of only separators degrades to all', () {
      expect(AlarmFormat.parseTokenFilter(', , ,'), 'all');
    });
  });

  group('display', () {
    test('formats dollars at each magnitude', () {
      expect(AlarmFormat.usd(50), r'$50');
      expect(AlarmFormat.usd(2500), r'$2.5k');
      expect(AlarmFormat.usd(3000), r'$3k');
      expect(AlarmFormat.usd(2500000), r'$2.5M');
      expect(AlarmFormat.usd(12.5), r'$12.50');
    });

    test('renders the quiet preset in plain 12-hour time', () {
      expect(AlarmFormat.prettyPreset('22:00-07:00'), '10:00 PM – 7:00 AM');
      expect(AlarmFormat.prettyPreset('00:30-12:00'), '12:30 AM – 12:00 PM');
    });

    test('leaves an unparseable preset alone rather than crashing', () {
      expect(AlarmFormat.prettyPreset('nonsense'), 'nonsense');
    });

    test('builds a preset from two hours', () {
      expect(AlarmFormat.preset(22, 7), '22:00-07:00');
      expect(AlarmFormat.preset(9, 17), '09:00-17:00');
    });

    test('summary reads as plain English', () {
      expect(Alarm.withDefaults('w').summary,
          'All activity · grouped every 10m');
      final tuned = Alarm.withDefaults('w').copyWith(
          direction: Alarm.dirIn,
          valueThresholdUsd: 5000,
          batchingEnabled: false);
      expect(tuned.summary, r'Incoming only over $5k');
    });

    test('a disabled alarm says so and nothing else', () {
      expect(Alarm.withDefaults('w').copyWith(enabled: false).summary,
          'Alarm off');
    });
  });

  group('copyWith', () {
    test('clearThreshold removes a threshold that was set', () {
      final a = Alarm.withDefaults('w').copyWith(valueThresholdUsd: 100);
      expect(a.valueThresholdUsd, 100);
      expect(a.copyWith(clearThreshold: true).valueThresholdUsd, isNull);
    });

    test('leaves untouched fields alone', () {
      final a = Alarm.withDefaults('w').copyWith(direction: Alarm.dirOut);
      expect(a.direction, 'out');
      expect(a.batchingWindowMin, 10);
      expect(a.spamFilter, isTrue);
    });
  });
}
