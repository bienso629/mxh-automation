import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  Uint8List? _cachedKey;

  Uint8List getCryptoKey() {
    if (_cachedKey != null) return _cachedKey!;
    String machineId = "tadu-cloud-ai-agent-control-center-secret-salt-2026";
    try {
      if (Platform.isLinux || Platform.isAndroid) {
        for (final p in ["/etc/machine-id", "/var/lib/dbus/machine-id"]) {
          final f = File(p);
          if (f.existsSync()) {
            machineId += f.readAsStringSync().trim();
            break;
          }
        }
      }
    } catch (_) {}
    final digest = sha256.convert(utf8.encode(machineId));
    _cachedKey = Uint8List.fromList(digest.bytes);
    return _cachedKey!;
  }

  String decryptValue(dynamic cipherText) {
    if (cipherText == null) return '';
    final s = cipherText.toString();
    if (!s.startsWith('enc:')) return s;

    try {
      final rawToken = s.substring(4);
      final normalized = base64.normalize(rawToken);
      final tokenBytes = base64Url.decode(normalized);

      if (tokenBytes.length < 57) return s; // Minimum Fernet token length

      final keyBytes = getCryptoKey();
      final encKey = keyBytes.sublist(16, 32);
      final ivBytes = tokenBytes.sublist(9, 25);
      final cipherBytes = tokenBytes.sublist(25, tokenBytes.length - 32);

      final key = enc.Key(encKey);
      final iv = enc.IV(ivBytes);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

      final decrypted = encrypter.decrypt(enc.Encrypted(cipherBytes), iv: iv);
      return decrypted;
    } catch (e) {
      return s;
    }
  }

  String encryptValue(dynamic plainText) {
    if (plainText == null) return '';
    final s = plainText.toString();
    if (s.isEmpty || s.startsWith('enc:')) return s;

    try {
      final keyBytes = getCryptoKey();
      final signKey = keyBytes.sublist(0, 16);
      final encKey = keyBytes.sublist(16, 32);

      final ivBytes = enc.IV.fromSecureRandom(16).bytes;
      final key = enc.Key(encKey);
      final iv = enc.IV(ivBytes);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

      final encrypted = encrypter.encrypt(s, iv: iv);
      final cipherBytes = encrypted.bytes;

      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final timeBytes = Uint8List(8);
      ByteData.view(timeBytes.buffer).setUint64(0, nowSeconds, Endian.big);

      final headerAndCipher = Uint8List.fromList([
        0x80,
        ...timeBytes,
        ...ivBytes,
        ...cipherBytes,
      ]);

      final hmac = Hmac(sha256, signKey);
      final hmacDigest = hmac.convert(headerAndCipher);

      final fullToken = Uint8List.fromList([
        ...headerAndCipher,
        ...hmacDigest.bytes,
      ]);

      final b64 = base64Url.encode(fullToken);
      return 'enc:$b64';
    } catch (e) {
      return s;
    }
  }
}
