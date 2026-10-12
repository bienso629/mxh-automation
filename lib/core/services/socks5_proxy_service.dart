import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'package:dartssh2/dartssh2.dart';
import '../../models/server_model.dart';
import 'adb_manager_service.dart';
import 'emulator_manager_service.dart';
import 'local_config_service.dart';
import 'persona_service.dart';

/// Hàm chuẩn hóa chuỗi tiếng Việt có dấu thành không dấu an toàn cho tên hệ thống / tên tệp / tên AVD
String removeVietnameseDiacritics(String str) {
  var result = str;
  const vietnameseMap = {
    'a': 'áàảãạăắằẳẵặâấầẩẫậ',
    'A': 'ÁÀẢÃẠĂẮẰẲẴẶÂẤẦẨẪẬ',
    'd': 'đ',
    'D': 'Đ',
    'e': 'éèẻẽẹêếềểễệ',
    'E': 'ÉÈẺẼẸÊẾỀỂỄỆ',
    'i': 'íìỉĩị',
    'I': 'ÍÌỈĨỊ',
    'o': 'óòỏõọôốồổỗộơớờởỡợ',
    'O': 'ÓÒỎÕỌÔỐỒỔỖỘƠỚỜỞỠỢ',
    'u': 'úùủũụưứừửữự',
    'U': 'ÚÙỦŨỤƯỨỪỬỮỰ',
    'y': 'ýỳỷỹỵ',
    'Y': 'ÝỲỶỸỴ',
  };

  vietnameseMap.forEach((nonAccent, accents) {
    for (int i = 0; i < accents.length; i++) {
      result = result.replaceAll(accents[i], nonAccent);
    }
  });

  return result;
}

/// Sinh tên AVD máy ảo đồng nhất theo tên nhân vật (Persona Name), fallback về địa chỉ IP nếu tên rỗng
String generatePersonaAvdName({required String ip, String? personaName}) {
  final cleanIp = ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  if (personaName != null && personaName.trim().isNotEmpty) {
    final noDiacritics = removeVietnameseDiacritics(personaName.trim());
    var slug = noDiacritics
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (slug.isNotEmpty) {
      return 'Pixel_10_Pro_persona_$slug';
    }
  }
  return 'Pixel_10_Pro_persona_$cleanIp';
}

class Socks5Session {
  final int localPort;
  final ServerModel? server;
  final String ip;
  final Process? sshProcess;
  final File? askpassFile;
  final SSHClient? sshClient;
  final SSHDynamicForward? dynamicForward;
  final ServerSocket? localPortForwardServer;
  Process? browserProcess;
  Process? deviceProcess;
  Process? httpBridgeProcess;
  ServerSocket? httpBridgeServer;
  int? emulatorPort;
  String? remoteDeviceAddress;
  DateTime createdAt = DateTime.now();
  DateTime? browserLaunchedAt;

  Socks5Session({
    required this.localPort,
    this.server,
    required this.ip,
    this.sshProcess,
    this.askpassFile,
    this.sshClient,
    this.dynamicForward,
    this.localPortForwardServer,
    this.remoteDeviceAddress,
  });

  Future<void> stop() async {
    try {
      await dynamicForward?.close();
    } catch (_) {}
    try {
      await localPortForwardServer?.close();
    } catch (_) {}
    try {
      sshClient?.close();
    } catch (_) {}
    try {
      sshProcess?.kill(ProcessSignal.sigterm);
    } catch (_) {}
    try {
      if (askpassFile != null && askpassFile!.existsSync()) {
        askpassFile!.deleteSync();
      }
    } catch (_) {}
    try {
      browserProcess?.kill();
    } catch (_) {}
    try {
      deviceProcess?.kill();
    } catch (_) {}
    try {
      httpBridgeProcess?.kill();
    } catch (_) {}
    try {
      await httpBridgeServer?.close();
    } catch (_) {}
  }
}

class Socks5ProxyService extends ChangeNotifier {
  static final Socks5ProxyService _instance = Socks5ProxyService._internal();
  factory Socks5ProxyService() => _instance;
  Timer? _watchdogTimer;

