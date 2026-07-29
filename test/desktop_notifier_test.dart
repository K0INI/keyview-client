import 'package:flutter_test/flutter_test.dart';
import 'package:keyview/desktop_notifier.dart';
import 'package:keyview/push.dart';

NotificationEntry _e(String id, int ms) => NotificationEntry(
      id: id,
      address: '0xabc',
      summary: 'Wallet moved $id',
      firedAt: DateTime.fromMillisecondsSinceEpoch(ms),
    );

void main() {
  group('DesktopNotifier.pickNew', () {
    test('only entries strictly newer than lastSeen, oldest first', () {
      final feed = [_e('c', 3000), _e('b', 2000), _e('a', 1000)];
      final out = DesktopNotifier.pickNew(feed, 1000);
      expect(out.map((e) => e.id).toList(), ['b', 'c']);
    });

    test('caps at max, keeping the MOST RECENT entries', () {
      final feed = [for (var i = 10; i >= 1; i--) _e('$i', i * 1000)];
      final out = DesktopNotifier.pickNew(feed, 0, max: 3);
      expect(out.map((e) => e.id).toList(), ['8', '9', '10']);
    });

    test('entries without firedAt are never notified', () {
      final feed = [
        const NotificationEntry(id: 'x', address: '0x1', summary: 's'),
        _e('y', 5000),
      ];
      final out = DesktopNotifier.pickNew(feed, 4000);
      expect(out.map((e) => e.id).toList(), ['y']);
    });
  });

  group('DesktopNotifier.newestFiredMs', () {
    test('returns the newest timestamp in the feed', () {
      expect(
        DesktopNotifier.newestFiredMs([_e('a', 1000), _e('b', 9000)]),
        9000,
      );
    });

    test('falls back when the feed has no timestamps', () {
      const feed = [NotificationEntry(id: 'x', address: '0x1', summary: 's')];
      expect(DesktopNotifier.newestFiredMs(feed, fallback: 42), 42);
    });
  });
}
