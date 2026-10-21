// Display-currency tests (0.1.9).
//
// These lock down the defects a beta tester reported on 0.1.8:
//   "When I select currency on Mac it still populates in dollars"
//   "On Android when selecting euro the total value watched also remains in
//    dollars and does not fully populate"
//
// Rates below are the live figures from /v1/fx on 2026-10-17.

import 'package:flutter_test/flutter_test.dart';
import 'package:keyview/money.dart';

void main() {
  group('Money', () {
    setUp(Money.debugReset);

    test('defaults to US dollars', () {
      expect(Money.code, 'USD');
      expect(Money.format(1234.56), r'$1,234.56');
    });

    test('USD never waits on a rate', () {
      // No rates loaded at all — dollars must still render immediately.
      expect(Money.awaitingRate, isFalse);
      expect(Money.format(10), r'$10.00');
    });

    test('converts to euros once rates arrive', () {
      Money.debugSetRates({'EUR': 0.889517, 'GBP': 0.750839});
      Money.debugSetCode('EUR');
      expect(Money.format(1000), '€889.52');
    });

    test('converts to pounds once rates arrive', () {
      Money.debugSetRates({'EUR': 0.889517, 'GBP': 0.750839});
      Money.debugSetCode('GBP');
      expect(Money.format(1000), '£750.84');
    });

    test('zero-decimal currencies drop the cents', () {
      Money.debugSetRates({'JPY': 157.994345});
      Money.debugSetCode('JPY');
      expect(Money.format(100), '¥15,799');
    });

    test('REGRESSION: a chosen currency never renders as dollars while its '
        'rate is still in flight', () {
      // The 0.1.8 defect: EUR selected, rates not back yet, every figure
      // printed with a "$". A placeholder is the honest answer for the one
      // round trip that window lasts.
      Money.debugSetCode('EUR'); // no rates, first load not finished
      expect(Money.awaitingRate, isTrue);
      expect(Money.format(1000), Money.placeholder);
      expect(Money.formatPrice(0.000003965), Money.placeholder);
      expect(Money.formatCompact(2500), Money.placeholder);
    });

    test('falls back to dollars, and says so, when rates cannot be fetched',
        () {
      Money.debugSetCode('EUR');
      Money.debugFinishFirstLoad(); // fetch finished, no rates
      expect(Money.awaitingRate, isFalse);
      expect(Money.rateMissing, isTrue, reason: 'the banner relies on this');
      expect(Money.format(1000), r'$1,000.00');
    });

    test('tiny prices stay readable — the EthFan case', () {
      // $EFB traded at $0.000003965 on 2026-10-17. Rendering that as
      // "$0.00" is the same as showing no price at all.
      // formatPrice renders sub-cent values with toStringAsPrecision(3), so
      // $EFB reads "$0.00000397" — the significant digits survive, but there
      // is no decimal point between them. Assert the digits, not a formatting
      // accident, so this passes under fixed or exponential rendering.
      String digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');
      final efb = Money.formatPrice(0.000003965);
      expect(efb, isNot(r'$0.00'));
      expect(efb, startsWith(r'$'));
      expect(digits(efb), contains('397'));
      final efbp = Money.formatPrice(0.000001582);
      expect(efbp, isNot(r'$0.00'));
      expect(digits(efbp), contains('158'));
    });

    test('compact money follows the chosen currency', () {
      Money.debugSetRates({'EUR': 0.889517});
      Money.debugSetCode('EUR');
      expect(Money.formatCompact(2500), startsWith('€'));
      expect(Money.formatCompact(2500000), '€2.2M');
    });

    test('conversion is display-only and never compounds', () {
      Money.debugSetRates({'EUR': 0.889517});
      Money.debugSetCode('EUR');
      // Converting twice must not double-apply: convert() always takes USD.
      expect(Money.convert(100), closeTo(88.9517, 0.0001));
      expect(Money.convert(100), closeTo(88.9517, 0.0001));
    });

    test('an unknown currency code is ignored', () {
      Money.debugSetCode('XXX');
      expect(Money.code, 'USD');
    });
  
    // ── 0.1.10: the rate table must survive a failed fetch ────────────────
    //
    // Beta report (0.1.9, macOS): "when euro is selected dollar value still
    // shows ... 'Today's rate isn't available, so values stay in US dollars'".
    // Everything else in the app worked, so the wallet endpoints were fine and
    // only /v1/fx failed. Before 0.1.10 a single failed fx request left the
    // app in dollars for the whole session with nothing cached and nothing
    // logged. These lock in the new behaviour.

    test('a cached rate still converts after a failed refresh', () {
      Money.debugSetCachedRates({'EUR': 0.89075});
      Money.debugSetCode('EUR');
      Money.debugSetError('Timed out after 20s');
      expect(Money.rateMissing, isFalse,
          reason: 'a cached rate means we are not stuck in dollars');
      expect(Money.format(1000), startsWith('\u20AC'));
      expect(Money.ratesStale, isTrue);
    });

    test('a fresh rate is not reported as stale', () {
      Money.debugSetRates({'EUR': 0.89075});
      Money.debugSetCode('EUR');
      expect(Money.ratesStale, isFalse);
      expect(Money.rateMissing, isFalse);
    });

    test('rateMissing only once the first load has finished', () {
      Money.debugSetCode('EUR');
      expect(Money.awaitingRate, isTrue);
      expect(Money.rateMissing, isFalse);
      expect(Money.format(1000), Money.placeholder);
      Money.debugFinishFirstLoad();
      expect(Money.rateMissing, isTrue);
      expect(Money.format(1000), r'$1,000.00',
          reason: 'with no rate at all we show dollars and say so');
    });

    test('the failure reason is recorded for Settings to show', () {
      Money.debugSetError('HTTP 429 from /v1/fx');
      expect(Money.lastError, 'HTTP 429 from /v1/fx');
    });

    test('USD is never stale and never missing', () {
      Money.debugSetCachedRates({'EUR': 0.89075});
      expect(Money.code, 'USD');
      expect(Money.ratesStale, isFalse);
      expect(Money.rateMissing, isFalse);
    });
});
}
