import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  late SharedPreferences _prefs;
  bool _isInitialized = false;

  static const String _keyGatewayUrl = 'gateway_url';
  static const String _keySecretToken = 'secret_token';
  static const String _keyActiveServerId = 'active_server_id';
  static const String _keyDefaultModel = 'default_ai_model';
  static const String _keyBiometricEnabled = 'biometric_enabled';
  static const String _keyAuthToken = 'auth_token';
  static const String _keyUserEmail = 'user_email';
  static const String _keyUserName = 'user_name';
  static const String _keyUserAvatar = 'user_avatar';
  static const String _keyUserKey = 'user_key';
  static const String _keyUserUid = 'user_uid';
  static const String _keyAuthServer = 'auth_server';
  static const String _keyForumSessionCookie = 'forum_session_cookie';
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyRememberMe = 'remember_me';

  Future<void> init() async {
    if (_isInitialized) return;
    _prefs = await SharedPreferences.getInstance();
    _isInitialized = true;
  }

  // Gateway URL
  Future<String> getGatewayUrl() async {
    await init();
    return _prefs.getString(_keyGatewayUrl) ?? 'http://127.0.0.1:8888';
  }

  Future<void> setGatewayUrl(String url) async {
    await init();
    var cleanUrl = url.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    await _prefs.setString(_keyGatewayUrl, cleanUrl);
  }

  // Secret Token
  Future<String> getSecretToken() async {
    await init();
    return _prefs.getString(_keySecretToken) ?? '';
  }

  Future<void> setSecretToken(String token) async {
    await init();
    await _prefs.setString(_keySecretToken, token.trim());
  }

  // Active Server ID
  Future<String?> getActiveServerId() async {
    await init();
    return _prefs.getString(_keyActiveServerId);
  }

  Future<void> setActiveServerId(String id) async {
    await init();
    await _prefs.setString(_keyActiveServerId, id);
  }

  Future<void> clearActiveServerId() async {
    await init();
    await _prefs.remove(_keyActiveServerId);
  }

  // Default AI Model
  Future<String> getDefaultModel() async {
    await init();
    return _prefs.getString(_keyDefaultModel) ?? 'glm-5.3';
  }

  Future<void> setDefaultModel(String model) async {
    await init();
    await _prefs.setString(_keyDefaultModel, model);
  }

  // Biometric Auth
  Future<bool> getBiometricEnabled() async {
    await init();
    return _prefs.getBool(_keyBiometricEnabled) ?? false;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await init();
    await _prefs.setBool(_keyBiometricEnabled, enabled);
  }

  // Tadu Cloud Authentication
  Future<String?> getAuthToken() async {
    await init();
    return _prefs.getString(_keyAuthToken);
  }

  Future<void> setAuthToken(String? token) async {
    await init();
    if (token == null || token.isEmpty) {
      await _prefs.remove(_keyAuthToken);
    } else {
      await _prefs.setString(_keyAuthToken, token);
    }
  }

  Future<String?> getUserEmail() async {
    await init();
    return _prefs.getString(_keyUserEmail);
  }

  Future<void> setUserEmail(String? email) async {
    await init();
    if (email == null || email.isEmpty) {
      await _prefs.remove(_keyUserEmail);
    } else {
      await _prefs.setString(_keyUserEmail, email);
    }
  }

  Future<String?> getUserName() async {
    await init();
    return _prefs.getString(_keyUserName);
  }

  Future<void> setUserName(String? name) async {
    await init();
    if (name == null || name.isEmpty) {
      await _prefs.remove(_keyUserName);
    } else {
      await _prefs.setString(_keyUserName, name);
    }
  }

  Future<String?> getUserAvatar() async {
    await init();
    return _prefs.getString(_keyUserAvatar);
  }

  Future<void> setUserAvatar(String? avatar) async {
    await init();
    if (avatar == null || avatar.isEmpty) {
      await _prefs.remove(_keyUserAvatar);
    } else {
      await _prefs.setString(_keyUserAvatar, avatar);
    }
  }

  Future<bool> isLoggedIn() async {
    await init();
    return _prefs.getBool(_keyIsLoggedIn) ?? false;
  }

  Future<void> setLoggedIn(bool value) async {
    await init();
    await _prefs.setBool(_keyIsLoggedIn, value);
  }

  Future<bool> getRememberMe() async {
    await init();
    return _prefs.getBool(_keyRememberMe) ?? true;
  }

  Future<void> setRememberMe(bool value) async {
    await init();
    await _prefs.setBool(_keyRememberMe, value);
  }

  Future<String?> getStoredUserKey() async {
    await init();
    return _prefs.getString(_keyUserKey);
  }

  Future<void> setUserKey(String? key) async {
    await init();
    final cleaned = key?.trim() ?? '';
    if (cleaned.isEmpty) {
      await _prefs.remove(_keyUserKey);
    } else {
      await _prefs.setString(_keyUserKey, cleaned);
    }
  }

  Future<String?> getUserUid() async {
    await init();
    return _prefs.getString(_keyUserUid);
  }

  Future<void> setUserUid(String? uid) async {
    await init();
    final cleaned = uid?.trim() ?? '';
    if (cleaned.isEmpty) {
      await _prefs.remove(_keyUserUid);
    } else {
      await _prefs.setString(_keyUserUid, cleaned);
    }
  }

  Future<String?> getAuthServer() async {
    await init();
    return _prefs.getString(_keyAuthServer);
  }

  Future<void> setAuthServer(String? server) async {
    await init();
    final cleaned = server?.trim() ?? '';
    if (cleaned.isEmpty) {
      await _prefs.remove(_keyAuthServer);
    } else {
      await _prefs.setString(_keyAuthServer, cleaned);
    }
  }

  Future<String?> getForumSessionCookie() async {
    await init();
    return _prefs.getString(_keyForumSessionCookie);
  }

  Future<void> setForumSessionCookie(String? cookie) async {
    await init();
    final cleaned = cookie?.trim() ?? '';
    if (cleaned.isEmpty) {
      await _prefs.remove(_keyForumSessionCookie);
    } else {
      await _prefs.setString(_keyForumSessionCookie, cleaned);
    }
  }

  Future<void> clearAuth() async {
    await init();
    await _prefs.remove(_keyAuthToken);
    await _prefs.remove(_keyUserEmail);
    await _prefs.remove(_keyUserName);
    await _prefs.remove(_keyUserAvatar);
    await _prefs.remove(_keyUserKey);
    await _prefs.remove(_keyUserUid);
    await _prefs.remove(_keyAuthServer);
    await _prefs.remove(_keyForumSessionCookie);
    await _prefs.remove(_keyActiveServerId);
    await _prefs.setBool(_keyIsLoggedIn, false);
  }

  static String sanitizeUserKey(String? user) {
    if (user == null || user.trim().isEmpty) {
      return '';
    }
    var u = user.trim();
    if (u.contains('@')) {
      u = u.split('@')[0];
    }
    final cleaned = u.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').toLowerCase();
    return cleaned.replaceAll(RegExp(r'^_+|_+$'), '');
  }

  /// Tạo khóa tài khoản bao gồm cả domain email (tránh trùng lặp giữa hai email khác domain cùng tiền tố)
  static String sanitizeEmailWithDomain(String? user) {
    if (user == null || user.trim().isEmpty) {
      return '';
    }
    final u = user.trim().toLowerCase();
    final cleaned = u.replaceAll('@', '__').replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return cleaned.replaceAll(RegExp(r'^_+|_+$'), '');
  }

  Future<String> getUserKey() async {
    await init();
    final stored = _prefs.getString(_keyUserKey);
    if (stored != null && stored.trim().isNotEmpty) {
      return stored.trim();
    }
    final email = await getUserEmail();
    if (email != null && email.isNotEmpty) {
      final key = sanitizeUserKey(email);
      if (key.isNotEmpty) return key;
    }
    final name = await getUserName();
    if (name != null && name.isNotEmpty) {
      final key = sanitizeUserKey(name);
      if (key.isNotEmpty) return key;
    }
    return '';
  }
}
