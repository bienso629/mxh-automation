import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Dịch vụ tự động cung cấp công cụ ADB (Android Debug Bridge)
/// Hỗ trợ đa nền tảng: Linux, Windows, macOS
/// Tự động tải từ kho chính thức của Google Android và giải nén vào thư mục dữ liệu của ứng dụng
class AdbManagerService {
  static final AdbManagerService _instance = AdbManagerService._internal();
  factory AdbManagerService() => _instance;
  AdbManagerService._internal();

  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _statusMessage = '';

  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String get statusMessage => _statusMessage;

  /// URL tải Android SDK Platform-Tools chính thức từ Google
  String? _getPlatformToolsUrl() {
    if (Platform.isWindows) {
      return 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip';
    } else if (Platform.isMacOS) {
      return 'https://dl.google.com/android/repository/platform-tools-latest-darwin.zip';
    } else if (Platform.isLinux) {
      return 'https://dl.google.com/android/repository/platform-tools-latest-linux.zip';
    }
    return null;
  }

  /// Trả về thư mục lưu trữ ADB nhúng riêng của ứng dụng
  Future<Directory> getAdbDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    final adbDir = Directory(p.join(appDir.path, 'embedded_platform_tools'));
    if (!adbDir.existsSync()) {
      adbDir.createSync(recursive: true);
    }
    return adbDir;
  }

  /// Trả về đường dẫn file binary ADB nhúng
  Future<String> getEmbeddedAdbPath() async {
    final adbDir = await getAdbDirectory();
    final binName = Platform.isWindows ? 'adb.exe' : 'adb';
    return p.join(adbDir.path, 'platform-tools', binName);
  }

  /// Kiểm tra ADB nhúng có tồn tại và sẵn sàng hoạt động hay không
  Future<bool> isEmbeddedAdbReady() async {
    final exePath = await getEmbeddedAdbPath();
    final file = File(exePath);
    if (!file.existsSync()) return false;

    // Trên Linux / macOS cần đảm bảo quyền execute
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['+x', exePath]);
      } catch (_) {}
    }
    return true;
  }

  /// Lấy đường dẫn binary ADB hợp lệ nhất (Ưu tiên: 1. Đã nhúng -> 2. Biến môi trường hệ thống / SDK)
  Future<String> resolveAdbPath() async {
    // 1. Kiểm tra ADB trong bộ nhúng nội bộ của ứng dụng
    final embeddedPath = await getEmbeddedAdbPath();
    if (File(embeddedPath).existsSync()) {
      if (!Platform.isWindows) {
        try {
          await Process.run('chmod', ['+x', embeddedPath]);
        } catch (_) {}
      }
      return embeddedPath;
    }

    // 2. Tìm kiếm trên các đường dẫn tiêu chuẩn của hệ điều hành
    final sysCandidates = _getSystemCandidates();
    for (final c in sysCandidates) {
      if (File(c).existsSync()) {
        return c;
      }
    }

    // 3. Nếu chưa có, tự động tải và cài đặt ngay
    final downloadedPath = await ensureAdbInstalled();
    if (downloadedPath != null) {
      return downloadedPath;
    }

    // 4. Fallback cuối cùng
    return Platform.isWindows ? 'adb.exe' : 'adb';
  }

  List<String> _getSystemCandidates() {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final list = <String>[];

    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      list.addAll([
        p.join(localAppData, 'Android', 'Sdk', 'platform-tools', 'adb.exe'),
        p.join(home, 'AppData', 'Local', 'Android', 'Sdk', 'platform-tools', 'adb.exe'),
      ]);
    } else if (Platform.isMacOS) {
      list.addAll([
        p.join(home, 'Library', 'Android', 'sdk', 'platform-tools', 'adb'),
        '/opt/homebrew/bin/adb',
        '/usr/local/bin/adb',
      ]);
    } else if (Platform.isLinux) {
      list.addAll([
        p.join(home, 'Android', 'Sdk', 'platform-tools', 'adb'),
        p.join(home, 'android-sdk', 'platform-tools', 'adb'),
        '/usr/bin/adb',
        '/usr/local/bin/adb',
      ]);
    }
    return list;
  }

  /// Tự động tải xuống, giải nén và phân quyền chạy binary ADB cho máy người dùng
  Future<String?> ensureAdbInstalled({Function(double progress, String status)? onProgress}) async {
    final embeddedAdb = await getEmbeddedAdbPath();
    if (await isEmbeddedAdbReady()) {
      return embeddedAdb;
    }

    final downloadUrl = _getPlatformToolsUrl();
    if (downloadUrl == null) {
      debugPrint('[AdbManager] Không hỗ trợ tải tự động cho nền tảng: ${Platform.operatingSystem}');
      return null;
    }

    if (_isDownloading) {
      // Đang có tiến trình tải, đợi hoàn thành
      while (_isDownloading) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
      return File(embeddedAdb).existsSync() ? embeddedAdb : null;
    }

    _isDownloading = true;
    _downloadProgress = 0.0;
    _statusMessage = 'Bắt đầu tải công cụ ADB tự động...';
    onProgress?.call(_downloadProgress, _statusMessage);

    try {
      final adbDir = await getAdbDirectory();
      final zipFile = File(p.join(adbDir.path, 'platform-tools.zip'));

      debugPrint('[AdbManager] Đang tải Platform-Tools từ: $downloadUrl');
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Không thể tải ADB từ Google (HTTP ${response.statusCode})');
      }

      final contentLength = response.contentLength ?? 0;
      int downloadedBytes = 0;
      final sink = zipFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (contentLength > 0) {
          _downloadProgress = downloadedBytes / contentLength;
          _statusMessage = 'Đang tải ADB: ${(_downloadProgress * 100).toStringAsFixed(1)}%';
          onProgress?.call(_downloadProgress, _statusMessage);
        }
      }
      await sink.flush();
      await sink.close();

      // Giải nén gói zip
      _statusMessage = 'Đang giải nén bộ công cụ ADB...';
      onProgress?.call(1.0, _statusMessage);
      debugPrint('[AdbManager] Đang giải nén vào: ${adbDir.path}');

      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filename = file.name;
        final outPath = p.join(adbDir.path, filename);
        if (file.isFile) {
          final outFile = File(outPath);
          outFile.createSync(recursive: true);
          outFile.writeAsBytesSync(file.content as List<int>);
        } else {
          Directory(outPath).createSync(recursive: true);
        }
      }

      // Xóa file zip tạm sau khi giải nén xong
      try {
        if (zipFile.existsSync()) {
          zipFile.deleteSync();
        }
      } catch (_) {}

      // Cấp quyền thực thi binary trên Linux & macOS
      if (!Platform.isWindows && File(embeddedAdb).existsSync()) {
        await Process.run('chmod', ['+x', embeddedAdb]);
      }

      _statusMessage = 'Hoàn tất cấu hình ADB tự động.';
      debugPrint('[AdbManager] Cài đặt ADB thành công tại: $embeddedAdb');
      return embeddedAdb;
    } catch (e, stack) {
      debugPrint('[AdbManager] Lỗi cài đặt ADB tự động: $e\n$stack');
      _statusMessage = 'Lỗi tải ADB: $e';
      return null;
    } finally {
      _isDownloading = false;
      onProgress?.call(1.0, _statusMessage);
    }
  }
}
