import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Dịch vụ tự động quản lý và tải Android Command-Line Tools & Emulator
/// Cho phép máy tính người dùng chạy máy ảo AVD hoàn toàn độc lập,
/// không bắt buộc phải cài đặt Android Studio thủ công.
class EmulatorManagerService {
  static final EmulatorManagerService _instance = EmulatorManagerService._internal();
  factory EmulatorManagerService() => _instance;
  EmulatorManagerService._internal();

  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _statusMessage = '';

  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String get statusMessage => _statusMessage;

  /// URL tải Android Command-Line Tools chính thức từ Google repository
  String? _getCommandLineToolsUrl() {
    if (Platform.isWindows) {
      return 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip';
    } else if (Platform.isMacOS) {
      return 'https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip';
    } else if (Platform.isLinux) {
      return 'https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip';
    }
    return null;
  }

  /// URL tải Android Emulator độc lập từ Google repository
  String? _getEmulatorUrl() {
    if (Platform.isWindows) {
      return 'https://dl.google.com/android/repository/emulator-windows_x64-16489710.zip';
    } else if (Platform.isMacOS) {
      // Hỗ trợ nhận diện Apple Silicon vs Intel
      final isArm64 = Platform.version.contains('arm64') || Platform.version.contains('aarch64');
      if (isArm64) {
        return 'https://dl.google.com/android/repository/emulator-darwin_aarch64-16489710.zip';
      }
      return 'https://dl.google.com/android/repository/emulator-darwin_x64-16489710.zip';
    } else if (Platform.isLinux) {
      return 'https://dl.google.com/android/repository/emulator-linux_x64-16489710.zip';
    }
    return null;
  }

  /// Trả về thư mục lưu trữ Android SDK nội bộ của ứng dụng
  /// Ví dụ: ~/.agent_mxh_auto/android_sdk hoặc AppSupport
  Future<Directory> getSdkDirectory() async {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        (await getApplicationSupportDirectory()).path;
    final sdkDir = Directory(p.join(home, '.agent_mxh_auto', 'android_sdk'));
    if (!sdkDir.existsSync()) {
      sdkDir.createSync(recursive: true);
    }
    return sdkDir;
  }

  /// Trả về đường dẫn binary emulator độc lập nếu đã tải
  Future<String> getEmbeddedEmulatorPath() async {
    final sdkDir = await getSdkDirectory();
    final binName = Platform.isWindows ? 'emulator.exe' : 'emulator';
    return p.join(sdkDir.path, 'emulator', binName);
  }

  /// Trả về đường dẫn binary avdmanager
  Future<String> getEmbeddedAvdManagerPath() async {
    final sdkDir = await getSdkDirectory();
    final binName = Platform.isWindows ? 'avdmanager.bat' : 'avdmanager';
    return p.join(sdkDir.path, 'cmdline-tools', 'latest', 'bin', binName);
  }

  /// Trả về đường dẫn binary sdkmanager
  Future<String> getEmbeddedSdkManagerPath() async {
    final sdkDir = await getSdkDirectory();
    final binName = Platform.isWindows ? 'sdkmanager.bat' : 'sdkmanager';
    return p.join(sdkDir.path, 'cmdline-tools', 'latest', 'bin', binName);
  }

