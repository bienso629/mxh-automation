import 'dart:convert';
import 'dart:io';

/// Loại trình duyệt được phát hiện trên hệ thống
enum BrowserKind { chromium, firefox, unknown }

/// Thông tin một profile của trình duyệt hệ thống (Chrome, Edge, Brave, Firefox...)
class BrowserProfileInfo {
  final String id; // Chromium: 'Default', 'Profile 1'... | Firefox: tên profile
  final String name; // Tên hiển thị của profile
  final String? email; // Email đồng bộ đăng nhập (nếu có)
  final String? path; // Đường dẫn thư mục dữ liệu tuyệt đối của profile
  final BrowserKind kind;
  final bool isDefault; // Đây có phải profile đang dùng gần nhất / mặc định hay không

  const BrowserProfileInfo({
    required this.id,
    required this.name,
    this.email,
    this.path,
    this.kind = BrowserKind.chromium,
    this.isDefault = false,
  });

  String get displayLabel {
    final n = name.trim().isNotEmpty ? name.trim() : id;
    if (isDefault) return '$n (mặc định)';
    return n;
  }

  String get labelWithEmail {
    final base = displayLabel;
    final mail = email?.trim() ?? '';
    if (mail.isNotEmpty && !base.contains(mail)) return '$base - $mail';
    return base;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'path': path,
        'kind': kind.name,
        'is_default': isDefault,
      };

  factory BrowserProfileInfo.fromJson(Map<String, dynamic> json) {
    final kindStr = json['kind']?.toString() ?? 'chromium';
    return BrowserProfileInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString(),
      path: json['path']?.toString(),
      kind: BrowserKind.values.firstWhere(
        (k) => k.name == kindStr,
        orElse: () => BrowserKind.chromium,
      ),
      isDefault: json['is_default'] == true,
    );
  }
}

/// Service quét danh sách profiles có sẵn của trình duyệt đang cài trên máy.
/// - Nhóm Chromium (Chrome, Edge, Brave, Opera, Cốc Cốc, Vivaldi): đọc file "Local State"
/// - Firefox: đọc file "profiles.ini"
class BrowserProfileService {
  static final BrowserProfileService _instance = BrowserProfileService._internal();
  factory BrowserProfileService() => _instance;
  BrowserProfileService._internal();

  String _homeDir() =>
      Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.systemTemp.path;

  /// Phân loại trình duyệt dựa trên đường dẫn binary
  BrowserKind detectKindFromExecutable(String executable) {
    final base = executable.toLowerCase().replaceAll('\\', '/').split('/').last;
    if (base.contains('firefox')) return BrowserKind.firefox;
    return BrowserKind.chromium;
  }

  // ================== CHROMIUM ==================

  /// Xác định thư mục User Data gốc của trình duyệt Chromium-based theo binary
  String? _chromiumUserDataDir(String executable) {
    final base = executable.toLowerCase().replaceAll('\\', '/').split('/').last;
    final home = _homeDir();

    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      final appData = Platform.environment['APPDATA'] ?? '';
      if (base.contains('msedge') || base.contains('edge')) {
        return localAppData.isNotEmpty ? '$localAppData\\Microsoft\\Edge\\User Data' : null;
      }
      if (base.contains('brave')) {
        return localAppData.isNotEmpty ? '$localAppData\\BraveSoftware\\Brave-Browser\\User Data' : null;
      }
      if (base.contains('coccoc')) {
        return localAppData.isNotEmpty ? '$localAppData\\CocCoc\\Browser\\User Data' : null;
      }
      if (base.contains('vivaldi')) {
        return localAppData.isNotEmpty ? '$localAppData\\Vivaldi\\User Data' : null;
      }
      if (base.contains('opera')) {
        return appData.isNotEmpty ? '$appData\\Opera Software\\Opera Stable' : null;
      }
      if (base.contains('chromium')) {
        return localAppData.isNotEmpty ? '$localAppData\\Chromium\\User Data' : null;
      }
      return localAppData.isNotEmpty ? '$localAppData\\Google\\Chrome\\User Data' : null;
    }

