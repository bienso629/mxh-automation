import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Phân loại nguồn máy ảo / thiết bị Android hiển thị trong Hồ sơ nhân vật AI
enum VirtualDeviceKind {
  /// Máy ảo Android Studio AVD truyền thống (~/.android/avd)
  androidAvd,

  /// Giả lập LDPlayer trên máy trạm (quản lý qua ldconsole / leidian*.config)
  ldPlayer,

  /// Giả lập / Thiết bị Android đang kết nối trực tiếp trong danh sách ADB của Android Studio
  adbConnected,
}

/// Thông tin một máy ảo / giả lập khả dụng để gắn vào Nhân vật AI
class VirtualDeviceOption {
  final String id;
  final String name;
  final VirtualDeviceKind kind;
  final bool isRunning;
  final String? adbSerial;
  final int? ldIndex;
  final String? model;
  final bool isThirdPartyEmulator;

  const VirtualDeviceOption({
    required this.id,
    required this.name,
    required this.kind,
    this.isRunning = false,
    this.adbSerial,
    this.ldIndex,
    this.model,
    this.isThirdPartyEmulator = false,
  });

  String get displayLabel {
    switch (kind) {
      case VirtualDeviceKind.ldPlayer:
        final idxPrefix = ldIndex != null ? '[LDPlayer #$ldIndex] ' : '[LDPlayer] ';
        if (isRunning) {
          final serialInfo = (adbSerial != null && adbSerial!.isNotEmpty) ? ' - $adbSerial' : '';
          return '$idxPrefix$name (Đang chạy$serialInfo)';
        }
        return '$idxPrefix$name (Sẵn sàng)';
      case VirtualDeviceKind.adbConnected:
        final tag = isThirdPartyEmulator ? '[LDPlayer / ADB]' : '[Thiết bị ADB]';
        final serialStr = (adbSerial != null && adbSerial!.isNotEmpty) ? adbSerial! : id.replaceFirst('adb:', '');
        if (name.isNotEmpty && name != serialStr) {
          return '$tag $name ($serialStr - Đang chạy)';
        }
        return '$tag $serialStr (Đang chạy)';
      case VirtualDeviceKind.androidAvd:
        if (isRunning && adbSerial != null && adbSerial!.isNotEmpty) {
          return '$name (Đang chạy - $adbSerial)';
        }
        return name;
    }
  }
}

/// Cấu hình đọc từ file `vms/config/leidian<index>.config` của LDPlayer
class LdPlayerVmConfig {
  final int index;
  final String? playerName;
  final String? manufacturer;
  final String? model;
  final int? adbDebug;
  final String? configFilePath;

  const LdPlayerVmConfig({
    required this.index,
    this.playerName,
    this.manufacturer,
    this.model,
    this.adbDebug,
    this.configFilePath,
  });
}

/// Trạng thái một máy ảo LDPlayer tổng hợp từ ldconsole list2 + leidian*.config
class LdPlayerInstance {
  final int index;
  final String name;
  final bool isRunning;
  final int? pid;
  final int? vboxPid;
  final String? model;

  const LdPlayerInstance({
    required this.index,
    required this.name,
    required this.isRunning,
    this.pid,
    this.vboxPid,
    this.model,
  });
}

/// Bản ghi thiết bị đọc từ `adb devices -l` (đã khử trùng lặp cặp port local của cùng 1 emulator)
class AdbDeviceRecord {
  final String serial;
  final List<String> aliasSerials;
  final String state;
  final String? model;
  final String? product;
  final String? device;

  const AdbDeviceRecord({
    required this.serial,
    this.aliasSerials = const [],
    required this.state,
    this.model,
    this.product,
    this.device,
  });

  bool matchesSerial(String candidate) {
    final clean = candidate.trim();
    return serial == clean || aliasSerials.contains(clean);
  }
}

/// Thông tin tóm tắt đọc từ `adb -s <serial> shell getprop`
class AdbGetpropSummary {
  final String? qemuAvdName;
  final String? manufacturer;
  final String? model;
  final bool isThirdPartyEmulator;

  const AdbGetpropSummary({
    this.qemuAvdName,
    this.manufacturer,
    this.model,
    this.isThirdPartyEmulator = false,
  });
}

/// Thông tin thư mục cài đặt LDPlayer tìm thấy trên hệ thống
class LdPlayerInstallInfo {
  final String installDir;
  final String consolePath;
  final String? dataDir;

  const LdPlayerInstallInfo({
    required this.installDir,
    required this.consolePath,
    this.dataDir,
  });

  List<Directory> get candidateConfigDirs {
    final dirs = <Directory>[];
    final seen = <String>{};
    void addDir(String path) {
      final norm = p.normalize(path);
      if (seen.add(norm.toLowerCase())) {
        dirs.add(Directory(norm));
      }
    }

    if (dataDir != null && dataDir!.trim().isNotEmpty) {
      addDir(p.join(dataDir!.trim(), 'config'));
      addDir(p.join(dataDir!.trim(), 'vms', 'config'));
    }
    addDir(p.join(installDir, 'vms', 'config'));
    return dirs;
  }

