// Conformance rule C1 (docs/CLIENT_CONFORMANCE.md): this client must decrypt the reference WAMBK1 vectors
// byte-exactly and reject the wrong passphrase and both tampered files. Vectors: test/vectors (synced
// from conformance/vectors by tool/sync_shared.mjs). Run: flutter test test/conformance_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wamwins/backup/wambk.dart';
import 'package:wamwins/security/crypto.dart';

Uint8List _hex(String h) => Uint8List.fromList([for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);

void main() {
  final spec = jsonDecode(File('test/vectors/backup-vectors.json').readAsStringSync()) as Map<String, dynamic>;
  final expected = List<String>.from(spec['expected_plaintext_lines'] as List);

  for (final v in (spec['vectors'] as List).cast<Map<String, dynamic>>()) {
    test('${v['file']} -> ${v['expect']}${v['passphrase'] != null ? ' (passphrase "${v['passphrase']}")' : ''}', () {
      final bytes = File('test/vectors/${v['file']}').readAsBytesSync();
      Uint8List key;
      if (v['passphrase'] != null) {
        key = Wambk.passphraseKey(Wambk.parse(bytes), v['passphrase'] as String);
        if (v['derived_key_hex'] != null) expect(hexOf(key), v['derived_key_hex'], reason: 'scrypt derivation must match the reference');
      } else {
        key = _hex(v['key_hex'] as String);
      }
      if (v['expect'] == 'DECRYPTS') {
        expect(Wambk.decrypt(bytes, key), expected);
        if (v['sha256'] != null) expect(sha256HexBytes(bytes), v['sha256']);
        if (v['header_key'] != null) expect(Wambk.parse(bytes).header['key'], v['header_key']);
      } else {
        expect(() => Wambk.decrypt(bytes, key), throwsA(isA<BackupIntegrityException>()));
      }
    });
  }

  test('a backup written by this client opens with the reference rules (round trip, header bound)', () {
    final key = _hex('000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f');
    final header = {'formatVersion': 1, 'backupId': 'dart-roundtrip', 'createdAt': '2026-11-05T00:00:00.000Z', 'algorithm': 'AES-256-GCM',
      'iv': base64.encode(List<int>.filled(12, 9)), 'key': {'kind': 'DEVICE_KEY'}};
    final file = Wambk.encrypt(header: header, key: key, lines: expected);
    expect(Wambk.decrypt(file, key), expected);
    final tampered = Uint8List.fromList(file)..[20] ^= 1;     // inside the header
    expect(() => Wambk.decrypt(tampered, key), throwsA(isA<BackupIntegrityException>()));
  });
}
