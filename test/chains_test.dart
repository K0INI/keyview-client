// Mirrors backend test/chains.test.mjs — same vectors, same verdicts, so the
// client and the Worker can never disagree about what an address is.
import 'package:flutter_test/flutter_test.dart';
import 'package:keyview/chains.dart';

void main() {
  test('bitcoin: all four formats', () {
    expect(classifyAddress('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa'), 'bitcoin');
    expect(classifyAddress('3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy'), 'bitcoin');
    expect(classifyAddress('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4'),
        'bitcoin');
    expect(
        classifyAddress(
            'bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0'),
        'bitcoin');
  });

  test('corrupted checksums are invalid, never solana', () {
    expect(classifyAddress('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb'), 'invalid');
    expect(classifyAddress('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5'),
        'invalid');
  });

  test('litecoin / dogecoin / tron / xrp / cardano / ton', () {
    expect(classifyAddress('LbTjMGN7gELw4KbeyQf6cTCq859hD18guE'), 'litecoin');
    expect(classifyAddress('MGxNPPB7eBoWPUaprtX9v9CXJZoD2465zN'), 'litecoin');
    expect(classifyAddress('ltc1qw508d6qejxtdg4y5r3zarvary0c5xw7kgmn4n9'),
        'litecoin');
    expect(classifyAddress('DH5yaieqoZN36fDVciNyRueRGvGLR3mr7L'), 'dogecoin');
    expect(classifyAddress('TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t'), 'tron');
    expect(classifyAddress('rvYAfWj5gh67oV6fW32ZzP3Aw4Eubs59B'), 'xrp');
    expect(
        classifyAddress(
            'addr1qx2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzer3n0d3vllmyqwsx5wktcd8cc3sq835lu7drv2xwl2wywfgse35a3x'),
        'cardano');
    expect(
        classifyAddress('EQCD39VS5jcptHL8vMjEXrzGaRcCVYto7HUn4bpAOg8xqB2N'),
        'ton');
  });

  test('existing kinds unchanged — the collision traps', () {
    expect(classifyAddress('0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045'),
        'evm');
    // SPL token program id starts with T like Tron, stays solana.
    expect(classifyAddress('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA'),
        'solana');
    expect(classifyAddress('11111111111111111111111111111111'), 'solana');
    expect(classifyAddress('DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263'),
        'solana');
    expect(classifyAddress(''), 'invalid');
    expect(classifyAddress('hello world'), 'invalid');
  });

  test('alarm support and wording', () {
    expect(alarmKinds.contains('evm'), true);
    expect(alarmKinds.contains('bitcoin'), false);
    expect(balancesOnlyNote('bitcoin'), contains('Bitcoin'));
    expect(balancesOnlyNote('bitcoin'), contains('balances only'));
  });
}
