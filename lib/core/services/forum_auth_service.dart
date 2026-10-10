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
          'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
        body: jsonEncode({'params': encryptedParams}),
      ).timeout(const Duration(seconds: 15));

      Map<String, dynamic> resData = {};
      try {
        resData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {}

      // Nếu gateway v3 trả về thành công với code ok
      if (response.statusCode == 200 &&
          resData['data'] != null &&
          resData['data']['status'] != null &&
          resData['data']['status']['code'] == 'ok') {
        return {
          'statusCode': 200,
          'body': resData,
        };
      }

      // Nếu API gateway bị lỗi 500, 502 hoặc trả về fail, fallback xác thực trực tiếp qua type.vn
      final directResult = await loginDirectTypeVn(username: username, password: password);
      if (directResult['statusCode'] == 200) {
        return directResult;
      }

      return {
        'statusCode': response.statusCode,
        'body': resData,
      };
    } catch (_) {
      // Khi mạng timeout hoặc gateway chết hẳn, fallback sang type.vn
      return await loginDirectTypeVn(username: username, password: password);
    }
  }

  /// Xác thực trực tiếp qua diễn đàn type.vn (Cơ chế fallback chuẩn của ai.type)
  Future<Map<String, dynamic>> loginDirectTypeVn({
    required String username,
    required String password,
  }) async {
    try {
      String getCookieStr(Map<String, String> headers) {
        final raw = headers['set-cookie'] ?? headers['Set-Cookie'] ?? '';
        if (raw.isEmpty) return '';
        return raw.split(';')[0];
      }

      // 1. Lấy CSRF token và initial session cookie từ /api/config
      final configRes = await _client.get(
        Uri.parse('https://type.vn/api/config'),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 12));

      if (configRes.statusCode != 200) {
        return {
          'statusCode': configRes.statusCode,
          'body': {'message': 'Không thể kết nối đến máy chủ type.vn'},
        };
      }

      final configData = jsonDecode(utf8.decode(configRes.bodyBytes)) as Map<String, dynamic>? ?? {};
      final csrfToken = configData['csrf_token']?.toString() ?? '';
      final initialCookie = getCookieStr(configRes.headers);

      if (csrfToken.isEmpty) {
        return {
          'statusCode': 500,
          'body': {'message': 'Không thể khởi tạo phiên đăng nhập từ type.vn'},
        };
      }

      // 2. Thực hiện đăng nhập vào https://type.vn/login
      final loginRes = await _client.post(
        Uri.parse('https://type.vn/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/plain, */*',
          'x-csrf-token': csrfToken,
          if (initialCookie.isNotEmpty) 'Cookie': initialCookie,
          'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
        body: jsonEncode({
          'username': username,
          'password': password,
          '_csrf': csrfToken,
        }),
      ).timeout(const Duration(seconds: 12));

      if (loginRes.statusCode != 200) {
        return {
          'statusCode': 401,
          'body': {'message': 'Email hoặc mật khẩu không chính xác.'},
        };
      }

      final sessionCookie = getCookieStr(loginRes.headers).isNotEmpty
          ? getCookieStr(loginRes.headers)
          : initialCookie;

      // 3. Lấy định danh slug người dùng hiện tại qua /api/me
      final meRes = await _client.get(
        Uri.parse('https://type.vn/api/me'),
        headers: {
          'Accept': 'application/json',
          if (sessionCookie.isNotEmpty) 'Cookie': sessionCookie,
          'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 10));

      var rawMe = '';
      if (meRes.statusCode == 200) {
        final decodedMe = jsonDecode(utf8.decode(meRes.bodyBytes));
        rawMe = decodedMe is String ? decodedMe : decodedMe.toString();
      }

      final userSlug = rawMe.replaceFirst(RegExp(r'^/user/'), '').trim().isNotEmpty
          ? rawMe.replaceFirst(RegExp(r'^/user/'), '').trim()
          : username;

      // 4. Lấy chi tiết hồ sơ tài khoản từ /api/user/:slug
      final userRes = await _client.get(
        Uri.parse('https://type.vn/api/user/${Uri.encodeComponent(userSlug)}'),
        headers: {
          'Accept': 'application/json',
          if (sessionCookie.isNotEmpty) 'Cookie': sessionCookie,
          'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 10));

      if (userRes.statusCode != 200) {
        return {
          'statusCode': userRes.statusCode,
          'body': {'message': 'Không thể tải thông tin tài khoản từ diễn đàn.'},
        };
      }

      final u = jsonDecode(utf8.decode(userRes.bodyBytes)) as Map<String, dynamic>? ?? {};
      if (u['uid'] == null) {
        return {
          'statusCode': 400,
          'body': {'message': 'Không tìm thấy dữ liệu người dùng.'},
        };
      }

      // 5. Lấy danh sách nhóm người dùng từ /api/user/:slug/groups
      final userGroups = <String>[];
      try {
        final groupsRes = await _client.get(
          Uri.parse('https://type.vn/api/user/${Uri.encodeComponent(userSlug)}/groups'),
          headers: {
            'Accept': 'application/json',
            if (sessionCookie.isNotEmpty) 'Cookie': sessionCookie,
            'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        ).timeout(const Duration(seconds: 10));

        if (groupsRes.statusCode == 200) {
          final gData = jsonDecode(utf8.decode(groupsRes.bodyBytes));
          if (gData is Map && gData['groups'] is List) {
            for (final grp in gData['groups']) {
              final slug = grp['slug']?.toString() ?? '';
              if (slug.isNotEmpty && !userGroups.contains(slug)) {
                userGroups.add(slug);
              }
            }
          }
        }
      } catch (_) {}

      return {
        'statusCode': 200,
        'body': {
          'data': {
            'status': {'code': 'ok', 'message': 'OK'},
            'response': {
              'uid': u['uid'],
              'username': u['username'] ?? username,
              'picture': u['picture'],
              'postcount': u['postcount'] ?? 0,
              'reputation': u['reputation'] ?? 0,
              'status': u['status'] ?? 'online',
              'groups': userGroups,
            },
          },
        },
      };
    } catch (e) {
      return {
        'statusCode': 0,
        'error': e.toString(),
        'body': {'message': 'Lỗi kết nối diễn đàn: $e'},
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
