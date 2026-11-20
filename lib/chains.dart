// Address classification — mirrors backend src/chains.ts (network expansion
// 2026-11-20). Checksum-validated, never shape-guessed: legacy Bitcoin (1…/3…),
// Tron (T…), Litecoin and Dogecoin are all base58 and would otherwise satisfy
// the Solana shape. The backend is still authoritative (it re-validates and
// 400s), but classifying correctly here gives instant feedback and writes the
// right chain_kind to the watchlist.

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;

/// Networks that support transfer alarms (Alchemy webhooks). Everything else
/// is balances-only and the UI says so in plain words.
const Set<String> alarmKinds = {'evm', 'solana'};

/// Display names for every chain_kind the app can store.
const Map<String, String> kindNames = {
  'evm': 'EVM',
  'solana': 'Solana',
  'bitcoin': 'Bitcoin',
  'litecoin': 'Litecoin',
  'dogecoin': 'Dogecoin',
  'tron': 'Tron',
  'xrp': 'XRP',
  'cardano': 'Cardano',
  'ton': 'TON',
};

String kindName(String kind) => kindNames[kind] ?? kind;

/// Plain-words wording for a balances-only network, used anywhere alarms
/// could otherwise be offered.
String balancesOnlyNote(String kind) =>
    '${kindName(kind)} shows balances only — transfer alarms are not available on this network.';

final _evmRe = RegExp(r'^0x[0-9a-fA-F]{40}$');
final _solRe = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$');

const _b58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
const _xrp58 = 'rpshnaf39wBUDNEGHJKLM4PQRST7VWXYZ2bcdeCg65jkm8oFqi1tuvAxyz';

Uint8List? _base58Decode(String s, String alphabet) {
  if (s.isEmpty || s.length > 64) return null;
  var bytes = <int>[0];
  for (final c in s.split('')) {
    final v = alphabet.indexOf(c);
    if (v < 0) return null;
    var carry = v;
    for (var i = 0; i < bytes.length; i++) {
      carry += bytes[i] * 58;
      bytes[i] = carry & 0xff;
      carry >>= 8;
    }
    while (carry > 0) {
      bytes.add(carry & 0xff);
      carry >>= 8;
    }
  }
  var zeros = 0;
  for (final c in s.split('')) {
    if (c == alphabet[0]) {
      zeros++;
    } else {
      break;
    }
  }
  final rev = bytes.reversed.toList();
  while (rev.isNotEmpty && rev.first == 0) {
    rev.removeAt(0); // zero value = no limbs (leading zeros carry it)
  }
  return Uint8List.fromList([...List.filled(zeros, 0), ...rev]);
}

Uint8List? _base58CheckDecode(String s, [String alphabet = _b58]) {
  final b = _base58Decode(s, alphabet);
  if (b == null || b.length < 5) return null;
  final payload = b.sublist(0, b.length - 4);
  final check = b.sublist(b.length - 4);
  final digest =
      crypto.sha256.convert(crypto.sha256.convert(payload).bytes).bytes;
  for (var i = 0; i < 4; i++) {
    if (digest[i] != check[i]) return null;
  }
  return Uint8List.fromList(payload);
}

const _bech = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
const _bech32mConst = 0x2bc830a3;

int _bech32Polymod(List<int> values) {
  const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
  var chk = 1;
  for (final v in values) {
    final b = chk >> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ v;
    for (var i = 0; i < 5; i++) {
      if ((b >> i) & 1 != 0) chk ^= gen[i];
    }
  }
  return chk;
}

