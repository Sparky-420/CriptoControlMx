import 'dart:convert';
import 'dart:typed_data';

String canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

String sha256Hex(String value) {
  final digest = _sha256(Uint8List.fromList(utf8.encode(value)));
  return digest.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

String sha256BytesHex(Uint8List value) {
  final digest = _sha256(value);
  return digest.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

String deterministicUuidFromSha256(String value) {
  final bytes = _sha256(Uint8List.fromList(utf8.encode(value)));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .take(16)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalize).toList();
  }
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  throw ArgumentError.value(value, 'value', 'must be JSON encodable');
}

Uint8List _sha256(Uint8List input) {
  final bitLength = input.length * 8;
  final paddedLength = ((input.length + 9 + 63) ~/ 64) * 64;
  final bytes = Uint8List(paddedLength)..setRange(0, input.length, input);
  bytes[input.length] = 0x80;
  for (var index = 0; index < 8; index++) {
    bytes[paddedLength - 1 - index] = (bitLength >> (index * 8)) & 0xff;
  }
  var h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
  var h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;
  for (var offset = 0; offset < bytes.length; offset += 64) {
    final words = Uint32List(64);
    for (var i = 0; i < 16; i++) {
      final p = offset + i * 4;
      words[i] =
          (bytes[p] << 24) |
          (bytes[p + 1] << 16) |
          (bytes[p + 2] << 8) |
          bytes[p + 3];
    }
    for (var i = 16; i < 64; i++) {
      words[i] = _add32(
        _small1(words[i - 2]),
        words[i - 7],
        _small0(words[i - 15]),
        words[i - 16],
      );
    }
    var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
    for (var i = 0; i < 64; i++) {
      final t1 = _add32(h, _big1(e), _choose(e, f, g), _k[i], words[i]);
      final t2 = _add32(_big0(a), _majority(a, b, c));
      h = g;
      g = f;
      f = e;
      e = _add32(d, t1);
      d = c;
      c = b;
      b = a;
      a = _add32(t1, t2);
    }
    h0 = _add32(h0, a);
    h1 = _add32(h1, b);
    h2 = _add32(h2, c);
    h3 = _add32(h3, d);
    h4 = _add32(h4, e);
    h5 = _add32(h5, f);
    h6 = _add32(h6, g);
    h7 = _add32(h7, h);
  }
  final output = Uint8List(32);
  for (final entry in <int>[h0, h1, h2, h3, h4, h5, h6, h7].asMap().entries) {
    final index = entry.key * 4, word = entry.value;
    output[index] = word >> 24;
    output[index + 1] = word >> 16;
    output[index + 2] = word >> 8;
    output[index + 3] = word;
  }
  return output;
}

int _add32(int a, [int b = 0, int c = 0, int d = 0, int e = 0]) =>
    (a + b + c + d + e) & 0xffffffff;
int _rotr(int value, int bits) =>
    ((value >>> bits) | (value << (32 - bits))) & 0xffffffff;
int _choose(int x, int y, int z) => (x & y) ^ (~x & z);
int _majority(int x, int y, int z) => (x & y) ^ (x & z) ^ (y & z);
int _big0(int x) => _rotr(x, 2) ^ _rotr(x, 13) ^ _rotr(x, 22);
int _big1(int x) => _rotr(x, 6) ^ _rotr(x, 11) ^ _rotr(x, 25);
int _small0(int x) => _rotr(x, 7) ^ _rotr(x, 18) ^ (x >>> 3);
int _small1(int x) => _rotr(x, 17) ^ _rotr(x, 19) ^ (x >>> 10);

const List<int> _k = <int>[
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
];
