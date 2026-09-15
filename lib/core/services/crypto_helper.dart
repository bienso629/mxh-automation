import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

class CryptoHelper {
  static const String defaultGenKey = '31d0a5e6e04fc470418db218464e8ac165816e8309afdd801725e3c2f42c43b8';
  static const String jwtSecret = 'sh-0hPYnFVwEa5ydU9zWP9ET3BlbkFJeb81DqndysS0Zun3pOmK';

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
  static String encrypt(Map<String, dynamic> data, [String key = defaultGenKey]) {
    final plainText = jsonEncode(data);
    final salt = enc.SecureRandom(8).bytes;
    final derived = _evpBytesToKey(key, salt, 32, 16);
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
  static dynamic decrypt(String cipherTextBase64, [String key = defaultGenKey]) {
    try {
      final raw = base64.decode(cipherTextBase64);
      if (raw.length < 16) return null;

      final header = utf8.decode(raw.sublist(0, 8), allowMalformed: true);
      if (header != 'Salted__') return null;

      final salt = raw.sublist(8, 16);
      final cipherBytes = raw.sublist(16);

      final derived = _evpBytesToKey(key, salt, 32, 16);
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
