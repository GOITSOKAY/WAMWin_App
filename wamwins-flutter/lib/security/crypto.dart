import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

final _rng = Random.secure();
Uint8List randomBytes(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));
String hexOf(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
Uint8List utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// Same normalisation as the web client (String.prototype.normalize('NFKC')).
String nfkc(String s) => unorm.nfkc(s);

/// PBKDF2-HMAC-SHA-256, 32-byte output.
Uint8List pbkdf2Sha256(String password, Uint8List salt, int iterations) {
  final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(salt, iterations, 32));
  return kdf.process(utf8Bytes(nfkc(password)));
}

/// scrypt, 32-byte output (WAMBK1 passphrase key).
Uint8List scrypt32(String passphrase, Uint8List salt, {required int n, required int r, required int p}) {
  final kdf = Scrypt()..init(ScryptParameters(n, r, p, 32, salt));
  return kdf.process(utf8Bytes(nfkc(passphrase)));
}

String sha256Hex(String s) => hexOf(SHA256Digest().process(utf8Bytes(s)));
String sha256HexBytes(Uint8List b) => hexOf(SHA256Digest().process(b));

/// Constant-time comparison (no early exit).
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
