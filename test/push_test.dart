// Notifications feed formatting + device-registration guards.
// Pure logic only — no Firebase project, no network.

import 'package:flutter_test/flutter_test.dart';
import 'package:keyview/push.dart';

NotificationEntry e(String id, {DateTime? at, String address = '0x322F0929c4625eD5bAd873c95208D54E1c003b2d'}) =>
    NotificationEntry(id: id, address: address, summary: 'Wallet "W" received 1 ETH.', firedAt: at);

void main() {
  final now = DateTime(2026, 7, 24, 15, 0);

  group('relative time', () {
    test('collapses anything under a minute to "just now"', () {
      expect(FeedFormat.relative(now.subtract(const Duration(seconds: 5)), now), 'just now');
      expect(FeedFormat.relative(now, now), 'just now');
    });

    test('minutes, hours, days', () {
      expect(FeedFormat.relative(now.subtract(const Duration(minutes: 12)), now), '12m ago');
      expect(FeedFormat.relative(now.subtract(const Duration(hours: 3)), now), '3h ago');
      expect(FeedFormat.relative(now.subtract(const Duration(days: 1)), now), 'yesterday');
      expect(FeedFormat.relative(now.subtract(const Duration(days: 4)), now), '4d ago');
    });

    test('falls back to a date beyond a week', () {
      expect(FeedFormat.relative(DateTime(2026, 7, 2, 9), now), 'Jul 2');
    });

    test('a future timestamp reads as "just now", never "in 3 minutes"', () {
      // Device and server clocks disagree; a negative age must not leak to UI.
      expect(FeedFormat.relative(now.add(const Duration(minutes: 3)), now), 'just now');
    });

    test('a null timestamp renders as empty, not "null"', () {
      expect(FeedFormat.relative(null, now), '');
    });
  });

  group('day grouping', () {
    test('groups consecutive entries under one heading', () {
      final items = [
        e('1', at: now.subtract(const Duration(hours: 1))),
        e('2', at: now.subtract(const Duration(hours: 2))),
        e('3', at: now.subtract(const Duration(days: 1))),
      ];
      final secs = FeedFormat.groupByDay(items, now);
      expect(secs.length, 2);
      expect(secs[0].label, 'Today');
      expect(secs[0].entries.length, 2);
      expect(secs[1].label, 'Yesterday');
    });

    test('older entries get a day-count then a date', () {
      final secs = FeedFormat.groupByDay([
        e('1', at: now.subtract(const Duration(days: 3))),
        e('2', at: DateTime(2026, 6, 10)),
      ], now);
      expect(secs[0].label, '3 days ago');
      expect(secs[1].label, 'June 10');
    });

    test('entries without a timestamp land under Earlier', () {
      final secs = FeedFormat.groupByDay([e('1')], now);
      expect(secs.single.label, 'Earlier');
    });

    test('an empty feed produces no sections', () {
      expect(FeedFormat.groupByDay([], now), isEmpty);
    });

    test('preserves the order it was given', () {
      final items = [
        e('a', at: now),
        e('b', at: now.subtract(const Duration(minutes: 5))),
      ];
      final secs = FeedFormat.groupByDay(items, now);
      expect(secs.single.entries.map((x) => x.id), ['a', 'b']);
    });
  });

  group('entry parsing', () {
    test('reads a notification_log row', () {
      final n = NotificationEntry.fromJson({
        'id': 'n1',
        'address': '0xabc',
        'tx_hash': '0xdead',
        'summary': 'Wallet "Whale #1" received 2.5 ETH (~\$8,900).',
        'fired_at': '2026-07-24T12:00:00Z',
      });
      expect(n.id, 'n1');
      expect(n.txHash, '0xdead');
      expect(n.summary, contains('2.5 ETH'));
      expect(n.firedAt, isNotNull);
    });

    test('tolerates missing and malformed fields', () {
      final n = NotificationEntry.fromJson({});
      expect(n.id, '');
      expect(n.summary, '');
      expect(n.firedAt, isNull);
      expect(NotificationEntry.fromJson({'fired_at': 'not-a-date'}).firedAt, isNull);
    });

    test('shortens long addresses only', () {
      expect(e('1').shortAddress, '0x322F…3b2d');
      expect(e('1', address: '0xabc').shortAddress, '0xabc');
    });
  });

  group('device registration guards', () {
    test('only the four platforms schema.sql allows', () {
      expect(PushService.platforms, {'ios', 'android', 'windows', 'macos'});
      expect(PushService.platforms.contains('linux'), isFalse);
      expect(PushService.platforms.contains('web'), isFalse);
    });
  });
}
