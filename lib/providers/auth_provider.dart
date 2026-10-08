import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/services/crypto_helper.dart';
import '../core/services/database_service.dart';
import '../core/services/forum_auth_service.dart';
import '../core/services/local_config_service.dart';
import '../core/services/multi_account_service.dart';
import '../core/services/persona_service.dart';
import '../core/services/storage_service.dart';

class AuthProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final DatabaseService _db = DatabaseService();
  final LocalConfigService _localConfig = LocalConfigService();
  final PersonaService _persona = PersonaService();
  final MultiAccountService _multiAccount = MultiAccountService();
  final ForumAuthService _forumAuth = ForumAuthService();

  bool _isLoading = false;
  bool _isCheckingAuth = true;
  bool _isAuthenticated = false;
  String? _userEmail;
  String? _userName;
  String? _authToken;
  String? _avatar;
  String? _selectedServer = 'vn.s3';
  String? _errorMessage;
  List<AccountProfile> _accounts = [];
  List<String> _userGroups = [];

  bool get isLoading => _isLoading;
  bool get isCheckingAuth => _isCheckingAuth;
  bool get isAuthenticated => _isAuthenticated;
  String? get userEmail => _userEmail;
  String? get userName => _userName;
  String? get authToken => _authToken;
  String? get avatar => _avatar;
  String get selectedServer => _selectedServer ?? 'vn.s3';
  String? get errorMessage => _errorMessage;
  List<AccountProfile> get accounts => _accounts;
  List<String> get userGroups => _userGroups;

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

  AuthProvider() {
    checkAuthStatus();
  }

  Future<void> refreshAccountsList() async {
    _accounts = await _multiAccount.getAllAccounts();
    notifyListeners();
  }

  Future<void> checkAuthStatus() async {
    _isCheckingAuth = true;
    notifyListeners();

    try {
      await refreshAccountsList();
      final loggedIn = await _storage.isLoggedIn();
      if (loggedIn) {
        _isAuthenticated = true;
        _userEmail = await _storage.getUserEmail();
        _userName = await _storage.getUserName();
        _avatar = await _storage.getUserAvatar();
        _authToken = await _storage.getAuthToken();

        // Tự động khôi phục avatar từ JWT token nếu storage lưu trước đó chưa có avatar
        if ((_avatar == null || _avatar!.isEmpty) && _authToken != null && _authToken!.contains('.')) {
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
                if (userObj['avatar'] != null) {
                  final tokenAvatar = userObj['avatar'].toString();
                  if (tokenAvatar.isNotEmpty && tokenAvatar != 'null') {
                    _avatar = tokenAvatar;
                    await _storage.setUserAvatar(_avatar);
                  }
                }
                if (userObj['groups'] is List) {
                  _userGroups = (userObj['groups'] as List).map((e) => e.toString()).toList();
                }
              }
            }
          } catch (_) {}
        }

        final userKey = await _storage.getUserKey();
        await _db.switchUser(userKey);
        await _localConfig.switchUser(userKey);
        _persona.switchUser(userKey);
      } else {
        _isAuthenticated = false;
      }
    } catch (_) {
      _isAuthenticated = false;
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

        final user = <String, dynamic>{
          'id': resp['uid']?.toString() ?? '',
          'name': resp['username']?.toString() ?? cleanEmail.split('@').first,
          'email': cleanEmail,
          'server': server,
          'postcount': resp['postcount'],
          'reputation': resp['reputation'],
          'avatar': avatarUrl,
          'status': resp['status'],
          'groups': <String>[],
        };

        // Kiểm tra quyền nhóm qua /forum/groups giống hệt checkAccount() của ai.type
        try {
          final groupsRes = await _forumAuth.getGroups(server);
          if (groupsRes != null && groupsRes['success'] == true && groupsRes['data'] != null) {
            final groupsList = groupsRes['data']['groups'] as List? ?? [];
            for (final g in groupsList) {
              final slug = g['slug']?.toString() ?? '';
              final members = g['members'] as List? ?? [];
              for (final m in members) {
                if (m['uid']?.toString() == user['id']?.toString()) {
                  final list = user['groups'] as List<String>;
                  if (!list.contains(slug)) {
                    list.add(slug);
                  }
                }
              }
            }
          }
        } catch (_) {}

        // Tạo JWT Token theo chuẩn AuthUtils._generateJWTToken
        final jwtToken = CryptoHelper.generateJWTToken(user);

        // Lưu vào MultiAccountService (tương thích MultiAccountService trong ai.type)
        await _multiAccount.saveAccount(cleanEmail, {'user': user, 'profile': user});

        if (rememberMe) {
          await _storage.setRememberMe(true);
          await _storage.setAuthToken(jwtToken);
        } else {
          await _storage.setRememberMe(false);
          await _storage.setAuthToken(jwtToken);
        }

        await _storage.setUserEmail(cleanEmail);
        await _storage.setUserName(user['name']?.toString() ?? cleanEmail);
        await _storage.setUserAvatar(avatarUrl);
        await _storage.setLoggedIn(true);

        _authToken = jwtToken;
        _userEmail = cleanEmail;
        _userName = user['name']?.toString();
        _avatar = avatarUrl;
        _userGroups = (user['groups'] as List?)?.map((e) => e.toString()).toList() ?? [];
        _isAuthenticated = true;
        _errorMessage = null;
        _isLoading = false;

        final userKey = StorageService.sanitizeUserKey(cleanEmail);
        await _db.switchUser(userKey);
        await _localConfig.switchUser(userKey);
        _persona.switchUser(userKey);

        await refreshAccountsList();
        notifyListeners();
        return true;
      } else {
        // Tài khoản không đúng hoặc không được chấp nhận
        _errorMessage = (body['message'] ?? 'Tài khoản của bạn không đúng hoặc không được chấp nhận.').toString();
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Tài khoản của bạn không được chấp nhận: $e';
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

        _userEmail = email;
        _userName = name;
        _avatar = avatar;
        _userGroups = (profile['groups'] as List?)?.map((e) => e.toString()).toList() ?? [];
        _isAuthenticated = true;
        _errorMessage = null;

        await _storage.setUserEmail(email);
        await _storage.setUserName(name);
        await _storage.setUserAvatar(avatar);
        await _storage.setLoggedIn(true);

        final userKey = StorageService.sanitizeUserKey(email);
        await _db.switchUser(userKey);
        await _localConfig.switchUser(userKey);
        _persona.switchUser(userKey);

        await refreshAccountsList();
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
    _isAuthenticated = true;
    _userEmail = 'local.admin@type.vn';
    _userName = 'Local Administrator';
    _authToken = 'native_local_token';
    _userGroups = ['administrators'];
    await _storage.setLoggedIn(true);
    await _storage.setUserEmail(_userEmail!);
    await _storage.setUserName(_userName!);
    await _storage.setAuthToken(_authToken!);
    final userKey = StorageService.sanitizeUserKey(_userEmail);
    await _db.switchUser(userKey);
    await _localConfig.switchUser(userKey);
    _persona.switchUser(userKey);
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> logout() async {
    await _storage.clearAuth();
    _isAuthenticated = false;
    _authToken = null;
    _userEmail = null;
    _userName = null;
    _avatar = null;
    _errorMessage = null;
    await _db.switchUser('');
    await _localConfig.switchUser('');
    _persona.switchUser('');
    await refreshAccountsList();
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }
}