  /// Kiểm tra xem emulator binary đã sẵn sàng hay chưa
  Future<bool> isEmulatorReady() async {
    final exePath = await getEmbeddedEmulatorPath();
    final file = File(exePath);
    if (!file.existsSync()) return false;

    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['+x', exePath]);
      } catch (_) {}
    }
    return true;
  }

  /// Kiểm tra xem command-line tools đã sẵn sàng hay chưa
  Future<bool> isCommandLineToolsReady() async {
    final exePath = await getEmbeddedAvdManagerPath();
    return File(exePath).existsSync();
  }

  /// Tải file qua HTTP với cập nhật tiến trình
  Future<void> _downloadFile(
    String url,
    File destination, {
    required String taskTitle,
    Function(double progress, String status)? onProgress,
  }) async {
    debugPrint('[EmulatorManager] Đang tải $taskTitle từ $url');
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(url));
    final response = await client.send(request);

    if (response.statusCode != 200) {
      throw Exception('Tải $taskTitle thất bại (HTTP ${response.statusCode})');
    }

    final contentLength = response.contentLength ?? 0;
    int downloadedBytes = 0;
    final sink = destination.openWrite();

    await for (final chunk in response.stream) {
      sink.add(chunk);
      downloadedBytes += chunk.length;
      if (contentLength > 0) {
        _downloadProgress = downloadedBytes / contentLength;
        _statusMessage = 'Đang tải $taskTitle: ${(_downloadProgress * 100).toStringAsFixed(1)}%';
        onProgress?.call(_downloadProgress, _statusMessage);
      }
    }
    await sink.flush();
    await sink.close();
  }

  /// Giải nén file ZIP vào thư mục đích
  Future<void> _extractZip(
    File zipFile,
    Directory destinationDir, {
    required String taskTitle,
    Function(double progress, String status)? onProgress,
  }) async {
    _statusMessage = 'Đang giải nén $taskTitle...';
    onProgress?.call(1.0, _statusMessage);
    debugPrint('[EmulatorManager] Đang giải nén ${zipFile.path} vào ${destinationDir.path}');

    bool extractedWithNative = false;
    try {
      if (Platform.isWindows) {
        final res = await Process.run('tar', ['-xf', zipFile.path, '-C', destinationDir.path]);
        if (res.exitCode == 0) extractedWithNative = true;
      } else {
        final res = await Process.run('unzip', ['-q', '-o', zipFile.path, '-d', destinationDir.path]);
        if (res.exitCode == 0) extractedWithNative = true;
      }
    } catch (_) {}

    if (!extractedWithNative) {
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filename = file.name;
        final outPath = p.join(destinationDir.path, filename);
        if (file.isFile) {
          final outFile = File(outPath);
          outFile.parent.createSync(recursive: true);
          outFile.writeAsBytesSync(file.content as List<int>);
        } else {
          Directory(outPath).createSync(recursive: true);
        }
      }
    }

    try {
      if (zipFile.existsSync()) {
        zipFile.deleteSync();
      }
    } catch (_) {}
  }

  /// Tự động tải và cài đặt Android Command-Line Tools
  Future<String?> ensureCommandLineToolsInstalled({Function(double progress, String status)? onProgress}) async {
    final avdManagerBin = await getEmbeddedAvdManagerPath();
    if (await isCommandLineToolsReady()) {
      return avdManagerBin;
    }

    final downloadUrl = _getCommandLineToolsUrl();
    if (downloadUrl == null) {
      debugPrint('[EmulatorManager] Không hỗ trợ Command-Line Tools cho nền tảng: ${Platform.operatingSystem}');
      return null;
    }

    if (_isDownloading) {
      while (_isDownloading) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
      return File(avdManagerBin).existsSync() ? avdManagerBin : null;
    }

    _isDownloading = true;
    _downloadProgress = 0.0;
    _statusMessage = 'Chuẩn bị tải Command-Line Tools...';
    onProgress?.call(_downloadProgress, _statusMessage);

    try {
      final sdkDir = await getSdkDirectory();
      final tempZip = File(p.join(sdkDir.path, 'cmdline-tools.zip'));

      await _downloadFile(
        downloadUrl,
        tempZip,
        taskTitle: 'Android Command-Line Tools',
        onProgress: onProgress,
      );

      final cmdlineDir = Directory(p.join(sdkDir.path, 'cmdline-tools'));
      if (!cmdlineDir.existsSync()) {
        cmdlineDir.createSync(recursive: true);
      }

      await _extractZip(
        tempZip,
        cmdlineDir,
        taskTitle: 'Android Command-Line Tools',
        onProgress: onProgress,
      );

      // Thư viện giải nén của Google tạo ra folder `cmdline-tools`. Cần đổi tên thành `latest` theo chuẩn Android SDK
      final extractedCmdline = Directory(p.join(cmdlineDir.path, 'cmdline-tools'));
      final targetLatest = Directory(p.join(cmdlineDir.path, 'latest'));

      if (extractedCmdline.existsSync()) {
        if (targetLatest.existsSync()) {
          try {
            targetLatest.deleteSync(recursive: true);
          } catch (_) {}
        }
        try {
          extractedCmdline.renameSync(targetLatest.path);
        } catch (_) {
          // Nếu rename lỗi do khác volume, copy sang
          _copyDirectoryRecursive(extractedCmdline, targetLatest);
          try {
            extractedCmdline.deleteSync(recursive: true);
          } catch (_) {}
        }
      }

      // Cấp quyền execute trên Unix
      if (!Platform.isWindows) {
        final binDir = Directory(p.join(targetLatest.path, 'bin'));
        if (binDir.existsSync()) {
          for (final entity in binDir.listSync()) {
            if (entity is File) {
              try {
                await Process.run('chmod', ['+x', entity.path]);
              } catch (_) {}
            }
          }
        }
      }

      _statusMessage = 'Đã hoàn tất cài đặt Command-Line Tools.';
      return avdManagerBin;
    } catch (e, stack) {
      debugPrint('[EmulatorManager] Lỗi cài đặt Command-Line Tools: $e\n$stack');
      _statusMessage = 'Lỗi tải Command-Line Tools: $e';
      return null;
    } finally {
      _isDownloading = false;
      onProgress?.call(1.0, _statusMessage);
    }
  }

  /// Tự động tải và cài đặt Android Emulator độc lập từ Google
  Future<String?> ensureEmulatorInstalled({Function(double progress, String status)? onProgress}) async {
    final embeddedEmulator = await getEmbeddedEmulatorPath();
    if (await isEmulatorReady()) {
      return embeddedEmulator;
    }

    final downloadUrl = _getEmulatorUrl();
    if (downloadUrl == null) {
      debugPrint('[EmulatorManager] Không hỗ trợ Emulator cho nền tảng: ${Platform.operatingSystem}');
      return null;
    }

    if (_isDownloading) {
      while (_isDownloading) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
      return File(embeddedEmulator).existsSync() ? embeddedEmulator : null;
    }

    _isDownloading = true;
    _downloadProgress = 0.0;
    _statusMessage = 'Bắt đầu tải Android Emulator từ Google...';
    onProgress?.call(_downloadProgress, _statusMessage);

    try {
      final sdkDir = await getSdkDirectory();
      final tempZip = File(p.join(sdkDir.path, 'emulator.zip'));

      await _downloadFile(
        downloadUrl,
        tempZip,
        taskTitle: 'Android Emulator',
        onProgress: onProgress,
      );

      await _extractZip(
        tempZip,
        sdkDir,
        taskTitle: 'Android Emulator',
        onProgress: onProgress,
      );

      // Cấp quyền execute trên Unix
      if (!Platform.isWindows && File(embeddedEmulator).existsSync()) {
        try {
          await Process.run('chmod', ['+x', embeddedEmulator]);
          final binDir = Directory(p.join(sdkDir.path, 'emulator'));
          for (final entity in binDir.listSync()) {
            if (entity is File && !entity.path.endsWith('.txt') && !entity.path.endsWith('.ini')) {
              try {
                await Process.run('chmod', ['+x', entity.path]);
              } catch (_) {}
            }
          }
        } catch (_) {}
      }

      _statusMessage = 'Đã cài đặt Android Emulator thành công.';
      debugPrint('[EmulatorManager] Cài đặt Emulator thành công tại: $embeddedEmulator');
      return embeddedEmulator;
    } catch (e, stack) {
      debugPrint('[EmulatorManager] Lỗi cài đặt Emulator tự động: $e\n$stack');
      _statusMessage = 'Lỗi tải Android Emulator: $e';
      return null;
    } finally {
      _isDownloading = false;
      onProgress?.call(1.0, _statusMessage);
    }
  }

  /// Đọc `image.sysdir.1` trong config.ini của AVD (ví dụ
  /// `system-images/android-37.0/google_apis_playstore_ps16k/x86_64/`).
  String? readAvdSysDir(Directory avdDir) {
    final cfg = File(p.join(avdDir.path, 'config.ini'));
    if (!cfg.existsSync()) return null;
    for (final line in cfg.readAsLinesSync()) {
      final t = line.trim();
      if (t.startsWith('image.sysdir.1=')) {
        final v = t.substring('image.sysdir.1='.length).trim().replaceAll('\\', '/');
        return v.isEmpty ? null : v;
      }
    }
    return null;
  }

  /// Kiểm tra system image của AVD đã có trong [sdkRoot] chưa.
  bool isSystemImagePresent(String sdkRoot, String sysDir) {
    final dir = Directory(p.joinAll([sdkRoot, ...sysDir.split('/').where((s) => s.isNotEmpty)]));
    return File(p.join(dir.path, 'system.img')).existsSync();
  }

  /// File backup AVD (.avd + .ini) KHÔNG chứa Android System Image (~2-3 GB).
  /// Máy chưa từng cài Android Studio sẽ thiếu image => emulator tắt ngay khi khởi động.
  /// Hàm này tự tra kho Google và tải đúng image AVD yêu cầu vào [sdkRoot].
  Future<bool> ensureSystemImageForAvd(
    Directory avdDir,
    String sdkRoot, {
    Function(double progress, String status)? onProgress,
  }) async {
    final sysDir = readAvdSysDir(avdDir);
    if (sysDir == null) return true; // Không xác định được, để emulator tự xử lý
    if (isSystemImagePresent(sdkRoot, sysDir)) return true;

    final parts = sysDir.split('/').where((s) => s.isNotEmpty).toList();
    // [system-images, android-37.0, google_apis_playstore_ps16k, x86_64]
    if (parts.length < 4 || parts[0] != 'system-images') return false;
    final api = parts[1];
    final tag = parts[2];
    final abi = parts[3];
    final pkgPath = 'system-images;$api;$tag;$abi';

    // Kho XML của Google gộp nhiều biến thể tag (vd: *_ps16k nằm trong google_apis_playstore)
    final baseTag = tag.replaceAll(RegExp(r'_(ps16k|tablet)$'), '');
    final repoTags = <String>{tag, baseTag, 'google_apis_playstore', 'google_apis', 'default'};

    String? zipUrl;
    for (final rt in repoTags) {
      for (final ver in ['4', '3']) {
        final xmlUrl = 'https://dl.google.com/android/repository/sys-img/$rt/sys-img2-$ver.xml';
        try {
          final res = await http.get(Uri.parse(xmlUrl));
          if (res.statusCode != 200) continue;
          final m = RegExp(
            '<remotePackage path="${RegExp.escape(pkgPath)}">(.*?)</remotePackage>',
            dotAll: true,
          ).firstMatch(res.body);
          if (m == null) continue;
          final urlMatch = RegExp(r'<url>([^<]+)</url>').firstMatch(m.group(1)!);
          if (urlMatch == null) continue;
          zipUrl = 'https://dl.google.com/android/repository/sys-img/$rt/${urlMatch.group(1)!.trim()}';
          break;
        } catch (_) {}
      }
      if (zipUrl != null) break;
    }

    if (zipUrl == null) {
      _statusMessage = 'Không tìm thấy system image $pkgPath trên kho Google.';
      debugPrint('[EmulatorManager] $_statusMessage');
      return false;
    }

    while (_isDownloading) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    if (isSystemImagePresent(sdkRoot, sysDir)) return true;

    _isDownloading = true;
    final targetDir = Directory(p.joinAll([sdkRoot, ...parts]));
    final tempZip = File(p.join(sdkRoot, 'sysimg_${DateTime.now().millisecondsSinceEpoch}.zip'));
    final tempExtract = Directory(p.join(sdkRoot, '.sysimg_tmp_${DateTime.now().millisecondsSinceEpoch}'));
    try {
      Directory(sdkRoot).createSync(recursive: true);
      await _downloadFile(zipUrl, tempZip, taskTitle: 'Android System Image ($api)', onProgress: onProgress);
      tempExtract.createSync(recursive: true);
      await _extractZip(tempZip, tempExtract, taskTitle: 'Android System Image', onProgress: onProgress);

      // Zip của Google có 1 thư mục gốc (thường là tên ABI, vd: x86_64/)
      Directory srcDir = tempExtract;
      final children = tempExtract.listSync().whereType<Directory>().toList();
      if (!File(p.join(tempExtract.path, 'system.img')).existsSync() && children.length == 1) {
        srcDir = children.first;
      }
      if (!File(p.join(srcDir.path, 'system.img')).existsSync()) {
        throw Exception('Gói system image tải về không hợp lệ (thiếu system.img).');
      }

      if (targetDir.existsSync()) targetDir.deleteSync(recursive: true);
      targetDir.parent.createSync(recursive: true);
      try {
        srcDir.renameSync(targetDir.path);
      } catch (_) {
        _copyDirectoryRecursive(srcDir, targetDir);
      }
      _statusMessage = 'Đã cài đặt Android System Image $api.';
      debugPrint('[EmulatorManager] Đã cài system image tại ${targetDir.path}');
      return true;
    } catch (e, stack) {
      debugPrint('[EmulatorManager] Lỗi tải system image: $e\n$stack');
      _statusMessage = 'Lỗi tải Android System Image: $e';
      return false;
    } finally {
      _isDownloading = false;
      try {
        if (tempZip.existsSync()) tempZip.deleteSync();
      } catch (_) {}
      try {
        if (tempExtract.existsSync()) tempExtract.deleteSync(recursive: true);
      } catch (_) {}
      onProgress?.call(1.0, _statusMessage);
    }
  }

  void _copyDirectoryRecursive(Directory src, Directory dst) {
    if (!dst.existsSync()) {
      dst.createSync(recursive: true);
    }
    for (final entity in src.listSync(recursive: false)) {
      final newPath = p.join(dst.path, p.basename(entity.path));
      if (entity is Directory) {
        _copyDirectoryRecursive(entity, Directory(newPath));
      } else if (entity is File) {
        entity.copySync(newPath);
      }
    }
  }
}
