import 'dart:convert';
import 'package:http/http.dart' as http;
import 'crypto_helper.dart';

class ForumAuthService {
  static const Map<String, String> apiEndpoints = {
    'local': 'http://localhost:1122/v1',
    'vn.s1': 'https://apiv1.type.vn/v1',
    'vn.s2': 'https://apiv2.type.vn/v1',
    'vn.s3': 'https://apiv3.type.vn/v1',
  };

  final http.Client _client = http.Client();

  String _getBaseUrl(String server) {
    return apiEndpoints[server] ?? 'https://apiv3.type.vn/v1';
  }

  /// Gọi API đăng nhập /forum/login/v3 theo chuẩn mã hoá của ai.type
  Future<Map<String, dynamic>> loginV3({
    required String username,
    required String password,
    required String server,
    required bool rememberMe,
  }) async {
    final baseUrl = _getBaseUrl(server);
    final url = Uri.parse('$baseUrl/forum/login/v3');

    final payload = {
      'username': username,
      'password': password,
      'server': server,
      'rememberMe': rememberMe,
    };

    final encryptedParams = CryptoHelper.encrypt(payload);

    try {
      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'params': encryptedParams}),
      ).timeout(const Duration(seconds: 15));

      Map<String, dynamic> resData = {};
      try {
        resData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {}

      return {
        'statusCode': response.statusCode,
        'body': resData,
      };
    } catch (e) {
      return {
        'statusCode': 0,
        'error': e.toString(),
      };
    }
  }

  /// Lấy danh sách nhóm quyền từ /forum/groups
  Future<Map<String, dynamic>?> getGroups(String server) async {
    final baseUrl = _getBaseUrl(server);
    final url = Uri.parse('$baseUrl/forum/groups');

    final payload = {'server': server};
    final encryptedParams = CryptoHelper.encrypt(payload);

    try {
      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'params': encryptedParams}),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