  Directory? get primaryVmsDir {
    if (dataDir != null && dataDir!.trim().isNotEmpty) {
      final d1 = Directory(dataDir!.trim());
      if (d1.existsSync() && p.basename(d1.path).toLowerCase() == 'vms') {
        return d1;
      }
      final d2 = Directory(p.join(dataDir!.trim(), 'vms'));
      if (d2.existsSync()) return d2;
      if (d1.existsSync()) return d1;
    }
    final defaultVms = Directory(p.join(installDir, 'vms'));
    return defaultVms.existsSync() ? defaultVms : null;
  }
}

/// Các hàm nhận diện và phân tích định danh máy ảo LDPlayer / ADB thuần túy
class LdPlayerAdbParser {
  static bool isLdPlayerId(String? avdId) {
    if (avdId == null) return false;
    return avdId.trim().startsWith('ldplayer:');
  }

  static bool isAdbConnectedId(String? avdId) {
    if (avdId == null) return false;
    return avdId.trim().startsWith('adb:');
  }

  static bool isExternalEmulatorId(String? avdId) {
    return isLdPlayerId(avdId) || isAdbConnectedId(avdId);
  }

  static int? parseLdPlayerIndex(String? avdId) {
    if (!isLdPlayerId(avdId)) return null;
    final rest = avdId!.trim().substring('ldplayer:'.length);
    final idxPart = rest.split(':').first.trim();
    return int.tryParse(idxPart);
  }

  static String? parseAdbSerial(String? avdId) {
    if (!isAdbConnectedId(avdId)) return null;
    final serial = avdId!.trim().substring('adb:'.length).trim();
    return serial.isEmpty ? null : serial;
  }

  static String buildLdPlayerId(int index) => 'ldplayer:$index';

  static String buildAdbConnectedId(String serial) => 'adb:${serial.trim()}';

  /// LDPlayer quy ước: instance index (0, 1, 2, ...) ánh xạ sang emulator-(5554 + index * 2)
  static String ldPlayerEmulatorSerial(int index) => 'emulator-${5554 + index * 2}';

  /// LDPlayer quy ước cổng TCP ADB local: 127.0.0.1:(5555 + index * 2)
  static String ldPlayerTcpSerial(int index) => '127.0.0.1:${5555 + index * 2}';

  /// Suy luận chỉ số `index` của giả lập LDPlayer từ serial ADB chuẩn (`emulator-5554` hoặc `127.0.0.1:5555`)
  static int? inferLdPlayerIndexFromSerial(String? serial) {
    if (serial == null || serial.trim().isEmpty) return null;
    final clean = serial.trim();
    final emuMatch = RegExp(r'^emulator-(\d+)$').firstMatch(clean);
    if (emuMatch != null) {
      final port = int.tryParse(emuMatch.group(1)!);
      if (port != null && port >= 5554 && port <= 5682 && port.isEven) {
        return (port - 5554) ~/ 2;
      }
    }
    final tcpMatch = RegExp(r'^(?:127\.0\.0\.1|localhost):(\d+)$').firstMatch(clean);
    if (tcpMatch != null) {
      final port = int.tryParse(tcpMatch.group(1)!);
      if (port != null && port >= 5555 && port <= 5683 && port.isOdd) {
        return (port - 5555) ~/ 2;
      }
    }
    return null;
  }

  /// Nhãn dự phòng khi chưa tải kịp catalog chi tiết
  static String fallbackDisplayLabelForId(String id) {
    final clean = id.trim();
    if (isLdPlayerId(clean)) {
      final idx = parseLdPlayerIndex(clean);
      final parts = clean.split(':');
      final customLabel = parts.length >= 3 ? parts.sublist(2).join(':').trim() : '';
      if (idx != null) {
        return customLabel.isNotEmpty
            ? '[LDPlayer #$idx] $customLabel'
            : '[LDPlayer #$idx] Giả lập LDPlayer #$idx';
      }
      return '[LDPlayer] $clean';
    }
    if (isAdbConnectedId(clean)) {
      final serial = parseAdbSerial(clean) ?? clean;
      return '[LDPlayer / ADB] $serial';
    }
    return clean;
  }

  /// Phân tích nội dung JSON của một file `leidian<index>.config`
  static LdPlayerVmConfig? parseLdPlayerConfigJson(
    int index,
    String jsonContent, {
    String? configFilePath,
  }) {
    try {
      final decoded = jsonDecode(jsonContent);
      if (decoded is! Map) return null;

      String? readString(String dottedKey, String groupKey, String leafKey) {
        final direct = decoded[dottedKey];
        if (direct != null && direct.toString().trim().isNotEmpty) {
          return direct.toString().trim();
        }
        final group = decoded[groupKey];
        if (group is Map && group[leafKey] != null && group[leafKey].toString().trim().isNotEmpty) {
          return group[leafKey].toString().trim();
        }
        return null;
      }

      int? readInt(String dottedKey, String groupKey, String leafKey) {
        final direct = decoded[dottedKey];
        if (direct is int) return direct;
        if (direct is bool) return direct ? 1 : 0;
        if (direct != null) {
          final pInt = int.tryParse(direct.toString().trim());
          if (pInt != null) return pInt;
        }
        final group = decoded[groupKey];
        if (group is Map && group[leafKey] != null) {
          final v = group[leafKey];
          if (v is int) return v;
          if (v is bool) return v ? 1 : 0;
          return int.tryParse(v.toString().trim());
        }
        return null;
      }

      return LdPlayerVmConfig(
        index: index,
        playerName: readString('statusSettings.playerName', 'statusSettings', 'playerName'),
        manufacturer: readString('propertySettings.phoneManufacturer', 'propertySettings', 'phoneManufacturer'),
        model: readString('propertySettings.phoneModel', 'propertySettings', 'phoneModel'),
        adbDebug: readInt('basicSettings.adbDebug', 'basicSettings', 'adbDebug'),
        configFilePath: configFilePath,
      );
    } catch (_) {
      return null;
    }
  }

