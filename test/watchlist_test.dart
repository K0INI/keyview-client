// Pure-logic tests for the watchlist model and ordering helpers.
// No Flutter binding, no network — these run under `flutter test` in CI.

import 'package:flutter_test/flutter_test.dart';
import 'package:keyview/watch.dart';

WatchedAddress w(String id, {String? label, List<String> tags = const [], int order = 0}) =>
    WatchedAddress(id, '0x$id', 'evm', label, tags: tags, sortOrder: order);

void main() {
  group('tag parsing', () {
    test('parses a Postgres text[] arriving as a JSON list', () {
      expect(WatchedAddress.parseTags(['cold', 'defi']), ['cold', 'defi']);
    });

    test('is forgiving about nulls, blanks and a bare string', () {
      expect(WatchedAddress.parseTags(['cold', '', null, '  x  ']), ['cold', 'x']);
      expect(WatchedAddress.parseTags('solo'), ['solo']);
      expect(WatchedAddress.parseTags(null), isEmpty);
      expect(WatchedAddress.parseTags(42), isEmpty);
    });

    test('splits comma input, trims, and de-dupes case-insensitively', () {
      expect(WatchedAddress.splitTagInput('cold, DeFi , cold ,COLD'),
          ['cold', 'DeFi']);
    });

    test('keeps the first spelling the user typed', () {
      expect(WatchedAddress.splitTagInput('DeFi, defi'), ['DeFi']);
    });

    test('caps the tag count', () {
      expect(WatchedAddress.splitTagInput('a,b,c,d,e,f,g,h').length, 6);
    });

    test('handles emoji tags', () {
      expect(WatchedAddress.splitTagInput('🐋, cold'), ['🐋', 'cold']);
    });
  });

  group('display name', () {
    test('prefers the label', () {
      expect(w('1', label: 'Whale #1').displayName, 'Whale #1');
    });

    test('falls back to a shortened address when the label is blank', () {
      const long = WatchedAddress(
          'i', '0x322F0929c4625eD5bAd873c95208D54E1c003b2d', 'evm', '   ');
      expect(long.displayName, long.shortAddress);
      expect(long.shortAddress, '0x322F…3b2d');
    });

    test('leaves short addresses intact', () {
      const short = WatchedAddress('i', '0xabc', 'evm', null);
      expect(short.shortAddress, '0xabc');
    });
  });

  group('reordering', () {
    final list = [w('a'), w('b'), w('c'), w('d')];
    List<String> ids(List<WatchedAddress> l) => l.map((e) => e.id).toList();

    test('moving upward inserts at the reported index', () {
      expect(ids(WatchlistOrdering.move(list, 2, 0)), ['c', 'a', 'b', 'd']);
    });

    test('moving downward compensates for the removed row', () {
      // ReorderableListView reports newIndex counting the row being dragged,
      // so a naive insert lands one slot short. a → position 2 must yield
      // b, c, a, d — not b, a, c, d.
      expect(ids(WatchlistOrdering.move(list, 0, 3)), ['b', 'c', 'a', 'd']);
    });

    test('moving to the very end works', () {
      expect(ids(WatchlistOrdering.move(list, 0, 4)), ['b', 'c', 'd', 'a']);
    });

    test('a no-op move keeps the order', () {
      expect(ids(WatchlistOrdering.move(list, 1, 1)), ['a', 'b', 'c', 'd']);
    });

    test('does not mutate the input list', () {
      final original = [w('a'), w('b')];
      WatchlistOrdering.move(original, 0, 2);
      expect(ids(original), ['a', 'b']);
    });

    test('out-of-range indices are survived, not thrown', () {
      expect(ids(WatchlistOrdering.move(list, 9, 0)), ['a', 'b', 'c', 'd']);
      expect(ids(WatchlistOrdering.move(list, -1, 0)), ['a', 'b', 'c', 'd']);
    });

    test('pin moves an entry to the top', () {
      expect(ids(WatchlistOrdering.pinToTop(list, 3)), ['d', 'a', 'b', 'c']);
    });

    test('pinning the first entry changes nothing', () {
      expect(ids(WatchlistOrdering.pinToTop(list, 0)), ['a', 'b', 'c', 'd']);
    });
  });

  group('tag filtering', () {
    final items = [
      w('a', tags: ['cold', 'defi']),
      w('b', tags: ['Cold']),
      w('c'),
    ];

    test('collects every distinct tag in first-seen order', () {
      expect(WatchlistOrdering.allTags(items), ['cold', 'defi']);
    });

    test('filters case-insensitively', () {
      expect(WatchlistOrdering.filterByTag(items, 'COLD').map((e) => e.id),
          ['a', 'b']);
    });

    test('a null or empty tag shows everything', () {
      expect(WatchlistOrdering.filterByTag(items, null).length, 3);
      expect(WatchlistOrdering.filterByTag(items, '').length, 3);
    });

    test('an unknown tag yields nothing', () {
      expect(WatchlistOrdering.filterByTag(items, 'nope'), isEmpty);
    });
  });

  group('copyWith', () {
    test('replaces only what is given', () {
      final base = w('a', label: 'One', tags: ['x'], order: 3);
      final renamed = base.copyWith(label: 'Two');
      expect(renamed.label, 'Two');
      expect(renamed.tags, ['x']);
      expect(renamed.sortOrder, 3);
      expect(renamed.address, base.address);
    });
  });
}
