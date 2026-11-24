import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

class CryptoHelper {
  static const String _envGenKey = String.fromEnvironment('FORUM_CRYPTO_KEY');
  static const String _envJwtSecret = String.fromEnvironment('JWT_SECRET_KEY');
  static const String _envMultiAccountSecret = String.fromEnvironment('MULTI_ACCOUNT_SECRET');

  static const List<int> _obfGenKey = [
    105, 72, 252, 135, 183, 192, 113, 5, 55, 65, 164, 201, 173, 217, 59, 27,
    126, 88, 176, 195, 164, 215, 53, 27, 118, 87, 180, 250, 134, 188, 159, 42,
    12, 108, 64, 166, 128, 176, 204, 32, 2, 104, 17, 233, 202, 169, 212, 59,
    27, 126, 90, 178, 195, 246, 135, 49, 68, 117, 82, 28, 170, 142, 190, 195,
  ];
  static const List<int> _obfJwtSecret = [
    208, 170, 204, 48, 119, 110, 4, 18, 221, 236, 174, 189, 118, 3, 44, 16,
    198, 139, 171, 167, 95, 23, 8, 56, 184, 232, 165, 138, 108, 96, 15, 1,
    225, 154, 240, 164, 142, 112, 89, 37, 8, 201, 137, 130, 130, 120, 6, 36,
    60, 255, 250,
  ];
  static const List<int> _obfMultiAccountSecret = [
    28, 245, 228, 174, 128, 104, 82, 9, 6, 241, 208, 160, 148, 100, 112, 37,
    8, 245, 244, 248, 217, 58, 17, 25, 68, 196, 128,
  ];

  static String _decodeSecret(List<int> encoded, int mask) {
    final out = List<int>.generate(
      encoded.length,
      (i) => encoded[i] ^ ((mask + i * 31) & 0xFF),
      growable: false,
    );
    return utf8.decode(out);
  }

  static String? _cachedGenKey;
  static String? _cachedJwtSecret;
  static String? _cachedMultiAccountSecret;

  static String get defaultGenKey =>
      _cachedGenKey ??= _envGenKey.isNotEmpty ? _envGenKey : _decodeSecret(_obfGenKey, 0x5A);

  static String get jwtSecret =>
      _cachedJwtSecret ??= _envJwtSecret.isNotEmpty ? _envJwtSecret : _decodeSecret(_obfJwtSecret, 0xA3);

  static String get multiAccountSecret => _cachedMultiAccountSecret ??=
      _envMultiAccountSecret.isNotEmpty ? _envMultiAccountSecret : _decodeSecret(_obfMultiAccountSecret, 0x7D);

  static Uint8List _evpBytesToKey(String password, Uint8List salt, int keyLen, int ivLen) {
    final passBytes = utf8.encode(password);
    final totalLen = keyLen + ivLen;
    final d = <int>[];
    var currentD = <int>[];

    while (d.length < totalLen) {
      final buffer = <int>[];
      if (currentD.isNotEmpty) {
        buffer.addAll(currentD);
      }
      buffer.addAll(passBytes);
      buffer.addAll(salt);

      currentD = md5.convert(buffer).bytes;
      d.addAll(currentD);
    }

    return Uint8List.fromList(d.sublist(0, totalLen));
  }

  /// Encrypts an object to match CryptoJS / crypto-ts AES password format:
  /// Base64('Salted__' + 8-byte salt + AES-256-CBC ciphertext)
  static String encrypt(Map<String, dynamic> data, [String? key]) {
    final effectiveKey = (key != null && key.isNotEmpty) ? key : defaultGenKey;
    final plainText = jsonEncode(data);
    final salt = enc.SecureRandom(8).bytes;
    final derived = _evpBytesToKey(effectiveKey, salt, 32, 16);
    final keyBytes = derived.sublist(0, 32);
    final ivBytes = derived.sublist(32, 48);

    final aesKey = enc.Key(keyBytes);
    final iv = enc.IV(ivBytes);
    final encrypter = enc.Encrypter(enc.AES(aesKey, mode: enc.AESMode.cbc));

    final encrypted = encrypter.encrypt(plainText, iv: iv);

    final header = utf8.encode('Salted__');
    final result = Uint8List(header.length + salt.length + encrypted.bytes.length);
    result.setRange(0, 8, header);
    result.setRange(8, 16, salt);
    result.setRange(16, result.length, encrypted.bytes);

    return base64.encode(result);
  }

  /// Decrypts ciphertext formatted with OpenSSL / CryptoJS 'Salted__' header
  static dynamic decrypt(String cipherTextBase64, [String? key]) {
    try {
      final effectiveKey = (key != null && key.isNotEmpty) ? key : defaultGenKey;
      final raw = base64.decode(cipherTextBase64);
      if (raw.length < 16) return null;

      final header = utf8.decode(raw.sublist(0, 8), allowMalformed: true);
      if (header != 'Salted__') return null;

      final salt = raw.sublist(8, 16);
      final cipherBytes = raw.sublist(16);

      final derived = _evpBytesToKey(effectiveKey, salt, 32, 16);
      final keyBytes = derived.sublist(0, 32);
      final ivBytes = derived.sublist(32, 48);

      final aesKey = enc.Key(keyBytes);
      final iv = enc.IV(ivBytes);
      final encrypter = enc.Encrypter(enc.AES(aesKey, mode: enc.AESMode.cbc));

      final decrypted = encrypter.decrypt(enc.Encrypted(cipherBytes), iv: iv);
      return jsonDecode(decrypted);
    } catch (_) {
      return null;
    }
  }

  /// Generates mock JWT token compatible with ai.type AuthUtils
  static String generateJWTToken(Map<String, dynamic> user) {
    final header = {'alg': 'HS256', 'typ': 'JWT'};
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final exp = now + 7 * 24 * 3600; // 7 days

    final payload = {
      'iat': now,
      'iss': 'ai.type',
      'exp': exp,
      'user': user,
    };

    String base64UrlEncode(String input) {
      return base64Url.encode(utf8.encode(input)).replaceAll('=', '');
    }

    final encodedHeader = base64UrlEncode(jsonEncode(header));
    final encodedPayload = base64UrlEncode(jsonEncode(payload));
    final dataToSign = '$encodedHeader.$encodedPayload';

    final hmac = Hmac(sha256, utf8.encode(jwtSecret));
    final digest = hmac.convert(utf8.encode(dataToSign));
    final signature = base64Url.encode(digest.bytes).replaceAll('=', '');

    return '$encodedHeader.$encodedPayload.$signature';
  }
}