  /// Đọc toàn bộ các file `leidian<index>.config` trong thư mục config của LDPlayer
  static Map<int, LdPlayerVmConfig> readLdPlayerConfigsFromDir(
    Directory configDir, {
    Directory? vmsDir,
  }) {
    final result = <int, LdPlayerVmConfig>{};
    if (!configDir.existsSync()) return result;

    final fileRegex = RegExp(r'^leidian(\d+)\.config$', caseSensitive: false);
    try {
      for (final entity in configDir.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final base = p.basename(entity.path);
        final match = fileRegex.firstMatch(base);
        if (match == null) continue;
        final idx = int.tryParse(match.group(1)!);
        if (idx == null) continue;

        // Nếu có thư mục vms, kiểm tra thư mục leidian<idx> còn tồn tại không (tránh VM đã xóa còn sót config)
        if (idx > 0 && vmsDir != null && vmsDir.existsSync()) {
          final vmFolder = Directory(p.join(vmsDir.path, 'leidian$idx'));
          if (!vmFolder.existsSync()) {
            continue;
          }
        }

        try {
          final bytes = entity.readAsBytesSync();
          final content = utf8.decode(bytes, allowMalformed: true);
          final parsed = parseLdPlayerConfigJson(
            idx,
            content,
            configFilePath: entity.path,
          );
          if (parsed != null) {
            result[idx] = parsed;
          }
        } catch (_) {}
      }
    } catch (_) {}

    return result;
  }

  /// Phân tích kết quả từ `ldconsole.exe list2` kết hợp dữ liệu UTF-8 chuẩn từ `leidian*.config`
  static List<LdPlayerInstance> parseLdConsoleList2Output(
    String rawOutput, {
    Map<int, LdPlayerVmConfig>? configsByIndex,
    bool includeConfigOnlyFallbacks = false,
  }) {
    final instancesByIndex = <int, LdPlayerInstance>{};
    final lines = rawOutput.split(RegExp(r'\r?\n'));

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final parts = line.split(',');
      if (parts.length < 5) continue;

      final idx = int.tryParse(parts[0].trim());
      if (idx == null || idx < 0) continue;

      String cliTitle;
      int androidStarted = 0;
      int? pid;
      int? vboxPid;

      // Xử lý an toàn kể cả khi tên giả lập LDPlayer có chứa dấu phẩy:
      // Định dạng chuẩn LDPlayer 9 (10 cột): index,title,topWnd,bindWnd,androidStarted,pid,vboxPid,width,height,dpi
      // Định dạng chuẩn LDPlayer 3/4 (7 cột): index,title,topWnd,bindWnd,androidStarted,pid,vboxPid
      final tail6IsNumeric = parts.length >= 10 &&
          parts.sublist(parts.length - 8).every((s) => int.tryParse(s.trim()) != null);
      final tail3IsNumeric = !tail6IsNumeric &&
          parts.length >= 7 &&
          parts.sublist(parts.length - 5).every((s) => int.tryParse(s.trim()) != null);

      if (tail6IsNumeric) {
        final titleEnd = parts.length - 8;
        cliTitle = parts.sublist(1, titleEnd).join(',').trim();
        androidStarted = int.tryParse(parts[titleEnd + 2].trim()) ?? 0;
        pid = int.tryParse(parts[titleEnd + 3].trim());
        vboxPid = int.tryParse(parts[titleEnd + 4].trim());
      } else if (tail3IsNumeric) {
        final titleEnd = parts.length - 5;
        cliTitle = parts.sublist(1, titleEnd).join(',').trim();
        androidStarted = int.tryParse(parts[titleEnd + 2].trim()) ?? 0;
        pid = int.tryParse(parts[titleEnd + 3].trim());
        vboxPid = int.tryParse(parts[titleEnd + 4].trim());
      } else {
        cliTitle = parts[1].trim();
        androidStarted = int.tryParse(parts[4].trim()) ?? 0;
        if (parts.length > 5) pid = int.tryParse(parts[5].trim());
        if (parts.length > 6) vboxPid = int.tryParse(parts[6].trim());
      }

      final cfg = configsByIndex?[idx];
      final effectiveName = (cfg?.playerName != null && cfg!.playerName!.isNotEmpty)
          ? cfg.playerName!
          : (cliTitle.isNotEmpty ? cliTitle : (idx == 0 ? 'LDPlayer' : 'LDPlayer-$idx'));
      final isRunning = androidStarted > 0 || ((vboxPid ?? -1) > 0 && (pid ?? -1) > 0);

      String? modelLabel;
      if (cfg?.model != null && cfg!.model!.isNotEmpty) {
        final mfg = cfg.manufacturer?.trim() ?? '';
        modelLabel = mfg.isNotEmpty && !cfg.model!.toLowerCase().startsWith(mfg.toLowerCase())
            ? '$mfg ${cfg.model}'
            : cfg.model;
      }

      instancesByIndex[idx] = LdPlayerInstance(
        index: idx,
        name: effectiveName,
        isRunning: isRunning,
        pid: (pid != null && pid > 0) ? pid : null,
        vboxPid: (vboxPid != null && vboxPid > 0) ? vboxPid : null,
        model: modelLabel,
      );
    }

