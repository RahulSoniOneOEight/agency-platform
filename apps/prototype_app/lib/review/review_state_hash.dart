/// Canonical, dependency-free SHA-256 hashing for [ReviewState].
///
/// The repository does not depend on `package:crypto`, so a small pure-Dart
/// SHA-256 implementation is used here instead of adding a dependency. The hash
/// is taken over the canonical UTF-8 JSON produced by [ReviewState.toJson]
/// (sorted screen keys, fixed top-level key order), so identical review state
/// always yields an identical `sha256:<hex>` value.
library;

import 'dart:convert';

import 'review_state.dart';

/// Deterministic canonical JSON for [state].
String canonicalReviewStateJson(ReviewState state) => jsonEncode(state.toJson());

/// `sha256:<hex>` over the canonical UTF-8 JSON of [state].
String reviewStateHash(ReviewState state) =>
    'sha256:${sha256Hex(utf8.encode(canonicalReviewStateJson(state)))}';

const List<int> _k = <int>[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

int _rotr(int value, int amount) =>
    ((value >> amount) | (value << (32 - amount))) & 0xffffffff;

int _add32(int a, int b) => (a + b) & 0xffffffff;

/// Hex-encoded SHA-256 digest of [bytes].
String sha256Hex(List<int> bytes) {
  final message = <int>[...bytes, 0x80];
  final bitLength = bytes.length * 8;
  while (message.length % 64 != 56) {
    message.add(0);
  }
  for (var shift = 56; shift >= 0; shift -= 8) {
    message.add((bitLength >> shift) & 0xff);
  }

  var h0 = 0x6a09e667;
  var h1 = 0xbb67ae85;
  var h2 = 0x3c6ef372;
  var h3 = 0xa54ff53a;
  var h4 = 0x510e527f;
  var h5 = 0x9b05688c;
  var h6 = 0x1f83d9ab;
  var h7 = 0x5be0cd19;

  final w = List<int>.filled(64, 0);
  for (var offset = 0; offset < message.length; offset += 64) {
    for (var i = 0; i < 16; i++) {
      final base = offset + i * 4;
      w[i] = (message[base] << 24) |
          (message[base + 1] << 16) |
          (message[base + 2] << 8) |
          message[base + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = _add32(_add32(w[i - 16], s0), _add32(w[i - 7], s1));
    }

    var a = h0;
    var b = h1;
    var c = h2;
    var d = h3;
    var e = h4;
    var f = h5;
    var g = h6;
    var h = h7;

    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e & 0xffffffff) & g);
      final temp1 = _add32(_add32(_add32(h, s1), _add32(ch, _k[i])), w[i]);
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = _add32(s0, maj);
      h = g;
      g = f;
      f = e;
      e = _add32(d, temp1);
      d = c;
      c = b;
      b = a;
      a = _add32(temp1, temp2);
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

  final buffer = StringBuffer();
  for (final value in [h0, h1, h2, h3, h4, h5, h6, h7]) {
    buffer.write(value.toRadixString(16).padLeft(8, '0'));
  }
  return buffer.toString();
}
