import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/profile_model.dart';

class ProfileService {
  static const String _kBackendUrlKey = 'mxh_backend_url';
  static const String _kProfilesRootKey = 'mxh_profiles_root';
  static const String _kOperaPathKey = 'mxh_opera_path';

  static const String defaultBackendUrl = 'http://127.0.0.1:8000';
  static const String defaultOperaPath = '/usr/bin/opera-gx';

  Future<String> getBackendUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kBackendUrlKey) ?? defaultBackendUrl;
  }

  Future<void> setBackendUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBackendUrlKey, url.trim());
  }

  Future<String> getProfilesRoot() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kProfilesRootKey) ?? '';
  }

  Future<void> setProfilesRoot(String root) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProfilesRootKey, root.trim());
  }

  Future<String> getOperaPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kOperaPathKey) ?? defaultOperaPath;
  }

  Future<void> setOperaPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOperaPathKey, path.trim());
  }

  Future<List<ProfileItem>> fetchProfiles({
    String host = '127.0.0.1',
    String? username,
    String? profilesRoot,
  }) async {
    final baseUrl = await getBackendUrl();
    final root = profilesRoot ?? await getProfilesRoot();

    final queryParams = <String, String>{
      'host': host,
      'verify': 'true',
      'filter': 'all',
      'include_accounts': 'true',
      'platform': 'tiktok',
      if (username != null && username.isNotEmpty) 'username': username,
      if (root.isNotEmpty) 'profiles_root': root,
    };

    final uri = Uri.parse('$baseUrl/v1/opera/profiles/list').replace(queryParameters: queryParams);

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map<String, dynamic> && data['results'] is List) {
          return (data['results'] as List)
              .whereType<Map<String, dynamic>>()
              .map((e) => ProfileItem.fromJson(e))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<bool> startProfile({
    required String profileName,
    bool headless = false,
    String? username,
  }) async {
    final baseUrl = await getBackendUrl();
    final root = await getProfilesRoot();
    final operaPath = await getOperaPath();

    final payload = <String, dynamic>{
      'profiles': [profileName],
      'base_debug_port': 0,
      'opera_path': operaPath,
      'extra_args': ['--ignore-certificate-errors', '--disable-quic'],
      'devtools_ready_timeout_ms': 8000,
      'close_tabs_on_start': false,
      'leave_one_tab': false,
      'new_tab_url': null,
      'mode': 'skip',
      'window_state': 'maximized',
      'headless': headless,
      'prefix_title_with_profile': true,
      'title_prefix_apply_all_tabs': true,
      'post_open_wait_ms': 800,
      'activate_opened_tab': false,
      if (username != null && username.isNotEmpty) 'username': username,
      if (root.isNotEmpty) 'profiles_root': root,
    };

    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/v1/opera/profiles/start-profiles'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopProfile({
    required String profileName,
    String? username,
  }) async {
    final baseUrl = await getBackendUrl();
    final root = await getProfilesRoot();

    final payload = <String, dynamic>{
      'profiles': [profileName],
      'mode': 'force',
      'force': true,
      'cache_action': 'prune',
      if (username != null && username.isNotEmpty) 'username': username,
      if (root.isNotEmpty) 'profiles_root': root,
    };

    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/v1/opera/profiles/kill-profiles'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteProfile({
    required String profileName,
    String? username,
  }) async {
    final baseUrl = await getBackendUrl();
    final root = await getProfilesRoot();

    final payload = <String, dynamic>{
      'profiles': [profileName],
      if (username != null && username.isNotEmpty) 'username': username,
      if (root.isNotEmpty) 'profiles_root': root,
    };

    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/v1/opera/profiles/delete'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