    // Chỉ fallback sang danh sách file config khi ldconsole list2 không trả về dữ liệu (ví dụ lỗi thực thi)
    if ((instancesByIndex.isEmpty || includeConfigOnlyFallbacks) &&
        configsByIndex != null &&
        configsByIndex.isNotEmpty) {
      for (final entry in configsByIndex.entries) {
        instancesByIndex.putIfAbsent(entry.key, () {
          final cfg = entry.value;
          final name = (cfg.playerName != null && cfg.playerName!.isNotEmpty)
              ? cfg.playerName!
              : (entry.key == 0 ? 'LDPlayer' : 'LDPlayer-${entry.key}');
          String? modelLabel;
          if (cfg.model != null && cfg.model!.isNotEmpty) {
            final mfg = cfg.manufacturer?.trim() ?? '';
            modelLabel = mfg.isNotEmpty && !cfg.model!.toLowerCase().startsWith(mfg.toLowerCase())
                ? '$mfg ${cfg.model}'
                : cfg.model;
          }
          return LdPlayerInstance(
            index: entry.key,
            name: name,
            isRunning: false,
            model: modelLabel,
          );
        });
      }
    }

    final list = instancesByIndex.values.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return list;
  }

  /// Phân tích output của `adb devices -l` và khử trùng lặp cặp `emulator-<even>` + `127.0.0.1:<even+1>`
  static List<AdbDeviceRecord> parseAdbDevicesLongOutput(String rawOutput) {
    final rawRecords = <AdbDeviceRecord>[];
    final lines = rawOutput.split(RegExp(r'\r?\n'));

    for (final rawLine in lines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('List of devices') ||
          trimmed.startsWith('* daemon')) {
        continue;
      }
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;

      final serial = parts[0].trim();
      final state = parts[1].trim();
      if (state != 'device') {
        // Chỉ lấy các thiết bị đang online sẵn sàng trong Android Studio (state == 'device')
        continue;
      }

      String? model;
      String? product;
      String? device;
      for (int i = 2; i < parts.length; i++) {
        final token = parts[i];
        if (token.startsWith('model:')) {
          model = token.substring('model:'.length).replaceAll('_', ' ').trim();
        } else if (token.startsWith('product:')) {
          product = token.substring('product:'.length).trim();
        } else if (token.startsWith('device:')) {
          device = token.substring('device:'.length).trim();
        }
      }

      rawRecords.add(AdbDeviceRecord(
        serial: serial,
        state: state,
        model: (model != null && model.isNotEmpty) ? model : null,
        product: (product != null && product.isNotEmpty) ? product : null,
        device: (device != null && device.isNotEmpty) ? device : null,
      ));
    }

    // Khử trùng lặp trường hợp cùng 1 LDPlayer / Emulator xuất hiện đồng thời dưới dạng
    // `emulator-5554` VÀ `127.0.0.1:5555` (hoặc `localhost:5555`) trong `adb devices -l`
    final bySerial = <String, AdbDeviceRecord>{
      for (final r in rawRecords) r.serial: r,
    };
    final consumedAliases = <String>{};
    final merged = <AdbDeviceRecord>[];

    for (final rec in rawRecords) {
      if (consumedAliases.contains(rec.serial)) continue;

      final emuMatch = RegExp(r'^emulator-(\d+)$').firstMatch(rec.serial);
      if (emuMatch != null) {
        final consolePort = int.tryParse(emuMatch.group(1)!);
        if (consolePort != null && consolePort.isEven) {
          final adbPort = consolePort + 1;
          final aliases = <String>[];
          for (final candidate in ['127.0.0.1:$adbPort', 'localhost:$adbPort']) {
            if (bySerial.containsKey(candidate)) {
              aliases.add(candidate);
              consumedAliases.add(candidate);
            }
          }
          if (aliases.isNotEmpty) {
            final altModel = aliases
                .map((a) => bySerial[a]?.model)
                .firstWhere((m) => m != null && m.isNotEmpty, orElse: () => null);
            merged.add(AdbDeviceRecord(
              serial: rec.serial,
              aliasSerials: aliases,
              state: rec.state,
              model: rec.model ?? altModel,
              product: rec.product,
              device: rec.device,
            ));
            continue;
          }
        }
      }
      merged.add(rec);
    }

    return merged;
  }

  /// Phân tích output của `adb -s <serial> shell getprop`
  static AdbGetpropSummary parseAndroidGetpropOutput(String rawOutput) {
    final props = <String, String>{};
    final propRegex = RegExp(r'^\[([^\]]+)\]:\s*\[(.*)\]$');

    for (final rawLine in rawOutput.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final m = propRegex.firstMatch(line);
      if (m != null) {
        props[m.group(1)!.trim()] = m.group(2)!.trim();
      }
    }

    String? nonEmpty(String? v) => (v != null && v.trim().isNotEmpty) ? v.trim() : null;

    final avdName = nonEmpty(props['ro.boot.qemu.avd_name']) ??
        nonEmpty(props['ro.kernel.qemu.avd_name']) ??
        nonEmpty(props['qemu.avd_name']);

    final manufacturer = nonEmpty(props['ro.product.manufacturer']);
    final model = nonEmpty(props['ro.product.model']);
    final hardware = (props['ro.hardware'] ?? '').toLowerCase();
    final board = (props['ro.product.board'] ?? '').toLowerCase();
    final characteristics = (props['ro.build.characteristics'] ?? '').toLowerCase();
    final qemu = props['ro.kernel.qemu'] ?? '';

    final hasLdOrVboxProps = props.keys.any((k) =>
        k.startsWith('ro.ld.') ||
        k.startsWith('persist.vbox86.') ||
        k.contains('vbox') ||
        k.contains('leidian') ||
        k.contains('ldplayer') ||
        k.contains('nox') ||
        k.contains('mumu'));

    final isThirdPartyEmu = avdName == null &&
        (hasLdOrVboxProps ||
            hardware.contains('vbox') ||
            hardware.contains('ttvm') ||
            hardware.contains('nox') ||
            hardware.contains('x86') ||
            board.contains('goldfish') ||
            characteristics.contains('emulator') ||
            qemu == '1');

    return AdbGetpropSummary(
      qemuAvdName: avdName,
      manufacturer: manufacturer,
      model: model,
      isThirdPartyEmulator: isThirdPartyEmu,
    );
  }

  /// Hợp nhất danh sách máy ảo từ 3 nguồn:
  /// 1. Giả lập LDPlayer cài trên máy (cả đang chạy lẫn đang tắt)
  /// 2. Thiết bị / Giả lập đang kết nối trong danh sách thiết bị của Android Studio (ADB)
  /// 3. Máy ảo Android Studio AVD truyền thống (~/.android/avd)
  static List<VirtualDeviceOption> mergeVirtualDeviceCatalog({
    required List<String> standardAvds,
    required List<LdPlayerInstance> ldPlayerInstances,
    required List<AdbDeviceRecord> adbDevices,
    required Map<String, AdbGetpropSummary> adbPropsBySerial,
  }) {
    final result = <VirtualDeviceOption>[];
    final consumedAdbSerials = <String>{};
    final runningAvdSerialMap = <String, String>{};

    // 1. Xác định những ADB serial nào thuộc về máy ảo Android Studio AVD chuẩn đang mở
    for (final adbDev in adbDevices) {
      final prop = adbPropsBySerial[adbDev.serial];
      final avdName = prop?.qemuAvdName;
      if (avdName != null && avdName.isNotEmpty) {
        runningAvdSerialMap[avdName] = adbDev.serial;
        consumedAdbSerials.add(adbDev.serial);
        consumedAdbSerials.addAll(adbDev.aliasSerials);
      }
    }

    // 2. Đưa danh sách giả lập LDPlayer lên đầu để dễ chọn và gắn vào nhân vật
    for (final ld in ldPlayerInstances) {
      final expectedEmuSerial = ldPlayerEmulatorSerial(ld.index);
      final expectedTcpSerial = ldPlayerTcpSerial(ld.index);

      AdbDeviceRecord? matchedAdb;
      for (final adbDev in adbDevices) {
        if (consumedAdbSerials.contains(adbDev.serial)) continue;
        if (adbDev.matchesSerial(expectedEmuSerial) || adbDev.matchesSerial(expectedTcpSerial)) {
          matchedAdb = adbDev;
          break;
        }
      }

      if (matchedAdb != null) {
        consumedAdbSerials.add(matchedAdb.serial);
        consumedAdbSerials.addAll(matchedAdb.aliasSerials);
      }

      final prop = matchedAdb != null ? adbPropsBySerial[matchedAdb.serial] : null;
      final resolvedModel = ld.model ??
          prop?.model ??
          matchedAdb?.model;

      result.add(VirtualDeviceOption(
        id: buildLdPlayerId(ld.index),
        name: ld.name,
        kind: VirtualDeviceKind.ldPlayer,
        isRunning: ld.isRunning || matchedAdb != null,
        adbSerial: matchedAdb?.serial ?? (ld.isRunning ? expectedEmuSerial : null),
        ldIndex: ld.index,
        model: resolvedModel,
        isThirdPartyEmulator: true,
      ));
    }

    // 3. Bổ sung mọi giả lập / thiết bị đang chạy trong Android Studio ADB mà chưa nằm trong ldconsole hay AVD
    // (Ví dụ: LDPlayer kết nối qua ADB mạng LAN/port tùy chỉnh, hoặc cài ở thư mục riêng biệt)
    for (final adbDev in adbDevices) {
      if (consumedAdbSerials.contains(adbDev.serial)) continue;

      final prop = adbPropsBySerial[adbDev.serial];
      final mfg = prop?.manufacturer ?? '';
      final mdl = prop?.model ?? adbDev.model ?? '';
      String friendlyName;
      if (mfg.isNotEmpty && mdl.isNotEmpty && !mdl.toLowerCase().startsWith(mfg.toLowerCase())) {
        friendlyName = '$mfg $mdl';
      } else if (mdl.isNotEmpty) {
        friendlyName = mdl;
      } else if (adbDev.product != null && adbDev.product!.isNotEmpty) {
        friendlyName = adbDev.product!;
      } else {
        friendlyName = adbDev.serial;
      }

      final isEmuSerial = adbDev.serial.startsWith('emulator-') ||
          adbDev.serial.startsWith('127.0.0.1:') ||
          adbDev.serial.startsWith('localhost:');

      result.add(VirtualDeviceOption(
        id: buildAdbConnectedId(adbDev.serial),
        name: friendlyName,
        kind: VirtualDeviceKind.adbConnected,
        isRunning: true,
        adbSerial: adbDev.serial,
        model: mdl.isNotEmpty ? mdl : null,
        isThirdPartyEmulator: (prop?.isThirdPartyEmulator ?? false) || isEmuSerial,
      ));
    }

    // 4. Bổ sung danh sách máy ảo Android Studio AVD truyền thống
    final sortedAvds = List<String>.from(standardAvds)..sort();
    for (final avd in sortedAvds) {
      final runningSerial = runningAvdSerialMap[avd];
      result.add(VirtualDeviceOption(
        id: avd,
        name: avd,
        kind: VirtualDeviceKind.androidAvd,
        isRunning: runningSerial != null,
        adbSerial: runningSerial,
      ));
    }

    return result;
  }
}

