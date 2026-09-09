import 'package:flutter_test/flutter_test.dart';
import 'package:keyview/api.dart';

void main() {
  test('Portfolio.fromJson keeps unpriced out of the total', () {
    final p = Portfolio.fromJson({
      'address': '0xabc',
      'holdings': [
        {'symbol': 'ETH', 'name': 'Ethereum', 'chain': 'ethereum', 'amount': 2, 'priceUsd': 1000, 'change24h': 1.0, 'priceStatus': 'ok', 'priceConfidence': 0.95, 'priceSources': ['defillama', 'alchemy']},
      ],
      'unpriced': [
        {'symbol': 'DUST', 'name': 'Dust Token', 'chain': 'base', 'amount': 4000000, 'priceUsd': 1, 'change24h': 0, 'priceStatus': 'unreliable', 'priceConfidence': 0.2, 'priceReason': 'Only \$800 of liquidity exists', 'liquidityUsd': 800},
      ],
      'totalUsd': 2000,
      'pricedAt': '2026-09-08T12:00:00Z',
    });
    expect(p.totalUsd, 2000);
    expect(p.unpriced.length, 1);
    expect(p.unpriced.first.reliable, isFalse);
    expect(p.unpriced.first.priceReason, contains('liquidity'));
    expect(p.holdings.first.priceSources, ['defillama', 'alchemy']);
    expect(p.pricedAt, isNotNull);
  });

  test('old backend shape (no accuracy fields) still parses as reliable', () {
    final p = Portfolio.fromJson({
      'address': '0xabc',
      'holdings': [
        {'symbol': 'SOL', 'name': 'Solana', 'chain': 'solana', 'amount': 3, 'priceUsd': 100, 'change24h': 0},
      ],
    });
    expect(p.holdings.first.reliable, isTrue);
    expect(p.totalUsd, 300);
    expect(p.unpriced, isEmpty);
    expect(p.pricedAt, isNull);
  });
}
