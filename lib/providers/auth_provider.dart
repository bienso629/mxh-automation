import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/services/crypto_helper.dart';
import '../core/services/database_service.dart';
import '../core/services/forum_auth_service.dart';
import '../core/services/local_config_service.dart';
import '../core/services/multi_account_service.dart';
import '../core/services/persona_service.dart';
import '../core/services/storage_service.dart';

typedef LiveGroupChecker = Future<LiveGroupCheckResult> Function({
  String? uid,
  String? username,
  String? email,
  required String server,
  String? sessionCookie,
});

class AuthProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final DatabaseService _db = DatabaseService();
  final LocalConfigService _localConfig = LocalConfigService();
  final PersonaService _persona = PersonaService();
  final MultiAccountService _multiAccount = MultiAccountService();
  final ForumAuthService _forumAuth = ForumAuthService();

  /// Hook tùy chọn phục vụ kiểm thử đơn vị mà không cần gọi mạng thật tới type.vn
  LiveGroupChecker? liveGroupCheckerOverride;
  Duration groupCheckInterval = const Duration(seconds: 60);
  final bool _enablePeriodicCheck;

  bool _isLoading = false;
  bool _isCheckingAuth = true;
  bool _isAuthenticated = false;
  bool _isVerifyingLiveGroups = false;
  String? _userUid;
  String? _userEmail;
  String? _userName;
  String? _authToken;
  String? _forumSessionCookie;
  String? _avatar;
  String? _selectedServer = 'vn.s3';
  String? _errorMessage;
  String _activeUserKey = '';
  List<AccountProfile> _accounts = [];
  List<String> _userGroups = [];
  Timer? _groupMonitorTimer;

  bool get isLoading => _isLoading;
  bool get isCheckingAuth => _isCheckingAuth;
  bool get isAuthenticated => _isAuthenticated;
  String? get userUid => _userUid;
  String? get userEmail => _userEmail;
  String? get userName => _userName;
  String? get authToken => _authToken;
  String? get avatar => _avatar;
  String get selectedServer => _selectedServer ?? 'vn.s3';
  String? get errorMessage => _errorMessage;
  String get activeUserKey => _activeUserKey;
  List<AccountProfile> get accounts => _accounts;
  List<String> get userGroups => _userGroups;

  static bool isActorGroup(String group) {
    final g = group.toLowerCase().trim();
    // Bỏ qua dấu gạch ngang/dưới và dấu tiếng Việt để so sánh linh hoạt
    final normalized = g
        .replaceAll('đ', 'd')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('_', '-')
        .replaceAll(' ', '-');

    if (g == 'nhóm-diễn-viên-mxh' ||
        g == 'nhom-dien-vien-mxh' ||
        g == 'nhóm diễn viên mxh' ||
        g == 'nhom dien vien mxh' ||
        normalized == 'nhom-dien-vien-mxh' ||
        (normalized.contains('nhom') && normalized.contains('dien-vien') && normalized.contains('mxh')) ||
        normalized.contains('dien-vien-mxh') ||
        (normalized.contains('dien-vien') && normalized.contains('mxh'))) {
      return true;
    }
    return false;
  }

  static bool checkActorAccess({
    String? email,
    String? name,
    List<String>? groups,
  }) {
    final em = (email ?? '').toLowerCase().trim();
    final nm = (name ?? '').toLowerCase().trim();
    // Tài khoản admin hệ thống luôn có quyền quản trị và vận hành
    if (nm == 'admin' ||
        em.contains('admin') ||
        em == 'local.admin@type.vn' ||
        em == 'admin@type.vn' ||
        em.startsWith('admin@') ||
        em.contains('typing.vn')) {
      return true;
    }

    if (groups != null) {
      for (final g in groups) {
        final slug = g.toLowerCase().trim();
        if (slug.contains('admin') ||
            slug.contains('quan-tri') ||
            slug == 'administrators' ||
            slug.contains('lap-trinh')) {
          return true;
        }
        if (isActorGroup(g)) {
          return true;
        }
      }
    }
    return false;
  }

  bool get hasActorRole {
    if (isAdmin) return true;
    return checkActorAccess(
      email: _userEmail,
      name: _userName,
      groups: _userGroups,
    );
  }

  bool get isAdmin {
    final email = (_userEmail ?? '').toLowerCase().trim();
    final name = (_userName ?? '').toLowerCase().trim();
    if (name == 'admin' ||
        email.contains('admin') ||
        email == 'local.admin@type.vn' ||
        email == 'admin@type.vn' ||
        email.startsWith('admin@') ||
        email.contains('typing.vn')) {
      return true;
    }
    for (final g in _userGroups) {
      final slug = g.toLowerCase();
      if (slug.contains('admin') || slug.contains('quan-tri') || slug == 'administrators' || slug.contains('lap-trinh')) {
        return true;
      }
    }
    // Kiểm tra trong danh sách accounts
    final activeAcc = _accounts.where((a) => a.isActive).firstOrNull;
    if (activeAcc != null) {
      final accName = (activeAcc.name ?? '').toLowerCase().trim();
      final accEmail = (activeAcc.email ?? '').toLowerCase().trim();
      if (accName == 'admin' || accEmail.contains('admin') || accEmail.contains('typing.vn')) {
        return true;
      }
      for (final g in activeAcc.groups) {
        final slug = g.toLowerCase();
        if (slug.contains('admin') || slug.contains('quan-tri') || slug == 'administrators' || slug.contains('lap-trinh')) {
          return true;
        }
      }
    }
    return false;
  }

  set selectedServer(String server) {
    _selectedServer = server;
    notifyListeners();
  }

  AuthProvider({
    bool autoCheck = true,
    bool enablePeriodicCheck = true,
  }) : _enablePeriodicCheck = enablePeriodicCheck {
    if (autoCheck) {
      checkAuthStatus();
    } else {
      _isCheckingAuth = false;
    }
  }

  @override
  void dispose() {
    _stopGroupMembershipMonitor();
    super.dispose();
  }

  void _startGroupMembershipMonitor() {
    _stopGroupMembershipMonitor();
    if (!_enablePeriodicCheck || !_isAuthenticated) return;
    if (_authToken == 'native_local_token') return;
    _groupMonitorTimer = Timer.periodic(groupCheckInterval, (_) {
      unawaited(verifyLiveGroupMembership());
    });
  }

  void _stopGroupMembershipMonitor() {
    _groupMonitorTimer?.cancel();
    _groupMonitorTimer = null;
  }

  Future<LiveGroupCheckResult> _checkLiveGroups({
    String? uid,
    String? username,
    String? email,
    String? server,
    String? sessionCookie,
  }) async {
    final effectiveServer = (server != null && server.trim().isNotEmpty) ? server.trim() : selectedServer;
    if (liveGroupCheckerOverride != null) {
      return liveGroupCheckerOverride!(
        uid: uid,
        username: username,
        email: email,
        server: effectiveServer,
        sessionCookie: sessionCookie,
      );
    }
    return _forumAuth.verifyUserGroupsLive(
      uid: uid,
      username: username,
      email: email,
      server: effectiveServer,
      sessionCookie: sessionCookie,
    );
  }

  Future<void> _forceLogoutDueToGroupRemoval({
    required String message,
    List<String>? latestGroups,
    String? targetUid,
    String? targetEmail,
    String? targetUsername,
  }) async {
    _stopGroupMembershipMonitor();
    if (latestGroups != null) {
      try {
        await _multiAccount.updateAccountGroups(
          uid: targetUid ?? _userUid,
          email: targetEmail ?? _userEmail,
          username: targetUsername ?? _userName,
          groups: latestGroups,
        );
      } catch (_) {}
    }

    await _storage.clearAuth();
    _isAuthenticated = false;
    _authToken = null;
    _forumSessionCookie = null;
    _userUid = null;
    _userEmail = null;
    _userName = null;
    _avatar = null;
    _userGroups = [];
    _activeUserKey = '';
    _errorMessage = message;
    await _db.closeForLogout();
    await _localConfig.clearForLogout();
    _persona.switchUser('');
    await refreshAccountsList(notify: false);
    notifyListeners();
  }

  /// Kiểm tra trực tuyến tư cách thành viên nhóm "nhóm-diễn-viên-mxh" cho tài khoản đang đăng nhập.
  /// Nếu máy chủ xác thực tài khoản đã bị gỡ khỏi nhóm -> tự động đăng xuất ngay lập tức.
  /// Nếu lỗi mạng tạm thời (`verified: false`) -> giữ nguyên phiên để tránh đăng xuất nhầm.
  Future<bool> verifyLiveGroupMembership() async {
    if (!_isAuthenticated || _isVerifyingLiveGroups) return _isAuthenticated;
    if (_authToken == 'native_local_token') return true;
    // Tài khoản admin hệ thống không bị phụ thuộc nhóm thường
    if (checkActorAccess(email: _userEmail, name: _userName, groups: const [])) {
      return true;
    }

    _isVerifyingLiveGroups = true;
    try {
      final liveRes = await _checkLiveGroups(
        uid: _userUid,
        username: _userName,
        email: _userEmail,
        server: _selectedServer,
        sessionCookie: _forumSessionCookie,
      );
      if (!liveRes.verified || !_isAuthenticated) {
        return _isAuthenticated;
      }

      final stillHasAccess = checkActorAccess(
        email: _userEmail,
        name: _userName,
        groups: liveRes.groups,
      );

      if (!stillHasAccess) {
        await _forceLogoutDueToGroupRemoval(
          message:
              'Tài khoản của bạn đã bị gỡ khỏi nhóm "nhóm-diễn-viên-mxh" trên diễn đàn type.vn và đã được tự động đăng xuất.',
          latestGroups: liveRes.groups,
        );
        return false;
      }

      // Cập nhật lại danh sách nhóm mới nhất khi vẫn còn quyền
      final changed = _userGroups.length != liveRes.groups.length ||
          !_userGroups.toSet().containsAll(liveRes.groups);
      _userGroups = List<String>.from(liveRes.groups);
      try {
        await _multiAccount.updateAccountGroups(
          uid: _userUid,
          email: _userEmail,
          username: _userName,
          groups: _userGroups,
        );
      } catch (_) {}
      if (changed) {
        await refreshAccountsList(notify: false);
        notifyListeners();
      }
      return true;
    } catch (_) {
      return _isAuthenticated;
    } finally {
      _isVerifyingLiveGroups = false;
    }
  }

  Future<void> refreshAccountsList({bool notify = true}) async {
    _accounts = await _multiAccount.getAllAccounts();
    if (notify) {
      notifyListeners();
    }
  }

  /// Xác định khóa lưu trữ ổn định duy nhất (userKey) cho tài khoản.
  /// - Tránh tạo DB rỗng mới khi người dùng lúc đăng nhập bằng email, lúc đăng nhập bằng username của CÙNG 1 tài khoản (cùng uid).
  /// - Tránh va chạm dữ liệu khi 2 tài khoản KHÁC NHAU có cùng phần tên trước dấu '@' (vd: foo@gmail.com và foo@type.vn).
  Future<String> _resolveCanonicalUserKey({
    String? uid,
    String? username,
    String? respEmail,
    required String typedInput,
  }) async {
    final cleanUid = uid?.trim() ?? '';
    final cleanUsername = username?.trim() ?? '';
    final cleanRespEmail = respEmail?.trim() ?? '';
    final cleanTyped = typedInput.trim();
    final canonicalEmail = cleanRespEmail.isNotEmpty
        ? cleanRespEmail
        : (cleanTyped.contains('@') ? cleanTyped : '');

    // 1. Ưu tiên tái sử dụng userKey của chính tài khoản này đã lưu trong MultiAccountService
    final matched = await _multiAccount.findMatchingAccount(
      uid: cleanUid,
      email: canonicalEmail.isNotEmpty ? canonicalEmail : cleanTyped,
      username: cleanUsername,
    );
    if (matched != null) {
      if (matched.userKey != null && matched.userKey!.trim().isNotEmpty) {
        return matched.userKey!.trim();
      }
      final legacyFromMatched = StorageService.sanitizeUserKey(
        (matched.email != null && matched.email!.trim().isNotEmpty)
            ? matched.email
            : matched.id,
      );
      if (legacyFromMatched.isNotEmpty && DatabaseService.hasUserDataOnDisk(legacyFromMatched)) {
        return legacyFromMatched;
      }
    }

    // Gom tập các khóa đang thuộc sở hữu của TÀI KHOẢN KHÁC để chống đè dữ liệu
    final allSaved = await _multiAccount.getAllAccounts();
    final keysOwnedByOthers = <String>{};
    for (final acc in allSaved) {
      final isSameUid = cleanUid.isNotEmpty && acc.uid != null && acc.uid!.trim() == cleanUid;
      final isSameEmail = canonicalEmail.isNotEmpty &&
          (acc.email?.trim().toLowerCase() == canonicalEmail.toLowerCase() ||
              acc.id.trim().toLowerCase() == canonicalEmail.toLowerCase());
      final isSameUsername = cleanUsername.isNotEmpty &&
          acc.name?.trim().toLowerCase() == cleanUsername.toLowerCase() &&
          (cleanUid.isEmpty || acc.uid == null || acc.uid!.isEmpty);
      if (isSameUid || isSameEmail || isSameUsername) continue;

      if (acc.userKey != null && acc.userKey!.trim().isNotEmpty) {
        keysOwnedByOthers.add(acc.userKey!.trim());
      }
      final accLegacy = StorageService.sanitizeUserKey(
        (acc.email != null && acc.email!.trim().isNotEmpty) ? acc.email : acc.id,
      );
      if (accLegacy.isNotEmpty) {
        keysOwnedByOthers.add(accLegacy);
      }
    }

    // 2. Dò tìm dữ liệu sẵn có trên đĩa theo các khóa ứng viên của chính tài khoản này
    final candidates = <String>[
      if (canonicalEmail.isNotEmpty) StorageService.sanitizeEmailWithDomain(canonicalEmail),
      if (canonicalEmail.isNotEmpty) StorageService.sanitizeUserKey(canonicalEmail),
      StorageService.sanitizeUserKey(cleanTyped),
      if (cleanUsername.isNotEmpty) StorageService.sanitizeUserKey(cleanUsername),
      if (cleanUid.isNotEmpty) 'uid_$cleanUid',
    ].where((k) => k.isNotEmpty).toSet().toList();

    for (final cand in candidates) {
      if (!keysOwnedByOthers.contains(cand) && DatabaseService.hasUserDataOnDisk(cand)) {
        return cand;
      }
    }

    // 3. Tài khoản mới hoàn toàn: dùng khóa chuẩn nhưng tự tách tên miền/uid nếu bị trùng tài khoản khác
    final primaryBase = canonicalEmail.isNotEmpty
        ? StorageService.sanitizeUserKey(canonicalEmail)
        : StorageService.sanitizeUserKey(cleanTyped.isNotEmpty ? cleanTyped : cleanUsername);

    if (primaryBase.isNotEmpty && !keysOwnedByOthers.contains(primaryBase)) {
      return primaryBase;
    }

    if (canonicalEmail.isNotEmpty) {
      final withDomain = StorageService.sanitizeEmailWithDomain(canonicalEmail);
      if (withDomain.isNotEmpty && !keysOwnedByOthers.contains(withDomain)) {
        return withDomain;
      }
    }

    if (cleanUid.isNotEmpty) {
      return primaryBase.isNotEmpty ? '${primaryBase}_u$cleanUid' : 'uid_$cleanUid';
    }
    return primaryBase.isNotEmpty ? primaryBase : 'user_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> checkAuthStatus() async {
    _isCheckingAuth = true;
    notifyListeners();

    try {
      await refreshAccountsList(notify: false);
      final loggedIn = await _storage.isLoggedIn();
      if (loggedIn) {
        _isAuthenticated = true;
        _userEmail = await _storage.getUserEmail();
        _userName = await _storage.getUserName();
        _avatar = await _storage.getUserAvatar();
        _authToken = await _storage.getAuthToken();
        _userUid = await _storage.getUserUid();
        _forumSessionCookie = await _storage.getForumSessionCookie();
        final storedServer = await _storage.getAuthServer();
        if (storedServer != null && storedServer.isNotEmpty) {
          _selectedServer = storedServer;
        }
        _userGroups = [];

        // Luôn khôi phục groups, uid, server (và avatar nếu thiếu) từ JWT token, kể cả khi đã có avatar
        if (_authToken != null && _authToken!.contains('.')) {
          try {
            final parts = _authToken!.split('.');
            if (parts.length >= 2) {
              var payloadStr = parts[1];
              while (payloadStr.length % 4 != 0) {
                payloadStr += '=';
              }
              final decodedJson = jsonDecode(utf8.decode(base64Url.decode(payloadStr)));
              if (decodedJson is Map && decodedJson['user'] != null) {
                final userObj = decodedJson['user'];
                if ((_avatar == null || _avatar!.isEmpty) && userObj['avatar'] != null) {
                  final tokenAvatar = userObj['avatar'].toString();
                  if (tokenAvatar.isNotEmpty && tokenAvatar != 'null') {
                    _avatar = tokenAvatar;
                    await _storage.setUserAvatar(_avatar);
                  }
                }
                if ((_userUid == null || _userUid!.isEmpty) && userObj['id'] != null) {
                  final tokenUid = userObj['id'].toString().trim();
                  if (tokenUid.isNotEmpty && tokenUid != 'null') {
                    _userUid = tokenUid;
                    await _storage.setUserUid(_userUid);
                  }
                }
                if (userObj['server'] != null && userObj['server'].toString().trim().isNotEmpty) {
                  _selectedServer = userObj['server'].toString().trim();
                }
                if (userObj['groups'] is List) {
                  _userGroups = (userObj['groups'] as List).map((e) => e.toString()).toList();
                }
              }
            }
          } catch (_) {}
        }

        // Dự phòng khôi phục groups và uid từ MultiAccountService nếu JWT không có
        final matchedAcc = await _multiAccount.findMatchingAccount(
          uid: _userUid,
          email: _userEmail,
          username: _userName,
        );
        if (matchedAcc != null) {
          if (_userGroups.isEmpty && matchedAcc.groups.isNotEmpty) {
            _userGroups = List<String>.from(matchedAcc.groups);
          }
          if ((_userUid == null || _userUid!.isEmpty) && matchedAcc.uid != null && matchedAcc.uid!.isNotEmpty) {
            _userUid = matchedAcc.uid;
          }
          if (matchedAcc.server != null && matchedAcc.server!.isNotEmpty) {
            _selectedServer = matchedAcc.server;
          }
        }

        // Xác thực trực tuyến tư cách thành viên nhóm "nhóm-diễn-viên-mxh" ngay khi mở lại app
        // (nếu bị gỡ khỏi nhóm trong lúc tắt app sẽ đăng xuất ngay, không tin mù JWT cũ)
        bool kickedByServer = false;
        if (_authToken != 'native_local_token' &&
            !checkActorAccess(email: _userEmail, name: _userName, groups: const [])) {
          final liveRes = await _checkLiveGroups(
            uid: _userUid,
            username: _userName,
            email: _userEmail,
            server: _selectedServer,
            sessionCookie: _forumSessionCookie,
          );
          if (liveRes.verified) {
            _userGroups = List<String>.from(liveRes.groups);
            try {
              await _multiAccount.updateAccountGroups(
                uid: _userUid,
                email: _userEmail,
                username: _userName,
                groups: _userGroups,
              );
            } catch (_) {}
            if (!checkActorAccess(email: _userEmail, name: _userName, groups: _userGroups)) {
              kickedByServer = true;
            }
          }
        }

        // Kiểm tra quyền nhóm của phiên lưu trữ
        final hasAccess = !kickedByServer &&
            checkActorAccess(
              email: _userEmail,
              name: _userName,
              groups: _userGroups,
            );

        if (!hasAccess) {
          // Nếu phiên cũ không còn thuộc nhóm diễn viên MXH, xoá phiên ngay lập tức
          _stopGroupMembershipMonitor();
          await _storage.clearAuth();
          _isAuthenticated = false;
          _userUid = null;
          _userEmail = null;
          _userName = null;
          _authToken = null;
          _forumSessionCookie = null;
          _avatar = null;
          _userGroups = [];
          _activeUserKey = '';
          await _db.closeForLogout();
          await _localConfig.clearForLogout();
          _persona.switchUser('');
          await refreshAccountsList(notify: false);
          _errorMessage = kickedByServer
              ? 'Tài khoản của bạn đã bị gỡ khỏi nhóm "nhóm-diễn-viên-mxh" trên diễn đàn type.vn và đã được tự động đăng xuất.'
              : 'Tài khoản chưa tham gia nhóm "nhóm-diễn-viên-mxh" trên diễn đàn type.vn.';
        } else {
          final storedKey = await _storage.getStoredUserKey();
          final userKey = (storedKey != null && storedKey.trim().isNotEmpty)
              ? storedKey.trim()
              : await _resolveCanonicalUserKey(
                  uid: _userUid,
                  username: _userName,
                  respEmail: _userEmail,
                  typedInput: _userEmail ?? _userName ?? '',
                );
          await _storage.setUserKey(userKey);
          await _db.switchUser(userKey);
          await _localConfig.switchUser(userKey);
          _persona.switchUser(userKey);
          _activeUserKey = userKey;
          _startGroupMembershipMonitor();
        }
      } else {
        _isAuthenticated = false;
        _activeUserKey = '';
      }
    } catch (_) {
      _isAuthenticated = false;
      _activeUserKey = '';
    } finally {
      _isCheckingAuth = false;
      notifyListeners();
    }
  }

  /// Đăng nhập theo logic chuẩn ai.type (Forum login v3 + AES OpenSSL + checkAccount nhóm)
  Future<bool> login({
    required String email,
    required String password,
    String server = 'vn.s3',
    bool rememberMe = true,
  }) async {
    final cleanEmail = email.trim();
    final cleanPass = password;

    if (cleanEmail.isEmpty || cleanPass.isEmpty) {
      _errorMessage = 'Thiếu thông tin đăng nhập.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _forumAuth.loginV3(
        username: cleanEmail,
        password: cleanPass,
        server: server,
        rememberMe: rememberMe,
      );

      final statusCode = res['statusCode'] as int? ?? 0;
      final body = res['body'] as Map<String, dynamic>? ?? {};

      if (statusCode == 200 && body['data'] != null && body['data']['status'] != null && body['data']['status']['code'] == 'ok') {
        final data = body['data'] as Map<String, dynamic>;
        final resp = data['response'] as Map<String, dynamic>? ?? {};

        String avatarUrl = '';
        if (resp['picture'] != null && resp['picture'].toString().isNotEmpty && resp['picture'].toString() != 'null') {
          var pic = resp['picture'].toString().replaceAll('&#x2F;', '/').replaceAll('&amp;', '&');
          avatarUrl = pic.startsWith('http') ? pic : 'https://type.vn$pic';
        }

        final respUid = resp['uid']?.toString() ?? '';
        final respUsername = resp['username']?.toString() ?? cleanEmail.split('@').first;
        final respEmail = resp['email']?.toString().trim() ?? '';
        final existingAcc = await _multiAccount.findMatchingAccount(
          uid: respUid,
          email: respEmail.isNotEmpty ? respEmail : cleanEmail,
          username: respUsername,
        );
        final effectiveEmail = respEmail.isNotEmpty
            ? respEmail
            : (cleanEmail.contains('@')
                ? cleanEmail
                : ((existingAcc?.email != null && existingAcc!.email!.contains('@'))
                    ? existingAcc.email!
                    : cleanEmail));

        final user = <String, dynamic>{
          'id': respUid,
          'name': respUsername,
          'email': effectiveEmail,
          'server': server,
          'postcount': resp['postcount'],
          'reputation': resp['reputation'],
          'avatar': avatarUrl,
          'status': resp['status'],
          'groups': (resp['groups'] is List)
              ? (resp['groups'] as List).map((e) => e.toString()).toList()
              : <String>[],
        };

        final loginSessionCookie = resp['_session_cookie']?.toString().trim();

        // Đảm bảo lấy đầy đủ danh sách nhóm của user trực tiếp từ type.vn
        try {
          final extraGroups = await _forumAuth.fetchUserGroupsByUsername(
            user['name']?.toString() ?? cleanEmail,
            sessionCookie: loginSessionCookie,
          );
          final list = user['groups'] as List<String>;
          for (final eg in extraGroups) {
            if (!list.contains(eg)) {
              list.add(eg);
            }
          }
        } catch (_) {}

        // Kiểm tra quyền nhóm qua /forum/groups giống hệt checkAccount() của ai.type
        try {
          final groupsRes = await _forumAuth.getGroups(server);
          if (groupsRes != null && groupsRes['success'] == true && groupsRes['data'] != null) {
            final groupsList = groupsRes['data']['groups'] as List? ?? [];
            for (final g in groupsList) {
              final slug = g['slug']?.toString() ?? '';
              final name = g['name']?.toString() ?? '';
              final members = g['members'] as List? ?? [];
              for (final m in members) {
                if (m['uid']?.toString() == user['id']?.toString()) {
                  final list = user['groups'] as List<String>;
                  if (slug.isNotEmpty && !list.contains(slug)) {
                    list.add(slug);
                  }
                  if (name.isNotEmpty && !list.contains(name)) {
                    list.add(name);
                  }
                }
              }
            }
          }
        } catch (_) {}

        final groupsList = (user['groups'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];

        // KIỂM TRA PHÂN QUYỀN BẮT BUỘC:
        // Chỉ tài khoản thuộc nhóm "nhóm-diễn-viên-mxh" trên type.vn (hoặc admin hệ thống) mới được phép sử dụng phần mềm
        final hasAccess = checkActorAccess(
          email: cleanEmail,
          name: user['name']?.toString(),
          groups: groupsList,
        );

        if (!hasAccess) {
          _errorMessage = 'Tài khoản của bạn chưa thuộc nhóm "nhóm-diễn-viên-mxh" trên diễn đàn type.vn. Vui lòng tham gia nhóm để được phép sử dụng phần mềm.';
          _isLoading = false;
          _isAuthenticated = false;
          notifyListeners();
          return false;
        }

        // Xác định khóa lưu trữ ổn định duy nhất theo tài khoản (không bị đổi khi đăng nhập bằng username vs email)
        final userKey = await _resolveCanonicalUserKey(
          uid: respUid,
          username: respUsername,
          respEmail: effectiveEmail,
          typedInput: cleanEmail,
        );

        // Tạo JWT Token theo chuẩn AuthUtils._generateJWTToken
        final jwtToken = CryptoHelper.generateJWTToken(user);

        // Lưu vào MultiAccountService (gộp theo uid/email, lưu kèm userKey ổn định)
        final accountIdToSave = effectiveEmail.isNotEmpty ? effectiveEmail : cleanEmail;
        await _multiAccount.saveAccount(
          accountIdToSave,
          {'user': user, 'profile': user},
          uid: respUid,
          userKey: userKey,
        );

        await _storage.clearActiveServerId();
        if (rememberMe) {
          await _storage.setRememberMe(true);
          await _storage.setAuthToken(jwtToken);
        } else {
          await _storage.setRememberMe(false);
          await _storage.setAuthToken(jwtToken);
        }

        await _storage.setUserEmail(effectiveEmail);
        await _storage.setUserName(respUsername);
        await _storage.setUserAvatar(avatarUrl);
        await _storage.setUserKey(userKey);
        await _storage.setUserUid(respUid);
        await _storage.setAuthServer(server);
        await _storage.setForumSessionCookie(loginSessionCookie);
        await _storage.setLoggedIn(true);

        await _db.switchUser(userKey);
        await _localConfig.switchUser(userKey);
        _persona.switchUser(userKey);

        _authToken = jwtToken;
        _forumSessionCookie = loginSessionCookie;
        _userUid = respUid;
        _selectedServer = server;
        _userEmail = effectiveEmail;
        _userName = respUsername;
        _avatar = avatarUrl;
        _userGroups = (user['groups'] as List?)?.map((e) => e.toString()).toList() ?? [];
        _activeUserKey = userKey;
        _isAuthenticated = true;
        _errorMessage = null;
        _isLoading = false;

        await refreshAccountsList(notify: false);
        _startGroupMembershipMonitor();
        notifyListeners();
        return true;
      } else {
        // Tài khoản không đúng hoặc máy chủ xác thực gặp sự cố
        final customMsg = body['message']?.toString();
        if (customMsg != null && customMsg.isNotEmpty && !customMsg.contains('Internal Server Error')) {
          _errorMessage = customMsg;
        } else if (statusCode == 500 || statusCode == 501 || statusCode == 502 || statusCode == 503 || statusCode == 504) {
          _errorMessage = 'Máy chủ xác thực ($server) đang gặp sự cố nội bộ (Mã lỗi: $statusCode - Internal Server Error). Vui lòng thử lại sau hoặc chuyển máy chủ khác.';
        } else if (statusCode == 403 || statusCode == 401) {
          _errorMessage = 'Email hoặc mật khẩu không chính xác.';
        } else {
          _errorMessage = (customMsg ?? 'Tài khoản của bạn không đúng hoặc không được chấp nhận.').toString();
        }
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Lỗi kết nối tới máy chủ xác thực: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Chuyển đổi tài khoản nhanh như trên giao diện ai.type
  Future<bool> switchAccount(String accountId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final accountData = await _multiAccount.switchAccount(accountId);
      if (accountData != null) {
        final profile = accountData['profile'] ?? accountData['user'] ?? accountData;
        final email = profile['email']?.toString() ?? accountId;
        final name = profile['name']?.toString() ?? profile['username']?.toString() ?? email;
        final avatar = profile['avatar']?.toString();

        final uid = profile['id']?.toString() ?? accountData['uid']?.toString() ?? '';
        final accServer = profile['server']?.toString().trim() ?? 'vn.s3';
        var groups = (profile['groups'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];

        // Luôn xác thực trực tuyến tư cách nhóm trước khi cho chuyển nhanh tài khoản
        if (!checkActorAccess(email: email, name: name, groups: const [])) {
          final liveRes = await _checkLiveGroups(
            uid: uid,
            username: name,
            email: email,
            server: accServer,
          );
          if (liveRes.verified) {
            groups = List<String>.from(liveRes.groups);
            await _multiAccount.updateAccountGroups(
              accountId: accountId,
              uid: uid,
              email: email,
              username: name,
              groups: groups,
            );
          }
        }

        if (!checkActorAccess(email: email, name: name, groups: groups)) {
          _errorMessage =
              'Tài khoản "$email" không thuộc hoặc đã bị gỡ khỏi nhóm "nhóm-diễn-viên-mxh" trên diễn đàn type.vn.';
          await refreshAccountsList(notify: false);
          _isLoading = false;
          notifyListeners();
          return false;
        }

        final storedKey = accountData['userKey']?.toString() ?? profile['userKey']?.toString();
        final userKey = (storedKey != null && storedKey.trim().isNotEmpty)
            ? storedKey.trim()
            : await _resolveCanonicalUserKey(
                uid: uid,
                username: name,
                respEmail: email,
                typedInput: accountId,
              );

        await _storage.clearActiveServerId();
        await _storage.setUserEmail(email);
        await _storage.setUserName(name);
        await _storage.setUserAvatar(avatar);
        await _storage.setUserKey(userKey);
        await _storage.setUserUid(uid);
        await _storage.setAuthServer(accServer);
        await _storage.setForumSessionCookie(null);
        await _storage.setLoggedIn(true);

        await _db.switchUser(userKey);
        await _localConfig.switchUser(userKey);
        _persona.switchUser(userKey);

        _userUid = uid;
        _selectedServer = accServer;
        _forumSessionCookie = null;
        _userEmail = email;
        _userName = name;
        _avatar = avatar;
        _userGroups = groups;
        _activeUserKey = userKey;
        _isAuthenticated = true;
        _errorMessage = null;

        await refreshAccountsList(notify: false);
        _startGroupMembershipMonitor();
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> loginStandaloneMode() async {
    const email = 'local.admin@type.vn';
    final userKey = StorageService.sanitizeUserKey(email);
    await _storage.clearActiveServerId();
    await _storage.setLoggedIn(true);
    await _storage.setUserEmail(email);
    await _storage.setUserName('Local Administrator');
    await _storage.setAuthToken('native_local_token');
    await _storage.setUserKey(userKey);
    await _db.switchUser(userKey);
    await _localConfig.switchUser(userKey);
    _persona.switchUser(userKey);
    _isAuthenticated = true;
    _userEmail = email;
    _userName = 'Local Administrator';
    _authToken = 'native_local_token';
    _userGroups = ['administrators'];
    _activeUserKey = userKey;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> logout() async {
    _stopGroupMembershipMonitor();
    await _storage.clearAuth();
    _isAuthenticated = false;
    _authToken = null;
    _forumSessionCookie = null;
    _userUid = null;
    _userEmail = null;
    _userName = null;
    _avatar = null;
    _userGroups = [];
    _activeUserKey = '';
    _errorMessage = null;
    await _db.closeForLogout();
    await _localConfig.clearForLogout();
    _persona.switchUser('');
    await refreshAccountsList(notify: false);
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }
}