/// Dịch vụ phát hiện và điều khiển giả lập LDPlayer trên hệ điều hành
class LdPlayerService {
  static final LdPlayerService _instance = LdPlayerService._internal();
  factory LdPlayerService() => _instance;
  LdPlayerService._internal();

  LdPlayerInstallInfo? _cachedInstall;

  /// Giải mã đầu ra process an toàn, tránh lỗi FormatException trên Windows codepage
  static String _decodeProcessBytes(Object? raw) {
    if (raw == null) return '';
    if (raw is String) return raw;
    if (raw is List<int>) {
      return utf8.decode(raw, allowMalformed: true);
    }
    return raw.toString();
  }

  /// Tìm thông tin cài đặt LDPlayer trên máy tính (hỗ trợ LDPlayer 9, LDPlayer 5, LDPlayer 4, LDPlayer 3)
  Future<LdPlayerInstallInfo?> findInstallation({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedInstall != null) {
      if (File(_cachedInstall!.consolePath).existsSync()) {
        return _cachedInstall;
      }
      _cachedInstall = null;
    }

    // 1. Kiểm tra biến môi trường tùy chỉnh (hỗ trợ cả Windows hoặc cấu hình thủ công)
    for (final envKey in ['LDPLAYER_HOME', 'LDPLAYER_DIR']) {
      final envDir = Platform.environment[envKey];
      if (envDir != null && envDir.trim().isNotEmpty) {
        final resolved = _probeInstallDir(envDir.trim());
        if (resolved != null) {
          _cachedInstall = resolved;
          return resolved;
        }
      }
    }

    if (!Platform.isWindows) {
      return null;
    }

    // 2. Truy vấn Windows Registry chính thức của XuanZhi / LeiDian (nhanh, chính xác cả InstallDir & DataDir, không bị chặn bởi UAC Admin)
    final regKeys = [
      r'HKCU\Software\XuanZhi\LDPlayer9',
      r'HKCU\Software\XuanZhi\LDPlayer64',
      r'HKCU\Software\XuanZhi\LDPlayer',
      r'HKCU\Software\leidian\ldplayer9',
      r'HKCU\Software\leidian\ldplayer64',
      r'HKCU\Software\leidian\ldplayer',
      r'HKLM\SOFTWARE\XuanZhi\LDPlayer9',
      r'HKLM\SOFTWARE\WOW6432Node\XuanZhi\LDPlayer9',
      r'HKLM\SOFTWARE\XuanZhi\LDPlayer64',
      r'HKLM\SOFTWARE\WOW6432Node\XuanZhi\LDPlayer64',
      r'HKLM\SOFTWARE\XuanZhi\LDPlayer',
      r'HKLM\SOFTWARE\WOW6432Node\XuanZhi\LDPlayer',
    ];

    for (final key in regKeys) {
      final regInfo = await _queryRegistryInstall(key);
      if (regInfo != null) {
        _cachedInstall = regInfo;
        return regInfo;
      }
    }

    // 3. Quét các đường dẫn cài đặt phổ biến trên các ổ đĩa C..H
    final drives = ['C', 'D', 'E', 'F', 'G', 'H'];
    final subPaths = [
      r'LDPlayer\LDPlayer9',
      r'LDPlayer\LDPlayer64',
      r'LDPlayer\LDPlayer4.0',
      r'LDPlayer\LDPlayer3.0',
      r'LDPlayer9',
      r'XuanZhi\LDPlayer9',
      r'XuanZhi\LDPlayer',
      r'ChangZhi\dnplayer2',
      r'Program Files\LDPlayer\LDPlayer9',
      r'Program Files\LDPlayer\LDPlayer4.0',
      r'Program Files (x86)\LDPlayer\LDPlayer9',
      r'Program Files (x86)\LDPlayer\LDPlayer4.0',
    ];

    for (final d in drives) {
      if (!Directory('$d:\\').existsSync()) continue;
      for (final sub in subPaths) {
        final resolved = _probeInstallDir('$d:\\$sub');
        if (resolved != null) {
          _cachedInstall = resolved;
          return resolved;
        }
      }
    }

    // 4. Kiểm tra tiến trình LDPlayer đang chạy thực tế trên Windows (fallback cho thư mục portable bất kỳ)
    try {
      final psRes = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          'Get-CimInstance Win32_Process -Filter "Name=\'dnplayer.exe\' OR Name=\'dnmultiplayer.exe\' OR Name=\'Ld9BoxHeadless.exe\' OR Name=\'LdVBoxHeadless.exe\'" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ExecutablePath',
        ],
        stdoutEncoding: null,
        stderrEncoding: null,
      ).timeout(const Duration(seconds: 3));

