import 'dart:convert';
import 'package:http/http.dart' as http;
import 'crypto_helper.dart';

class LiveGroupCheckResult {
  /// true khi máy chủ phản hồi xác thực rõ ràng trạng thái thành viên nhóm.
  /// false khi mất mạng / lỗi máy chủ / phiên chưa đủ quyền (không được đăng xuất nhầm).
  final bool verified;
  final List<String> groups;
  final String? source;

  const LiveGroupCheckResult({
    required this.verified,
    this.groups = const [],
    this.source,
  });
}

class ForumAuthService {
  static const String _chromeUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

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
      if (directResult['statusCode'] == 200 || directResult['statusCode'] != 0) {
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
        String msg = 'Email hoặc mật khẩu không chính xác.';
        try {
          final errBody = utf8.decode(loginRes.bodyBytes);
          if (errBody.contains('account-locked')) {
            msg = 'Tài khoản diễn đàn type.vn của bạn hiện đang bị tạm khóa (account-locked). Vui lòng liên hệ quản trị viên để mở khóa.';
          } else if (errBody.contains('invalid-credentials') || errBody.contains('user-not-found')) {
            msg = 'Email hoặc mật khẩu không chính xác.';
          } else if (errBody.isNotEmpty && !errBody.startsWith('<')) {
            final decoded = jsonDecode(errBody);
            if (decoded is Map && decoded['message'] != null) {
              msg = decoded['message'].toString();
            }
          }
        } catch (_) {}

        return {
          'statusCode': loginRes.statusCode,
          'body': {'message': msg},
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
              if (grp is Map) {
                final slug = grp['slug']?.toString().trim() ?? '';
                final name = grp['name']?.toString().trim() ?? '';
                final displayName = grp['displayName']?.toString().trim() ?? '';
                if (slug.isNotEmpty && !userGroups.contains(slug)) {
                  userGroups.add(slug);
                }
                if (name.isNotEmpty && !userGroups.contains(name)) {
                  userGroups.add(name);
                }
                if (displayName.isNotEmpty && !userGroups.contains(displayName)) {
                  userGroups.add(displayName);
                }
              } else if (grp != null) {
                final str = grp.toString().trim();
                if (str.isNotEmpty && !userGroups.contains(str)) {
                  userGroups.add(str);
                }
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
              if (u['email'] != null && u['email'].toString().trim().isNotEmpty)
                'email': u['email'].toString().trim(),
              'picture': u['picture'],
              'postcount': u['postcount'] ?? 0,
              'reputation': u['reputation'] ?? 0,
              'status': u['status'] ?? 'online',
              'groups': userGroups,
              if (sessionCookie.isNotEmpty) '_session_cookie': sessionCookie,
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
          'User-Agent': _chromeUserAgent,
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

  static bool _isTargetActorGroup(String slugOrName) {
    final g = slugOrName.toLowerCase().trim();
    final normalized = g
        .replaceAll('đ', 'd')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('_', '-')
        .replaceAll(' ', '-');
    return g == 'nhóm-diễn-viên-mxh' ||
        g == 'nhom-dien-vien-mxh' ||
        g == 'nhóm diễn viên mxh' ||
        g == 'nhom dien vien mxh' ||
        normalized == 'nhom-dien-vien-mxh' ||
        (normalized.contains('nhom') && normalized.contains('dien-vien') && normalized.contains('mxh')) ||
        normalized.contains('dien-vien-mxh') ||
        (normalized.contains('dien-vien') && normalized.contains('mxh'));
  }

  /// Trích xuất danh sách nhóm của user từ phản hồi `/forum/groups`.
  /// Đánh dấu `verified: true` nếu tìm thấy user trong nhóm mục tiêu/quản trị, HOẶC danh sách thành viên của
  /// nhóm `nhóm-diễn-viên-mxh` đầy đủ (`members.length >= memberCount`) và không chứa user.
  static LiveGroupCheckResult extractLiveGroupResultFromForumGroups({
    required Map<String, dynamic>? groupsRes,
    String? uid,
    String? username,
    String? email,
  }) {
    if (groupsRes == null || groupsRes['success'] != true || groupsRes['data'] is! Map) {
      return const LiveGroupCheckResult(verified: false);
    }
    final dataMap = groupsRes['data'] as Map;
    if (dataMap['groups'] is! List) {
      return const LiveGroupCheckResult(verified: false);
    }

    final groupsList = dataMap['groups'] as List;
    final cleanUid = uid?.trim() ?? '';
    final cleanUser = username?.trim().toLowerCase() ?? '';
    final cleanSlug = cleanUser.replaceAll(' ', '-');
    final emailPrefix = (email != null && email.contains('@'))
        ? email.split('@').first.trim().toLowerCase()
        : '';

    if (cleanUid.isEmpty && cleanUser.isEmpty && emailPrefix.isEmpty) {
      return const LiveGroupCheckResult(verified: false);
    }

    final matchedGroups = <String>[];
    bool actorGroupFoundInPayload = false;
    bool actorGroupMembersComplete = false;
    bool userInActorGroup = false;

    for (final rawGroup in groupsList) {
      if (rawGroup is! Map) continue;
      final slug = rawGroup['slug']?.toString().trim() ?? '';
      final name = rawGroup['name']?.toString().trim() ?? '';
      final displayName = rawGroup['displayName']?.toString().trim() ?? '';
      final members = rawGroup['members'] is List ? rawGroup['members'] as List : const [];
      final memberCount = int.tryParse(rawGroup['memberCount']?.toString() ?? '') ?? members.length;

      final isActorGrp = _isTargetActorGroup(slug) ||
          _isTargetActorGroup(name) ||
          _isTargetActorGroup(displayName);
      if (isActorGrp) {
        actorGroupFoundInPayload = true;
        if (members.length >= memberCount) {
          actorGroupMembersComplete = true;
        }
      }

      bool isMember = false;
      for (final rawMember in members) {
        if (rawMember is! Map) continue;
        final mUid = rawMember['uid']?.toString().trim() ?? '';
        final mUsername = rawMember['username']?.toString().trim().toLowerCase() ?? '';
        final mSlug = rawMember['userslug']?.toString().trim().toLowerCase() ?? '';
        final mDisplay = rawMember['displayname']?.toString().trim().toLowerCase() ?? '';

        if ((cleanUid.isNotEmpty && mUid == cleanUid) ||
            (cleanUser.isNotEmpty && (mUsername == cleanUser || mDisplay == cleanUser || mSlug == cleanSlug)) ||
            (emailPrefix.isNotEmpty && (mUsername == emailPrefix || mSlug == emailPrefix))) {
          isMember = true;
          break;
        }
      }

      if (isMember) {
        if (slug.isNotEmpty && !matchedGroups.contains(slug)) matchedGroups.add(slug);
        if (name.isNotEmpty && !matchedGroups.contains(name)) matchedGroups.add(name);
        if (displayName.isNotEmpty && !matchedGroups.contains(displayName)) matchedGroups.add(displayName);
        if (isActorGrp) {
          userInActorGroup = true;
        }
      }
    }

    if (userInActorGroup) {
      return LiveGroupCheckResult(verified: true, groups: matchedGroups, source: 'forum_groups');
    }

    // Nếu nhóm `nhóm-diễn-viên-mxh` có mặt đầy đủ danh sách thành viên (không bị phân trang cắt bớt)
    // mà tài khoản không còn trong đó -> xác thực chắc chắn đã bị gỡ khỏi nhóm.
    if (actorGroupFoundInPayload && actorGroupMembersComplete) {
      return LiveGroupCheckResult(verified: true, groups: matchedGroups, source: 'forum_groups');
    }

    return const LiveGroupCheckResult(verified: false);
  }

  /// Lấy danh sách nhóm của user trực tiếp từ https://type.vn/api/user/:slug/groups (có thể kèm session cookie)
  Future<LiveGroupCheckResult> fetchUserGroupsLiveByUsername(
    String username, {
    String? sessionCookie,
  }) async {
    final groups = <String>[];
    if (username.trim().isEmpty) {
      return const LiveGroupCheckResult(verified: false);
    }
    try {
      final userSlug = username.trim().toLowerCase().replaceAll(' ', '-');
      final res = await _client.get(
        Uri.parse('https://type.vn/api/user/${Uri.encodeComponent(userSlug)}/groups'),
        headers: {
          'Accept': 'application/json',
          if (sessionCookie != null && sessionCookie.trim().isNotEmpty) 'Cookie': sessionCookie.trim(),
          'User-Agent': _chromeUserAgent,
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final gData = jsonDecode(utf8.decode(res.bodyBytes));
        if (gData is Map) {
          final statusCodeStr = (gData['status'] is Map) ? gData['status']['code']?.toString() : null;
          if (statusCodeStr == 'not-authorised' || statusCodeStr == 'forbidden') {
            return const LiveGroupCheckResult(verified: false);
          }
          if (gData['groups'] is List) {
            for (final grp in gData['groups']) {
              if (grp is Map) {
                final slug = grp['slug']?.toString().trim() ?? '';
                final name = grp['name']?.toString().trim() ?? '';
                final displayName = grp['displayName']?.toString().trim() ?? '';
                if (slug.isNotEmpty && !groups.contains(slug)) groups.add(slug);
                if (name.isNotEmpty && !groups.contains(name)) groups.add(name);
                if (displayName.isNotEmpty && !groups.contains(displayName)) groups.add(displayName);
              } else if (grp != null) {
                final str = grp.toString().trim();
                if (str.isNotEmpty && !groups.contains(str)) groups.add(str);
              }
            }
            return LiveGroupCheckResult(verified: true, groups: groups, source: 'type_vn_user_groups');
          }
        }
      }
    } catch (_) {}
    return const LiveGroupCheckResult(verified: false);
  }

  /// Lấy danh sách nhóm của user trực tiếp từ https://type.vn/api/user/:slug/groups
  Future<List<String>> fetchUserGroupsByUsername(String username, {String? sessionCookie}) async {
    final res = await fetchUserGroupsLiveByUsername(username, sessionCookie: sessionCookie);
    return res.groups;
  }

  /// Kiểm tra trực tuyến danh sách nhóm hiện tại của tài khoản trên diễn đàn type.vn.
  /// Ưu tiên `/forum/groups` (hoạt động không cần cookie), fallback sang `vn.s3` và `type.vn/api/user/:slug/groups` nếu cần.
  Future<LiveGroupCheckResult> verifyUserGroupsLive({
    String? uid,
    String? username,
    String? email,
    String server = 'vn.s3',
    String? sessionCookie,
  }) async {
    final serversToTry = <String>[
      if (server.trim().isNotEmpty) server.trim(),
      if (server.trim() != 'vn.s3') 'vn.s3',
    ];

    for (final srv in serversToTry) {
      final groupsRes = await getGroups(srv);
      final parsed = extractLiveGroupResultFromForumGroups(
        groupsRes: groupsRes,
        uid: uid,
        username: username,
        email: email,
      );
      if (parsed.verified) {
        return parsed;
      }
    }

    // Dự phòng bằng phiên cookie trực tiếp trên type.vn (hữu ích khi nhóm có nhiều thành viên bị phân trang)
    if (sessionCookie != null && sessionCookie.trim().isNotEmpty && username != null && username.trim().isNotEmpty) {
      final direct = await fetchUserGroupsLiveByUsername(username, sessionCookie: sessionCookie);
      if (direct.verified) {
        return direct;
      }
    }

    return const LiveGroupCheckResult(verified: false);
  }
}