    if (Platform.isMacOS) {
      if (base.contains('msedge') || base.contains('edge')) return '$home/Library/Application Support/Microsoft Edge';
      if (base.contains('brave')) return '$home/Library/Application Support/BraveSoftware/Brave-Browser';
      if (base.contains('coccoc')) return '$home/Library/Application Support/CocCoc/Browser';
      if (base.contains('vivaldi')) return '$home/Library/Application Support/Vivaldi';
      if (base.contains('opera')) return '$home/Library/Application Support/com.operasoftware.Opera';
      if (base.contains('chromium')) return '$home/Library/Application Support/Chromium';
      return '$home/Library/Application Support/Google/Chrome';
    }

    // Linux
    if (base.contains('msedge') || base.contains('edge')) return '$home/.config/microsoft-edge';
    if (base.contains('brave')) return '$home/.config/BraveSoftware/Brave-Browser';
    if (base.contains('coccoc')) return '$home/.config/coccoc';
    if (base.contains('vivaldi')) return '$home/.config/vivaldi';
    if (base.contains('opera')) return '$home/.config/opera';
    if (base.contains('chromium')) return '$home/.config/chromium';
    return '$home/.config/google-chrome';
  }

  /// Đọc danh sách profiles từ file "Local State" của trình duyệt Chromium-based
  List<BrowserProfileInfo> listChromiumProfiles(String executable) {
    try {
      final userDataDir = _chromiumUserDataDir(executable);
      if (userDataDir == null || userDataDir.isEmpty) return const [];
      final localStateFile = File('$userDataDir/Local State');
      if (!localStateFile.existsSync()) return const [];

      final content = localStateFile.readAsStringSync();
      if (content.trim().isEmpty) return const [];
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return const [];

      final profileSection = decoded['profile'];
      if (profileSection is! Map) return const [];
      final infoCache = (profileSection as Map<String, dynamic>)['info_cache'];
      if (infoCache is! Map) return const [];

      final lastUsed = profileSection['last_used']?.toString();

      final result = <BrowserProfileInfo>[];
      infoCache.forEach((rawId, rawInfo) {
        final id = rawId.toString();
        if (id.isEmpty || rawInfo is! Map) return;
        final info = Map<String, dynamic>.from(rawInfo);
        final name = info['name']?.toString() ?? '';
        final email = info['user_name']?.toString();
        result.add(BrowserProfileInfo(
          id: id,
          name: name,
          email: (email != null && email.isNotEmpty) ? email : null,
          path: '$userDataDir/$id',
          kind: BrowserKind.chromium,
          isDefault: lastUsed != null && lastUsed == id,
        ));
      });

      result.sort((a, b) {
        if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return result;
    } catch (_) {
      return const [];
    }
  }

  // ================== FIREFOX ==================

  /// Các thư mục cấu hình Firefox trên từng hệ điều hành (bao gồm cả bản snap/flatpak)
  List<String> _firefoxConfigDirs() {
    final home = _homeDir();
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? '';
      return [if (appData.isNotEmpty) '$appData\\Mozilla\\Firefox'];
    }
    if (Platform.isMacOS) {
      return ['$home/Library/Application Support/Firefox'];
    }
    return [
      '$home/.mozilla/firefox',
      '$home/snap/firefox/common/.mozilla/firefox',
      '$home/.var/app/org.mozilla.firefox/.mozilla/firefox',
    ];
  }

  /// Parser INI tối giản dành cho profiles.ini của Firefox
  List<Map<String, String>> _parseIni(String content) {
    final sections = <Map<String, String>>[];
    Map<String, String> current = {};
    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        if (current.isNotEmpty) {
          sections.add(current);
          current = {};
        }
        current['__section__'] = line.substring(1, line.length - 1).trim().toLowerCase();
        continue;
      }
      final eq = line.indexOf('=');
      if (eq > 0) {
        current[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
      }
    }
    if (current.isNotEmpty) sections.add(current);
    return sections;
  }

  /// Đọc danh sách profiles từ file "profiles.ini" của Firefox
  List<BrowserProfileInfo> listFirefoxProfiles(String executable) {
    try {
      for (final dir in _firefoxConfigDirs()) {
        final iniFile = File('$dir/profiles.ini');
        if (!iniFile.existsSync()) continue;
        final content = iniFile.readAsStringSync();
        if (content.trim().isEmpty) continue;

        final sections = _parseIni(content);
        String? installDefaultPath;
        for (final s in sections) {
          final section = s['__section__'] ?? '';
          if (section.startsWith('install')) {
            final d = s['default'];
            if (d != null && d.isNotEmpty) installDefaultPath = d;
          }
        }

        final result = <BrowserProfileInfo>[];
        for (final s in sections) {
          final section = s['__section__'] ?? '';
          if (!section.startsWith('profile')) continue;
          final relPath = s['path'];
          if (relPath == null || relPath.isEmpty) continue;
          final isRelative = s['isrelative'] == null || s['isrelative'] == '1';
          final absPath = isRelative ? '$dir/$relPath' : relPath.replaceAll('\\', '/');
          final name = (s['name'] != null && s['name']!.isNotEmpty)
              ? s['name']!
              : relPath.replaceAll('\\', '/').split('/').last;
          // profiles.ini v2: khóa Default=1 ngay trong section Profile
          // profiles.ini v3: khóa Default=<path> trong section Install...
          final isProfileMarkedDefault = s['default'] == '1';
          result.add(BrowserProfileInfo(
            id: name,
            name: name,
            path: absPath,
            kind: BrowserKind.firefox,
            isDefault: isProfileMarkedDefault ||
                (installDefaultPath != null && installDefaultPath == relPath),
          ));
        }

        if (result.isNotEmpty) {
          result.sort((a, b) {
            if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
          return result;
        }
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  // ================== API CHÍNH ==================

  /// Lấy danh sách profiles của trình duyệt chỉ định (hoặc tự suy loại theo binary)
  List<BrowserProfileInfo> listSystemProfiles(String executable) {
    if (executable.trim().isEmpty) return const [];
    final kind = detectKindFromExecutable(executable);
    if (kind == BrowserKind.firefox) {
      return listFirefoxProfiles(executable);
    }
    return listChromiumProfiles(executable);
  }

  /// Tìm thông tin chi tiết 1 profile theo id (hoặc theo path với Firefox)
  BrowserProfileInfo? resolveProfile(String executable, String profileId) {
    final kind = detectKindFromExecutable(executable);
    if (kind == BrowserKind.firefox) {
      for (final p in listFirefoxProfiles(executable)) {
        if (p.id == profileId || p.path == profileId || p.name == profileId) return p;
      }
    } else {
      for (final p in listChromiumProfiles(executable)) {
        if (p.id == profileId) return p;
      }
    }
    return null;
  }

  /// Trả về đường dẫn thư mục dữ liệu thực tế của profile trình duyệt hệ thống
  String? resolveSystemProfileDirectory(String executable, String profileId) {
    final cleanId = profileId.trim();
    if (executable.trim().isEmpty || cleanId.isEmpty) return null;
    final resolved = resolveProfile(executable, cleanId);
    if (resolved?.path != null && resolved!.path!.isNotEmpty) {
      return resolved.path;
    }
    if (detectKindFromExecutable(executable) == BrowserKind.chromium) {
      final userDataDir = _chromiumUserDataDir(executable);
      if (userDataDir != null && userDataDir.isNotEmpty) {
        final sep = Platform.isWindows ? r'\' : '/';
        return '$userDataDir$sep$cleanId';
      }
    }
    return null;
  }
}