      final psOut = _decodeProcessBytes(psRes.stdout);
      for (final rawLine in psOut.split(RegExp(r'\r?\n'))) {
        final exePath = rawLine.trim();
        if (exePath.isEmpty) continue;
        final dir = p.dirname(exePath);
        final resolved = _probeInstallDir(dir) ?? _probeInstallDir(p.dirname(dir));
        if (resolved != null) {
          final dataDir = await _queryRegistryDataDirForInstall(resolved.installDir);
          _cachedInstall = dataDir != null
              ? LdPlayerInstallInfo(
                  installDir: resolved.installDir,
                  consolePath: resolved.consolePath,
                  dataDir: dataDir,
                )
              : resolved;
          return _cachedInstall;
        }
      }
    } catch (_) {}

    return null;
  }

  LdPlayerInstallInfo? _probeInstallDir(String dirPath) {
    final cleanDir = dirPath.trim().replaceAll('"', '');
    if (cleanDir.isEmpty || !Directory(cleanDir).existsSync()) return null;

    for (final bin in ['ldconsole.exe', 'dnconsole.exe', 'ldconsole']) {
      final consoleFile = File(p.join(cleanDir, bin));
      if (consoleFile.existsSync()) {
        return LdPlayerInstallInfo(
          installDir: cleanDir,
          consolePath: consoleFile.path,
        );
      }
    }
    return null;
  }

  Future<LdPlayerInstallInfo?> _queryRegistryInstall(String regKey) async {
    try {
      final res = await Process.run(
        'reg',
        ['query', regKey],
        stdoutEncoding: null,
        stderrEncoding: null,
      ).timeout(const Duration(seconds: 2));
      if (res.exitCode != 0) return null;

      final out = _decodeProcessBytes(res.stdout);
      String? installDir;
      String? dataDir;

      for (final rawLine in out.split(RegExp(r'\r?\n'))) {
        final line = rawLine.trim();
        final m = RegExp(r'^(InstallDir|DataDir)\s+REG_\w+\s+(.+)$', caseSensitive: false).firstMatch(line);
        if (m != null) {
          final name = m.group(1)!.toLowerCase();
          final val = m.group(2)!.trim();
          if (name == 'installdir') installDir = val;
          if (name == 'datadir') dataDir = val;
        }
      }

      if (installDir != null && installDir.isNotEmpty) {
        final probed = _probeInstallDir(installDir);
        if (probed != null) {
          return LdPlayerInstallInfo(
            installDir: probed.installDir,
            consolePath: probed.consolePath,
            dataDir: dataDir,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _queryRegistryDataDirForInstall(String installDir) async {
    final keys = [
      r'HKCU\Software\XuanZhi\LDPlayer9',
      r'HKCU\Software\XuanZhi\LDPlayer64',
      r'HKCU\Software\XuanZhi\LDPlayer',
    ];
    for (final k in keys) {
      final info = await _queryRegistryInstall(k);
      if (info != null &&
          p.equals(info.installDir.toLowerCase(), installDir.toLowerCase()) &&
          info.dataDir != null) {
        return info.dataDir;
      }
    }
    return null;
  }

  /// Đọc map cấu hình `leidian<index>.config` hiện tại của LDPlayer
  Map<int, LdPlayerVmConfig> loadVmConfigs(LdPlayerInstallInfo install) {
    final merged = <int, LdPlayerVmConfig>{};
    final vmsDir = install.primaryVmsDir;
    for (final cfgDir in install.candidateConfigDirs) {
      final map = LdPlayerAdbParser.readLdPlayerConfigsFromDir(cfgDir, vmsDir: vmsDir);
      for (final entry in map.entries) {
        merged.putIfAbsent(entry.key, () => entry.value);
      }
    }
    return merged;
  }

  /// Liệt kê đầy đủ toàn bộ các giả lập LDPlayer (cả đang bật lẫn đang tắt)
  Future<List<LdPlayerInstance>> discoverInstances({bool forceRefresh = false}) async {
    final install = await findInstallation(forceRefresh: forceRefresh);
    if (install == null) return const [];

    final configs = loadVmConfigs(install);
    String list2Out = '';
    bool list2Succeeded = false;

    try {
      final res = await Process.run(
        install.consolePath,
        ['list2'],
        workingDirectory: install.installDir,
        stdoutEncoding: null,
        stderrEncoding: null,
      ).timeout(const Duration(seconds: 4));
      if (res.exitCode == 0) {
        list2Out = _decodeProcessBytes(res.stdout);
        list2Succeeded = list2Out.trim().isNotEmpty;
      }
    } catch (e) {
      debugPrint('[LDPlayer] Lỗi gọi ldconsole list2: $e');
    }

    return LdPlayerAdbParser.parseLdConsoleList2Output(
      list2Out,
      configsByIndex: configs,
      includeConfigOnlyFallbacks: !list2Succeeded,
    );
  }

  /// Truy vấn trực tiếp trạng thái đang chạy thực tế từ `ldconsole list2`.
  /// Trả về `null` nếu không gọi được `ldconsole` (ví dụ vướng quyền UAC) để tránh báo tắt nhầm từ dữ liệu file config tĩnh.
  Future<List<LdPlayerInstance>?> queryLiveInstancesFromConsole() async {
    final install = await findInstallation();
    if (install == null) return null;

    try {
      final res = await Process.run(
        install.consolePath,
        ['list2'],
        workingDirectory: install.installDir,
        stdoutEncoding: null,
        stderrEncoding: null,
      ).timeout(const Duration(seconds: 3));
      if (res.exitCode == 0) {
        final list2Out = _decodeProcessBytes(res.stdout);
        if (list2Out.trim().isNotEmpty) {
          return LdPlayerAdbParser.parseLdConsoleList2Output(
            list2Out,
            includeConfigOnlyFallbacks: false,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// Tự động đảm bảo giả lập LDPlayer tại `index` đã bật cổng kết nối ADB cục bộ (`adbDebug = 1`)
  Future<void> ensureAdbEnabledForVm(int index) async {
    final install = await findInstallation();
    if (install == null) return;

    final configs = loadVmConfigs(install);
    final cfg = configs[index];
    if (cfg != null && (cfg.adbDebug == null || cfg.adbDebug == 0)) {
      if (cfg.configFilePath != null) {
        try {
          final file = File(cfg.configFilePath!);
          if (file.existsSync()) {
            final raw = utf8.decode(file.readAsBytesSync(), allowMalformed: true);
            final decoded = jsonDecode(raw);
            if (decoded is Map<String, dynamic>) {
              decoded['basicSettings.adbDebug'] = 1;
              file.writeAsStringSync(const JsonEncoder.withIndent('    ').convert(decoded));
            }
          }
        } catch (_) {}
      }
      try {
        await Process.run(
          install.consolePath,
          ['modify', '--index', index.toString(), '--adb', '1'],
          workingDirectory: install.installDir,
          stdoutEncoding: null,
          stderrEncoding: null,
        ).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
  }

  /// Khởi chạy một giả lập LDPlayer theo `index` nếu chưa chạy
  Future<bool> launchVm(int index) async {
    final install = await findInstallation();
    if (install == null) return false;

    await ensureAdbEnabledForVm(index);

    try {
      final res = await Process.run(
        install.consolePath,
        ['launch', '--index', index.toString()],
        workingDirectory: install.installDir,
        stdoutEncoding: null,
        stderrEncoding: null,
      ).timeout(const Duration(seconds: 6));
      if (res.exitCode == 0) return true;
    } catch (e) {
      debugPrint('[LDPlayer] Gọi trực tiếp ldconsole launch gặp lỗi (thử fallback UAC shell): $e');
    }

    if (Platform.isWindows) {
      try {
        final shellRes = await Process.run(
          'cmd',
          ['/c', 'start', '', install.consolePath, 'launch', '--index', index.toString()],
          workingDirectory: install.installDir,
          stdoutEncoding: null,
          stderrEncoding: null,
        ).timeout(const Duration(seconds: 6));
        return shellRes.exitCode == 0;
      } catch (e) {
        debugPrint('[LDPlayer] Không thể khởi chạy LDPlayer index $index: $e');
      }
    }
    return false;
  }

  /// Đóng an toàn một giả lập LDPlayer theo `index`
  Future<bool> quitVm(int index) async {
    final install = await findInstallation();
    if (install == null) return false;

    try {
      final res = await Process.run(
        install.consolePath,
        ['quit', '--index', index.toString()],
        workingDirectory: install.installDir,
        stdoutEncoding: null,
        stderrEncoding: null,
      ).timeout(const Duration(seconds: 5));
      if (res.exitCode == 0) return true;
    } catch (_) {}

    if (Platform.isWindows) {
      try {
        final shellRes = await Process.run(
          'cmd',
          ['/c', 'start', '', install.consolePath, 'quit', '--index', index.toString()],
          workingDirectory: install.installDir,
          stdoutEncoding: null,
          stderrEncoding: null,
        ).timeout(const Duration(seconds: 5));
        return shellRes.exitCode == 0;
      } catch (_) {}
    }
    return false;
  }
}
