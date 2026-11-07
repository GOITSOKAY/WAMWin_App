import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../security/crypto.dart';

/// WAMBK1 backup container - identical to the reference (src/modules/backup/domain/BackupCrypto.ts):
///   "WAMBK1\n" | uint32 BE header length | header JSON | AES-256-GCM ciphertext | 16-byte tag
/// The header bytes are the GCM additional authenticated data, so changing the header is detected.
/// Nothing is returned unless the authentication tag verifies (conformance rule C1).
class BackupIntegrityException implements Exception {
  BackupIntegrityException(this.message);
  final String message;
  @override
  String toString() => message;
}

class WambkFile {
  WambkFile(this.header, this.headerBytes, this.body);
  final Map<String, dynamic> header;
  final Uint8List headerBytes;
  final Uint8List body; // ciphertext || tag
  String get keyKind => (header['key'] as Map)['kind'] as String;
}

class Wambk {
  static final Uint8List magic = Uint8List.fromList(utf8.encode('WAMBK1\n'));

  static WambkFile parse(Uint8List file) {
    if (file.length < magic.length + 4) throw BackupIntegrityException('Backup file is truncated');
    for (var i = 0; i < magic.length; i++) {
      if (file[i] != magic[i]) throw BackupIntegrityException('Not a WAMWins backup file');
    }
    final len = ByteData.sublistView(file, magic.length, magic.length + 4).getUint32(0, Endian.big);
    final start = magic.length + 4 + len;
    if (len > 64 * 1024 || file.length < start + 16) throw BackupIntegrityException('Backup file is truncated');
    final headerBytes = Uint8List.sublistView(file, magic.length + 4, start);
    final header = jsonDecode(utf8.decode(headerBytes)) as Map<String, dynamic>;
    return WambkFile(header, Uint8List.fromList(headerBytes), Uint8List.sublistView(file, start));
  }

  /// Key for a PASSPHRASE backup (scrypt with the header's salt and parameters).
  static Uint8List passphraseKey(WambkFile f, String passphrase) {
    final k = f.header['key'] as Map<String, dynamic>;
    if (k['kind'] != 'PASSPHRASE') throw ArgumentError('Not a passphrase backup');
    return scrypt32(passphrase, base64.decode(k['salt'] as String), n: k['N'] as int, r: k['r'] as int, p: k['p'] as int);
  }

  /// Returns the JSON lines (manifest, rows, end) only if authentication succeeds.
  static List<String> decrypt(Uint8List file, Uint8List key) {
    final f = parse(file);
    final iv = base64.decode(f.header['iv'] as String);
    final gcm = GCMBlockCipher(AESEngine())..init(false, AEADParameters(KeyParameter(key), 128, iv, f.headerBytes));
    final Uint8List plain;
    try {
      plain = gcm.process(f.body);
    } catch (_) {
      throw BackupIntegrityException('Backup could not be decrypted: wrong key or passphrase, or the file was changed or damaged');
    }
    return utf8.decode(plain).split('\n').where((l) => l.isNotEmpty).toList();
  }

  /// Writes a WAMBK1 file (same layout the reference writes).
  static Uint8List encrypt({required Map<String, dynamic> header, required Uint8List key, required List<String> lines}) {
    final headerBytes = Uint8List.fromList(utf8.encode(jsonEncode(header)));
    final iv = base64.decode(header['iv'] as String);
    final gcm = GCMBlockCipher(AESEngine())..init(true, AEADParameters(KeyParameter(key), 128, iv, headerBytes));
    final body = gcm.process(Uint8List.fromList(utf8.encode(lines.map((l) => '$l\n').join())));
    final len = ByteData(4)..setUint32(0, headerBytes.length, Endian.big);
    return Uint8List.fromList([...magic, ...len.buffer.asUint8List(), ...headerBytes, ...body]);
  }
}