/// Returns ('hrp', 'bech32'|'bech32m', dataWithoutChecksum) or null.
(String, String, List<int>)? bech32Verify(String sIn, {int maxLen = 90}) {
  if (sIn.length > maxLen || sIn.length < 8) return null;
  final hasLower = sIn.contains(RegExp(r'[a-z]'));
  final hasUpper = sIn.contains(RegExp(r'[A-Z]'));
  if (hasLower && hasUpper) return null;
  final s = sIn.toLowerCase();
  final pos = s.lastIndexOf('1');
  if (pos < 1 || pos + 7 > s.length) return null;
  final hrp = s.substring(0, pos);
  final data = <int>[];
  for (final c in s.substring(pos + 1).split('')) {
    final v = _bech.indexOf(c);
    if (v < 0) return null;
    data.add(v);
  }
  final exp = [
    ...hrp.codeUnits.map((c) => c >> 5),
    0,
    ...hrp.codeUnits.map((c) => c & 31),
  ];
  final pm = _bech32Polymod([...exp, ...data]);
  if (pm == 1) return (hrp, 'bech32', data.sublist(0, data.length - 6));
  if (pm == _bech32mConst) {
    return (hrp, 'bech32m', data.sublist(0, data.length - 6));
  }
  return null;
}

int _crc16XModem(List<int> data) {
  var reg = 0;
  for (final byte in data) {
    reg ^= byte << 8;
    for (var i = 0; i < 8; i++) {
      reg = reg & 0x8000 != 0 ? ((reg << 1) ^ 0x1021) & 0xffff : (reg << 1) & 0xffff;
    }
  }
  return reg;
}

bool tonVerify(String s) {
  if (!RegExp(r'^[A-Za-z0-9+/_-]{48}$').hasMatch(s)) return false;
  Uint8List b;
  try {
    final std = s.replaceAll('-', '+').replaceAll('_', '/');
    b = base64Decode(std);
  } catch (_) {
    return false;
  }
  if (b.length != 36) return false;
  if (![0x11, 0x51, 0x91, 0xd1].contains(b[0])) return false;
  if (b[1] != 0x00 && b[1] != 0xff) return false;
  return _crc16XModem(b.sublist(0, 34)) == ((b[34] << 8) | b[35]);
}

/// Classify an address. Mirrors backend classifyAddress exactly; see the
/// backend file for the collision rationale.
String classifyAddress(String a) {
  if (a.length < 8 || a.length > 128) return 'invalid';
  if (_evmRe.hasMatch(a)) return 'evm';

  final lower = a.toLowerCase();
  if (lower.startsWith('bc1') || lower.startsWith('ltc1')) {
    final v = bech32Verify(a);
    if (v != null) {
      final (hrp, enc, data) = v;
      if (data.length >= 2 && data[0] <= 16) {
        final okEnc = data[0] == 0 ? enc == 'bech32' : enc == 'bech32m';
        if (okEnc) {
          if (hrp == 'bc') return 'bitcoin';
          if (hrp == 'ltc') return 'litecoin';
        }
      }
    }
    return 'invalid';
  }
  if (lower.startsWith('addr1')) {
    final v = bech32Verify(a, maxLen: 120);
    if (v != null && v.$1 == 'addr' && v.$2 == 'bech32') return 'cardano';
    return 'invalid';
  }

  if (a.length == 48 &&
      RegExp(r'^[EU0k][Qq]').hasMatch(a) &&
      tonVerify(a)) {
    return 'ton';
  }

  if (a.startsWith('r') && a.length >= 25 && a.length <= 35) {
    final p = _base58CheckDecode(a, _xrp58);
    if (p != null && p.length == 21 && p[0] == 0x00) return 'xrp';
  }
  if (RegExp(r'^[13LMD9AT]').hasMatch(a) && a.length >= 25 && a.length <= 36) {
    final p = _base58CheckDecode(a);
    if (p != null && p.length == 21) {
      switch (p[0]) {
        case 0x00:
        case 0x05:
          return 'bitcoin';
        case 0x30:
        case 0x32:
          return 'litecoin';
        case 0x1e:
        case 0x16:
          return 'dogecoin';
        case 0x41:
          return 'tron';
      }
    }
  }

  if (_solRe.hasMatch(a)) {
    final d = _base58Decode(a, _b58);
    if (d != null && d.length == 32) return 'solana';
  }
  return 'invalid';
}