  Socks5ProxyService._internal() {
    _startWatchdog();
    // Tự động kiểm tra và dọn dẹp các lock file rác, tiến trình zombie khi khởi chạy app
    repairBrowserProfilesAndEnvironment().catchError((_) => <String, dynamic>{});
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    // Quét định kỳ mỗi 1.5 giây để phát hiện ngay khi trình duyệt bị tắt bằng tay (tắt cứng)
    _watchdogTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _checkTerminatedBrowsers();
    });
  }

  /// Kiểm tra các session đang ghi nhận, dọn dẹp khi tiến trình tắt và tự động phát hiện thiết bị đang chạy ngoài OS
  void _checkTerminatedBrowsers() {
    final now = DateTime.now();
    bool stateChanged = false;

    // 1. Dọn dẹp session đã kết thúc
    if (_activeSessions.isNotEmpty) {
      final deadIps = <String>[];
      for (final entry in _activeSessions.entries) {
        final ip = entry.key;
        final session = entry.value;

        // Thời gian ân hạn 10 giây sau khi tạo session hoặc vừa mở trình duyệt
        final timeSinceCreated = now.difference(session.createdAt);
        if (timeSinceCreated < const Duration(seconds: 10)) {
          continue;
        }
        if (session.browserLaunchedAt != null) {
          final timeSinceLaunch = now.difference(session.browserLaunchedAt!);
          if (timeSinceLaunch < const Duration(seconds: 10)) {
            continue;
          }
        }

        // Kiểm tra thực tế trên hệ thống xem profile IP này còn tiến trình trình duyệt hoặc device nào không
        if (!_isSystemProcessAliveForIp(ip) && !_isDeviceProcessAliveForIp(ip)) {
          deadIps.add(ip);
        }
      }

      if (deadIps.isNotEmpty) {
        for (final ip in deadIps) {
          final session = _activeSessions.remove(ip);
          session?.stop();
        }
        stateChanged = true;
      }
    }

    // 2. Tự động quét và phát hiện các mobile device / emulator đang chạy trên OS (kể cả do CLI mxh-tool mở hoặc app vừa khởi động lại)
    try {
      final homeDir = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path;
      final tmpDir = Directory(p.join(homeDir, '.agent_mxh_auto', 'tmp'));
      if (tmpDir.existsSync()) {
        for (final f in tmpDir.listSync(followLinks: false)) {
          if (f is File && f.path.contains('device_') && f.path.endsWith('.json')) {
            try {
              final content = f.readAsStringSync();
              final meta = json.decode(content);
              final ip = meta['ip']?.toString();
              final emuPid = meta['emulator_pid'];
              final cport = meta['console_port'];
              if (ip != null && ip.isNotEmpty && emuPid != null && emuPid is int) {
                final isAlive = File('/proc/$emuPid/cmdline').existsSync() || Process.killPid(emuPid, ProcessSignal.sigcont);
                if (isAlive) {
                  if (!_activeSessions.containsKey(ip)) {
                    final newSession = Socks5Session(
                      localPort: 0,
                      ip: ip,
                    );
                    if (cport != null) {
                      newSession.emulatorPort = int.tryParse(cport.toString());
                    }
                    _activeSessions[ip] = newSession;
                    stateChanged = true;
                  } else {
                    final exist = _activeSessions[ip]!;
                    if (exist.emulatorPort == null && cport != null) {
                      exist.emulatorPort = int.tryParse(cport.toString());
                      stateChanged = true;
                    }
                  }
                } else {
                  // Tiến trình không còn tồn tại, xóa file metadata rác
                  try {
                    f.deleteSync();
                  } catch (_) {}
                }
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    if (stateChanged) {
      notifyListeners();
    }
  }

  final Map<String, Socks5Session> _activeSessions = {};
  final Set<String> _closingDeviceIps = {};

  bool isIpRunning(String ip) => _activeSessions.containsKey(ip);

  Socks5Session? getSession(String ip) => _activeSessions[ip];

  /// Quét xem trên hệ thống OS có tiến trình trình duyệt nào đang chạy profile của IP này không
  bool _isSystemProcessAliveForIp(String ip) {
    try {
      final session = _activeSessions[ip];
      // Nếu có đối tượng Process đang giữ và chưa thoát
      if (session != null && session.browserProcess != null) {
        return true;
      }

      // Trên Windows:
      if (Platform.isWindows) {
        if (session != null && session.browserLaunchedAt != null) {
          // Trong 5 giây đầu sau khi mở, giữ trạng thái là true để trình duyệt kịp khởi động
          final elapsed = DateTime.now().difference(session.browserLaunchedAt!);
          if (elapsed.inSeconds < 5) {
            return true;
          }
          // Sau 5 giây, kiểm tra thực tế xem profile lock có còn tồn tại không
          final sanitizedIp = ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
          final homeDir = Platform.environment['USERPROFILE'] ??
              Platform.environment['HOME'] ??
              Directory.systemTemp.path;
          final lockFile = File(p.join(homeDir, '.agent_mxh_auto', 'browser_profiles', 'ip_$sanitizedIp', 'lockfile'));
          final singletonLock = File(p.join(homeDir, '.agent_mxh_auto', 'browser_profiles', 'ip_$sanitizedIp', 'SingletonLock'));
          if (lockFile.existsSync() || singletonLock.existsSync()) {
            return true;
          }
          // Nếu cả lock file đều không còn, trình duyệt đã bị đóng
          session.browserLaunchedAt = null;
          return false;
        }
      }

      final sanitizedIp = ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final needle = 'browser_profiles/ip_$sanitizedIp';

      if (Platform.isLinux) {
        final procDir = Directory('/proc');
        if (procDir.existsSync()) {
          final myPid = pid;
          for (final entity in procDir.listSync(followLinks: false)) {
            final baseName = entity.path.split('/').last;
            final p = int.tryParse(baseName);
            if (p == null || p == myPid) continue;
            try {
              final cmdFile = File('${entity.path}/cmdline');
              if (cmdFile.existsSync()) {
                final bytes = cmdFile.readAsBytesSync();
                final cmd = String.fromCharCodes(bytes);
                if (cmd.contains(needle) && !cmd.contains('device_profiles') && !cmd.contains('python') && !cmd.contains('pgrep')) {
                  return true;
                }
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// Quét xem trên hệ thống OS có tiến trình mobile device nào đang chạy cho IP này không
  bool _isDeviceProcessAliveForIp(String ip) {
    try {
      final session = _activeSessions[ip];
      if (session != null && session.deviceProcess != null) {
        return true;
      }
      if (session?.remoteDeviceAddress != null) {
        return true;
      }
      if (Platform.isWindows) {
        if (session != null && session.emulatorPort != null) {
          return true;
        }
      }

      final sanitizedIp = ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

      // 1. Kiểm tra file metadata device_<ip>.json do CLI mxh-tool hoặc app tạo ra
      try {
        final homeDir = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path;
        final metaFile = File(p.join(homeDir, '.agent_mxh_auto', 'tmp', 'device_$sanitizedIp.json'));
        if (metaFile.existsSync()) {
          final content = metaFile.readAsStringSync();
          final meta = json.decode(content);
          final emuPid = meta['emulator_pid'];
          if (emuPid != null && emuPid is int) {
            if (File('/proc/$emuPid/cmdline').existsSync() || Process.killPid(emuPid, ProcessSignal.sigcont)) {
              return true;
            }
          }
        }
      } catch (_) {}

      final port = session?.emulatorPort;
      final needleProfile = 'device_profiles/ip_$sanitizedIp';
      final needlePersonaAvd = 'persona_$sanitizedIp';
      final needlePort = port != null ? '-port\x00$port' : null;

      if (Platform.isLinux) {
        final procDir = Directory('/proc');
        if (procDir.existsSync()) {
          final myPid = pid;
          for (final entity in procDir.listSync(followLinks: false)) {
            final baseName = entity.path.split('/').last;
            final p = int.tryParse(baseName);
            if (p == null || p == myPid) continue;
            try {
              final cmdFile = File('${entity.path}/cmdline');
              if (cmdFile.existsSync()) {
                final bytes = cmdFile.readAsBytesSync();
                final cmd = String.fromCharCodes(bytes);
                final matchesProfile = cmd.contains(needleProfile) || cmd.contains(needlePersonaAvd);
                final matchesPort = needlePort != null && cmd.contains(needlePort);
                if ((matchesProfile || matchesPort) && !cmd.contains('python') && !cmd.contains('pgrep')) {
                  return true;
                }
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// Tìm console port (5554, 5556,...) của máy ảo AVD đang chạy trên hệ thống
  int? _findRunningConsolePortForAvd(String avdName) {
    // 1. Kiểm tra trong metadata json trước nếu có
    try {
      final homeDir = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path;
      final tmpDir = Directory(p.join(homeDir, '.agent_mxh_auto', 'tmp'));
      if (tmpDir.existsSync()) {
        for (final f in tmpDir.listSync(followLinks: false)) {
          if (f is File && f.path.contains('device_') && f.path.endsWith('.json')) {
            try {
              final meta = json.decode(f.readAsStringSync());
              if (meta['target_avd'] == avdName || (meta['ip'] != null && avdName.contains(meta['ip'].toString().replaceAll('.', '_')))) {
                final emuPid = meta['emulator_pid'];
                if (emuPid != null && emuPid is int && File('/proc/$emuPid/cmdline').existsSync()) {
                  final cport = meta['console_port'];
                  if (cport != null) {
                    final parsed = int.tryParse(cport.toString());
                    if (parsed != null) return parsed;
                  }
                }
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    // 2. Quét tiến trình thực tế trong /proc khớp tên avdName và -port
    try {
      final procDir = Directory('/proc');
      if (procDir.existsSync()) {
        final myPid = pid;
        for (final entity in procDir.listSync(followLinks: false)) {
          final baseName = entity.path.split('/').last;
          final p = int.tryParse(baseName);
          if (p == null || p == myPid) continue;
          try {
            final cmdFile = File('${entity.path}/cmdline');
            if (cmdFile.existsSync()) {
              final raw = cmdFile.readAsStringSync();
              if (raw.contains(avdName) && raw.contains('-port')) {
                final match = RegExp(r'-port[\x00\s]+(\d+)').firstMatch(raw);
                if (match != null) {
                  return int.tryParse(match.group(1)!);
                }
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return null;
  }

  /// Đọc authentication token của emulator console
  String? _getEmulatorConsoleAuthToken() {
    try {
      final homeDir = Platform.environment['HOME'] ?? Directory.systemTemp.path;
      final tokenFile = File('$homeDir/.emulator_console_auth_token');
      if (tokenFile.existsSync()) {
        final t = tokenFile.readAsStringSync().trim();
        if (t.isNotEmpty) return t;
      }
    } catch (_) {}
    return null;
  }

  /// Lưu trạng thái và snapshot của máy ảo qua Telnet Console
  Future<bool> _saveSnapshotViaConsole(int consolePort, {String snapshotName = 'default_boot'}) async {
    try {
      final token = _getEmulatorConsoleAuthToken();
      final socket = await Socket.connect('127.0.0.1', consolePort, timeout: const Duration(seconds: 3));
      final completer = Completer<void>();
      socket.listen(
        (_) {},
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete();
        },
      );

      if (token != null && token.isNotEmpty) {
        socket.write('auth $token\n');
        await Future.delayed(const Duration(milliseconds: 200));
      }
      socket.write('avd snapshot save $snapshotName\n');
      await Future.delayed(const Duration(milliseconds: 1000));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Tắt máy ảo an toàn chuẩn graceful qua Telnet Console để emulator tự flush userdata xuống đĩa
  Future<bool> _gracefulKillEmulatorViaConsole(int consolePort) async {
    try {
      final token = _getEmulatorConsoleAuthToken();
      final socket = await Socket.connect('127.0.0.1', consolePort, timeout: const Duration(seconds: 3));
      if (token != null && token.isNotEmpty) {
        socket.write('auth $token\n');
        await Future.delayed(const Duration(milliseconds: 150));
      }
      socket.write('kill\n');
      await Future.delayed(const Duration(milliseconds: 300));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Kiểm tra xem trình duyệt gắn với IP này có đang mở hay không
  bool isBrowserRunningForIp(String ip) {
    return _isSystemProcessAliveForIp(ip);
  }

  /// Kiểm tra xem mobile device gắn với IP này có đang chạy hay không
  bool isDeviceRunningForIp(String ip) {
    if (_closingDeviceIps.contains(ip)) {
      return false;
    }
    final session = _activeSessions[ip];
    if (session?.remoteDeviceAddress != null) {
      return true;
    }
    return _isDeviceProcessAliveForIp(ip);
  }

  /// Danh sách tất cả IP hiện đang có thiết bị mobile / AVD đang chạy
  List<String> get runningDeviceIps {
    final res = <String>[];
    for (final ip in _activeSessions.keys) {
      if (isDeviceRunningForIp(ip)) {
        res.add(ip);
      }
    }
    return res;
  }

  /// Lấy số lượng thiết bị tối đa được mở đồng thời từ cấu hình hệ thống
  Future<int> getMaxConcurrentDevices() async {
    try {
      final cfg = await LocalConfigService().loadConfig();
      final val = cfg['max_concurrent_devices'];
      if (val != null) {
        final parsed = int.tryParse(val.toString());
        if (parsed != null && parsed > 0) {
          return parsed;
        }
      }
    } catch (_) {}
    return 2;
  }

  /// Kiểm tra số lượng devices chạy đồng thời (mặc định theo cấu hình hệ thống hoặc 2 devices).
  /// Khi số lượng Device được mở đang vượt quá giới hạn thì tuyệt đối KHÔNG tự ý đóng device trước
  /// mà ném lỗi thông báo: "Số lượng thiết bị đã mở quá [effectiveMax]"
  Future<void> ensureDeviceCapacity({int? maxConcurrent, List<String>? exemptIps}) async {
    final effectiveMax = maxConcurrent ?? await getMaxConcurrentDevices();
    final running = runningDeviceIps;
    
    // Đếm số lượng thiết bị đang chạy mà không tính thiết bị hiện tại (nếu đang chạy lại chính nó)
    final runningOthers = running.where((ip) => exemptIps == null || !exemptIps.contains(ip)).toList();
    if (runningOthers.length >= effectiveMax) {
      throw Exception('Số lượng thiết bị đã mở quá $effectiveMax');
    }
  }

  /// QUY TRÌNH HÀNG ĐỢI THIẾT BỊ AN TOÀN (DEVICE TASK QUEUE):
  /// Đảm bảo dù có yêu cầu chạy 10, 50 hay 100 devices cùng một lúc thì:
  /// 1. Tối đa chỉ có [maxConcurrent] thiết bị được mở đồng thời để chống treo máy.
  /// 2. BẮT BUỘC mỗi thiết bị phải chạy XONG HOÀN TOÀN tác vụ [taskRunner] của nó trước khi bị tắt đi.
  /// 3. Khi một thiết bị chạy xong và tắt đi, thiết bị tiếp theo trong hàng đợi mới được mở lên.
  /// 4. Đảm bảo toàn bộ danh sách thiết bị (kể cả 100 devices) đều sẽ được phục vụ và hoàn thành lần lượt.
  Future<Map<String, dynamic>> runDeviceTaskQueue<T>({
    required List<String> ips,
    required Future<T> Function(String ip) taskRunner,
    int? maxConcurrent,
    void Function(String ip, int completed, int total, String status)? onProgress,
  }) async {
    final effectiveMax = maxConcurrent ?? await getMaxConcurrentDevices();
    final distinctIps = ips.toSet().toList();
    final total = distinctIps.length;
    final Map<String, dynamic> results = {
      'total': total,
      'success': <String>[],
      'failed': <String, dynamic>{},
    };

    if (distinctIps.isEmpty) return results;

    int completedCount = 0;
    int currentIndex = 0;

    // Worker pool xử lý luân phiên
    Future<void> worker() async {
      while (true) {
        if (currentIndex >= distinctIps.length) return;
        final ip = distinctIps[currentIndex++];

        onProgress?.call(ip, completedCount, total, 'Bắt đầu xử lý thiết bị $ip...');

        try {
          // 1. Kiểm soát sức chứa trước khi khởi chạy thiết bị mới
          await ensureDeviceCapacity(maxConcurrent: effectiveMax, exemptIps: [ip]);

          // 2. Chờ tác vụ auto trên thiết bị HOÀN THÀNH TOÀN DIỆN (bất kể thời gian bao lâu)
          await taskRunner(ip);
          (results['success'] as List<String>).add(ip);
          onProgress?.call(ip, completedCount + 1, total, 'Hoàn thành tác vụ trên $ip.');
        } catch (e) {
          (results['failed'] as Map<String, dynamic>)[ip] = e.toString();
          onProgress?.call(ip, completedCount + 1, total, 'Lỗi trên thiết bị $ip: $e');
        } finally {
          // 3. TẮT THIẾT BỊ XONG XUÔI để giải phóng RAM & CPU cho thiết bị tiếp theo
          try {
            await closeDeviceForIp(ip);
          } catch (_) {}

          completedCount++;
          onProgress?.call(ip, completedCount, total, 'Đã đóng thiết bị $ip để nhường tài nguyên.');
        }
      }
    }

    // Khởi chạy đồng thời số worker bằng effectiveMax
    final poolSize = distinctIps.length < effectiveMax ? distinctIps.length : effectiveMax;
    final workers = List.generate(poolSize, (_) => worker());
    await Future.wait(workers);

    return results;
  }

  /// Khởi tạo Dynamic SOCKS5 Proxy thông qua Pure Dart SSH (hoặc OpenSSH native tunnel)
  /// Đảm bảo hoạt động trơn tru 100% trên cả Windows, Linux và macOS không phụ thuộc Askpass hay OpenSSH bên ngoài
  Future<Socks5Session> startSocks5Server({
    required ServerModel server,
    required String ip,
  }) async {
    // 1. Nếu đã có session đang chạy và còn sống thì tái sử dụng
    if (_activeSessions.containsKey(ip)) {
      final existing = _activeSessions[ip]!;
      try {
        final check = await Socket.connect('127.0.0.1', existing.localPort, timeout: const Duration(milliseconds: 500));
        await check.close();
        return existing;
      } catch (_) {
        await existing.stop();
        _activeSessions.remove(ip);
      }
    }

    // 2. Tìm cổng local còn trống
    final tempServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final localPort = tempServer.port;
    await tempServer.close();

    final sshHost = server.serverIp;

    // Tính toán remote socks5 port dựa theo IP nếu là Server hỗ trợ Multi-IP Proxy (Server 100)
    final parts = ip.split('.');
    int? remoteSocksPort;
    if (parts.length == 4) {
      final p2 = int.tryParse(parts[2]);
      final p3 = int.tryParse(parts[3]);
      if (p2 != null && p3 != null) {
        remoteSocksPort = 20000 + (p2 * 256 + p3) % 10000;
      }
    }

    final isAlias = ip != server.serverIp;
    final useRemoteSocks = remoteSocksPort != null && (isAlias || server.serverIp == '103.74.116.119');

    // CÁCH 1: Thử nghiệm Pure Dart SSHClient (hoàn toàn không cần OpenSSH hay askpass CLI ngoài OS)
    try {
      final socket = await SSHSocket.connect(
        sshHost,
        server.sshPort,
        timeout: const Duration(seconds: 10),
      );
      final client = SSHClient(
        socket,
        username: server.sshUser,
        onPasswordRequest: () => server.sshPass,
        identities: (server.sshKey != null && server.sshKey!.isNotEmpty)
            ? SSHKeyPair.fromPem(server.sshKey!)
            : null,
      );
      await client.authenticated;

      if (useRemoteSocks) {
        // Forward local port -> remote socks port trên VPS (tương đương -L localPort:127.0.0.1:remotePort)
        final serverSocket = await ServerSocket.bind('127.0.0.1', localPort);
        serverSocket.listen((clientSocket) async {
          bool isClientClosed = false;
          void closeClient() {
            if (isClientClosed) return;
            isClientClosed = true;
            try {
              clientSocket.destroy();
            } catch (_) {}
          }

          // QUAN TRỌNG: Lỗi EPIPE/ECONNRESET khi write socket KHÔNG nổ tại chỗ gọi add()
          // mà bị đẩy bất đồng bộ qua Future done của socket. Phải nuốt lỗi trên done,
          // nếu không sẽ nổ Unhandled Exception (Broken pipe) làm rung cả zone.
          unawaited(clientSocket.done.catchError((_) {}));
          void safeWriteClient(List<int> data) {
            if (isClientClosed) return;
            try {
              clientSocket.add(data);
            } catch (_) {
              closeClient();
            }
          }

          try {
            final channel = await client.forwardLocal('127.0.0.1', remoteSocksPort!);
            clientSocket.listen(
              (data) {
                try {
                  channel.sink.add(data);
                } catch (_) {
                  closeClient();
                }
              },
              onDone: () {
                try {
                  channel.sink.close();
                } catch (_) {}
              },
              onError: (_) => closeClient(),
              cancelOnError: true,
            );
            channel.stream.listen(
              (data) {
                safeWriteClient(data);
              },
              onDone: () => closeClient(),
              onError: (_) => closeClient(),
              cancelOnError: true,
            );
          } catch (_) {
            closeClient();
          }
        });

        final session = Socks5Session(
          localPort: localPort,
          server: server,
          ip: ip,
          sshClient: client,
          localPortForwardServer: serverSocket,
        );
        _activeSessions[ip] = session;
        notifyListeners();
        return session;
      } else {
        // Dynamic SOCKS5 Forwarding thuần Dart (tương đương -D localPort)
        final dynamicForward = await client.forwardDynamic(
          bindHost: '127.0.0.1',
          bindPort: localPort,
        );

        final session = Socks5Session(
          localPort: localPort,
          server: server,
          ip: ip,
          sshClient: client,
          dynamicForward: dynamicForward,
        );
        _activeSessions[ip] = session;
        notifyListeners();
        return session;
      }
    } catch (_) {
      // CÁCH 2: Fallback sang OpenSSH CLI của hệ điều hành nếu Pure Dart SSH gặp sự cố mạng
    }

    // 3. Chuẩn bị file script Askpass để cấp mật khẩu tự động cho lệnh ssh CLI (Linux fallback)
    final homeDir = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    final runDir = Directory(p.join(homeDir, '.agent_mxh_auto', 'tmp'));
    if (!runDir.existsSync()) {
      runDir.createSync(recursive: true);
    }

    final askpassExt = Platform.isWindows ? '.bat' : '.sh';
    final askpassPath = p.join(runDir.path, 'ssh_askpass_${DateTime.now().millisecondsSinceEpoch}_$localPort$askpassExt');
    final askpassFile = File(askpassPath);

    if (Platform.isWindows) {
      askpassFile.writeAsStringSync('@echo off\r\necho ${server.sshPass}\r\n');
    } else {
      final escapedPass = server.sshPass.replaceAll(r'\', r'\\').replaceAll(r'"', r'\"').replaceAll(r'$', r'\$');
      askpassFile.writeAsStringSync('#!/bin/sh\necho "$escapedPass"\n');
      try {
        await Process.run('chmod', ['700', askpassPath]);
      } catch (_) {}
    }

    // 4. Khởi chạy tiến trình OpenSSH CLI
    final environment = Map<String, String>.from(Platform.environment);
    environment['SSH_ASKPASS'] = askpassPath;
    environment['SSH_ASKPASS_REQUIRE'] = 'force';
    if (!environment.containsKey('DISPLAY') || environment['DISPLAY']!.isEmpty) {
      environment['DISPLAY'] = ':0';
    }

    final List<String> forwardArgs;
    if (useRemoteSocks) {
      forwardArgs = ['-L', '127.0.0.1:$localPort:127.0.0.1:$remoteSocksPort'];
    } else {
      forwardArgs = ['-D', '127.0.0.1:$localPort'];
    }

    final sshArgs = [
      '-N',
      ...forwardArgs,
      '-p',
      server.sshPort.toString(),
      '-o',
      'StrictHostKeyChecking=no',
      '-o',
      'UserKnownHostsFile=/dev/null',
      '-o',
      'ExitOnForwardFailure=yes',
      '-o',
      'ServerAliveInterval=15',
      '-o',
      'ServerAliveCountMax=3',
      '${server.sshUser}@$sshHost',
    ];

    Process? sshProcess;
    try {
      sshProcess = await Process.start(
        'ssh',
        sshArgs,
        environment: environment,
        mode: ProcessStartMode.normal,
      );

      sshProcess.exitCode.then((code) {
        if (askpassFile.existsSync()) {
          try {
            askpassFile.deleteSync();
          } catch (_) {}
        }
        _activeSessions.remove(ip);
        notifyListeners();
      });
    } catch (_) {}

    // 5. Chờ socket SOCKS5 sẵn sàng chấp nhận kết nối
    bool ready = false;
    for (int i = 0; i < 40; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
      try {
        final testSock = await Socket.connect('127.0.0.1', localPort, timeout: const Duration(milliseconds: 300));
        await testSock.close();
        ready = true;
        break;
      } catch (_) {}
    }

    if (!ready) {
      try {
        sshProcess?.kill(ProcessSignal.sigterm);
      } catch (_) {}
      if (askpassFile.existsSync()) {
        try {
          askpassFile.deleteSync();
        } catch (_) {}
      }
      throw Exception('Không thể khởi tạo đường hầm SOCKS5 tới máy chủ $sshHost:${server.sshPort}. Vui lòng kiểm tra lại kết nối mạng và mật khẩu SSH.');
    }

    final session = Socks5Session(
      localPort: localPort,
      server: server,
      ip: ip,
      sshProcess: sshProcess,
      askpassFile: askpassFile,
    );

    _activeSessions[ip] = session;
    notifyListeners();
    return session;
  }

  /// Lấy đường dẫn binary của trình duyệt mặc định trên Linux thông qua xdg
  String? _getDefaultLinuxBrowser() {
    try {
      var desktopFile = '';
      final res = Process.runSync('xdg-settings', ['get', 'default-web-browser']);
      if (res.exitCode == 0 && res.stdout != null) {
        desktopFile = res.stdout.toString().trim();
      }
      if (desktopFile.isEmpty) {
        final resMime = Process.runSync('xdg-mime', ['query', 'default', 'x-scheme-handler/http']);
        if (resMime.exitCode == 0 && resMime.stdout != null) {
          desktopFile = resMime.stdout.toString().trim();
        }
      }

      if (desktopFile.isNotEmpty) {
        final home = Platform.environment['HOME'] ?? '';
        final searchDirs = [
          if (home.isNotEmpty) '$home/.local/share/applications',
          '/usr/share/applications',
          '/usr/local/share/applications',
          '/var/lib/snapd/desktop/applications',
        ];

        for (final dir in searchDirs) {
          final file = File('$dir/$desktopFile');
          if (file.existsSync()) {
            final lines = file.readAsLinesSync();
            for (final line in lines) {
              final trimmed = line.trim();
              if (trimmed.startsWith('Exec=')) {
                var execPart = trimmed.substring(5).trim();
                // Bỏ qua các cờ thay thế định dạng %U, %u, %F, %f
                execPart = execPart.replaceAll(RegExp(r'%[a-zA-Z]'), '').trim();
                final parts = execPart.split(' ');
                final bin = parts.isNotEmpty ? parts.first : '';
                if (bin.isNotEmpty) {
                  if (bin.startsWith('/')) {
                    if (File(bin).existsSync()) return bin;
                  } else {
                    final whichRes = Process.runSync('which', [bin]);
                    if (whichRes.exitCode == 0 && whichRes.stdout != null) {
                      final path = whichRes.stdout.toString().trim();
                      if (path.isNotEmpty && File(path).existsSync()) return path;
                    }
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Lấy binary trình duyệt mặc định trên Windows thông qua Registry
  String? _getDefaultWindowsBrowser() {
    try {
      final res = Process.runSync('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice',
        '/v',
        'ProgId',
      ]);
      if (res.exitCode == 0 && res.stdout != null) {
        final out = res.stdout.toString();
        final match = RegExp(r'ProgId\s+REG_SZ\s+(\S+)').firstMatch(out);
        if (match != null) {
          final progId = match.group(1)?.toLowerCase() ?? '';
          final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
          final programFiles = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
          final programFilesX86 = Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';

          if (progId.contains('chrome')) {
            final candidates = [
              '$programFiles\\Google\\Chrome\\Application\\chrome.exe',
              '$programFilesX86\\Google\\Chrome\\Application\\chrome.exe',
              if (localAppData.isNotEmpty) '$localAppData\\Google\\Chrome\\Application\\chrome.exe',
            ];
            for (final c in candidates) {
              if (File(c).existsSync()) return c;
            }
          } else if (progId.contains('edge') || progId.contains('msedge') || progId.contains('appx')) {
            final candidates = [
              '$programFiles (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
              '$programFiles\\Microsoft\\Edge\\Application\\msedge.exe',
              '$programFilesX86\\Microsoft\\Edge\\Application\\msedge.exe',
            ];
            for (final c in candidates) {
              if (File(c).existsSync()) return c;
            }
          } else if (progId.contains('brave')) {
            final candidates = [
              '$programFiles\\BraveSoftware\\Brave-Browser\\Application\\brave.exe',
              '$programFilesX86\\BraveSoftware\\Brave-Browser\\Application\\brave.exe',
              if (localAppData.isNotEmpty) '$localAppData\\BraveSoftware\\Brave-Browser\\Application\\brave.exe',
            ];
            for (final c in candidates) {
              if (File(c).existsSync()) return c;
            }
          } else if (progId.contains('firefox')) {
            final candidates = [
              '$programFiles\\Mozilla Firefox\\firefox.exe',
              '$programFilesX86\\Mozilla Firefox\\firefox.exe',
            ];
            for (final c in candidates) {
              if (File(c).existsSync()) return c;
            }
          } else if (progId.contains('opera')) {
            final candidates = [
              if (localAppData.isNotEmpty) '$localAppData\\Programs\\Opera GX\\opera.exe',
              if (localAppData.isNotEmpty) '$localAppData\\Programs\\Opera\\opera.exe',
              '$programFiles\\Opera\\launcher.exe',
            ];
            for (final c in candidates) {
              if (File(c).existsSync()) return c;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Lấy binary trình duyệt khả dụng trên macOS
  String? _findMacBrowserExecutable() {
    // Ưu tiên đọc trình duyệt mặc định trên macOS nếu có cấu hình qua LaunchServices / defaults
    try {
      final res = Process.runSync('defaults', [
        'read',
        'com.apple.LaunchServices/com.apple.launchservices.secure',
        'LSHandlers',
      ]);
      if (res.exitCode == 0 && res.stdout != null) {
        final out = res.stdout.toString().toLowerCase();
        if (out.contains('google.chrome')) {
          const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
          if (File(chrome).existsSync()) return chrome;
        } else if (out.contains('brave')) {
          const brave = '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser';
          if (File(brave).existsSync()) return brave;
        } else if (out.contains('edge')) {
          const edge = '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge';
          if (File(edge).existsSync()) return edge;
        } else if (out.contains('firefox')) {
          const ff = '/Applications/Firefox.app/Contents/MacOS/firefox';
          if (File(ff).existsSync()) return ff;
        }
      }
    } catch (_) {}

    final home = Platform.environment['HOME'] ?? '';
    final macCandidates = [
      // Google Chrome
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      if (home.isNotEmpty) '$home/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',

      // Microsoft Edge
      '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
      if (home.isNotEmpty) '$home/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',

      // Brave Browser
      '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
      if (home.isNotEmpty) '$home/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',

      // Opera & Opera GX
      '/Applications/Opera GX.app/Contents/MacOS/Opera GX',
      '/Applications/Opera.app/Contents/MacOS/Opera',

      // Cốc Cốc
      '/Applications/CocCoc.app/Contents/MacOS/CocCoc',

      // Chromium
      '/Applications/Chromium.app/Contents/MacOS/Chromium',

      // Mozilla Firefox
      '/Applications/Firefox.app/Contents/MacOS/firefox',
      if (home.isNotEmpty) '$home/Applications/Firefox.app/Contents/MacOS/firefox',
    ];

    for (final b in macCandidates) {
      if (File(b).existsSync()) {
        return b;
      }
    }
    return null;
  }

  /// Tìm binary trình duyệt khả dụng trên hệ thống Windows, macOS hoặc Linux.
  /// Tự động ưu tiên trình duyệt mặc định được thiết lập của hệ điều hành.
  String? findBrowserExecutable() {
    if (Platform.isMacOS) {
      return _findMacBrowserExecutable();
    }

    if (Platform.isWindows) {
      final defaultWinBrowser = _getDefaultWindowsBrowser();
      if (defaultWinBrowser != null && File(defaultWinBrowser).existsSync()) {
        return defaultWinBrowser;
      }

      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      final programFiles = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      final programFilesX86 = Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';

      final windowsCandidates = [
        // Google Chrome
        '$programFiles\\Google\\Chrome\\Application\\chrome.exe',
        '$programFilesX86\\Google\\Chrome\\Application\\chrome.exe',
        if (localAppData.isNotEmpty) '$localAppData\\Google\\Chrome\\Application\\chrome.exe',

        // Microsoft Edge (luôn có sẵn 100% trên Windows 10/11)
        '$programFiles (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
        '$programFiles\\Microsoft\\Edge\\Application\\msedge.exe',
        '$programFilesX86\\Microsoft\\Edge\\Application\\msedge.exe',

        // Brave Browser
        '$programFiles\\BraveSoftware\\Brave-Browser\\Application\\brave.exe',
        '$programFilesX86\\BraveSoftware\\Brave-Browser\\Application\\brave.exe',
        if (localAppData.isNotEmpty) '$localAppData\\BraveSoftware\\Brave-Browser\\Application\\brave.exe',

        // Opera & Opera GX
        if (localAppData.isNotEmpty) '$localAppData\\Programs\\Opera GX\\opera.exe',
        if (localAppData.isNotEmpty) '$localAppData\\Programs\\Opera\\opera.exe',
        '$programFiles\\Opera\\launcher.exe',

        // Cốc Cốc
        if (localAppData.isNotEmpty) '$localAppData\\CocCoc\\Browser\\Application\\browser.exe',
        '$programFiles\\CocCoc\\Browser\\Application\\browser.exe',
        '$programFilesX86\\CocCoc\\Browser\\Application\\browser.exe',

        // Mozilla Firefox
        '$programFiles\\Mozilla Firefox\\firefox.exe',
        '$programFilesX86\\Mozilla Firefox\\firefox.exe',
      ];

      for (final b in windowsCandidates) {
        if (File(b).existsSync()) {
          return b;
        }
      }
      return null;
    }

    // Trên Linux: Ưu tiên phát hiện trình duyệt mặc định qua xdg
    final defaultLinuxBrowser = _getDefaultLinuxBrowser();
    if (defaultLinuxBrowser != null && File(defaultLinuxBrowser).existsSync()) {
      return defaultLinuxBrowser;
    }

    final browserCandidates = [
      '/usr/bin/google-chrome',
      '/usr/bin/google-chrome-stable',
      '/usr/bin/opera-gx',
      '/usr/bin/opera',
      '/usr/bin/chromium',
      '/usr/bin/chromium-browser',
      '/usr/bin/brave-browser',
      '/snap/bin/firefox',
      '/usr/bin/firefox',
    ];

    for (final b in browserCandidates) {
      if (File(b).existsSync()) {
        return b;
      }
    }
    return null;
  }

  /// Lấy thư mục gốc lưu trữ browser profiles đa nền tảng
  Directory getBrowserProfilesDirectory() {
    final homeDir = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Directory.systemTemp.path;
    return Directory('$homeDir/.agent_mxh_auto/browser_profiles');
  }

  /// Mở trình duyệt độc lập cho Persona IP (có proxy socks5 nếu có Server, hoặc mở local trực tiếp)
  Future<bool> launchPersonaBrowser({
    required String ip,
    ServerModel? server,
    String? startUrl,
  }) async {
    // Nếu trình duyệt của nhân vật này đang chạy sẵn rồi thì không mở thêm cửa sổ trùng lặp nữa
    if (isBrowserRunningForIp(ip)) {
      debugPrint('[Browser] Trình duyệt cho IP $ip đang hoạt động, bỏ qua không mở thêm phiên trùng lặp.');
      return true;
    }

    final executable = findBrowserExecutable();
    if (executable == null) {
      throw Exception('Không tìm thấy trình duyệt khả dụng (Chrome, Edge, Opera, Brave, Firefox) trên hệ thống local.');
    }

    // Đường dẫn thư mục dữ liệu riêng cho từng IP để cô lập profile không ảnh hưởng trình duyệt gốc
    final sanitizedIp = ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final profileDir = Directory('${getBrowserProfilesDirectory().path}/ip_$sanitizedIp');
    if (!profileDir.existsSync()) {
      profileDir.createSync(recursive: true);
    }

    // Cấu hình ngôn ngữ tiếng Việt và tắt translate trong file Preferences của profile
    try {
      final defaultDir = Directory('${profileDir.path}/Default');
      if (!defaultDir.existsSync()) {
        defaultDir.createSync(recursive: true);
      }
      final prefFile = File('${defaultDir.path}/Preferences');
      Map<String, dynamic> prefData = {};
      if (prefFile.existsSync()) {
        try {
          final content = prefFile.readAsStringSync();
          if (content.trim().isNotEmpty) {
            final decoded = jsonDecode(content);
            if (decoded is Map<String, dynamic>) {
              prefData = decoded;
            }
          }
        } catch (_) {}
      }
      prefData['translate'] = {'enabled': false};
      prefData['translate_blocked_hosts'] = [];
      prefData['intl'] = {
        'selected_languages': 'vi-VN,vi,en-US,en',
        'accept_languages': 'vi-VN,vi,en-US,en',
      };
      prefFile.writeAsStringSync(jsonEncode(prefData));
    } catch (_) {}

    // Cấu hình Local State của Chrome cho profile (ép app_locale = vi)
    try {
      final localStateFile = File('${profileDir.path}/Local State');
      Map<String, dynamic> localStateData = {};
      if (localStateFile.existsSync()) {
        try {
          final content = localStateFile.readAsStringSync();
          if (content.trim().isNotEmpty) {
            final decoded = jsonDecode(content);
            if (decoded is Map<String, dynamic>) {
              localStateData = decoded;
            }
          }
        } catch (_) {}
      }
      localStateData['intl'] = {'app_locale': 'vi'};
      localStateFile.writeAsStringSync(jsonEncode(localStateData));
    } catch (_) {}

    // Ép buộc Facebook sử dụng giao diện Tiếng Việt bằng cách tiêm cookie locale=vi_VN vào profile
    _ensureFacebookVietnameseCookie(profileDir.path);

    // Xử lý URL khởi chạy: nếu mở Facebook thì ưu tiên kèm locale=vi_VN
    var targetUrl = (startUrl != null && startUrl.isNotEmpty) ? startUrl : 'https://type.vn';
    if (targetUrl.contains('facebook.com')) {
      if (!targetUrl.contains('locale=') && !targetUrl.contains('set_token=')) {
        final sep = targetUrl.contains('?') ? '&' : '?';
        targetUrl = '$targetUrl${sep}locale=vi_VN';
      }
    }

    // Thử kết nối SOCKS5 nếu có server được chỉ định (ngoại trừ 127.0.0.1 / localhost là mạng trực tiếp của máy tính)
    String? socks5Proxy;
    Socks5Session? session;
    final isLocalDirect = ip == '127.0.0.1' || ip == 'localhost';
    if (server != null && !isLocalDirect) {
      try {
        session = await startSocks5Server(server: server, ip: ip);
        socks5Proxy = 'socks5://127.0.0.1:${session.localPort}';
      } catch (_) {
        // Fallback: Nếu kết nối SSH server lỗi thì vẫn cho phép mở local browser
      }
    }

    // Dọn dẹp triệt để các lock file Singleton và tiến trình cũ của profile này nếu bị crash trước đó
    try {
      if (profileDir.existsSync()) {
        for (final entity in profileDir.listSync(followLinks: false)) {
          final baseName = entity.path.split(Platform.isWindows ? r'\' : '/').last;
          if (baseName.startsWith('Singleton')) {
            try {
              final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
              if (type == FileSystemEntityType.link) {
                Link(entity.path).deleteSync();
              } else if (type == FileSystemEntityType.file) {
                File(entity.path).deleteSync();
              } else if (type == FileSystemEntityType.directory) {
                Directory(entity.path).deleteSync(recursive: true);
              }
            } catch (_) {
              try {
                entity.deleteSync(recursive: true);
              } catch (_) {}
            }
          }
        }
        for (final lockName in ['SingletonLock', 'SingletonSocket', 'SingletonCookie']) {
          try {
            final f = File('${profileDir.path}/$lockName');
            if (f.existsSync()) f.deleteSync();
          } catch (_) {}
          try {
            final l = Link('${profileDir.path}/$lockName');
            if (l.existsSync()) l.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}

    final isFirefox = executable.toLowerCase().contains('firefox');
    List<String> args;
    if (isFirefox) {
      args = [
        '-new-tab',
        targetUrl,
      ];
    } else {
      final extDir = '${profileDir.path}/vietnamese_meta_ext';
      final currentExeDir = File(Platform.resolvedExecutable).parent.path;
      final candidatesCaptcha = [
        '${Directory.current.path}/extensions/tiktok_captcha_solver',
        '$currentExeDir/extensions/tiktok_captcha_solver',
        '$currentExeDir/data/flutter_assets/extensions/tiktok_captcha_solver',
        '/home/yenai/Documents/Projects/Typing/apps/plugins/agent-mxh-auto/extensions/tiktok_captcha_solver',
      ];
      final List<String> loadedExtensions = [];
      if (Directory(extDir).existsSync()) {
        loadedExtensions.add(extDir);
      }
      for (final capDir in candidatesCaptcha) {
        if (Directory(capDir).existsSync()) {
          loadedExtensions.add(capDir);
          break;
        }
      }

      args = [
        '--lang=vi',
        '--accept-lang=vi-VN,vi,en-US,en',
        '--test-type',
        '--disable-features=Translate,TranslateUI',
        '--disable-translate',
        // Chỉ thêm ozone platform x11 trên Linux để tránh xung đột Wayland NVIDIA
        if (Platform.isLinux) '--ozone-platform=x11',
        if (socks5Proxy != null) '--proxy-server=$socks5Proxy',
        '--user-data-dir=${profileDir.path}',
        if (loadedExtensions.isNotEmpty) '--load-extension=${loadedExtensions.join(',')}',
        '--no-first-run',
        '--no-default-browser-check',
        '--ignore-certificate-errors',
        '--disable-blink-features=AutomationControlled',
        targetUrl,
      ];
    }

    // Thiết lập biến môi trường
    Map<String, String>? browserEnv;
    if (Platform.isLinux) {
      browserEnv = <String, String>{};
      Platform.environment.forEach((k, v) {
        if (!k.startsWith('SNAP') &&
            k != 'GTK_MODULES' &&
            k != 'GIO_MODULE_DIR' &&
            k != 'GIO_LAUNCHED_DESKTOP_FILE' &&
            k != 'GIO_LAUNCHED_DESKTOP_FILE_PID' &&
            k != 'XDG_ACTIVATION_TOKEN') {
          browserEnv![k] = v;
        }
      });

      if (!browserEnv.containsKey('DISPLAY') || browserEnv['DISPLAY']!.isEmpty) {
        browserEnv['DISPLAY'] = ':0';
      }
      browserEnv.remove('WAYLAND_DISPLAY');
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        browserEnv['HOME'] = home;
      }
      browserEnv['LANG'] = 'vi_VN.UTF-8';
      browserEnv['LANGUAGE'] = 'vi_VN:vi';
      browserEnv['LC_ALL'] = 'vi_VN.UTF-8';
    }

    try {
      Process? proc;
      final hasSystemdRun = Platform.isLinux && File('/usr/bin/systemd-run').existsSync();
      if (hasSystemdRun) {
        final unitName = 'agy-browser-$sanitizedIp-${DateTime.now().millisecondsSinceEpoch}';
        final systemdArgs = [
          '--user',
          '--unit=$unitName',
          executable,
          ...args,
        ];
        await Process.run(
          '/usr/bin/systemd-run',
          systemdArgs,
          environment: browserEnv,
          includeParentEnvironment: false,
        );
      } else {
        proc = await Process.start(
          executable,
          args,
          environment: browserEnv,
          includeParentEnvironment: browserEnv == null,
          mode: ProcessStartMode.detached,
        );
      }

      if (session != null) {
        session.browserProcess = proc;
        session.browserLaunchedAt = DateTime.now();
      } else {
        // Lưu lại session cục bộ không SSH để theo dõi trạng thái tiến trình
        final localSession = _activeSessions[ip] ?? Socks5Session(
          localPort: 0,
          server: server,
          ip: ip,
          sshProcess: null,
          askpassFile: null,
        );
        localSession.browserProcess = proc;
        localSession.browserLaunchedAt = DateTime.now();
        _activeSessions[ip] = localSession;
      }

      notifyListeners();
      return true;
    } catch (e) {
      throw Exception('Lỗi khi mở trình duyệt: $e');
    }
  }

  /// Tiêm cookie locale=vi_VN vào database Cookies của Chrome và tạo extension ép tiếng Việt
  void _ensureFacebookVietnameseCookie(String profilePath) {
    try {
      // 1. Tạo Extension declarativeNetRequest ép Accept-Language tiếng Việt cho toàn bộ request tới Meta/Facebook
      final extDir = Directory('$profilePath/vietnamese_meta_ext');
      if (!extDir.existsSync()) {
        extDir.createSync(recursive: true);
      }
      final manifestFile = File('${extDir.path}/manifest.json');
      final rulesFile = File('${extDir.path}/rules.json');
      if (!manifestFile.existsSync() || !rulesFile.existsSync()) {
        manifestFile.writeAsStringSync(jsonEncode({
          'manifest_version': 3,
          'name': 'Force Vietnamese Meta',
          'version': '1.0',
          'description': 'Forces Facebook and Meta to use Vietnamese interface',
          'permissions': ['declarativeNetRequest'],
          'host_permissions': ['*://*.facebook.com/*', '*://*.fb.com/*', '*://*.messenger.com/*'],
          'declarative_net_request': {
            'rule_resources': [
              {
                'id': 'ruleset_1',
                'enabled': true,
                'path': 'rules.json',
              }
            ]
          }
        }));
        rulesFile.writeAsStringSync(jsonEncode([
          {
            'id': 1,
            'priority': 1,
            'action': {
              'type': 'modifyHeaders',
              'requestHeaders': [
                {
                  'header': 'Accept-Language',
                  'operation': 'set',
                  'value': 'vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7',
                }
              ]
            },
            'condition': {
              'urlFilter': '*facebook.com*',
              'resourceTypes': ['main_frame', 'sub_frame', 'stylesheet', 'script', 'image', 'xmlhttprequest', 'other'],
            }
          }
        ]));
      }

      // 2. Tiêm cookie locale=vi_VN vào SQLite Cookies của profile
      final cookieFile = File('$profilePath/Default/Cookies');
      if (!cookieFile.existsSync()) return;

      final pyScript = '''
import sqlite3, time
CHROME_EPOCH_DIFF = 11644473600
def to_chrome_time(ts):
    return int((ts + CHROME_EPOCH_DIFF) * 1000000)

now = time.time()
now_chrome = to_chrome_time(now)
expire_chrome = to_chrome_time(now + 365 * 24 * 3600)

try:
    con = sqlite3.connect(r"${cookieFile.path}")
    cur = con.cursor()
    cur.execute("DELETE FROM cookies WHERE host_key LIKE '%facebook.com%' AND name = 'locale'")
    for host in ['.facebook.com', 'facebook.com', 'www.facebook.com', 'm.facebook.com']:
        cur.execute("""
            INSERT OR REPLACE INTO cookies 
            (creation_utc, host_key, top_frame_site_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent, priority, samesite, source_scheme, source_port, last_update_utc, source_type, has_cross_site_ancestor)
            VALUES (?, ?, '', 'locale', 'vi_VN', X'', '/', ?, 1, 0, ?, 1, 1, 1, -1, 2, 443, ?, 1, 0)
        """, (now_chrome, host, expire_chrome, now_chrome, now_chrome))
    con.commit()
    con.close()
except Exception:
    pass
''';
      Process.runSync('python3', ['-c', pyScript]);
    } catch (_) {}
  }

  /// Mở trình duyệt trên máy local với cấu hình SOCKS5 trỏ qua SSH Server
  Future<bool> launchBrowserWithSocks5({
    required ServerModel server,
    required String ip,
    String? startUrl,
  }) async {
    return launchPersonaBrowser(ip: ip, server: server, startUrl: startUrl);
  }

  /// Thư mục chứa cấu hình và dữ liệu máy ảo Android AVD của người dùng
  Directory getAndroidAvdDirectory() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return Directory(p.join(home, '.android', 'avd'));
  }

  /// Tìm binary Android Emulator trên hệ thống (hỗ trợ Linux, macOS, Windows)
  String? _findAndroidEmulatorExecutable() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    final exeExt = Platform.isWindows ? '.exe' : '';
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';

    final candidates = [
      if (Platform.isWindows && localAppData.isNotEmpty)
        p.join(localAppData, 'Android', 'Sdk', 'emulator', 'emulator.exe'),
      p.join(home, 'AppData', 'Local', 'Android', 'Sdk', 'emulator', 'emulator.exe'),
      p.join(home, 'Android', 'Sdk', 'emulator', 'emulator$exeExt'),
      p.join(home, 'android-sdk', 'emulator', 'emulator$exeExt'),
      '/opt/android-sdk/emulator/emulator',
      if (Platform.isWindows) 'C:\\Android\\Sdk\\emulator\\emulator.exe',
      if (Platform.isWindows) 'D:\\Android\\Sdk\\emulator\\emulator.exe',
      '/usr/bin/emulator',
      '/usr/local/bin/emulator',
      p.join(home, '.android-sdk', 'emulator', 'emulator$exeExt'),
      p.join(home, '.agent_mxh_auto', 'android_sdk', 'emulator', 'emulator$exeExt'),
      p.join(home, '.agent_mxh_auto', 'emulator', 'emulator$exeExt'),
      p.join(home, '.tadu_ai_agent', 'emulator', 'emulator$exeExt'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) {
        return c;
      }
    }
    return null;
  }

  /// Tìm hoặc tự động tải Android Emulator binary nếu máy chưa cài
  Future<String?> resolveAndroidEmulatorExecutable({Function(double progress, String status)? onProgress}) async {
    final existing = _findAndroidEmulatorExecutable();
    if (existing != null) {
      return existing;
    }
    return await EmulatorManagerService().ensureEmulatorInstalled(onProgress: onProgress);
  }

  /// Tìm danh sách AVD khả dụng trên máy tính
  /// Quét đồng thời từ CLI emulator và quét trực tiếp file .ini trong thư mục ~/.android/avd/
  Future<List<String>> getAvailableAvds() async {
    final avds = <String>{};

    // 1. Quét trực tiếp thư mục ~/.android/avd/ (hoạt động 100% ngay cả khi chưa có Emulator CLI)
    try {
      final avdsDir = getAndroidAvdDirectory();
      if (avdsDir.existsSync()) {
        for (final entity in avdsDir.listSync()) {
          final fileName = p.basename(entity.path);
          if (fileName.endsWith('.ini')) {
            final avdName = fileName.substring(0, fileName.length - 4);
            // Kiểm tra thư mục .avd tương ứng có tồn tại không
            final dataDir = Directory(p.join(avdsDir.path, '$avdName.avd'));
            if (dataDir.existsSync()) {
              avds.add(avdName);
            }
          }
        }
      }
    } catch (_) {}

    // 2. Bổ sung thêm từ emulator -list-avds nếu có binary emulator
    final emulatorBin = _findAndroidEmulatorExecutable();
    if (emulatorBin != null) {
      try {
        final res = await Process.run(emulatorBin, ['-list-avds']);
        if (res.exitCode == 0) {
          final lines = (res.stdout as String).split('\n');
          for (final l in lines) {
            final clean = l.trim();
            if (clean.isNotEmpty) {
              avds.add(clean);
            }
          }
        }
      } catch (_) {}
    }

    final result = avds.toList();
    result.sort();
    return result;
  }

  /// Tìm binary qemu-img đi kèm SDK Emulator
  String? _findQemuImgExecutable() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    final exeExt = Platform.isWindows ? '.exe' : '';
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';

    final candidates = [
      if (Platform.isWindows && localAppData.isNotEmpty)
        p.join(localAppData, 'Android', 'Sdk', 'emulator', 'qemu-img.exe'),
      p.join(home, 'AppData', 'Local', 'Android', 'Sdk', 'emulator', 'qemu-img.exe'),
      p.join(home, 'Android', 'Sdk', 'emulator', 'qemu-img$exeExt'),
      p.join(home, 'android-sdk', 'emulator', 'qemu-img$exeExt'),
      '/opt/android-sdk/emulator/qemu-img',
      if (Platform.isWindows) 'C:\\Android\\Sdk\\emulator\\qemu-img.exe',
      if (Platform.isWindows) 'D:\\Android\\Sdk\\emulator\\qemu-img.exe',
      '/usr/bin/qemu-img',
      '/usr/local/bin/qemu-img',
      p.join(home, '.android-sdk', 'emulator', 'qemu-img$exeExt'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) {
        return c;
      }
    }
    return null;
  }

  /// Kiểm tra xem nhân vật theo IP đã có thiết bị (AVD clone hoặc địa chỉ ngoại vi) hay chưa
  Future<bool> hasDeviceForPersona({
    required String ip,
    String? personaName,
    String? avdName,
    bool useExternalDevice = false,
    String? externalDeviceAddress,
  }) async {
    // 1. Nếu cấu hình dùng thiết bị ngoại vi, kiểm tra địa chỉ IP:Port có hợp lệ không
    if (useExternalDevice) {
      return externalDeviceAddress != null && externalDeviceAddress.trim().isNotEmpty;
    }

    // 2. Kiểm tra AVD trên máy local:
    final avdsDir = getAndroidAvdDirectory();
    if (!avdsDir.existsSync()) return false;

    final sanitizedIp = ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final expectedPersonaAvd = generatePersonaAvdName(ip: ip, personaName: personaName);

    // Quét xem có file .ini của persona hoặc clone của IP này hoặc theo tên nhân vật không
    try {
      final entities = avdsDir.listSync();
      for (final e in entities) {
        final name = p.basename(e.path);
        if (name.endsWith('.ini')) {
          final iniName = name.substring(0, name.length - 4);
          if (iniName == expectedPersonaAvd || iniName.contains('persona_$sanitizedIp')) {
            // Kiểm tra thư mục .avd tương ứng có tồn tại không
            final avdFolder = Directory(p.join(avdsDir.path, '$iniName.avd'));
            if (avdFolder.existsSync()) return true;
          }
        }
      }
    } catch (_) {}

    // Nếu nhân vật chỉ định đích danh avdName và avdName đó tồn tại
    if (avdName != null && avdName.trim().isNotEmpty) {
      final specificIni = File(p.join(avdsDir.path, '${avdName.trim()}.ini'));
      final specificDir = Directory(p.join(avdsDir.path, '${avdName.trim()}.avd'));
      if (specificIni.existsSync() && specificDir.existsSync()) {
        return true;
      }
    }

    return false;
  }

  /// Import thiết bị từ file backup (.tar.gz hoặc .zip) cho nhân vật theo IP và tên nhân vật
  Future<String> importPersonaDeviceBackup({
    required String ip,
    String? personaName,
    required String archivePath,
  }) async {
    final file = File(archivePath);
    if (!file.existsSync()) {
      throw Exception('File backup không tồn tại: $archivePath');
    }

    final avdsDir = getAndroidAvdDirectory();
    if (!avdsDir.existsSync()) {
      avdsDir.createSync(recursive: true);
    }

    final targetAvdName = generatePersonaAvdName(ip: ip, personaName: personaName);
    final targetAvdDir = Directory(p.join(avdsDir.path, '$targetAvdName.avd'));
    final targetIniFile = File(p.join(avdsDir.path, '$targetAvdName.ini'));

    // 1. Tạo thư mục tạm trực tiếp trong ~/.android/avd/
    final tempExtractDir = Directory(p.join(avdsDir.path, '.import_temp_${DateTime.now().millisecondsSinceEpoch}'));
    tempExtractDir.createSync(recursive: true);

    try {
      // 2. Giải nén file backup: hỗ trợ cả tar, tar.gz, tgz, zip trên cả Windows và Linux
      bool extractSuccess = false;
      String? extractErr;

      final lowerPath = archivePath.toLowerCase();
      if (lowerPath.endsWith('.tar.gz') || lowerPath.endsWith('.tgz') || lowerPath.endsWith('.tar')) {
        // Thử giải nén bằng tar (Windows 10/11 và Linux đều có sẵn tar)
        try {
          final tarFlags = (lowerPath.endsWith('.tar.gz') || lowerPath.endsWith('.tgz')) ? '-zxf' : '-xf';
          final res = await Process.run('tar', [tarFlags, archivePath, '-C', tempExtractDir.path]);
          if (res.exitCode == 0) {
            extractSuccess = true;
          } else {
            extractErr = res.stderr?.toString();
          }
        } catch (e) {
          extractErr = e.toString();
        }

        // Fallback thư viện archive thuần Dart nếu lệnh tar không thành công
        if (!extractSuccess) {
          try {
            final bytes = file.readAsBytesSync();
            final decompressed = (lowerPath.endsWith('.tar.gz') || lowerPath.endsWith('.tgz'))
                ? GZipDecoder().decodeBytes(bytes)
                : bytes;
            final archive = TarDecoder().decodeBytes(decompressed);
            for (final entry in archive) {
              final outPath = p.join(tempExtractDir.path, entry.name);
              if (entry.isFile) {
                final outFile = File(outPath);
                outFile.parent.createSync(recursive: true);
                outFile.writeAsBytesSync(entry.content as List<int>);
              } else {
                Directory(outPath).createSync(recursive: true);
              }
            }
            extractSuccess = true;
          } catch (e) {
            extractErr = 'Archive decode lỗi: $e';
          }
        }
      } else if (lowerPath.endsWith('.zip')) {
        // Giải nén file zip: thử unzip (Linux) hoặc tar (Windows tar hỗ trợ zip) hoặc PowerShell
        try {
          if (!Platform.isWindows) {
            final res = await Process.run('unzip', ['-o', archivePath, '-d', tempExtractDir.path]);
            if (res.exitCode == 0) extractSuccess = true;
          } else {
            final res = await Process.run('tar', ['-xf', archivePath, '-C', tempExtractDir.path]);
            if (res.exitCode == 0) extractSuccess = true;
          }
        } catch (_) {}

        // Fallback archive Dart thuần nếu chưa giải nén được
        if (!extractSuccess) {
          try {
            final bytes = file.readAsBytesSync();
            final archive = ZipDecoder().decodeBytes(bytes);
            for (final entry in archive) {
              final outPath = p.join(tempExtractDir.path, entry.name);
              if (entry.isFile) {
                final outFile = File(outPath);
                outFile.parent.createSync(recursive: true);
                outFile.writeAsBytesSync(entry.content as List<int>);
              } else {
                Directory(outPath).createSync(recursive: true);
              }
            }
            extractSuccess = true;
          } catch (e) {
            extractErr = e.toString();
          }
        }
      } else {
        throw Exception('Định dạng file không được hỗ trợ (chỉ hỗ trợ .tar.gz, .tgz, .tar, .zip)');
      }

      if (!extractSuccess) {
        throw Exception('Lỗi khi giải nén backup: $extractErr');
      }

      // 3. Quét tìm thư mục .avd trong dữ liệu giải nén
      Directory? extractedAvdDir;
      void scanDir(Directory dir) {
        for (final entity in dir.listSync()) {
          if (entity is Directory && entity.path.endsWith('.avd')) {
            extractedAvdDir = entity;
          }
        }
      }

      scanDir(tempExtractDir);
      if (extractedAvdDir == null) {
        for (final entity in tempExtractDir.listSync()) {
          if (entity is Directory) {
            scanDir(entity);
            if (extractedAvdDir != null) break;
          }
        }
      }

      if (extractedAvdDir == null) {
        throw Exception('Không tìm thấy thư mục dữ liệu .avd bên trong file backup.');
      }

      // 4. Xóa thư mục AVD cũ của persona nếu đã có, sau đó di chuyển thư mục vừa giải nén sang đích
      if (targetAvdDir.existsSync()) {
        try {
          targetAvdDir.deleteSync(recursive: true);
        } catch (_) {}
      }

      try {
        extractedAvdDir!.renameSync(targetAvdDir.path);
      } catch (_) {
        // Sao chép đệ quy bằng Dart thuần (hoạt động 100% không phụ thuộc lệnh cp)
        targetAvdDir.createSync(recursive: true);
        _copyDirectoryRecursiveSync(extractedAvdDir!, targetAvdDir);
      }

      // 5. Cập nhật hoặc tạo file .ini chuẩn chỉ đường dẫn path tới thư mục máy ảo vừa import
      targetIniFile.writeAsStringSync(
        'avd.ini.encoding=UTF-8\n'
        'path=${targetAvdDir.path}\n'
        'path.rel=avd/$targetAvdName.avd\n'
        'target=android-37.0\n',
      );

      // 6. Xử lý qemu-img rebase cho các file qcow2 (userdata, cache, encryptionkey)
      final qemuImgBin = _findQemuImgExecutable();
      if (qemuImgBin != null) {
        final qcowFiles = ['userdata-qemu.img.qcow2', 'cache.img.qcow2', 'encryptionkey.img.qcow2'];
        for (final qf in qcowFiles) {
          final file = File(p.join(targetAvdDir.path, qf));
          if (file.existsSync()) {
            final baseRaw = qf.replaceAll('.qcow2', '');
            final baseRawFile = File(p.join(targetAvdDir.path, baseRaw));
            if (baseRawFile.existsSync()) {
              try {
                await Process.run(qemuImgBin, [
                  'rebase',
                  '-u',
                  '-b',
                  baseRaw,
                  file.path,
                ]);
              } catch (_) {}
            }

            if (qf == 'userdata-qemu.img.qcow2') {
              try {
                await Process.run(qemuImgBin, [
                  'snapshot',
                  '-a',
                  'default_boot',
                  file.path,
                ]);
              } catch (_) {}
            }
          }
        }
      }

      // 7. Đồng bộ và sửa tên AVD trong toàn bộ file cấu hình text thuần bằng Dart
      try {
        _patchPersonaNameInAvdDir(targetAvdDir, targetAvdName);
      } catch (_) {}

      // 8. Nếu hệ thống có python3, hỗ trợ thêm vá file nhị phân .pb
      try {
        final pythonBin = Platform.isWindows ? 'python' : 'python3';
        final patchScript = '''
import os, re
target_avd = "$targetAvdName"
target_dir = r"${targetAvdDir.path}"
def encode_varint(val):
    out = []
    while val > 0x7f:
        out.append((val & 0x7f) | 0x80)
        val >>= 7
    out.append(val & 0x7f)
    return bytes(out)

def decode_varint(b, p):
    val = 0; shift = 0
    while True:
        byte = b[p]; p += 1
        val |= (byte & 0x7f) << shift
        shift += 7
        if not (byte & 0x80): break
    return val, p

persona_pattern = re.compile(rb'Pixel_10_Pro_persona_[a-zA-Z0-9_-]+')

def transform_bytes(b):
    p = 0
    res = bytearray()
    while p < len(b):
        key, p = decode_varint(b, p)
        wire = key & 0x7
        field = key >> 3
        if wire == 0:
            v, p = decode_varint(b, p)
            res.extend(encode_varint(key))
            res.extend(encode_varint(v))
        elif wire == 2:
            length, p = decode_varint(b, p)
            val = b[p:p+length]
            p += length
            if field == 3:
                new_val = transform_bytes(val)
            elif persona_pattern.search(val):
                new_val = persona_pattern.sub(target_avd.encode('utf-8'), val)
            else:
                new_val = val
            res.extend(encode_varint(key))
            res.extend(encode_varint(len(new_val)))
            res.extend(new_val)
        elif wire == 1:
            res.extend(encode_varint(key))
            res.extend(b[p:p+8])
            p += 8
        elif wire == 5:
            res.extend(encode_varint(key))
            res.extend(b[p:p+4])
            p += 4
        else:
            break
    return bytes(res)

for root, _, files in os.walk(target_dir):
    for fn in files:
        if fn.endswith(".pb"):
            pb_path = os.path.join(root, fn)
            try:
                with open(pb_path, "rb") as f:
                    data = f.read()
                new_data = transform_bytes(data)
                with open(pb_path, "wb") as f:
                    f.write(new_data)
            except Exception:
                pass
''';
        await Process.run(pythonBin, ['-c', patchScript]);
      } catch (_) {}

      // 9. Xóa các lock file và file trạng thái tạm thời cũ
      try {
        for (final f in targetAvdDir.listSync(recursive: true)) {
          if (f.path.endsWith('.lock') || f.path.endsWith('multiinstance.lock')) {
            try {
              f.deleteSync();
            } catch (_) {}
          }
        }
      } catch (_) {}

      notifyListeners();
      return targetAvdName;
    } finally {
      try {
        if (tempExtractDir.existsSync()) {
          tempExtractDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    }
  }

  /// Hàm hỗ trợ sao chép đệ quy thư mục bằng Dart thuần (chạy độc lập nền tảng)
  void _copyDirectoryRecursiveSync(Directory src, Directory dst) {
    if (!dst.existsSync()) {
      dst.createSync(recursive: true);
    }
    for (final entity in src.listSync(recursive: false)) {
      final newPath = p.join(dst.path, p.basename(entity.path));
      if (entity is Directory) {
        _copyDirectoryRecursiveSync(entity, Directory(newPath));
      } else if (entity is File) {
        entity.copySync(newPath);
      }
    }
  }

  /// Vá chuỗi tên AVD trong các file cấu hình text (.ini, AVD.conf, txt) bằng Dart thuần
  void _patchPersonaNameInAvdDir(Directory dir, String targetAvd) {
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (name.endsWith('.ini') || name == 'AVD.conf' || name == 'emu-launch-params.txt') {
          try {
            final content = entity.readAsStringSync();
            final updated = content.replaceAll(RegExp(r'Pixel_10_Pro_persona_[a-zA-Z0-9_-]+'), targetAvd);
            if (updated != content) {
              entity.writeAsStringSync(updated);
            }
          } catch (_) {}
        }
      }
    }
  }

  /// Backup thiết bị máy ảo AVD thành file nén .tar.gz lưu trữ vào thư mục đích
  Future<String> backupPersonaDeviceAvd({
    required String avdName,
    String? destinationPath,
    void Function(String message)? onProgress,
  }) async {
    final avdsDir = getAndroidAvdDirectory();
    final avdDir = Directory(p.join(avdsDir.path, '$avdName.avd'));
    final iniFile = File(p.join(avdsDir.path, '$avdName.ini'));

    if (!avdDir.existsSync()) {
      throw Exception('Thư mục máy ảo $avdName không tồn tại trên hệ thống.');
    }

    // 1. Đảm bảo thư mục lưu backup tồn tại (mặc định là ~/Documents/devices)
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    final resolvedDefaultDir = Directory(p.join(home, 'Documents', 'devices')).path;
    final backupDir = Directory(destinationPath ?? resolvedDefaultDir);
    if (!backupDir.existsSync()) {
      backupDir.createSync(recursive: true);
    }

    // 2. Nếu máy ảo đang mở chạy, đồng bộ dữ liệu vào đĩa và lưu snapshot default_boot chuẩn xác
    final runningPort = _findRunningConsolePortForAvd(avdName);
    if (runningPort != null) {
      onProgress?.call('Đang lưu trạng thái và ứng dụng máy ảo vào snapshot...');
      try {
        final adbBin = await _findAdbExecutable();
        await Process.run(adbBin, ['-s', 'emulator-$runningPort', 'shell', 'sync']);
      } catch (_) {}
      try {
        await _saveSnapshotViaConsole(runningPort, snapshotName: 'default_boot');
        // Đợi 1 giây để QEMU commit toàn bộ RAM và userdata-qemu.img.qcow2 xuống đĩa
        await Future.delayed(const Duration(milliseconds: 1000));
      } catch (_) {}
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '_');
    final targetTarFile = File(p.join(backupDir.path, '${avdName}_backup_$timestamp.tar.gz'));

    // 3. Dọn dẹp các file lock tạm thời trước khi đóng gói
    try {
      for (final f in avdDir.listSync(recursive: true)) {
        if (f.path.endsWith('.lock') || f.path.endsWith('multiinstance.lock')) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}

    onProgress?.call('Đang nén dữ liệu máy ảo $avdName...');

    // 4. Thực thi nén thư mục .avd và file .ini
    final args = [
      '-czf',
      targetTarFile.path,
      '--exclude=*.lock',
      '--exclude=multiinstance.lock',
      '--exclude=modem_simulator/*.sock',
      '--exclude=modem_simulator/modem_nvram.json',
      '-C',
      avdsDir.path,
      '$avdName.avd',
      if (iniFile.existsSync()) '$avdName.ini',
    ];

    final res = await Process.run('tar', args);
    if (res.exitCode != 0) {
      throw Exception('Lỗi khi nén backup máy ảo: ${res.stderr}');
    }

    notifyListeners();
    return targetTarFile.path;
  }

  /// Tạo thiết bị (AVD Clone) riêng biệt cho nhân vật theo IP và tên nhân vật
  Future<String> createPersonaDeviceAvd({
    required String ip,
    String? personaName,
    String? baseAvd,
    void Function(String message)? onProgress,
  }) async {
    final avdsDir = getAndroidAvdDirectory();
    String targetBase = baseAvd ?? '';

    if (targetBase.isEmpty || !Directory(p.join(avdsDir.path, '$targetBase.avd')).existsSync()) {
      final avds = await getAvailableAvds();
      if (avds.isEmpty) {
        throw Exception(
          'Máy tính chưa có máy ảo Android mẫu để nhân bản. '
          'Bạn vui lòng bấm nút "Import" bên cạnh để nạp file backup máy ảo có sẵn (.tar.gz, .zip), '
          'hoặc chuyển sang chế độ "Thiết bị ngoại vi (WiFi ADB)" để kết nối trực tiếp điện thoại thật.'
        );
      }
      // Ưu tiên chọn base AVD có sẵn snapshot default_boot và dung lượng userdata lớn nhất (đầy đủ app)
      String? bestCandidate;
      int maxScore = -1;

      for (final a in avds) {
        final dir = Directory(p.join(avdsDir.path, '$a.avd'));
        if (!dir.existsSync()) continue;
        int score = 0;
        final snapFile = File(p.join(dir.path, 'snapshots', 'default_boot', 'ram.bin'));
        if (snapFile.existsSync() && snapFile.lengthSync() > 1000000) {
          score += 100;
        }
        final qcowFile = File(p.join(dir.path, 'userdata-qemu.img.qcow2'));
        if (qcowFile.existsSync()) {
          score += (qcowFile.lengthSync() / (1024 * 1024 * 100)).toInt(); // cộng điểm theo dung lượng
        }
        if (score > maxScore) {
          maxScore = score;
          bestCandidate = a;
        }
      }

      targetBase = bestCandidate ?? avds.first;
    }

    final createdName = await _ensurePersonaCloneAvd(targetBase, ip, personaName: personaName, onProgress: onProgress);
    notifyListeners();
    return createdName;
  }

  /// Xóa thiết bị máy ảo AVD khỏi hệ thống (tự động đóng device trước khi xóa)
  Future<bool> deleteAvd(String avdName, {String? ip}) async {
    final sanitizedIp = ip != null ? ip.replaceAll(RegExp(r"[^a-zA-Z0-9_-]"), "_") : "";
    final dedicatedPersonaAvd = sanitizedIp.isNotEmpty ? "Pixel_10_Pro_persona_$sanitizedIp" : "";

    // 1. Đóng device nếu đang chạy liên kết với IP
    if (ip != null && ip.isNotEmpty) {
      try {
        await closeDeviceForIp(ip);
      } catch (_) {}
    }

    // 2. Dừng triệt để qua ADB emu kill đối với mọi instance emulator đang chạy AVD này
    try {
      final adbBin = await _findAdbExecutable();
      final devRes = await Process.run(adbBin, ["devices"]);
      final lines = (devRes.stdout as String).split("\n");
      for (final line in lines) {
        final parts = line.trim().split(RegExp(r"\s+"));
        if (parts.length >= 2 && parts[0].startsWith("emulator-") && parts[1] == "device") {
          final serial = parts[0];
          try {
            final emuNameRes = await Process.run(adbBin, ["-s", serial, "emu", "avd", "name"]);
            final runningAvd = (emuNameRes.stdout as String).trim().split("\n").first.trim();
            if (runningAvd == avdName || (dedicatedPersonaAvd.isNotEmpty && runningAvd == dedicatedPersonaAvd)) {
              await Process.run(adbBin, ["-s", serial, "emu", "kill"]);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 3. Quét và dừng mọi tiến trình emulator / qemu đang chạy gắn với avdName hoặc IP này
    try {
      if (!Platform.isWindows) {
        await Process.run("pkill", ["-f", avdName]);
        await Process.run("pkill", ["-9", "-f", avdName]);
        if (dedicatedPersonaAvd.isNotEmpty) {
          await Process.run("pkill", ["-f", dedicatedPersonaAvd]);
          await Process.run("pkill", ["-9", "-f", dedicatedPersonaAvd]);
        }
        if (sanitizedIp.isNotEmpty) {
          await Process.run("pkill", ["-f", "device_profiles/ip_$sanitizedIp"]);
          await Process.run("pkill", ["-9", "-f", "device_profiles/ip_$sanitizedIp"]);
        }
      } else {
        await Process.run("taskkill", ["/F", "/IM", "emulator.exe"]);
        await Process.run("taskkill", ["/F", "/IM", "qemu-system-x86_64.exe"]);
      }
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 500));

    final avdsDir = getAndroidAvdDirectory();
    bool deleted = false;

    // 5. Xóa AVD được chỉ định
    final avdDir = Directory(p.join(avdsDir.path, '$avdName.avd'));
    final iniFile = File(p.join(avdsDir.path, '$avdName.ini'));
    try {
      if (avdDir.existsSync()) {
        avdDir.deleteSync(recursive: true);
        deleted = true;
      }
    } catch (_) {}
    try {
      if (iniFile.existsSync()) {
        iniFile.deleteSync();
        deleted = true;
      }
    } catch (_) {}

    // 6. Xóa cả dedicated persona clone AVD nếu có
    if (dedicatedPersonaAvd.isNotEmpty && dedicatedPersonaAvd != avdName) {
      final pDir = Directory(p.join(avdsDir.path, '$dedicatedPersonaAvd.avd'));
      final pIni = File(p.join(avdsDir.path, '$dedicatedPersonaAvd.ini'));
      try {
        if (pDir.existsSync()) {
          pDir.deleteSync(recursive: true);
          deleted = true;
        }
      } catch (_) {}
      try {
        if (pIni.existsSync()) {
          pIni.deleteSync();
          deleted = true;
        }
      } catch (_) {}
    }

    notifyListeners();
    return deleted;
  }

  /// Tự động tạo hoặc kiểm tra AVD Clone riêng biệt cho từng IP nhân vật
  /// Sao chép toàn bộ userdata, cache, encryptionkey và snapshot từ baseAvd chuẩn nhất để máy ảo tạo mới khởi động được ngay với đầy đủ app
  Future<String> _ensurePersonaCloneAvd(
    String baseAvd,
    String ip, {
    String? personaName,
    void Function(String message)? onProgress,
  }) async {
    final avdsDir = getAndroidAvdDirectory();
    final cloneAvdName = generatePersonaAvdName(ip: ip, personaName: personaName);

    final baseAvdDir = Directory(p.join(avdsDir.path, '$baseAvd.avd'));
    final cloneAvdDir = Directory(p.join(avdsDir.path, '$cloneAvdName.avd'));
    final cloneIniFile = File(p.join(avdsDir.path, '$cloneAvdName.ini'));

    // 1. Tạo thư mục AVD clone nếu chưa có
    if (!cloneAvdDir.existsSync()) {
      cloneAvdDir.createSync(recursive: true);
    }

    // 2. Tạo hoặc ghi đè file .ini trong ~/.android/avd/
    cloneIniFile.writeAsStringSync(
      'avd.ini.encoding=UTF-8\n'
      'path=${cloneAvdDir.path}\n'
      'path.rel=avd/$cloneAvdName.avd\n'
      'target=android-37.0\n',
    );

    // 3. Sao chép các file cấu hình và dữ liệu nền tảng từ baseAvd sang cloneAvd
    if (baseAvdDir.existsSync()) {
      onProgress?.call('Đang sao chép file cấu hình hệ thống...');
      final configFiles = [
        'config.ini',
        'user-settings.ini',
        'emulator-user.ini',
        'netsim.ini',
        'AVD.conf',
        'qemu-version.txt',
        'version_num.cache',
        'userdata-qemu.img',
        'cache.img',
        'encryptionkey.img',
      ];
      for (final cfg in configFiles) {
        final src = File(p.join(baseAvdDir.path, cfg));
        final dst = File(p.join(cloneAvdDir.path, cfg));
        if (src.existsSync() && !dst.existsSync()) {
          try {
            src.copySync(dst.path);
          } catch (_) {}
        }
      }

      // Sao chép thư mục data và bootcompleted.ini nếu base có
      final baseDataDir = Directory(p.join(baseAvdDir.path, 'data'));
      final cloneDataDir = Directory(p.join(cloneAvdDir.path, 'data'));
      if (baseDataDir.existsSync() && !cloneDataDir.existsSync()) {
        try {
          _copyDirectoryRecursiveSync(baseDataDir, cloneDataDir);
        } catch (_) {}
      }
      final baseBootCompleted = File(p.join(baseAvdDir.path, 'bootcompleted.ini'));
      if (baseBootCompleted.existsSync()) {
        try {
          baseBootCompleted.copySync(p.join(cloneAvdDir.path, 'bootcompleted.ini'));
        } catch (_) {}
      }

      // 4. Sao chép và rebase các file QCOW2 (userdata, cache, encryptionkey)
      onProgress?.call('Đang thiết lập dữ liệu phân vùng và ứng dụng...');
      final qemuImgBin = _findQemuImgExecutable();
      final qcowFiles = ['userdata-qemu.img.qcow2', 'cache.img.qcow2', 'encryptionkey.img.qcow2'];

      for (final qf in qcowFiles) {
        final baseQcow = File(p.join(baseAvdDir.path, qf));
        final cloneQcow = File(p.join(cloneAvdDir.path, qf));
        if (baseQcow.existsSync() && !cloneQcow.existsSync()) {
          try {
            baseQcow.copySync(cloneQcow.path);
          } catch (_) {}
        }

        // Rebase backing file thành tên tương đối trong cùng thư mục của máy ảo mới
        if (cloneQcow.existsSync() && qemuImgBin != null) {
          final baseRaw = qf.replaceAll('.qcow2', '');
          final cloneRawFile = File(p.join(cloneAvdDir.path, baseRaw));
          if (cloneRawFile.existsSync()) {
            try {
              await Process.run(qemuImgBin, [
                'rebase',
                '-u',
                '-b',
                baseRaw,
                cloneQcow.path,
              ]);
            } catch (_) {}
          }
        }
      }

      // 5. Sao chép thư mục snapshots (chứa default_boot) từ base sang máy ảo clone
      final baseSnapshotsDir = Directory(p.join(baseAvdDir.path, 'snapshots'));
      final cloneSnapshotsDir = Directory(p.join(cloneAvdDir.path, 'snapshots'));
      if (baseSnapshotsDir.existsSync() && !cloneSnapshotsDir.existsSync()) {
        onProgress?.call('Đang sao chép snapshot khởi động siêu tốc...');
        try {
          _copyDirectoryRecursiveSync(baseSnapshotsDir, cloneSnapshotsDir);
        } catch (_) {}
      }

      // 6. Vá toàn bộ cấu hình text bằng Dart thuần
      onProgress?.call('Đang cấu hình định danh thiết bị...');
      try {
        _patchPersonaNameInAvdDir(cloneAvdDir, cloneAvdName);
      } catch (_) {}

      // Vá thêm .pb nếu có python
      try {
        final pythonBin = Platform.isWindows ? 'python' : 'python3';
        final patchScript = '''
import os, re
target_avd = "$cloneAvdName"
target_dir = r"${cloneAvdDir.path}"
def encode_varint(val):
    out = []
    while val > 0x7f:
        out.append((val & 0x7f) | 0x80)
        val >>= 7
    out.append(val & 0x7f)
    return bytes(out)

def decode_varint(b, p):
    val = 0; shift = 0
    while True:
        byte = b[p]; p += 1
        val |= (byte & 0x7f) << shift
        shift += 7
        if not (byte & 0x80): break
    return val, p

persona_pattern = re.compile(rb'Pixel_10_Pro_persona_[a-zA-Z0-9_-]+')

def transform_bytes(b):
    p = 0
    res = bytearray()
    while p < len(b):
        key, p = decode_varint(b, p)
        wire = key & 0x7
        field = key >> 3
        if wire == 0:
            v, p = decode_varint(b, p)
            res.extend(encode_varint(key))
            res.extend(encode_varint(v))
        elif wire == 2:
            length, p = decode_varint(b, p)
            val = b[p:p+length]
            p += length
            if field == 3:
                new_val = transform_bytes(val)
            elif persona_pattern.search(val):
                new_val = persona_pattern.sub(target_avd.encode('utf-8'), val)
            else:
                new_val = val
            res.extend(encode_varint(key))
            res.extend(encode_varint(len(new_val)))
            res.extend(new_val)
        elif wire == 1:
            res.extend(encode_varint(key))
            res.extend(b[p:p+8])
            p += 8
        elif wire == 5:
            res.extend(encode_varint(key))
            res.extend(b[p:p+4])
            p += 4
        else:
            break
    return bytes(res)

for root, _, files in os.walk(target_dir):
    for fn in files:
        if fn.endswith(".pb"):
            pb_path = os.path.join(root, fn)
            try:
                with open(pb_path, "rb") as f:
                    data = f.read()
                new_data = transform_bytes(data)
                with open(pb_path, "wb") as f:
                    f.write(new_data)
            except Exception:
                pass
''';
        await Process.run(pythonBin, ['-c', patchScript]);
      } catch (_) {}
    }

    // 7. Dọn dẹp lock file cũ và file sinh tự động không tương thích
    try {
      final hwIni = File(p.join(cloneAvdDir.path, 'hardware-qemu.ini'));
      if (hwIni.existsSync()) {
        try {
          hwIni.deleteSync();
        } catch (_) {}
      }
      for (final f in cloneAvdDir.listSync(recursive: true)) {
        if (f.path.endsWith('.lock') || f.path.endsWith('multiinstance.lock')) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
      final cleanFlag = File(p.join(cloneAvdDir.path, '.clean_needed'));
      cleanFlag.writeAsStringSync('1');

      final cfgFile = File(p.join(cloneAvdDir.path, 'config.ini'));
      if (cfgFile.existsSync()) {
        final persona = PersonaService().getPersona(ip);
        final title = (persona != null && persona.name.trim().isNotEmpty) ? persona.name.trim() : ip;
        var cfg = cfgFile.readAsStringSync();
        if (cfg.contains('avd.ini.displayname=')) {
          cfg = cfg.replaceAll(RegExp(r'avd\.ini\.displayname=.*'), 'avd.ini.displayname=$title');
        } else {
          cfg = 'avd.ini.displayname=$title\n$cfg';
        }
        cfgFile.writeAsStringSync(cfg);
      }
    } catch (_) {}

    return cloneAvdName;
  }

  /// Khởi chạy thiết bị Android (Emulator chuẩn Android Studio hoặc Kết nối Ngoại vi ADB WiFi)
  /// Tự động kết nối proxy SOCKS5 nếu có server, hoặc khởi chạy thiết bị độc lập nếu server null
  Future<bool> launchPersonaDevice({
    required String ip,
    ServerModel? server,
    String? avdName,
    String? startUrl,
    String? remoteDeviceAddress,
    String deviceType = 'mobile',
    String? phoneNumber,
    bool autoSyncPhone = false,
  }) async {
    // Nếu thiết bị của nhân vật này đang chạy sẵn rồi thì không khởi chạy trùng lặp
    if (isDeviceRunningForIp(ip)) {
      debugPrint('[Device] Thiết bị cho IP $ip đang hoạt động sẵn, bỏ qua không mở thêm phiên trùng lặp.');
      return true;
    }

    Socks5Session? session;
    int? httpProxyPort;

    final isLocalDirect = ip == '127.0.0.1' || ip == 'localhost';
    if (server != null && !isLocalDirect) {
      try {
        session = await startSocks5Server(server: server, ip: ip);
      } catch (_) {
        // Fallback: nếu lỗi SSH thì tiếp tục chạy thiết bị cục bộ
      }
    }

    if (session == null) {
      session = _activeSessions[ip] ?? Socks5Session(
        localPort: 0,
        server: server,
        ip: ip,
        sshProcess: null,
        askpassFile: null,
      );
      _activeSessions[ip] = session;
    }

    // Đảm bảo không vượt quá số lượng thiết bị tối đa được phép mở đồng thời theo cấu hình
    await ensureDeviceCapacity(exemptIps: [ip]);

    // TRƯỜNG HỢP 1: Kết nối thiết bị Android ngoại vi qua WiFi/TCP-IP và ép HTTP Proxy vào máy (nếu có socks5)
    if (remoteDeviceAddress != null && remoteDeviceAddress.trim().isNotEmpty) {
      final addr = remoteDeviceAddress.trim();
      try {
        await connectRemoteDevice(addr);
        session.remoteDeviceAddress = addr;

        // Tự động đồng bộ số điện thoại vào User Profile của thiết bị ngoại vi nếu được bật switch
        if (autoSyncPhone && phoneNumber != null && phoneNumber.trim().isNotEmpty) {
          try {
            await syncPhoneNumberToDevice(addr, phoneNumber.trim());
          } catch (_) {}
        }

        if (session.localPort > 0) {
          // 1. Khởi tạo HTTP Bridge cho phép truy cập từ mạng LAN (0.0.0.0) chuyển tiếp vào SOCKS5 của IP này
          try {
            final tempSocket = await ServerSocket.bind('0.0.0.0', 0);
            final hPort = tempSocket.port;
            await tempSocket.close();

            try {
              session.httpBridgeProcess?.kill();
              await session.httpBridgeServer?.close();
            } catch (_) {}

            // Khởi tạo HTTP Bridge thuần Dart (không phụ thuộc Python)
            final bridgeServer = await startSocks2HttpBridge(
              httpPort: hPort,
              socksPort: session.localPort,
              listenHost: '0.0.0.0',
            );
            session.httpBridgeServer = bridgeServer;

            // 2. Lấy địa chỉ IP mạng LAN của máy host để điện thoại có thể bắt sóng
            final hostLanIp = await _getLocalHostIp();

            // 3. Ép HTTP Proxy vào hệ thống Android qua lệnh ADB
            await setAdbGlobalProxy(addr, hostLanIp, hPort);
          } catch (_) {}
        }

        notifyListeners();
        return true;
      } catch (e) {
        throw Exception('Không thể kết nối thiết bị ngoại vi $addr: $e');
      }
    }

    // TRƯỜNG HỢP 2: Khởi chạy Android Emulator chuẩn Android Studio trên máy Local
    // 1. Kiểm tra hoặc tự động tải Android Emulator binary từ Google repo nếu máy chưa có
    final emulatorBin = await resolveAndroidEmulatorExecutable();
    if (emulatorBin == null) {
      throw Exception('Không tìm thấy Android Emulator trên hệ thống và không thể tải tự động. Vui lòng chuyển sang tab Thiết bị ngoại vi (WiFi ADB) hoặc kiểm tra kết nối mạng.');
    }

    // 2. Xác định tên AVD để khởi chạy
    final avdsDir = getAndroidAvdDirectory();
    final sanitizedIp = ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final dedicatedPersonaAvd = 'Pixel_10_Pro_persona_$sanitizedIp';

    String actualAvd = '';
    // Kiểm tra xem persona đã có AVD riêng (từ Import hoặc Clone trước đó) hay chưa
    if (avdName != null && avdName.trim().isNotEmpty) {
      final requestedAvd = avdName.trim();
      final requestedDir = Directory(p.join(avdsDir.path, '$requestedAvd.avd'));
      if (requestedDir.existsSync()) {
        actualAvd = requestedAvd;
      }
    }

    if (actualAvd.isEmpty) {
      final personaProfile = PersonaService().getPersona(ip);
      final expectedNameAvd = generatePersonaAvdName(ip: ip, personaName: personaProfile?.name);
      final expectedDir = Directory(p.join(avdsDir.path, '$expectedNameAvd.avd'));
      if (expectedDir.existsSync()) {
        actualAvd = expectedNameAvd;
      }
    }

    if (actualAvd.isEmpty) {
      final dedicatedDir = Directory(p.join(avdsDir.path, '$dedicatedPersonaAvd.avd'));
      if (dedicatedDir.existsSync()) {
        actualAvd = dedicatedPersonaAvd;
      }
    }

    // Nếu chưa có AVD riêng cho persona này (hoặc đã bị xóa), không tự ý khởi chạy máy ảo khác
    if (actualAvd.isEmpty) {
      throw Exception('Nhân vật $ip chưa được cài đặt máy ảo hoặc máy ảo đã bị xóa. Vui lòng bấm "Cài đặt máy ảo" để cấu hình.');
    }

    // Cập nhật tên hiển thị của máy ảo (Title) theo Tên Nhân Vật trong file cấu hình AVD
    String personaTitle = ip;
    try {
      final cachedPersona = PersonaService().getPersona(ip);
      if (cachedPersona != null && cachedPersona.name.trim().isNotEmpty) {
        personaTitle = cachedPersona.name.trim();
      } else {
        final allPersonas = await PersonaService().loadSavedPersonas();
        if (allPersonas.containsKey(ip) && allPersonas[ip]!.name.trim().isNotEmpty) {
          personaTitle = allPersonas[ip]!.name.trim();
        }
      }

      final avdConfigFile = File(p.join(avdsDir.path, '$actualAvd.avd', 'config.ini'));
      if (avdConfigFile.existsSync()) {
        var cfgContent = avdConfigFile.readAsStringSync();
        if (cfgContent.contains('avd.ini.displayname=')) {
          cfgContent = cfgContent.replaceAll(
            RegExp(r'avd\.ini\.displayname=.*'),
            'avd.ini.displayname=$personaTitle',
          );
        } else {
          cfgContent = 'avd.ini.displayname=$personaTitle\n$cfgContent';
        }

        // Tối ưu hóa tối đa cấu hình thiết bị: Giảm CPU/RAM, tắt camera và toàn bộ cảm biến thừa (giữ lại âm thanh)
        final optimizations = {
          'hw.cpu.ncore': '2',
          'hw.ramSize': '1536',
          'vm.heapSize': '192',
          'hw.camera.back': 'none',
          'hw.camera.front': 'none',
          'hw.accelerometer': 'no',
          'hw.gyroscope': 'no',
          'hw.sensors.light': 'no',
          'hw.sensors.magnetic_field': 'no',
          'hw.sensors.orientation': 'no',
          'hw.sensors.pressure': 'no',
          'hw.sensors.proximity': 'no',
          'hw.audioInput': 'yes',
          'hw.audioOutput': 'yes',
        };

        for (final entry in optimizations.entries) {
          final key = entry.key;
          final val = entry.value;
          if (cfgContent.contains('$key=')) {
            cfgContent = cfgContent.replaceAll(RegExp('$key=.*'), '$key=$val');
          } else {
            cfgContent = '$key=$val\n$cfgContent';
          }
        }

        avdConfigFile.writeAsStringSync(cfgContent);
      }

      // Ghi cả vào file $actualAvd.ini ở thư mục cha ~/.android/avd/ vì Android Emulator đọc displayname từ file này để đặt Window Title
      final outerIniFile = File(p.join(avdsDir.path, '$actualAvd.ini'));
      if (outerIniFile.existsSync()) {
        var outerContent = outerIniFile.readAsStringSync();
        if (outerContent.contains('avd.ini.displayname=')) {
          outerContent = outerContent.replaceAll(
            RegExp(r'avd\.ini\.displayname=.*'),
            'avd.ini.displayname=$personaTitle',
          );
        } else {
          outerContent = 'avd.ini.displayname=$personaTitle\n$outerContent';
        }
        outerIniFile.writeAsStringSync(outerContent);
      }
    } catch (_) {}

    // 4. Khởi tạo cổng HTTP Proxy cục bộ thông qua bridge tới SOCKS5 port của IP nếu có socks5
    if (session.localPort > 0) {
      try {
        final tempSocket = await ServerSocket.bind('127.0.0.1', 0);
        httpProxyPort = tempSocket.port;
        await tempSocket.close();

        try {
          session.httpBridgeProcess?.kill();
          await session.httpBridgeServer?.close();
        } catch (_) {}

        final bridgeServer = await startSocks2HttpBridge(
          httpPort: httpProxyPort,
          socksPort: session.localPort,
          listenHost: '127.0.0.1',
        );
        session.httpBridgeServer = bridgeServer;
      } catch (_) {}
    }

    // 5. Cấp phát console port (chẵn) cho emulator từ 5554 đến 5584 riêng cho từng nhân vật
    int consolePort = 5554;
    for (int pPort = 5554; pPort <= 5584; pPort += 2) {
      if (!_isPortInUse(pPort) && !_isPortInUse(pPort + 1)) {
        bool portAvailable = true;
        try {
          final s1 = await Socket.connect('127.0.0.1', pPort, timeout: const Duration(milliseconds: 200));
          s1.destroy();
          portAvailable = false;
        } catch (_) {}
        if (portAvailable) {
          try {
            final s2 = await Socket.connect('127.0.0.1', pPort + 1, timeout: const Duration(milliseconds: 200));
            s2.destroy();
            portAvailable = false;
          } catch (_) {}
        }
        if (portAvailable) {
          consolePort = pPort;
          break;
        }
      }
    }
    session.emulatorPort = consolePort;

    // Kiểm tra xem AVD có snapshot lưu trạng thái trước đó không (để nạp lại ngay thay vì cold boot)
    final snapshotDir = Directory(p.join(avdsDir.path, '$actualAvd.avd', 'snapshots', 'default_boot'));
    final hasSnapshot = snapshotDir.existsSync() && File(p.join(snapshotDir.path, 'ram.bin')).existsSync();

    final emulatorArgs = [
      '-avd', actualAvd,
      if (httpProxyPort != null) ...[
        '-http-proxy', 'http://127.0.0.1:$httpProxyPort',
      ],
      '-dns-server', '8.8.8.8,1.1.1.1',
      '-port', consolePort.toString(),
      '-netdelay', 'none',
      '-netspeed', 'full',
      '-gpu', 'auto',
      '-no-boot-anim',
      '-camera-back', 'none',
      '-camera-front', 'none',
      if (hasSnapshot) ...[
        '-snapshot', 'default_boot',
      ] else ...[
        '-no-snapshot-load',
      ],
      if (deviceType == 'tablet') ...[
        '-skin', '1200x1920',
      ],
    ];

    try {
      final env = Map<String, String>.from(Platform.environment);
      if (!env.containsKey('DISPLAY') || env['DISPLAY']!.isEmpty) {
        env['DISPLAY'] = ':0';
      }
      // Đảm bảo emulator tìm thấy SDK và config nếu chạy từ embedded path
      final sdkDir = Directory(p.dirname(p.dirname(emulatorBin)));
      if (!env.containsKey('ANDROID_HOME') && sdkDir.existsSync()) {
        env['ANDROID_HOME'] = sdkDir.path;
      }
      if (!env.containsKey('ANDROID_SDK_ROOT') && sdkDir.existsSync()) {
        env['ANDROID_SDK_ROOT'] = sdkDir.path;
      }
      final proc = await Process.start(
        emulatorBin,
        emulatorArgs,
        environment: env,
        mode: ProcessStartMode.detached,
      );
      session.deviceProcess = proc;

      // Đánh thức màn hình, mở khóa AVD và tự động thiết lập ADB Global HTTP Proxy cho hệ thống
      _autoWakeAndUnlockAvd(
        consolePort,
        actualAvd: actualAvd,
        personaTitle: personaTitle,
        emulatorPid: proc.pid,
        proxyPort: httpProxyPort,
      );

      notifyListeners();
      return true;
    } catch (e) {
      session.httpBridgeProcess?.kill();
      throw Exception('Lỗi khi khởi chạy Android Emulator: $e');
    }
  }

  /// Khởi chạy thiết bị Android (Emulator chuẩn Android Studio hoặc Kết nối Ngoại vi ADB WiFi)
  /// Định tuyến toàn bộ lưu lượng mạng máy ảo qua proxy SOCKS5 của chính IP đó
  Future<bool> launchDeviceWithSocks5({
    required ServerModel server,
    required String ip,
    String? avdName,
    String? startUrl,
    String? remoteDeviceAddress,
    String deviceType = 'mobile',
    String? phoneNumber,
    bool autoSyncPhone = false,
  }) async {
    return launchPersonaDevice(
      server: server,
      ip: ip,
      avdName: avdName,
      startUrl: startUrl,
      remoteDeviceAddress: remoteDeviceAddress,
      deviceType: deviceType,
      phoneNumber: phoneNumber,
      autoSyncPhone: autoSyncPhone,
    );
  }

  /// Tự động kiểm tra và đánh thức, mở khóa màn hình AVD tránh màn hình đen ngủ
  /// Tự động cấu hình global http_proxy trực tiếp qua ADB settings để tất cả ứng dụng Android (Chrome, WebView, App MXH) bắt buộc chạy qua proxy SOCKS5
  /// Nếu máy ảo vừa được tạo mới từ mẫu có sẵn (cờ .clean_needed), tự động gỡ sạch Facebook, TikTok để máy ảo trắng tinh nguyên bản
  void _autoWakeAndUnlockAvd(int consolePort, {String? actualAvd, String? personaTitle, int? emulatorPid, int? proxyPort}) {
    Future.microtask(() async {
      try {
        final adbBin = await _findAdbExecutable();
        final serial = 'emulator-$consolePort';

        // Cập nhật tiêu đề cửa sổ máy ảo theo Tên Nhân Vật thông qua helper script
        if (personaTitle != null && personaTitle.trim().isNotEmpty) {
          try {
            final titleScript = File('${Directory.current.path}/lib/core/services/scripts/update_emulator_title.py');
            if (titleScript.existsSync()) {
              Process.start('python3', [
                titleScript.path,
                actualAvd ?? consolePort.toString(),
                personaTitle.trim(),
                if (emulatorPid != null) emulatorPid.toString(),
              ], mode: ProcessStartMode.detached);
            }
          } catch (_) {}
        }

        // Đợi thiết bị boot xong và sẵn sàng nhận input (tối đa 40 giây)
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(seconds: 2));
          final res = await Process.run(adbBin, ['-s', serial, 'shell', 'getprop', 'sys.boot_completed']);
          if ((res.stdout as String).trim() == '1') {
            break;
          }
        }

        // ÉP CẤU HÌNH PROXY QUA ADB SETTINGS HOẶC GỠ SẠCH PROXY CHO IP LOCAL:
        // Android Emulator mặc định dùng 10.0.2.2 làm địa chỉ loopback quay về máy trạm (host)
        if (proxyPort != null && proxyPort > 0) {
          try {
            await setAdbGlobalProxy(serial, '10.0.2.2', proxyPort);
          } catch (_) {}
        } else {
          // Trường hợp chạy local không dùng proxy: Phải xóa sạch proxy cũ tránh rớt mạng
          try {
            await clearAdbGlobalProxy(serial);
          } catch (_) {}
        }

        // 1. Gửi phím WAKEUP (224) và POWER (26) để bật sáng màn hình
        await Process.run(adbBin, ['-s', serial, 'shell', 'input', 'keyevent', '224']);
        await Process.run(adbBin, ['-s', serial, 'shell', 'input', 'keyevent', '26']);
        await Future.delayed(const Duration(milliseconds: 400));
        // 2. Gửi phím MENU (82) để mở khóa màn hình
        await Process.run(adbBin, ['-s', serial, 'shell', 'input', 'keyevent', '82']);
        // 3. Vuốt nhẹ lên mở khóa phòng trường hợp màn hình khóa cần vuốt
        await Process.run(adbBin, ['-s', serial, 'shell', 'input', 'swipe', '500', '1500', '500', '500', '200']);

        // Tối ưu hóa tối đa đồ họa: Tắt hoàn toàn hiệu ứng chuyển cảnh (Window/Transition/Animator scale) để máy ảo nhẹ và phản hồi ngay lập tức
        try {
          await Process.run(adbBin, ['-s', serial, 'shell', 'settings', 'put', 'global', 'window_animation_scale', '0']);
          await Process.run(adbBin, ['-s', serial, 'shell', 'settings', 'put', 'global', 'transition_animation_scale', '0']);
          await Process.run(adbBin, ['-s', serial, 'shell', 'settings', 'put', 'global', 'animator_duration_scale', '0']);
        } catch (_) {}

        // 4. Kiểm tra xem có cờ .clean_needed của máy ảo vừa tạo mới không
        if (actualAvd != null && actualAvd.isNotEmpty) {
          final avdsDir = getAndroidAvdDirectory();
          final cleanFlagFile = File(p.join(avdsDir.path, '$actualAvd.avd', '.clean_needed'));
          if (cleanFlagFile.existsSync()) {
            try {
              // Gỡ bỏ hoàn toàn ứng dụng mẫu bên thứ ba (Facebook, TikTok)
              final appsToClean = [
                'com.facebook.katana',
                'com.facebook.orca',
                'com.facebook.lite',
                'com.ss.android.ugc.trill',
                'com.zhiliaoapp.musically',
              ];
              for (final app in appsToClean) {
                try {
                  await Process.run(adbBin, ['-s', serial, 'shell', 'pm', 'uninstall', app]);
                } catch (_) {}
              }

              // Lưu snapshot mới sạch bóng app để các lần khởi động sau nạp thẳng snapshot sạch
              try {
                await _saveSnapshotViaConsole(consolePort, snapshotName: 'default_boot');
              } catch (_) {
                try {
                  await Process.run(adbBin, ['-s', serial, 'emu', 'avd', 'snapshot', 'save', 'default_boot']);
                } catch (_) {}
              }

              // Xóa file cờ đánh dấu
              try {
                cleanFlagFile.deleteSync();
              } catch (_) {}
            } catch (_) {}
          }
        }
      } catch (_) {}
    });
  }

  bool _isPortInUse(int port) {
    try {
      for (final s in _activeSessions.values) {
        if (s.emulatorPort == port) return true;
      }
    } catch (_) {}
    return false;
  }

  /// Đóng trình duyệt và dừng toàn bộ kết nối SOCKS5 của IP
  Future<void> stopSession(String ip) async {
    // Đóng device an toàn trước nếu đang chạy để kịp flush dữ liệu ứng dụng
    if (isDeviceRunningForIp(ip)) {
      await closeDeviceForIp(ip);
    }
    final session = _activeSessions.remove(ip);
    if (session != null) {
      if (session.remoteDeviceAddress != null) {
        await disconnectRemoteDevice(session.remoteDeviceAddress!);
      }
      await session.stop();
    }
    // Dừng triệt để các tiến trình trình duyệt gắn với profile của IP này nếu còn chạy ngầm
    try {
      final sanitizedIp = ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      if (!Platform.isWindows) {
        await Process.run('pkill', ['-f', 'browser_profiles/ip_$sanitizedIp']);
        await Process.run('pkill', ['-f', 'ip_$sanitizedIp']);
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Đóng riêng trình duyệt của IP mà không làm mất hầm SOCKS5 nếu device vẫn đang chạy
  Future<void> closeBrowserForIp(String ip) async {
    final session = _activeSessions[ip];
    if (session != null) {
      if (session.browserProcess != null) {
        try {
          session.browserProcess!.kill();
        } catch (_) {}
        session.browserProcess = null;
      }
      session.browserLaunchedAt = null;
    }
    try {
      final sanitizedIp = ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      if (Platform.isWindows) {
        try {
          final winProfileNeedle = 'browser_profiles\\\\ip_$sanitizedIp';
          await Process.run('powershell', [
            '-NoProfile',
            '-Command',
            "Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -like '*$winProfileNeedle*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }"
          ]);
        } catch (_) {}
      } else {
        await Process.run('pkill', ['-f', 'browser_profiles/ip_$sanitizedIp']);
      }
      final homeDir = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          Directory.systemTemp.path;
      final profileDir = Directory(p.join(homeDir, '.agent_mxh_auto', 'browser_profiles', 'ip_$sanitizedIp'));
      if (profileDir.existsSync()) {
        for (final entity in profileDir.listSync(followLinks: false)) {
          final baseName = p.basename(entity.path);
          if (baseName.startsWith('Singleton')) {
            try {
              entity.deleteSync();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    // Nếu device cũng không còn chạy thì giải phóng hoàn toàn session SOCKS5
    if (!_isDeviceProcessAliveForIp(ip)) {
      final s = _activeSessions.remove(ip);
      if (s != null) {
        await s.stop();
      }
    }

    notifyListeners();
  }

  /// Đóng riêng mobile device của IP mà không làm mất hầm SOCKS5 nếu trình duyệt vẫn đang chạy
  Future<void> closeDeviceForIp(String ip) async {
    _closingDeviceIps.add(ip);
    notifyListeners();

    try {
      final session = _activeSessions[ip];
      final port = session?.emulatorPort;
      final remoteAddr = session?.remoteDeviceAddress;

      if (remoteAddr != null) {
        try {
          await disconnectRemoteDevice(remoteAddr);
        } catch (_) {}
        session?.remoteDeviceAddress = null;
      }

      final sanitizedIp = ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final personaAvdName = 'Pixel_10_Pro_persona_$sanitizedIp';
      final personaProfile = PersonaService().getPersona(ip);
      final expectedNameAvd = generatePersonaAvdName(ip: ip, personaName: personaProfile?.name);
      final customAvdName = personaProfile?.avdName?.trim();
      final targetAvd = (customAvdName != null && customAvdName.isNotEmpty)
          ? customAvdName
          : (expectedNameAvd.isNotEmpty ? expectedNameAvd : personaAvdName);
      final activePort = port ??
          _findRunningConsolePortForAvd(targetAvd) ??
          _findRunningConsolePortForAvd(expectedNameAvd) ??
          _findRunningConsolePortForAvd(personaAvdName);

      // 1. Nếu emulator đang chạy, gửi lệnh sync đĩa và yêu cầu thoát an toàn để ghi dữ liệu ứng dụng
      if (activePort != null) {
        final serial = 'emulator-$activePort';
        try {
          final adbBin = await _findAdbExecutable();
          await Process.run(adbBin, ['-s', serial, 'shell', 'sync']);
        } catch (_) {}
        try {
          // Gỡ proxy trước khi snapshot để tránh lưu cố định port proxy cũ của phiên này vào ảnh đĩa
          await clearAdbGlobalProxy(serial);
        } catch (_) {}
        try {
          // Lưu snapshot default_boot hiện tại để lưu trạng thái app mới nhất
          await _saveSnapshotViaConsole(activePort, snapshotName: 'default_boot');
        } catch (_) {}
        try {
          // Gửi lệnh kill an toàn tới emulator console
          await _gracefulKillEmulatorViaConsole(activePort);
        } catch (_) {}
        // Đợi tối đa 1.5 giây để tiến trình emulator tự động thoát êm đẹp
        for (int i = 0; i < 15; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (!_isDeviceProcessAliveForIp(ip)) break;
        }
      }

      if (session?.deviceProcess != null) {
        try {
          session!.deviceProcess!.kill();
        } catch (_) {}
        session?.deviceProcess = null;
      }

      if (session?.httpBridgeProcess != null) {
        try {
          session!.httpBridgeProcess!.kill(ProcessSignal.sigkill);
        } catch (_) {}
        session?.httpBridgeProcess = null;
      }

      session?.emulatorPort = null;

      // 2. Chỉ cưỡng bức pkill -9 nếu tiến trình vẫn còn bị kẹt sau graceful shutdown
      try {
        if (_isDeviceProcessAliveForIp(ip)) {
          await Process.run('pkill', ['-9', '-f', 'device_profiles/ip_$sanitizedIp']);
          await Process.run('pkill', ['-9', '-f', 'persona_$sanitizedIp']);
        }
      } catch (_) {}

      // Nếu browser cũng không còn chạy thì giải phóng hoàn toàn session SOCKS5
      if (!_isSystemProcessAliveForIp(ip)) {
        final s = _activeSessions.remove(ip);
        if (s != null) {
          await s.stop();
        }
      }
    } finally {
      // Đợi ngắn một chút để OS dọn sạch PID trong /proc trước khi gỡ cờ closing
      await Future.delayed(const Duration(milliseconds: 300));
      _closingDeviceIps.remove(ip);
      notifyListeners();
    }
  }

  /// Tìm serial ADB (ví dụ emulator-5554 hoặc IP:port) đang chạy cho một IP nhân vật cụ thể
  Future<String?> getRunningDeviceSerialForIp(String ip) async {
    final session = _activeSessions[ip];
    if (session?.remoteDeviceAddress != null && session!.remoteDeviceAddress!.isNotEmpty) {
      return session.remoteDeviceAddress;
    }
    if (session?.emulatorPort != null) {
      return 'emulator-${session!.emulatorPort}';
    }

    final sanitizedIp = ip.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final personaAvdName = 'Pixel_10_Pro_persona_$sanitizedIp';
    final personaProfile = PersonaService().getPersona(ip);
    final expectedNameAvd = generatePersonaAvdName(ip: ip, personaName: personaProfile?.name);
    final customAvdName = personaProfile?.avdName?.trim();
    final targetAvd = (customAvdName != null && customAvdName.isNotEmpty)
        ? customAvdName
        : (expectedNameAvd.isNotEmpty ? expectedNameAvd : personaAvdName);

    final port = _findRunningConsolePortForAvd(targetAvd) ??
        _findRunningConsolePortForAvd(expectedNameAvd) ??
        _findRunningConsolePortForAvd(personaAvdName);
    if (port != null) {
      return 'emulator-$port';
    }

    if (personaProfile != null && personaProfile.useExternalDevice && personaProfile.externalDeviceAddress != null) {
      return personaProfile.externalDeviceAddress;
    }

    return null;
  }

  /// Tìm và cung cấp đường dẫn binary adb (tự động tải và nhúng nếu hệ thống chưa có)
  Future<String> _findAdbExecutable() async {
    return await AdbManagerService().resolveAdbPath();
  }

  /// Kết nối tới một thiết bị Android ngoại vi qua mạng WiFi / TCP IP (ví dụ: 192.168.1.227:38233)
  Future<String> connectRemoteDevice(String address) async {
    final cleanAddress = address.trim();
    if (cleanAddress.isEmpty) {
      throw Exception('Địa chỉ thiết bị không được để trống.');
    }
    final adbBin = await _findAdbExecutable();
    final res = await Process.run(adbBin, ['connect', cleanAddress]);
    final output = ((res.stdout as String) + (res.stderr as String)).trim();

    if (output.toLowerCase().contains('connected to') || output.toLowerCase().contains('already connected to')) {
      notifyListeners();
      return output;
    } else {
      throw Exception(output.isNotEmpty ? output : 'Không thể kết nối tới thiết bị $cleanAddress');
    }
  }

  /// Khởi tạo HTTP-to-SOCKS5 Bridge thuần Dart cho phép thiết bị Android (Emulator hoặc thiết bị ngoại vi WiFi)
  /// định tuyến toàn bộ lưu lượng HTTP/HTTPS CONNECT vào đường hầm SOCKS5 mà KHÔNG cần Python
  Future<ServerSocket> startSocks2HttpBridge({
    required int httpPort,
    required int socksPort,
    String listenHost = '127.0.0.1',
  }) async {
    final server = await ServerSocket.bind(listenHost, httpPort);

    server.listen((clientSocket) {
      StreamSubscription<Uint8List>? clientSub;
      StreamSubscription<Uint8List>? socksSub;
      Socket? socksSocket;
      bool isClosed = false;

      void cleanUp() {
        if (isClosed) return;
        isClosed = true;
        try { clientSub?.cancel(); } catch (_) {}
        try { socksSub?.cancel(); } catch (_) {}
        try { clientSocket.destroy(); } catch (_) {}
        try { socksSocket?.destroy(); } catch (_) {}
      }

      // Nuốt lỗi EPIPE bất đồng bộ trên Future done của socket client
      unawaited(clientSocket.done.catchError((_) {}));
      void safeWriteClient(List<int> data) {
        if (isClosed) return;
        try {
          clientSocket.add(data);
        } catch (_) {
          cleanUp();
        }
      }
      void safeWriteSocks(List<int> data) {
        if (isClosed) return;
        final s = socksSocket;
        if (s == null) return;
        try {
          s.add(data);
        } catch (_) {
          cleanUp();
        }
      }

      int stage = 0; // 0: wait header, 1: greeting, 2: connecting, 3: streaming
      final clientBuffer = <int>[];
      String method = '';
      String targetHost = '';
      int targetPort = 80;

      clientSub = clientSocket.listen(
        (data) async {
          if (isClosed) return;
          if (stage == 3) {
            try {
              safeWriteSocks(data);
            } catch (_) {
              cleanUp();
            }
            return;
          }

          clientBuffer.addAll(data);
          final rawStr = String.fromCharCodes(clientBuffer);
          final headerEnd = rawStr.indexOf('\r\n\r\n');
          final headerEndAlt = rawStr.indexOf('\n\n');
          if (headerEnd == -1 && headerEndAlt == -1 && clientBuffer.length < 8192) {
            return;
          }

          clientSub?.pause();

          try {
            final firstLine = rawStr.split('\n').first.trim();
            final parts = firstLine.split(' ');
            if (parts.length < 2) {
              cleanUp();
              return;
            }

            method = parts[0].toUpperCase();
            final target = parts[1];

            if (method == 'CONNECT') {
              if (target.contains(':')) {
                final split = target.split(':');
                targetHost = split[0];
                targetPort = int.tryParse(split[1]) ?? 443;
              } else {
                targetHost = target;
                targetPort = 443;
              }
            } else {
              var url = target;
              if (url.startsWith('http://')) url = url.substring(7);
              final slashIdx = url.indexOf('/');
              final hostPort = slashIdx == -1 ? url : url.substring(0, slashIdx);
              if (hostPort.contains(':')) {
                final split = hostPort.split(':');
                targetHost = split[0];
                targetPort = int.tryParse(split[1]) ?? 80;
              } else {
                targetHost = hostPort;
                targetPort = 80;
              }
            }

            if (targetHost.isEmpty) {
              cleanUp();
              return;
            }

            socksSocket = await Socket.connect('127.0.0.1', socksPort, timeout: const Duration(seconds: 7));
            unawaited(socksSocket!.done.catchError((_) {}));
            stage = 1; // greeting

            socksSub = socksSocket!.listen(
              (sData) {
                if (isClosed) return;
                if (stage == 1) {
                  if (sData.length < 2 || sData[0] != 0x05 || sData[1] != 0x00) {
                    cleanUp();
                    return;
                  }
                  stage = 2; // connecting
                  final hostBytes = utf8.encode(targetHost);
                  final portBytes = [(targetPort >> 8) & 0xFF, targetPort & 0xFF];
                  safeWriteSocks([0x05, 0x01, 0x00, 0x03, hostBytes.length, ...hostBytes, ...portBytes]);
                  return;
                }

                if (stage == 2) {
                  if (sData.length < 4 || sData[1] != 0x00) {
                    cleanUp();
                    return;
                  }
                  stage = 3; // streaming

                  if (method == 'CONNECT') {
                    safeWriteClient(utf8.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
                  } else {
                    safeWriteSocks(clientBuffer);
                  }

                  int respLen = 4;
                  final atyp = sData[3];
                  if (atyp == 1) {
                    respLen = 10;
                  } else if (atyp == 3) {
                    respLen = 4 + 1 + sData[4] + 2;
                  } else if (atyp == 4) {
                    respLen = 22;
                  }

                  if (sData.length > respLen) {
                    safeWriteClient(sData.sublist(respLen));
                  }

                  clientSub?.resume();
                  return;
                }

                if (stage == 3) {
                  try {
                    safeWriteClient(sData);
                  } catch (_) {
                    cleanUp();
                  }
                }
              },
              onDone: () => cleanUp(),
              onError: (_) => cleanUp(),
              cancelOnError: true,
            );

            // Send SOCKS5 Greeting
            safeWriteSocks([0x05, 0x01, 0x00]);
          } catch (_) {
            cleanUp();
          }
        },
        onDone: () => cleanUp(),
        onError: (_) => cleanUp(),
        cancelOnError: true,
      );
    });

    return server;
  }

  /// Lấy địa chỉ IP nội bộ (LAN) của máy tính trạm đang kết nối cùng dải mạng với thiết bị
  Future<String> _getLocalHostIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        // Ưu tiên interface WiFi hoặc Ethernet LAN (bỏ qua loopback và docker/br/tun)
        final name = iface.name.toLowerCase();
        if (name.contains('lo') || name.contains('docker') || name.contains('br-') || name.contains('tun')) {
          continue;
        }
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168.') || addr.address.startsWith('10.') || addr.address.startsWith('172.')) {
            return addr.address;
          }
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  /// Ép cấu hình HTTP Proxy vào thiết bị Android qua lệnh ADB
  Future<void> setAdbGlobalProxy(String serial, String host, int port) async {
    final adbBin = await _findAdbExecutable();
    final cleanSerial = serial.trim();
    try {
      // 1. Cấu hình định dạng chuẩn http_proxy
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'settings', 'put', 'global', 'http_proxy', '$host:$port']);
      // 2. Cấu hình thêm host và port riêng lẻ (cho các dòng máy OEM như Samsung, Xiaomi, Pixel)
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'settings', 'put', 'global', 'global_http_proxy_host', host]);
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'settings', 'put', 'global', 'global_http_proxy_port', port.toString()]);
      // 3. Khởi động lại các trình duyệt nền để nhận diện proxy mới ngay lập tức
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'am', 'force-stop', 'com.android.chrome']);
    } catch (_) {}
  }

  /// Gỡ bỏ cấu hình HTTP Proxy khỏi thiết bị Android qua ADB về mặc định
  Future<void> clearAdbGlobalProxy(String serial) async {
    final adbBin = await _findAdbExecutable();
    final cleanSerial = serial.trim();
    try {
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'settings', 'put', 'global', 'http_proxy', ':0']);
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'settings', 'delete', 'global', 'http_proxy']);
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'settings', 'delete', 'global', 'global_http_proxy_host']);
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'settings', 'delete', 'global', 'global_http_proxy_port']);
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'am', 'force-stop', 'com.android.chrome']);
    } catch (_) {}
  }

  /// Ngắt kết nối một thiết bị ngoại vi qua ADB và gỡ proxy
  Future<void> disconnectRemoteDevice(String address) async {
    final adbBin = await _findAdbExecutable();
    final cleanAddr = address.trim();
    await clearAdbGlobalProxy(cleanAddr);
    await Process.run(adbBin, ['disconnect', cleanAddr]);
    notifyListeners();
  }

  /// Lấy danh sách các thiết bị ngoại vi / vật lý đang kết nối qua ADB
  Future<List<Map<String, String>>> getConnectedAdbDevices() async {
    final adbBin = await _findAdbExecutable();
    final res = await Process.run(adbBin, ['devices', '-l']);

    final lines = (res.stdout as String).split('\n');
    final List<Map<String, String>> devices = [];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('List of devices')) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final serial = parts[0];
        final state = parts[1];
        String model = 'Unknown';
        for (final p in parts) {
          if (p.startsWith('model:')) {
            model = p.replaceFirst('model:', '');
            break;
          }
        }
        final isWifi = serial.contains(':');
        devices.add({
          'serial': serial,
          'state': state,
          'model': model,
          'type': isWifi ? 'WiFi Remote' : (serial.startsWith('emulator-') ? 'Local AVD' : 'USB Device'),
        });
      }
    }
    return devices;
  }

  /// Đồng bộ số điện thoại vào thiết bị Android qua ADB (Profile chủ máy, Danh bạ chính, và Bộ nhớ tạm Clipboard)
  Future<bool> syncPhoneNumberToDevice(String serial, String phoneNumber, {String ownerName = 'Chủ Thiết Bị'}) async {
    try {
      final adbBin = await _findAdbExecutable();
      final cleanSerial = serial.trim();
      final cleanPhone = phoneNumber.trim();
      if (cleanPhone.isEmpty) return false;

      // 1. Tự động kết nối ADB WiFi nếu chưa kết nối
      if (cleanSerial.contains(':')) {
        await Process.run(adbBin, ['connect', cleanSerial]);
      }

      // 2. Set số điện thoại trực tiếp vào Clipboard của điện thoại Android để người dùng dán ngay vào ô đăng ký
      await Process.run(adbBin, [
        '-s', cleanSerial, 'shell',
        'cmd', 'clipboard', 'set', cleanPhone,
      ]);

      // 3. Chèn vào Danh bạ thông thường (Contacts Contract) để bất kỳ ứng dụng nào quét danh bạ cũng thấy ngay
      await Process.run(adbBin, [
        '-s', cleanSerial, 'shell',
        'am', 'start', '-a', 'android.intent.action.INSERT',
        '-t', 'vnd.android.cursor.dir/contact',
        '-e', 'name', ownerName,
        '-e', 'phone', cleanPhone,
      ]);
      // Nhấn nút BACK tự động lưu danh bạ và thoát form lưu nếu có popup
      await Future.delayed(const Duration(milliseconds: 600));
      await Process.run(adbBin, ['-s', cleanSerial, 'shell', 'input', 'keyevent', '4']);

      // 4. Đồng bộ User Profile (Hồ sơ chủ máy) thông qua Content Provider
      try {
        await Process.run(adbBin, [
          '-s', cleanSerial, 'shell',
          'content', 'insert',
          '--uri', 'content://com.android.contacts/profile/raw_contacts',
          '--bind', 'account_name:s:null',
          '--bind', 'account_type:s:null',
        ]);

        final queryRes = await Process.run(adbBin, [
          '-s', cleanSerial, 'shell',
          'content', 'query',
          '--uri', 'content://com.android.contacts/profile/raw_contacts',
          '--projection', '_id',
        ]);
        final queryOut = queryRes.stdout.toString();
        String? rawContactId;
        final match = RegExp(r'_id=(\d+)').firstMatch(queryOut);
        if (match != null) {
          rawContactId = match.group(1);
        }
        rawContactId ??= '9223372034707292161';

        await Process.run(adbBin, [
          '-s', cleanSerial, 'shell',
          'content', 'insert',
          '--uri', 'content://com.android.contacts/profile/data',
          '--bind', 'raw_contact_id:l:$rawContactId',
          '--bind', 'mimetype:s:vnd.android.cursor.item/phone_v2',
          '--bind', 'data1:s:$cleanPhone',
          '--bind', 'data2:i:2',
        ]);

        await Process.run(adbBin, [
          '-s', cleanSerial, 'shell',
          'content', 'insert',
          '--uri', 'content://com.android.contacts/profile/data',
          '--bind', 'raw_contact_id:l:$rawContactId',
          '--bind', 'mimetype:s:vnd.android.cursor.item/name',
          '--bind', 'data1:s:$ownerName',
          '--bind', 'data2:s:$ownerName',
        ]);
      } catch (_) {}

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Chức năng sửa chữa hệ thống (System Repair):
  /// Quét toàn bộ thư mục browser_profiles, bứng sạch các file symlink SingletonLock, SingletonCookie,
  /// SingletonSocket bị kẹt (broken/dangling symlinks), dọn dẹp các tiến trình zombie Chrome/Emulator
  /// và đồng bộ lại các extension tiếng Việt.
  Future<Map<String, dynamic>> repairBrowserProfilesAndEnvironment() async {
    int removedLocks = 0;
    int fixedProfiles = 0;
    int killedZombies = 0;
    final List<String> details = [];

    try {
      final profilesRoot = getBrowserProfilesDirectory();

      // 1. Quét các thư mục profile
      if (profilesRoot.existsSync()) {
        final entities = profilesRoot.listSync(followLinks: false);
        for (final entity in entities) {
          if (entity is Directory) {
            bool profileRepaired = false;
            for (final subEntity in entity.listSync(followLinks: false)) {
              final base = subEntity.path.split(Platform.isWindows ? r'\' : '/').last;
              if (base.startsWith('Singleton')) {
                try {
                  final type = FileSystemEntity.typeSync(subEntity.path, followLinks: false);
                  if (type == FileSystemEntityType.link) {
                    Link(subEntity.path).deleteSync();
                  } else if (type == FileSystemEntityType.file) {
                    File(subEntity.path).deleteSync();
                  } else if (type == FileSystemEntityType.directory) {
                    Directory(subEntity.path).deleteSync(recursive: true);
                  }
                  removedLocks++;
                  profileRepaired = true;
                } catch (_) {
                  try {
                    subEntity.deleteSync(recursive: true);
                    removedLocks++;
                    profileRepaired = true;
                  } catch (_) {}
                }
              }
            }

            for (final lockName in ['SingletonLock', 'SingletonSocket', 'SingletonCookie']) {
              try {
                final f = File('${entity.path}/$lockName');
                if (f.existsSync()) {
                  f.deleteSync();
                  removedLocks++;
                  profileRepaired = true;
                }
              } catch (_) {}
              try {
                final l = Link('${entity.path}/$lockName');
                if (l.existsSync()) {
                  l.deleteSync();
                  removedLocks++;
                  profileRepaired = true;
                }
              } catch (_) {}
            }

            // Đồng bộ / phục hồi Extension tiếng Việt cho Meta/Facebook nếu thiếu
            try {
              _ensureFacebookVietnameseCookie(entity.path);
            } catch (_) {}

            if (profileRepaired) {
              fixedProfiles++;
              final profileName = entity.path.split(Platform.isWindows ? r'\' : '/').last;
              details.add('Đã mở khóa profile: $profileName');
            }
          }
        }
      }

      // 2. Dọn dẹp tiến trình zombie kẹt ngầm (trên Linux)
      if (Platform.isLinux) {
        try {
          final procDir = Directory('/proc');
          if (procDir.existsSync()) {
            final myPid = pid;
            for (final entity in procDir.listSync(followLinks: false)) {
              final baseName = entity.path.split('/').last;
              final p = int.tryParse(baseName);
              if (p == null || p == myPid) continue;
              try {
                final cmdFile = File('${entity.path}/cmdline');
                if (cmdFile.existsSync()) {
                  final bytes = cmdFile.readAsBytesSync();
                  final cmd = String.fromCharCodes(bytes);
                  if (cmd.contains('browser_profiles/ip_') && cmd.contains('chrome') && !cmd.contains('agent_mxh_auto')) {
                    // Kiểm tra xem tiến trình này có còn thuộc session active trong app không
                    bool isInSession = false;
                    for (final s in _activeSessions.values) {
                      if (s.browserProcess?.pid == p) {
                        isInSession = true;
                        break;
                      }
                    }
                    if (!isInSession) {
                      Process.killPid(p);
                      killedZombies++;
                    }
                  }
                }
              } catch (_) {}
            }
          }
        } catch (_) {}
      }

      notifyListeners();

      return {
        'success': true,
        'removed_locks': removedLocks,
        'fixed_profiles': fixedProfiles,
        'killed_zombies': killedZombies,
        'details': details,
        'message': 'Đã sửa chữa thành công: giải phóng $removedLocks khóa lock, tối ưu $fixedProfiles profile, dọn dẹp $killedZombies tiến trình treo.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Lỗi khi chạy chức năng sửa chữa: $e',
      };
    }
  }
}

