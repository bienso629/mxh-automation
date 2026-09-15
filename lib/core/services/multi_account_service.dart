import 'package:shared_preferences/shared_preferences.dart';
import 'crypto_helper.dart';

class AccountProfile {
  final String id;
  final String? name;
  final String? email;
  final String? server;
  final String? avatar;
  final int? postcount;
  final int? reputation;
  final List<String> groups;
  final bool isActive;

  AccountProfile({
    required this.id,
    this.name,
    this.email,
    this.server,
    this.avatar,
    this.postcount,
    this.reputation,
    this.groups = const [],
    this.isActive = false,
  });

  factory AccountProfile.fromMap(Map<String, dynamic> map, {bool isActive = false}) {
    final profile = map['profile'] ?? map['user'] ?? map;
    String? avatar = profile['avatar']?.toString();
    if (avatar != null && avatar.isNotEmpty) {
      avatar = avatar.replaceAll('&#x2F;', '/').replaceAll('&amp;', '&');
      if (!avatar.startsWith('http') && avatar.startsWith('/')) {
        avatar = 'https://type.vn$avatar';
      }
    }
    return AccountProfile(
      id: map['id']?.toString() ?? profile['id']?.toString() ?? profile['email']?.toString() ?? '',
      name: profile['name']?.toString() ?? profile['username']?.toString() ?? '',
      email: profile['email']?.toString() ?? '',
      server: profile['server']?.toString() ?? 'vn.s3',
      avatar: avatar,
      postcount: int.tryParse(profile['postcount']?.toString() ?? ''),
      reputation: int.tryParse(profile['reputation']?.toString() ?? ''),
      groups: (profile['groups'] as List?)?.map((e) => e.toString()).toList() ?? [],
      isActive: isActive,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'server': server,
      'avatar': avatar,
      'postcount': postcount,
      'reputation': reputation,
      'groups': groups,
    };
  }
}

class MultiAccountService {
  static final MultiAccountService _instance = MultiAccountService._internal();
  factory MultiAccountService() => _instance;
  MultiAccountService._internal();

  static const String _keyAccounts = 'ai_type_multi_accounts';
  static const String _keyActiveAccountId = 'ai_type_active_account_id';
  static const String _multiAccountSecret = 'ai_type_secret_key_2026_!@#';

  SharedPreferences? _prefs;

  Future<void> _ensureInit() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<List<Map<String, dynamic>>> _loadAllRawAccounts() async {
    await _ensureInit();
    final rawList = _prefs!.getStringList(_keyAccounts) ?? [];
    final list = <Map<String, dynamic>>[];
    for (final item in rawList) {
      try {
        final decrypted = CryptoHelper.decrypt(item, _multiAccountSecret);
        if (decrypted is Map<String, dynamic>) {
          list.add(decrypted);
        }
      } catch (_) {}
    }
    return list;
  }

  Future<void> _saveAllRawAccounts(List<Map<String, dynamic>> list) async {
    await _ensureInit();
    final rawList = <String>[];
    for (final item in list) {
      try {
        final enc = CryptoHelper.encrypt(item, _multiAccountSecret);
        rawList.add(enc);
      } catch (_) {}
    }
    await _prefs!.setStringList(_keyAccounts, rawList);
  }

  Future<List<AccountProfile>> getAllAccounts() async {
    final list = await _loadAllRawAccounts();
    final activeId = await getActiveAccountId();
    return list.map((item) {
      final id = item['id']?.toString() ?? '';
      return AccountProfile.fromMap(item, isActive: id == activeId);
    }).toList();
  }

  Future<String?> getActiveAccountId() async {
    await _ensureInit();
    return _prefs!.getString(_keyActiveAccountId);
  }

  Future<void> saveAccount(String accountId, Map<String, dynamic> rawData) async {
    final list = await _loadAllRawAccounts();
    final index = list.indexWhere((e) => e['id']?.toString() == accountId);
    
    final payload = {
      'id': accountId,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      ...rawData,
    };

    if (index >= 0) {
      list[index] = {...list[index], ...payload};
    } else {
      list.add(payload);
    }

    await _saveAllRawAccounts(list);
    await _prefs!.setString(_keyActiveAccountId, accountId);
  }

  Future<Map<String, dynamic>?> switchAccount(String accountId) async {
    final list = await _loadAllRawAccounts();
    final item = list.firstWhere(
      (e) => e['id']?.toString() == accountId,
      orElse: () => <String, dynamic>{},
    );

    if (item.isNotEmpty) {
      await _ensureInit();
      await _prefs!.setString(_keyActiveAccountId, accountId);
      return item;
    }
    return null;
  }

  Future<void> removeAccount(String accountId) async {
    final list = await _loadAllRawAccounts();
    list.removeWhere((e) => e['id']?.toString() == accountId);
    await _saveAllRawAccounts(list);

    final activeId = await getActiveAccountId();
    if (activeId == accountId) {
      if (list.isNotEmpty) {
        await switchAccount(list.first['id']?.toString() ?? '');
      } else {
        await _ensureInit();
        await _prefs!.remove(_keyActiveAccountId);
      }
    }
  }
}
