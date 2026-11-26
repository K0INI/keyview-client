import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyview/api.dart';
import 'package:keyview/brand.dart';
import 'package:keyview/screens/collectibles.dart';

void main() {
  group('Collectibles model', () {
    test('parses a full response; no floor stays null, never zero', () {
      final c = Collectibles.fromJson({
        'address': '0xabc',
        'enabled': true,
        'supported': true,
        'collectiblesUsd': 4000.0,
        'hiddenCount': 3,
        'unpricedCollections': 1,
        'pricedAt': '2026-10-21T20:00:00Z',
        'collections': [
          {
            'chain': 'ethereum',
            'contract': '0x1',
            'name': 'Punkies',
            'symbol': 'PNK',
            'tokenType': 'ERC721',
            'count': 2,
            'itemCount': 2,
            'imageUrl': 'https://nft-cdn.alchemy.com/x',
            'floorEth': 0.5,
            'floorUsd': 2000.0,
            'valueUsd': 4000.0,
            'items': [
              {'tokenId': '1', 'name': 'Punky #1', 'imageUrl': null, 'balance': 1},
            ],
          },
          {
            'chain': 'base',
            'contract': '0x2',
            'name': 'NoFloor Art',
            'count': 1,
            'itemCount': 1,
          },
        ],
      });
      expect(c.enabled, true);
      expect(c.collections.length, 2);
      expect(c.collections[0].valueUsd, 4000.0);
      expect(c.collections[1].valueUsd, isNull);
      expect(c.collections[1].floorEth, isNull);
      expect(c.hiddenCount, 3);
      expect(c.collectiblesUsd, 4000.0);
    });

    test('kill-switch and unsupported responses parse safely', () {
      final off = Collectibles.fromJson({'address': '0xabc', 'enabled': false});
      expect(off.enabled, false);
      expect(off.collections, isEmpty);
      final sol = Collectibles.fromJson(
          {'address': 'So1...', 'enabled': true, 'supported': false});
      expect(sol.supported, false);
    });

    test('junk fields never throw', () {
      final c = Collectibles.fromJson({
        'collections': [<String, dynamic>{}],
        'collectiblesUsd': null,
      });
      expect(c.collections.single.name, 'Unnamed collection');
      expect(c.collectiblesUsd, 0);
    });
  });

  group('Collectibles UI', () {
    Widget wrap(Widget child) => MaterialApp(
        theme: Brand.theme(), home: Scaffold(body: ListView(children: [child])));

    testWidgets('section is collapsed and makes NO network call until opened',
        (tester) async {
      await tester.pumpWidget(wrap(const CollectiblesSection(address: '0xabc')));
      expect(find.text('COLLECTIBLES'), findsOneWidget);
      // Nothing fetched, nothing rendered below the header.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('collection grid labels a floorless collection honestly',
        (tester) async {
      const col = NftCollection('ethereum', '0x2', 'NoFloor Art',
          count: 1, itemCount: 1, items: [NftItem('7', name: 'Piece #7')]);
      await tester.pumpWidget(
          const MaterialApp(home: NftCollectionScreen(c: col)));
      expect(find.text('NO FLOOR PRICE'), findsOneWidget);
      expect(find.textContaining('invented number'), findsOneWidget);
    });

    testWidgets('floor value carries the indicative label, not a plain price',
        (tester) async {
      const col = NftCollection('ethereum', '0x1', 'Punkies',
          count: 2,
          itemCount: 2,
          floorEth: 0.5,
          floorUsd: 2000,
          valueUsd: 4000,
          items: [NftItem('1', name: 'Punky #1')]);
      await tester.pumpWidget(
          const MaterialApp(home: NftCollectionScreen(c: col)));
      expect(find.textContaining('FLOOR 0.500 ETH'), findsOneWidget);
      expect(find.textContaining('never added to your watched total'),
          findsOneWidget);
    });
  });
}
