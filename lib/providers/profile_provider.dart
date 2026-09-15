import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/profile_service.dart';
import '../models/profile_model.dart';

class ProfileProvider extends ChangeNotifier {
  final ProfileService _service = ProfileService();

  List<ProfileItem> _profiles = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String? _username;
  Timer? _pollingTimer;

  List<ProfileItem> get profiles {
    if (_searchQuery.isEmpty) return _profiles;
    return _profiles.where((p) {
      final matchName = p.profile.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchAcc = p.accounts.any((acc) =>
          (acc.alias?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
          (acc.email?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false));
      return matchName || matchAcc;
    }).toList();
  }

  int get totalProfiles => _profiles.length;
  int get runningCount => _profiles.where((p) => p.running).length;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;

  void setSearchQuery(String q) {
    _searchQuery = q.trim();
    notifyListeners();
  }

  void init(String? username) {
    _username = username;
    loadProfiles();
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      loadProfiles(silent: true);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> loadProfiles({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      final list = await _service.fetchProfiles(username: _username);
      if (list.isNotEmpty || _profiles.isEmpty) {
        _profiles = list;
      } else {
        // Cập nhật trạng thái running nếu có
        for (var item in list) {
          final idx = _profiles.indexWhere((p) => p.profile == item.profile);
          if (idx != -1) {
            _profiles[idx].running = item.running;
            _profiles[idx].devtoolsPort = item.devtoolsPort;
          }
        }
      }
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> startProfile(ProfileItem item, {bool headless = false}) async {
    final success = await _service.startProfile(
      profileName: item.profile,
      headless: headless,
      username: _username,
    );
    if (success) {
      item.running = true;
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 1500));
      await loadProfiles(silent: true);
    }
    return success;
  }

  Future<bool> stopProfile(ProfileItem item) async {
    final success = await _service.stopProfile(
      profileName: item.profile,
      username: _username,
    );
    if (success) {
      item.running = false;
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 500));
      await loadProfiles(silent: true);
    }
    return success;
  }

  Future<bool> deleteProfile(ProfileItem item) async {
    final success = await _service.deleteProfile(
      profileName: item.profile,
      username: _username,
    );
    if (success) {
      _profiles.removeWhere((p) => p.profile == item.profile);
      notifyListeners();
    }
    return success;
  }

  void addProfile(ProfileItem item) {
    _profiles.add(item);
    notifyListeners();
  }

  void addMockProfileIfEmpty() {
    if (_profiles.isEmpty) {
      _profiles = [
        ProfileItem(
          profile: 'Profile000',
          running: false,
          note: 'Master Profile quản lý kịch bản',
          accounts: [
            ProfileAccount(alias: 'Admin Master', email: 'master@mxh.auto', platform: 'tiktok', active: true),
          ],
        ),
        ProfileItem(
          profile: 'Profile001',
          running: true,
          devtoolsPort: 9222,
          note: 'Nick Farm TikTok tương tác',
          accounts: [
            ProfileAccount(alias: 'Mèo Máy AI', email: 'meomay@gmail.com', platform: 'tiktok', active: true),
          ],
        ),
        ProfileItem(
          profile: 'Profile002',
          running: false,
          note: 'Nick Seeding Facebook',
          accounts: [
            ProfileAccount(alias: 'Kỹ sư MXH', email: 'mxh.seed@fb.com', platform: 'facebook', active: true),
          ],
        ),
      ];
      notifyListeners();
    }
  }
}
