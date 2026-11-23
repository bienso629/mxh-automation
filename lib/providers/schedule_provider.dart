import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../core/services/adb_manager_service.dart';
import '../core/services/cli_automation_bridge_service.dart';
import '../core/services/database_service.dart';
import '../core/services/local_config_service.dart';
import '../core/services/native_ai_service.dart';
import '../core/services/persona_service.dart';
import '../core/services/socks5_proxy_service.dart';
import '../core/services/storage_service.dart';
import '../core/services/task_notification_service.dart';
import '../models/persona_profile_model.dart';
import '../models/schedule_task_model.dart';
import '../models/server_model.dart';

typedef ScheduleBrowserLauncher = Future<bool> Function(
  PersonaProfile persona,
  ScheduleTaskModel task,
  ServerModel? server,
);

typedef ScheduleDeviceTaskRunner = Future<void> Function(
  PersonaProfile persona,
  ScheduleTaskModel task,
  ServerModel? server,
);

typedef ScheduleAiTaskRunner = Future<AiTaskExecutionResult> Function({
  required PersonaProfile persona,
  required ScheduleTaskModel task,
  required ServerModel? server,
  required String prompt,
  required String scopeWorkingDir,
  required void Function(String status) onStatus,
  required bool Function() isCancelled,
});

class _ResourceWaiter {
  final int taskId;
  final Completer<bool> completer = Completer<bool>();
  bool cancelled = false;
  _ResourceWaiter(this.taskId);
}

class _ResourceLease {
  final int taskId;
  final List<String> keys;
  _ResourceLease({required this.taskId, required this.keys});
}

/// Hàng đợi khóa tài nguyên theo từng profile / thiết bị (FIFO, sắp xếp khóa theo thứ tự từ điển để chống deadlock).
/// Đảm bảo dù người dùng bấm tay `Chạy ngay` nhiều tác vụ cùng lúc hay bộ lập lịch kích hoạt nhiều tác vụ trùng giờ,
/// các tác vụ cùng profile / cùng máy ảo / cùng thiết bị ngoại vi sẽ luôn xếp hàng chạy LẦN LƯỢT, không xung đột.
class _ScheduleResourceQueue {
  final Map<String, int> _heldByTask = {};
  final Map<String, List<_ResourceWaiter>> _waiters = {};

  Future<_ResourceLease?> acquire(
    int taskId,
    List<String> rawKeys, {
    VoidCallback? onWaiting,
    required bool Function() isCancelled,
  }) async {
    final sortedKeys = rawKeys.toSet().toList()..sort();
    final acquired = <String>[];
    bool notifiedWaiting = false;

    for (final key in sortedKeys) {
      if (isCancelled()) {
        _releaseList(acquired, taskId);
        return null;
      }

      if (!_heldByTask.containsKey(key)) {
        _heldByTask[key] = taskId;
        acquired.add(key);
        continue;
      }

      final waiter = _ResourceWaiter(taskId);
      _waiters.putIfAbsent(key, () => []).add(waiter);
      if (!notifiedWaiting) {
        notifiedWaiting = true;
        onWaiting?.call();
      }

      final granted = await waiter.completer.future;
      if (!granted || waiter.cancelled || isCancelled()) {
        if (granted) {
          _releaseSingle(key, taskId);
        }
        _releaseList(acquired, taskId);
        return null;
      }
      acquired.add(key);
    }

    return _ResourceLease(taskId: taskId, keys: acquired);
  }

  bool hasWaitingTaskForAny(List<String> keys) {
    for (final k in keys) {
      final q = _waiters[k];
      if (q != null && q.any((w) => !w.cancelled && !w.completer.isCompleted)) {
        return true;
      }
    }
    return false;
  }

  void release(_ResourceLease lease) {
    _releaseList(lease.keys, lease.taskId);
  }

  void _releaseList(List<String> keys, int ownerTaskId) {
    for (int i = keys.length - 1; i >= 0; i--) {
      _releaseSingle(keys[i], ownerTaskId);
    }
  }

  void _releaseSingle(String key, int ownerTaskId) {
    if (_heldByTask[key] != ownerTaskId) return;
    final queue = _waiters[key];
    if (queue != null) {
      while (queue.isNotEmpty) {
        final next = queue.removeAt(0);
        if (next.cancelled || next.completer.isCompleted) continue;
        _heldByTask[key] = next.taskId;
        next.completer.complete(true);
        if (queue.isEmpty) {
          _waiters.remove(key);
        }
        return;
      }
      _waiters.remove(key);
    }
    _heldByTask.remove(key);
  }

  void cancelWaitersForTask(int taskId) {
    final emptyKeys = <String>[];
    _waiters.forEach((key, queue) {
      for (final w in queue) {
        if (w.taskId == taskId) {
          w.cancelled = true;
          if (!w.completer.isCompleted) {
            w.completer.complete(false);
          }
        }
      }
      queue.removeWhere((w) => w.cancelled);
      if (queue.isEmpty) emptyKeys.add(key);
    });
    for (final k in emptyKeys) {
      _waiters.remove(k);
    }
  }

  void clearAll() {
    for (final queue in _waiters.values) {
      for (final w in queue) {
        w.cancelled = true;
        if (!w.completer.isCompleted) {
          w.completer.complete(false);
        }
      }
    }
    _waiters.clear();
    _heldByTask.clear();
  }
}

/// Semaphore giới hạn số lượng thiết bị Android chạy đồng thời trên toàn bộ bộ lập lịch (mặc định 2 thiết bị)
class _DeviceSlotSemaphore {
  int _inUse = 0;
  final List<_ResourceWaiter> _waiters = [];

  Future<bool> acquire(
    int taskId,
    int maxSlots, {
    VoidCallback? onWaiting,
    required bool Function() isCancelled,
  }) async {
    final cap = maxSlots < 1 ? 1 : maxSlots;
    if (isCancelled()) return false;
    if (_inUse < cap) {
      _inUse++;
      return true;
    }

    final waiter = _ResourceWaiter(taskId);
    _waiters.add(waiter);
    onWaiting?.call();

    final granted = await waiter.completer.future;
    if (!granted || waiter.cancelled || isCancelled()) {
      if (granted) {
        release();
      }
      return false;
    }
    return true;
  }

  void release() {
    while (_waiters.isNotEmpty) {
      final next = _waiters.removeAt(0);
      if (next.cancelled || next.completer.isCompleted) continue;
      next.completer.complete(true);
      return;
    }
    if (_inUse > 0) _inUse--;
  }

  void cancelWaitersForTask(int taskId) {
    for (final w in _waiters) {
      if (w.taskId == taskId) {
        w.cancelled = true;
        if (!w.completer.isCompleted) {
          w.completer.complete(false);
        }
      }
    }
    _waiters.removeWhere((w) => w.cancelled);
  }

  void clearAll() {
    for (final w in _waiters) {
      w.cancelled = true;
      if (!w.completer.isCompleted) {
        w.completer.complete(false);
      }
    }
    _waiters.clear();
    _inUse = 0;
  }
}

class ScheduleProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  final LocalConfigService _configService = LocalConfigService();
  final PersonaService _personaService = PersonaService();
  final Socks5ProxyService _socks5Service = Socks5ProxyService();
  final TaskNotificationService _notifyService = TaskNotificationService();
  final NativeAiService _nativeAiService = NativeAiService();
  final AdbManagerService _adbManagerService = AdbManagerService();
  final _ScheduleResourceQueue _resourceQueue = _ScheduleResourceQueue();
  final _DeviceSlotSemaphore _deviceSlotSemaphore = _DeviceSlotSemaphore();

  /// Hook tùy chọn phục vụ kiểm thử đơn vị mà không cần khởi chạy Chrome / Emulator / AI API thật
  ScheduleBrowserLauncher? browserLauncherOverride;
  ScheduleDeviceTaskRunner? deviceTaskRunnerOverride;
  ScheduleAiTaskRunner? aiTaskRunnerOverride;
  Future<ServerModel?> Function()? serverResolverOverride;
  Future<Map<String, PersonaProfile>> Function()? personasLoaderOverride;
  int? maxConcurrentDeviceSlotsOverride;
  Duration perPersonaBrowserTimeout = const Duration(minutes: 5);
  Duration perPersonaDeviceTimeout = const Duration(minutes: 6);
  Duration stuckRunningThreshold = const Duration(minutes: 30);

  /// Thời gian chờ tăng dần (backoff) giữa các lần tự động thử lại: 2 phút -> 5 phút -> 10 phút
  List<Duration> retryBackoffSteps = const [
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
  ];

  List<ScheduleTaskModel> _tasks = [];
  bool _isLoading = false;
  bool _isCheckingDueTasks = false;
  DateTime _selectedDate = DateTime.now();
  String _filterType = 'all'; // 'all' | 'like' | 'comment' | 'livestream' | 'post'
  String _filterStatus = 'all'; // 'all' | 'pending' | 'running' | 'retrying' | 'partial' | 'completed' | 'failed'
  Timer? _schedulerTimer;

  final Set<int> _activeTaskIds = {};
  final Set<int> _queuedTaskIds = {};
  final Set<int> _cancelledTaskIds = {};

  List<ScheduleTaskModel> get tasks => _tasks;
  bool get isLoading => _isLoading;
  DateTime get selectedDate => _selectedDate;
  String get filterType => _filterType;
  String get filterStatus => _filterStatus;

  /// Danh sách các task gặp sự cố / chưa xong 100% cần chú ý hoặc chạy tiếp
  List<ScheduleTaskModel> get attentionTasks => _tasks.where((t) => t.needsAttention).toList();

  ScheduleTaskModel? getTaskById(int? id) {
    if (id == null) return null;
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  bool isTaskActivelyRunning(int? id) => id != null && _activeTaskIds.contains(id);

  /// Trả về true nếu tác vụ đang xếp hàng chờ profile / thiết bị / slot rảnh
  bool isTaskQueuedForResource(int? id) => id != null && _queuedTaskIds.contains(id);

  /// Tính danh sách khóa tài nguyên cần khóa độc quyền cho một (nhân vật, chế độ thực thi)
  static List<String> resourceLockKeysForPersona(PersonaProfile persona, String executionMode) {
    final keys = <String>['persona:${persona.effectiveEntryKey}'];
    if (executionMode == 'device') {
      final extAddr = persona.externalDeviceAddress?.trim() ?? '';
      final avd = persona.avdName?.trim() ?? '';
      if (persona.useExternalDevice && extAddr.isNotEmpty) {
        keys.add('device_ext:${extAddr.toLowerCase()}');
      } else if (avd.isNotEmpty) {
        keys.add('device_avd:${avd.toLowerCase()}');
      } else {
        keys.add('device_default:${persona.effectiveEntryKey}');
      }
    } else {
      final sysBrowserProfile = persona.browserProfileId?.trim() ?? '';
      if (sysBrowserProfile.isNotEmpty) {
        keys.add('browser_sys:${sysBrowserProfile.toLowerCase()}');
      }
    }
    keys.sort();
    return keys;
  }

  /// Tạo ngữ cảnh Scope chặt chẽ cho đúng 1 nhân vật và chế độ thực thi (Thiết bị hoặc Trình duyệt)
  static String buildPersonaScopeWorkingDir(
    PersonaProfile persona,
    String executionMode, {
    String? adbSerial,
    String? adbPath,
  }) {
    final isDevice = executionMode == 'device';
    final buf = StringBuffer();
    buf.writeln('=== DANH SÁCH NHÂN VẬT ĐƯỢC CHỈ ĐỊNH (SCOPE PERSONAS) ===');
    buf.writeln(
      '- ProfileKey: ${persona.effectiveEntryKey} | IP: ${persona.ip} | Họ tên: ${persona.name} '
      '| Tuổi: ${persona.age} | Giới tính: ${persona.gender} | Bio: ${persona.bio}',
    );
    if (isDevice) {
      if (persona.useExternalDevice && (persona.externalDeviceAddress?.trim().isNotEmpty ?? false)) {
        buf.writeln('  Thiết bị ngoại vi (ADB): ${persona.externalDeviceAddress!.trim()}');
      } else if (persona.avdName?.trim().isNotEmpty ?? false) {
        buf.writeln('  Máy ảo Android (AVD): ${persona.avdName!.trim()} (loại: ${persona.deviceType})');
      }
      if (adbSerial != null && adbSerial.trim().isNotEmpty) {
        buf.writeln('  ADB Serial đang chạy sẵn: ${adbSerial.trim()}');
      }
      if (adbPath != null && adbPath.trim().isNotEmpty) {
        buf.writeln('  Đường dẫn ADB: ${adbPath.trim()}');
      }
      buf.writeln('');
      buf.writeln('[YÊU CẦU MÔI TRƯỜNG THỰC THI: THIẾT BỊ / DEVICE / AVD / ANDROID]');
      buf.writeln('- BẮT BUỘC thực hiện tác vụ trên thiết bị di động / máy ảo Android bằng `mxh-tool ui-dump`, `mxh-tool adb-tap`, `mxh-tool adb-type`, `mxh-tool adb-screenshot` hoặc `adb` / `execute_adb_command`.');
      buf.writeln('- TUYỆT ĐỐI KHÔNG gọi `open_profile_browser` hay bất kỳ công cụ trình duyệt desktop nào.');
    } else {
      buf.writeln('');
      buf.writeln('[YÊU CẦU MÔI TRƯỜNG THỰC THI: TRÌNH DUYỆT / BROWSER]');
      buf.writeln('- BẮT BUỘC thực hiện tác vụ trên trình duyệt cô lập của nhân vật bằng `open_profile_browser`, `browser_navigate`, `browser_snapshot`, `browser_click`, `browser_type`, `browser_press_key`, `browser_wait`, `browser_screenshot` hoặc CDP.');
      buf.writeln('- TUYỆT ĐỐI KHÔNG gọi `open_profile_device`.');
    }
    return buf.toString().trim();
  }

  static String _detectPlatformLabel(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('facebook.com') || lower.contains('fb.watch') || lower.contains('fb.com')) {
      return 'Facebook';
    }
    if (lower.contains('tiktok.com')) return 'TikTok';
    if (lower.contains('youtube.com') || lower.contains('youtu.be')) return 'YouTube';
    if (lower.contains('instagram.com')) return 'Instagram';
    return 'MXH';
  }

  /// Xây dựng câu lệnh đầy đủ, rõ ràng từng bước và yêu cầu kiểm chứng 100% cho AI Agent (cả Proxy LLM và Local CLI Agent)
  static String buildScheduledTaskPrompt(
    ScheduleTaskModel task,
    PersonaProfile persona, {
    String? adbSerial,
    String? adbPath,
    String? mxhToolPath,
  }) {
    final isDevice = task.executionMode == 'device';
    final platform = _detectPlatformLabel(task.targetUrl);
    final commentText = task.commentContent?.trim() ?? '';
    final envLabel = isDevice ? 'THIẾT BỊ ANDROID (ADB/AVD)' : 'TRÌNH DUYỆT CÔ LẬP (CDP)';
    final serialHint = (adbSerial != null && adbSerial.trim().isNotEmpty) ? adbSerial.trim() : '<ADB_SERIAL>';
    final adbCmd = (adbPath != null && adbPath.trim().isNotEmpty) ? adbPath.trim() : 'adb';
    final toolCmd = (mxhToolPath != null && mxhToolPath.trim().isNotEmpty) ? mxhToolPath.trim() : 'mxh-tool';

    final buf = StringBuffer();
    buf.writeln('THỰC THI TÁC VỤ LỊCH TRÌNH HẸN GIỜ (BẮT BUỘC THAO TÁC THẬT VÀ KIỂM CHỨNG 100% TRÊN GIAO DIỆN)');
    buf.writeln('- Tiêu đề tác vụ: ${task.title}');
    buf.writeln('- Nhân vật thực thi (duy nhất): ${persona.name} (ProfileKey: ${persona.effectiveEntryKey})');
    buf.writeln('- Môi trường bắt buộc: $envLabel');
    buf.writeln('- Nền tảng mục tiêu: $platform');
    buf.writeln('- Đường dẫn mục tiêu: ${task.targetUrl}');
    if (isDevice) {
      buf.writeln('- Thiết bị Android ĐÃ ĐƯỢC KHỞI CHẠY SẴN: ADB serial = `$serialHint` (lệnh ADB: `$adbCmd -s $serialHint ...`)');
      buf.writeln('- Công cụ đọc & điều khiển UI thật: `$toolCmd ui-dump --serial $serialHint`, `$toolCmd adb-tap --serial $serialHint ...`, `$toolCmd adb-type --serial $serialHint --text "..."`, `$toolCmd adb-screenshot --serial $serialHint --out /tmp/mxh_verify.png`');
    }
    if (commentText.isNotEmpty) {
      buf.writeln('- Nội dung văn bản bắt buộc cần đăng / bình luận: "$commentText"');
    }
    buf.writeln('');
    buf.writeln('NGUYÊN TẮC CẤM BÁO XONG GIẢ (CỰC KỲ QUAN TRỌNG):');
    buf.writeln('- TUYỆT ĐỐI KHÔNG chỉ mở link rồi kết luận xong.');
    buf.writeln('- TUYỆT ĐỐI KHÔNG dùng `fast-action` / `fast_social_action` rồi tin là đã thành công mà không đọc lại UI thực tế.');
    buf.writeln('- Trước khi chạm/bấm BẤT KỲ nút nào trên Android: BẮT BUỘC chạy `ui-dump` (và `adb-screenshot` nếu cần xem hình trực quan) để thấy đúng vị trí nút thật và kiểm tra xem có màn hình đăng nhập/checkpoint/popup chặn không.');
    buf.writeln('- Nếu gặp màn hình yêu cầu đăng nhập Facebook/TikTok, checkpoint, nội dung không khả dụng hoặc không thể thực hiện sau khi thử phương án thay thế: BẮT BUỘC báo thất bại (`FAILED` / `status="failed"`) kèm lý do thật, TUYỆT ĐỐI KHÔNG báo `COMPLETED` giả.');
    buf.writeln('');
    buf.writeln('CÁC BƯỚC THỰC HIỆN CỤ THỂ:');

    switch (task.taskType) {
      case 'like':
        if (isDevice) {
          buf.writeln('1. Kiểm tra màn hình hiện tại trên `$serialHint` bằng `$toolCmd ui-dump --serial $serialHint` (nếu app $platform chưa mở đúng link `${task.targetUrl}`, mở bằng `$adbCmd -s $serialHint shell am start -a android.intent.action.VIEW -d "${task.targetUrl}"` rồi chờ 5 giây và chạy lại `ui-dump`).');
          buf.writeln('2. Nếu xuất hiện hộp thoại chọn app / popup / quảng cáo che màn hình -> đọc tọa độ nút đóng/chọn app từ `ui-dump` và bấm bằng `adb-tap`. Nếu gặp màn hình đăng nhập/checkpoint -> dừng và báo FAILED ngay.');
          buf.writeln('3. Tìm đúng node nút Like / Thích / Thả tim / React trong kết quả `ui-dump` (xem `desc`, `text`, `cx`, `cy`, `selected`).');
          buf.writeln('   - Nếu nút đã ở trạng thái đã thích (`selected: true` hoặc nhãn `Đã thích`/`Bỏ thích`/`Unlike`), ghi nhận rõ bằng chứng này.');
          buf.writeln('   - Nếu chưa thích: bấm đúng tọa độ `(cx, cy)` bằng `$toolCmd adb-tap --serial $serialHint --x <cx> --y <cy>` (hoặc `--match`).');
          buf.writeln('4. KIỂM CHỨNG SAU KHI BẤM (BẮT BUỘC): Chờ 2-3 giây, chạy lại `$toolCmd ui-dump --serial $serialHint` (và có thể chụp `$toolCmd adb-screenshot --serial $serialHint --out /tmp/mxh_like_verify.png`) để xác nhận nút Like/Tim đã THỰC SỰ đổi sang trạng thái `selected: true` / `Đã thích` / `Unlike` hoặc số lượt thích tăng lên. Nếu chưa đổi trạng thái -> tìm lại tọa độ chính xác và bấm lại rồi kiểm chứng lại.');
        } else {
          buf.writeln('1. Mở trình duyệt của nhân vật ${persona.effectiveEntryKey} tới ${task.targetUrl} (`open_profile_browser` / `browser_navigate`).');
          buf.writeln('2. Gọi `browser_snapshot` kiểm tra trang đã tải và tài khoản đã đăng nhập (nếu yêu cầu đăng nhập/checkpoint thì báo `failed` ngay).');
          buf.writeln('3. Tìm nút Like / Thích / Thả tim -> bấm bằng `browser_click` -> `browser_wait` 2 giây.');
          buf.writeln('4. KIỂM CHỨNG BẮT BUỘC: Gọi `browser_snapshot` xác nhận nút đã đổi sang trạng thái đã thích (`Đã thích`, `Bỏ thích`, `Unlike`, `aria-pressed="true"`) và gọi `browser_screenshot` lưu bằng chứng.');
        }
        break;

      case 'comment':
        final commentDirective = commentText.isNotEmpty
            ? 'BẮT BUỘC nhập CHÍNH XÁC nguyên văn nội dung bình luận: "$commentText"'
            : 'Tự viết 1 bình luận ngắn gọn, tự nhiên bằng tiếng Việt phù hợp với nội dung bài viết/video và tính cách nhân vật ${persona.name} (${persona.age} tuổi, ${persona.gender})';
        if (isDevice) {
          buf.writeln('1. Kiểm tra màn hình hiện tại trên `$serialHint` bằng `$toolCmd ui-dump --serial $serialHint` (nếu app $platform chưa mở đúng link `${task.targetUrl}`, mở lại bằng `$adbCmd -s $serialHint shell am start -a android.intent.action.VIEW -d "${task.targetUrl}"`, chờ 5 giây rồi chạy `ui-dump`).');
          buf.writeln('2. Xử lý popup nếu có. Nếu gặp màn hình đăng nhập/checkpoint -> báo FAILED ngay.');
          buf.writeln('3. Tìm đúng node nút Bình luận / Comment trong `ui-dump` và bấm đúng tọa độ `(cx, cy)` bằng `$toolCmd adb-tap --serial $serialHint --x <cx> --y <cy>`. Chờ 2-3 giây rồi chạy `ui-dump` để thấy khung bình luận mở ra.');
          buf.writeln('4. Tìm node ô nhập bình luận (`editable: true` / `EditText` / `Viết bình luận` / `Write a comment`), bấm vào tọa độ `(cx, cy)` của nó rồi nhập chữ bằng `$toolCmd adb-type --serial $serialHint --text "..."` ($commentDirective).');
          buf.writeln('5. Chạy `ui-dump` kiểm tra ô `EditText` đã chứa đúng nội dung bình luận, sau đó tìm ĐÚNG node nút Gửi / Đăng (`Send` / `Gửi` / `Post` / `Đăng` — KHÔNG chỉ bấm Enter mù) và bấm vào `(cx, cy)` của nút Gửi.');
          buf.writeln('6. KIỂM CHỨNG SAU KHI GỬI (BẮT BUỘC): Chờ 4-5 giây, chạy lại `$toolCmd ui-dump --serial $serialHint` (và chụp `$toolCmd adb-screenshot --serial $serialHint --out /tmp/mxh_comment_verify.png` nếu cần) để xác nhận dòng bình luận vừa gửi ĐÃ HIỂN THỊ trong danh sách bình luận công khai (không còn kẹt trong `EditText`, không có thông báo lỗi).');
        } else {
          buf.writeln('1. Mở trình duyệt của nhân vật ${persona.effectiveEntryKey} tới ${task.targetUrl}.');
          buf.writeln('2. Gọi `browser_snapshot` kiểm tra trang đã tải và tài khoản đã đăng nhập.');
          buf.writeln('3. Tìm nút mở bình luận / ô nhập bình luận -> `browser_click` -> `browser_type` với yêu cầu: $commentDirective -> gửi bình luận (`browser_press_key` "Enter" hoặc bấm nút Gửi/Đăng).');
          buf.writeln('4. KIỂM CHỨNG BẮT BUỘC: Gọi `browser_wait` và `browser_snapshot` xác nhận bình luận vừa gửi đã hiển thị trong danh sách bình luận trên trang, sau đó gọi `browser_screenshot` lưu bằng chứng.');
        }
        break;

      case 'livestream':
        if (isDevice) {
          buf.writeln('1. Kiểm tra livestream `${task.targetUrl}` đang mở trên `$serialHint` bằng `$toolCmd ui-dump --serial $serialHint` (mở lại nếu cần).');
          buf.writeln('2. Đóng popup che màn hình nếu có, đảm bảo livestream đang phát ổn định và duy trì xem tối thiểu 45 giây.');
          if (commentText.isNotEmpty) {
            buf.writeln('3. Tìm ô chat livestream trong `ui-dump`, bấm vào, nhập "$commentText" bằng `$toolCmd adb-type`, bấm nút Gửi từ `ui-dump` và kiểm chứng bình luận đã hiện.');
          }
          buf.writeln('4. Chạy lại `$toolCmd ui-dump --serial $serialHint` xác nhận phiên xem livestream đã duy trì thành công.');
        } else {
          buf.writeln('1. Mở trình duyệt của nhân vật ${persona.effectiveEntryKey} tới livestream ${task.targetUrl}.');
          buf.writeln('2. Gọi `browser_snapshot`, bấm Play nếu video tạm dừng, đóng popup nếu có, dùng `browser_wait` duy trì xem ít nhất 45 giây.');
          if (commentText.isNotEmpty) {
            buf.writeln('3. Gửi bình luận tương tác "$commentText" vào khung chat livestream và kiểm chứng đã hiện.');
          }
          buf.writeln('4. Gọi `browser_snapshot` và `browser_screenshot` xác nhận hoàn thành.');
        }
        break;

      case 'post':
      default:
        final postBody = commentText.isNotEmpty ? commentText : task.title;
        if (isDevice) {
          buf.writeln('1. Kiểm tra trang/nhóm `${task.targetUrl}` trên `$serialHint` bằng `$toolCmd ui-dump --serial $serialHint`.');
          buf.writeln('2. Tìm nút tạo bài viết trong `ui-dump`, bấm vào, nhập nội dung "$postBody" bằng `$toolCmd adb-type`, bấm nút Đăng/Post theo tọa độ thật từ `ui-dump`.');
          buf.writeln('3. Chờ hoàn tất đăng bài và chạy lại `$toolCmd ui-dump --serial $serialHint` kiểm chứng bài viết đã xuất hiện.');
        } else {
          buf.writeln('1. Mở trình duyệt của nhân vật ${persona.effectiveEntryKey} tới ${task.targetUrl}.');
          buf.writeln('2. Gọi `browser_snapshot`, mở khung soạn bài viết ("Bạn đang nghĩ gì?" / "Tạo bài viết"), nhập nội dung "$postBody", bấm nút Đăng / Post.');
          buf.writeln('3. Chờ khung soạn bài đóng và bài viết xuất hiện trên trang (`browser_wait` + `browser_snapshot` + `browser_screenshot`).');
        }
        break;
    }

    buf.writeln('');
    buf.writeln('QUY TẮC BẮT BUỘC KHI KẾT THÚC:');
    if (isDevice) {
      buf.writeln('- KHÔNG đóng thiết bị (`close-device` / `close_profile_device`): hệ thống lập lịch sẽ tự giữ ấm cho tác vụ kế tiếp hoặc đóng khi hết hàng đợi.');
    }
    buf.writeln('- Nếu bạn là Proxy AI có tool `report_task_result`: chỉ gọi `report_task_result(status="completed", summary=..., evidence=<trích dẫn bằng chứng đã kiểm chứng từ ui-dump/snapshot>)` khi đã xác nhận 100%; nếu không làm được thì gọi `report_task_result(status="failed", failure_reason=<lý do cụ thể>)`.');
    buf.writeln('- Nếu bạn là Local CLI Agent: dòng cuối cùng BẮT BUỘC ghi `MXH_TASK_STATUS: COMPLETED: <trích dẫn bằng chứng đã kiểm chứng từ ui-dump/snapshot>` hoặc `MXH_TASK_STATUS: FAILED: <lý do cụ thể>`.');
    return buf.toString().trim();
  }

  ScheduleProvider({bool autoStart = true}) {
    if (autoStart) {
      _initIfLoggedIn();
      _startBackgroundTicker();
    }
  }

  Future<void> _initIfLoggedIn() async {
    try {
      if (await StorageService().isLoggedIn()) {
        await loadTasks();
      }
    } catch (_) {}
  }

  void resetForUserSwitch() {
    _tasks = [];
    _isLoading = false;
    _activeTaskIds.clear();
    _queuedTaskIds.clear();
    _cancelledTaskIds.clear();
    _resourceQueue.clearAll();
    _deviceSlotSemaphore.clearAll();
    notifyListeners();
  }

  @override
  void dispose() {
    _schedulerTimer?.cancel();
    _resourceQueue.clearAll();
    _deviceSlotSemaphore.clearAll();
    super.dispose();
  }

  void _startBackgroundTicker() {
    _schedulerTimer?.cancel();
    // Quét mỗi 30 giây để kích hoạt tác vụ đến hạn, tự động thử lại và gỡ tác vụ treo
    _schedulerTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      checkAndRunDueTasks();
    });
  }

  void setSelectedDate(DateTime date) {
    _selectedDate = date;
    notifyListeners();
  }

  void setFilterType(String type) {
    _filterType = type;
    notifyListeners();
  }

  void setFilterStatus(String status) {
    _filterStatus = status;
    notifyListeners();
  }

  /// Lấy danh sách nhiệm vụ của ngày đang chọn
  List<ScheduleTaskModel> get tasksForSelectedDate {
    return _tasks.where((t) {
      final isSameDay = t.scheduledTime.year == _selectedDate.year &&
          t.scheduledTime.month == _selectedDate.month &&
          t.scheduledTime.day == _selectedDate.day;
      if (!isSameDay) return false;

      if (_filterType != 'all' && t.taskType != _filterType) return false;
      if (_filterStatus != 'all' && t.status != _filterStatus) return false;

      return true;
    }).toList();
  }

  /// Danh sách tất cả các ngày có tác vụ trong tháng
  Set<DateTime> getTaskDatesInMonth(DateTime monthDate) {
    final res = <DateTime>{};
    for (final t in _tasks) {
      if (t.scheduledTime.year == monthDate.year && t.scheduledTime.month == monthDate.month) {
        res.add(DateTime(t.scheduledTime.year, t.scheduledTime.month, t.scheduledTime.day));
      }
    }
    return res;
  }

  Future<void> loadTasks({bool recoverInterrupted = true}) async {
    _isLoading = true;
    notifyListeners();
    try {
      _tasks = await _dbService.getScheduleTasks();
      if (recoverInterrupted) {
        await recoverInterruptedTasks();
      }
    } catch (_) {
      _tasks = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Tự động phát hiện và khôi phục các task bị treo ở trạng thái `running`
  /// (ví dụ do ứng dụng tắt đột ngột, mất điện hoặc khởi động lại máy giữa chừng).
  Future<int> recoverInterruptedTasks({bool onlyExpiredThreshold = false}) async {
    int recoveredCount = 0;
    final now = DateTime.now();

    for (final task in List<ScheduleTaskModel>.from(_tasks)) {
      if (task.id == null || task.status != 'running') continue;
      final isLiveInProcess = _activeTaskIds.contains(task.id);

      if (isLiveInProcess) {
        if (!onlyExpiredThreshold) continue;
        if (_queuedTaskIds.contains(task.id)) continue;
        final refStart = task.startedAt ?? task.scheduledTime;
        if (now.difference(refStart) < stuckRunningThreshold) continue;
        // Quá ngưỡng treo: đánh dấu hủy phiên treo để giải phóng
        _cancelledTaskIds.add(task.id!);
      }

      recoveredCount++;
      final doneCount = task.completedIps.length;
      final totalCount = task.personaIps.length;
      final remaining = task.remainingIps;

      if (remaining.isEmpty && totalCount > 0) {
        await _persistTask(task.copyWith(
          status: 'completed',
          failedIps: const [],
          clearNextRetryAt: true,
          completedAt: now,
          resultNote: 'Khôi phục trạng thái: toàn bộ $doneCount/$totalCount nhân vật đã hoàn thành trước đó.',
        ));
        continue;
      }

      if (task.retryCount < task.maxRetries) {
        final nextRetry = task.retryCount + 1;
        final retryTime = now.add(const Duration(seconds: 30));
        await _persistTask(task.copyWith(
          status: 'retrying',
          retryCount: nextRetry,
          nextRetryAt: retryTime,
          clearStartedAt: true,
          resultNote:
              'Phát hiện tác vụ bị gián đoạn giữa chừng (đã xong $doneCount/$totalCount nhân vật). '
              'Hệ thống tự lên lịch chạy tiếp phần còn lại (lần thử $nextRetry/${task.maxRetries}).',
        ));
      } else {
        final finalStatus = doneCount > 0 ? 'partial' : 'failed';
        final reason =
            'Tác vụ bị gián đoạn/treo giữa chừng và đã hết ${task.maxRetries} lượt tự động thử lại '
            '(mới hoàn thành $doneCount/$totalCount nhân vật).';
        await _persistTask(task.copyWith(
          status: finalStatus,
          failedIps: remaining,
          clearNextRetryAt: true,
          clearStartedAt: true,
          completedAt: now,
          resultNote: reason,
        ));
        await _sendFailureAlert(
          task: task,
          outcome: finalStatus,
          reason: reason,
          completedIps: task.completedIps,
          failedDetails: remaining.map((ip) => '$ip: chưa hoàn thành do gián đoạn').toList(),
        );
      }
    }

    return recoveredCount;
  }

  Future<bool> createTask({
    required String title,
    required String taskType,
    String executionMode = 'device',
    required String targetUrl,
    String? commentContent,
    required List<String> personaIps,
    required DateTime scheduledTime,
    int maxRetries = 3,
  }) async {
    final task = ScheduleTaskModel(
      title: title.trim(),
      taskType: taskType,
      executionMode: executionMode,
      targetUrl: targetUrl.trim(),
      commentContent: commentContent?.trim(),
      personaIps: personaIps,
      scheduledTime: scheduledTime,
      status: 'pending',
      maxRetries: maxRetries.clamp(1, 10),
    );

    final id = await _dbService.insertScheduleTask(task);
    if (id > 0) {
      final savedTask = task.copyWith(id: id);
      _tasks.add(savedTask);
      _tasks.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Chỉnh sửa thông tin tác vụ hẹn giờ đã tạo (tiêu đề, loại, chế độ, URL, bình luận, nhân vật, thời gian)
  Future<bool> updateTask({
    required ScheduleTaskModel existing,
    required String title,
    required String taskType,
    required String executionMode,
    required String targetUrl,
    String? commentContent,
    required List<String> personaIps,
    required DateTime scheduledTime,
    bool resetToPending = false,
  }) async {
    if (existing.id == null) return false;
    final latest = getTaskById(existing.id) ?? existing;
    final personaSet = personaIps.toSet();
    final keptCompleted = resetToPending
        ? <String>[]
        : latest.completedIps.where((ip) => personaSet.contains(ip)).toList();
    final keptFailed = resetToPending
        ? <String>[]
        : latest.failedIps.where((ip) => personaSet.contains(ip)).toList();

    final isRescheduledFuture = scheduledTime.isAfter(DateTime.now());
    final shouldResetPending = resetToPending ||
        (isRescheduledFuture && (latest.status == 'failed' || latest.status == 'partial' || latest.status == 'cancelled'));

    final updated = latest.copyWith(
      title: title.trim(),
      taskType: taskType,
      executionMode: executionMode,
      targetUrl: targetUrl.trim(),
      commentContent: (commentContent != null && commentContent.trim().isNotEmpty) ? commentContent.trim() : null,
      personaIps: personaIps,
      completedIps: keptCompleted,
      failedIps: keptFailed,
      scheduledTime: scheduledTime,
      status: shouldResetPending ? 'pending' : latest.status,
      retryCount: shouldResetPending ? 0 : latest.retryCount,
      clearNextRetryAt: shouldResetPending,
      clearCompletedAt: shouldResetPending,
      resultNote: shouldResetPending
          ? 'Đã cập nhật lịch trình lúc ${_formatHm(DateTime.now())}, chờ tự động thực thi.'
          : latest.resultNote,
    );

    final ok = await _dbService.updateScheduleTask(updated);
    if (ok) {
      final idx = _tasks.indexWhere((t) => t.id == updated.id);
      if (idx != -1) {
        _tasks[idx] = updated;
        _tasks.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
        notifyListeners();
      }
    }
    return ok;
  }

  Future<bool> deleteTask(int id) async {
    _cancelledTaskIds.add(id);
    _activeTaskIds.remove(id);
    _queuedTaskIds.remove(id);
    _resourceQueue.cancelWaitersForTask(id);
    _deviceSlotSemaphore.cancelWaitersForTask(id);
    final success = await _dbService.deleteScheduleTask(id);
    if (success) {
      _tasks.removeWhere((t) => t.id == id);
      notifyListeners();
    }
    return success;
  }

  Future<bool> _persistTask(ScheduleTaskModel updated) async {
    final ok = await _dbService.updateScheduleTask(updated);
    if (ok) {
      final idx = _tasks.indexWhere((t) => t.id == updated.id);
      if (idx != -1) {
        _tasks[idx] = updated;
        notifyListeners();
      }
    }
    return ok;
  }

  Future<bool> updateTaskStatus(ScheduleTaskModel task, String newStatus, {String? note}) async {
    final latest = getTaskById(task.id) ?? task;
    final isTerminal = newStatus == 'completed' || newStatus == 'failed' || newStatus == 'partial' || newStatus == 'cancelled';
    final updated = latest.copyWith(
      status: newStatus,
      resultNote: note ?? latest.resultNote,
      completedAt: isTerminal ? DateTime.now() : latest.completedAt,
      clearNextRetryAt: isTerminal,
    );
    return _persistTask(updated);
  }

  Future<ServerModel?> _resolveEffectiveServer(ServerModel? defaultServer) async {
    if (defaultServer != null) return defaultServer;
    if (serverResolverOverride != null) {
      return await serverResolverOverride!();
    }
    try {
      final servers = await _configService.getServers();
      if (servers.isEmpty) return null;
      return servers.firstWhere((s) => s.isSelected, orElse: () => servers.first);
    } catch (_) {
      return null;
    }
  }

  Duration _retryDelayForAttempt(int attemptNumber) {
    if (retryBackoffSteps.isEmpty) return const Duration(minutes: 2);
    final idx = (attemptNumber - 1).clamp(0, retryBackoffSteps.length - 1);
    return retryBackoffSteps[idx];
  }

  String _formatHm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  /// Chạy tiếp CHỈ những nhân vật chưa hoàn thành / bị lỗi của một task (giữ checkpoint đã xong)
  Future<ScheduleTaskModel?> resumeTask(ScheduleTaskModel task, {ServerModel? defaultServer}) async {
    if (task.id == null) return null;
    final latest = getTaskById(task.id) ?? task;
    final reset = latest.copyWith(
      retryCount: 0,
      clearNextRetryAt: true,
      resultNote: 'Đang chạy tiếp ${latest.remainingIps.length}/${latest.personaIps.length} nhân vật chưa hoàn thành...',
    );
    await _persistTask(reset);
    return executeTaskNow(reset, defaultServer: defaultServer, resumeOnlyRemaining: true);
  }

  /// Xóa checkpoint và chạy lại toàn bộ các nhân vật từ đầu
  Future<ScheduleTaskModel?> restartTaskFromScratch(ScheduleTaskModel task, {ServerModel? defaultServer}) async {
    if (task.id == null) return null;
    final latest = getTaskById(task.id) ?? task;
    final fresh = latest.copyWith(
      completedIps: const [],
      failedIps: const [],
      retryCount: 0,
      clearNextRetryAt: true,
      clearCompletedAt: true,
      resultNote: 'Đang khởi chạy lại toàn bộ từ đầu...',
    );
    await _persistTask(fresh);
    return executeTaskNow(fresh, defaultServer: defaultServer, resumeOnlyRemaining: false);
  }

  /// Dừng hoặc gỡ kẹt một task đang ở trạng thái `running`, đang xếp hàng, hoặc `retrying`
  Future<bool> cancelOrResetStuckTask(ScheduleTaskModel task, {bool resetToPending = false}) async {
    if (task.id == null) return false;
    final id = task.id!;
    _cancelledTaskIds.add(id);
    _activeTaskIds.remove(id);
    _queuedTaskIds.remove(id);
    _resourceQueue.cancelWaitersForTask(id);
    _deviceSlotSemaphore.cancelWaitersForTask(id);

    final latest = getTaskById(id) ?? task;
    final now = DateTime.now();
    final updated = latest.copyWith(
      status: resetToPending ? 'pending' : 'cancelled',
      clearNextRetryAt: true,
      clearStartedAt: true,
      completedAt: resetToPending ? null : now,
      clearCompletedAt: resetToPending,
      retryCount: resetToPending ? 0 : latest.retryCount,
      resultNote: resetToPending
          ? 'Đã gỡ kẹt và đặt lại về trạng thái Đang chờ lúc ${_formatHm(now)}.'
          : 'Đã dừng/hủy tác vụ theo yêu cầu người dùng lúc ${_formatHm(now)} (đã xong ${latest.completedIps.length}/${latest.personaIps.length} nhân vật).',
    );
    return _persistTask(updated);
  }

  /// Chạy tiếp hàng loạt các tác vụ đang ở trạng thái lỗi / hoàn thành 1 phần / chờ thử lại
  Future<int> retryAllFailedOrPartialTasks({ServerModel? defaultServer, bool onlySelectedDate = false}) async {
    final source = onlySelectedDate
        ? _tasks.where((t) =>
            t.scheduledTime.year == _selectedDate.year &&
            t.scheduledTime.month == _selectedDate.month &&
            t.scheduledTime.day == _selectedDate.day)
        : _tasks;
    final targets = source.where((t) => t.id != null && t.needsAttention).toList();
    int triggered = 0;
    for (final t in targets) {
      if (_activeTaskIds.contains(t.id)) continue;
      triggered++;
      await resumeTask(t, defaultServer: defaultServer);
    }
    return triggered;
  }

  void _updateLiveResultNote(int taskId, String note) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx != -1) {
      _tasks[idx] = _tasks[idx].copyWith(resultNote: note);
      notifyListeners();
    }
  }

  Future<Map<String, PersonaProfile>> _loadPersonasMap() async {
    if (personasLoaderOverride != null) {
      return await personasLoaderOverride!();
    }
    return await _personaService.loadSavedPersonas();
  }

  Future<int> _resolveMaxConcurrentDeviceSlots() async {
    if (maxConcurrentDeviceSlotsOverride != null) {
      return maxConcurrentDeviceSlotsOverride!.clamp(1, 10);
    }
    try {
      final n = await _socks5Service.getMaxConcurrentDevices();
      return n.clamp(1, 10);
    } catch (_) {
      return 2;
    }
  }

  Future<String?> _waitForDeviceBootReady(
    PersonaProfile persona, {
    required bool Function() isCancelled,
    Duration maxWait = const Duration(seconds: 60),
  }) async {
    final deadline = DateTime.now().add(maxWait);
    String? adbExe;
    try {
      adbExe = await _adbManagerService.resolveAdbPath();
    } catch (_) {}

    while (DateTime.now().isBefore(deadline) && !isCancelled()) {
      final serial = await _socks5Service.getRunningDeviceSerialForIp(
        persona.ip,
        entryKey: persona.effectiveEntryKey,
      );
      if (serial != null && serial.isNotEmpty) {
        if (adbExe == null || adbExe.isEmpty) return serial;
        try {
          final bootRes = await Process.run(
            adbExe,
            ['-s', serial, 'shell', 'getprop', 'sys.boot_completed'],
          ).timeout(const Duration(seconds: 4));
          if (bootRes.stdout.toString().trim() == '1') {
            return serial;
          }
        } catch (_) {}
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    return null;
  }

  Future<void> _openTargetUrlOnBootedDevice({
    required String adbExe,
    required String serial,
    required String targetUrl,
  }) async {
    final url = targetUrl.trim();
    if (url.isEmpty) return;
    final lower = url.toLowerCase();
    final List<String> args = ['-s', serial, 'shell', 'am', 'start', '-a', 'android.intent.action.VIEW', '-d', url];
    if (lower.contains('facebook.com') || lower.contains('fb.watch') || lower.contains('fb.com')) {
      final fbRes = await Process.run(adbExe, [...args, 'com.facebook.katana']).timeout(const Duration(seconds: 8));
      if (fbRes.exitCode != 0 || fbRes.stderr.toString().toLowerCase().contains('error')) {
        await Process.run(adbExe, args).timeout(const Duration(seconds: 8));
      }
    } else if (lower.contains('tiktok.com')) {
      final ttRes = await Process.run(adbExe, [...args, 'com.zhiliaoapp.musically']).timeout(const Duration(seconds: 8));
      if (ttRes.exitCode != 0 || ttRes.stderr.toString().toLowerCase().contains('error')) {
        await Process.run(adbExe, args).timeout(const Duration(seconds: 8));
      }
    } else {
      await Process.run(adbExe, args).timeout(const Duration(seconds: 8));
    }
  }

  Future<AiTaskExecutionResult> _defaultAiTaskRunner({
    required PersonaProfile persona,
    required ScheduleTaskModel task,
    required ServerModel? server,
    required String prompt,
    required String scopeWorkingDir,
    required void Function(String status) onStatus,
    required bool Function() isCancelled,
  }) async {
    final sessionId = 'schedule_${task.id ?? 0}_${persona.effectiveEntryKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
    return _nativeAiService.runAutomatedTask(
      sessionId: sessionId,
      prompt: prompt,
      workingDir: scopeWorkingDir,
      persistToChatDb: false,
      suppressFailureNotification: true,
      onStatus: onStatus,
      isCancelled: isCancelled,
    );
  }

  /// Thực thi tác vụ cho ĐÚNG 1 nhân vật với khóa độc quyền theo profile/thiết bị,
  /// giới hạn slot thiết bị toàn cục và điều phối AI Agent thực tế + kiểm chứng 100%.
  Future<void> _runSinglePersonaWithLock({
    required int taskId,
    required ScheduleTaskModel taskSnapshot,
    required PersonaProfile persona,
    required int totalTargetCount,
    required ServerModel? effectiveServer,
    required Set<String> doneSet,
    required List<String> failedKeys,
    required List<String> errorMessages,
    required List<String> verifiedEvidences,
    required int maxDeviceSlots,
    VoidCallback? onLockAttempted,
  }) async {
    final key = persona.effectiveEntryKey;
    final isDeviceMode = taskSnapshot.executionMode == 'device';
    final lockKeys = resourceLockKeysForPersona(persona, taskSnapshot.executionMode);
    bool lockCallbackFired = false;

    void notifyLockAttempted() {
      if (!lockCallbackFired) {
        lockCallbackFired = true;
        onLockAttempted?.call();
      }
    }

    bool isCancelled() => _cancelledTaskIds.contains(taskId);

    _ResourceLease? lease;
    bool acquiredDeviceSlot = false;
    bool personaSucceeded = false;
    bool shouldManageRealDeviceLifecycle =
        isDeviceMode && deviceTaskRunnerOverride == null && aiTaskRunnerOverride == null;

    try {
      // 1. Khóa tài nguyên theo đúng profile + thiết bị (FIFO) để tránh xung đột khi chạy trùng
      lease = await _resourceQueue.acquire(
        taskId,
        lockKeys,
        onWaiting: () {
          _queuedTaskIds.add(taskId);
          _updateLiveResultNote(
            taskId,
            'Đang xếp hàng chờ nhân vật ${persona.name} ($key) hoàn tất tác vụ khác...',
          );
          notifyLockAttempted();
        },
        isCancelled: isCancelled,
      );
      notifyLockAttempted();

      if (lease == null || isCancelled()) {
        return;
      }

      // 2. Nếu ở chế độ thiết bị: lấy thêm slot thiết bị toàn cục (mặc định tối đa 2 thiết bị chạy đồng thời)
      if (isDeviceMode) {
        acquiredDeviceSlot = await _deviceSlotSemaphore.acquire(
          taskId,
          maxDeviceSlots,
          onWaiting: () {
            _queuedTaskIds.add(taskId);
            _updateLiveResultNote(
              taskId,
              'Đang xếp hàng chờ slot thiết bị rảnh (tối đa $maxDeviceSlots thiết bị đồng thời) cho ${persona.name}...',
            );
          },
          isCancelled: isCancelled,
        );
        if (!acquiredDeviceSlot || isCancelled()) {
          return;
        }
      }

      _queuedTaskIds.remove(taskId);
      // Làm mới startedAt sau khi đã thực sự có khóa (tránh thời gian xếp hàng bị tính nhầm là treo)
      final refreshed = (getTaskById(taskId) ?? taskSnapshot).copyWith(
        startedAt: DateTime.now(),
      );
      await _persistTask(refreshed);

      final timeout = isDeviceMode ? perPersonaDeviceTimeout : perPersonaBrowserTimeout;

      Future<void> runCoreWork() async {
        // Nhánh tương thích với unit test cũ dùng override trực tiếp
        if (isDeviceMode && deviceTaskRunnerOverride != null) {
          _updateLiveResultNote(taskId, '[${persona.name}] Đang chạy tác vụ thiết bị...');
          await deviceTaskRunnerOverride!(persona, refreshed, effectiveServer);
          return;
        }
        if (!isDeviceMode && browserLauncherOverride != null) {
          _updateLiveResultNote(taskId, '[${persona.name}] Đang chạy tác vụ trình duyệt...');
          final ok = await browserLauncherOverride!(persona, refreshed, effectiveServer);
          if (!ok) {
            throw Exception('Trình duyệt không khởi chạy thành công');
          }
          return;
        }

        // Nhánh thực thi THẬT bằng AI Agent (Thiết bị ADB/AVD hoặc Trình duyệt CDP)
        String? resolvedAdbSerial;
        String? resolvedAdbPath;
        String? resolvedMxhToolPath;

        if (aiTaskRunnerOverride == null) {
          try {
            resolvedMxhToolPath = await CliAutomationBridgeService().ensureCliHelperInstalled();
          } catch (_) {}

          if (isDeviceMode) {
            _updateLiveResultNote(taskId, '[${persona.name}] Đang chuẩn bị và khởi chạy thiết bị Android...');
            await _socks5Service.ensureDeviceCapacity(maxConcurrent: maxDeviceSlots, exemptIps: [key]);
            final launched = await _socks5Service.launchPersonaDevice(
              ip: persona.ip,
              entryKey: key,
              server: effectiveServer,
              deviceType: persona.deviceType,
              avdName: persona.avdName,
              remoteDeviceAddress: persona.useExternalDevice ? persona.externalDeviceAddress : null,
              startUrl: refreshed.targetUrl,
            );
            if (!launched) {
              throw Exception('Không thể khởi chạy thiết bị Android cho ${persona.name}');
            }
            if (isCancelled()) return;
            _updateLiveResultNote(taskId, '[${persona.name}] Đang chờ thiết bị Android khởi động hoàn tất qua ADB...');
            resolvedAdbSerial = await _waitForDeviceBootReady(persona, isCancelled: isCancelled);
            if (isCancelled()) return;
            if (resolvedAdbSerial == null || resolvedAdbSerial.isEmpty) {
              throw Exception('Thiết bị Android cho ${persona.name} không phản hồi ADB sau khi khởi chạy.');
            }
            resolvedAdbPath = await _adbManagerService.resolveAdbPath();
            // Đợi 2 giây sau boot rồi mở lại deep link mục tiêu để đảm bảo app mở đúng video/bài viết
            await Future.delayed(const Duration(seconds: 2));
            if (isCancelled()) return;
            _updateLiveResultNote(taskId, '[${persona.name}] Đang mở liên kết mục tiêu trên $resolvedAdbSerial...');
            try {
              await _openTargetUrlOnBootedDevice(
                adbExe: resolvedAdbPath,
                serial: resolvedAdbSerial,
                targetUrl: refreshed.targetUrl,
              );
              await Future.delayed(const Duration(seconds: 4));
            } catch (_) {}
            if (isCancelled()) return;
          } else {
            _updateLiveResultNote(taskId, '[${persona.name}] Đang chuẩn bị trình duyệt cho nhân vật...');
            final launched = await _socks5Service.launchPersonaBrowser(
              ip: persona.ip,
              server: effectiveServer,
              startUrl: refreshed.targetUrl,
              browserProfileId: persona.browserProfileId,
              entryKey: key,
            );
            if (!launched) {
              throw Exception('Trình duyệt không khởi chạy thành công cho ${persona.name}');
            }
            if (isCancelled()) return;
          }
        }

        final scopeWorkingDir = buildPersonaScopeWorkingDir(
          persona,
          refreshed.executionMode,
          adbSerial: resolvedAdbSerial,
          adbPath: resolvedAdbPath,
        );
        final prompt = buildScheduledTaskPrompt(
          refreshed,
          persona,
          adbSerial: resolvedAdbSerial,
          adbPath: resolvedAdbPath,
          mxhToolPath: resolvedMxhToolPath,
        );
        DateTime lastUiStatusPush = DateTime.fromMillisecondsSinceEpoch(0);

        _updateLiveResultNote(
          taskId,
          '[${persona.name}] AI Agent đang thực thi ${refreshed.taskType} (${isDeviceMode ? 'Thiết bị' : 'Trình duyệt'})...',
        );

        final runner = aiTaskRunnerOverride ?? _defaultAiTaskRunner;
        final aiResult = await runner(
          persona: persona,
          task: refreshed,
          server: effectiveServer,
          prompt: prompt,
          scopeWorkingDir: scopeWorkingDir,
          onStatus: (status) {
            final now = DateTime.now();
            if (now.difference(lastUiStatusPush) >= const Duration(milliseconds: 1200)) {
              lastUiStatusPush = now;
              _updateLiveResultNote(taskId, '[${persona.name}] $status');
            }
          },
          isCancelled: isCancelled,
        );

        if (isCancelled() || aiResult.outcome == 'cancelled') {
          return;
        }

        if (!aiResult.isCompleted) {
          final reason = (aiResult.failureReason != null && aiResult.failureReason!.trim().isNotEmpty)
              ? aiResult.failureReason!.trim()
              : 'AI Agent chưa xác nhận hoàn thành 100% (trạng thái: ${aiResult.outcome}).';
          throw Exception(reason);
        }

        final ev = aiResult.evidence?.trim() ?? '';
        if (ev.isNotEmpty) {
          verifiedEvidences.add('${persona.name}: $ev');
        }
      }

      await runCoreWork().timeout(timeout);

      if (isCancelled()) return;

      personaSucceeded = true;
      doneSet.add(key);
      final latestAfterDone = getTaskById(taskId) ?? refreshed;
      await _persistTask(latestAfterDone.copyWith(
        completedIps: doneSet.toList(),
        resultNote:
            'Đang chạy ${isDeviceMode ? 'thiết bị' : 'trình duyệt'}: đã hoàn thành xác thực ${doneSet.length}/$totalTargetCount nhân vật...',
      ));
    } catch (err) {
      if (!isCancelled()) {
        failedKeys.add(key);
        errorMessages.add('${persona.name} ($key): $err');
      }
    } finally {
      _queuedTaskIds.remove(taskId);
      notifyLockAttempted();

      // Quản lý vòng đời thiết bị Android thực tế:
      // - Nếu tác vụ xong thành công VÀ đang có tác vụ kế tiếp xếp hàng chờ CHÍNH profile/thiết bị này -> giữ thiết bị ấm để chạy nối tiếp ngay, tránh tắt/bật lại tốn thời gian.
      // - Ngược lại (hết hàng đợi, hoặc lỗi, hoặc bị hủy) -> đóng thiết bị sạch sẽ giải phóng RAM/CPU.
      if (shouldManageRealDeviceLifecycle && lease != null) {
        final keepWarmForNextQueuedTask =
            personaSucceeded && !isCancelled() && _resourceQueue.hasWaitingTaskForAny(lockKeys);
        if (!keepWarmForNextQueuedTask) {
          try {
            await _socks5Service.closeDeviceForIp(persona.ip, entryKey: key);
          } catch (_) {}
        }
      }

      if (acquiredDeviceSlot) {
        _deviceSlotSemaphore.release();
      }
      if (lease != null) {
        _resourceQueue.release(lease);
      }
    }
  }

  /// Kích hoạt và thực thi một tác vụ với đầy đủ cơ chế:
  /// - Khóa chống chạy trùng cùng taskId VÀ hàng đợi khóa độc quyền theo từng profile/thiết bị
  /// - Giới hạn tối đa số thiết bị chạy đồng thời toàn hệ thống
  /// - Nối trực tiếp AI Agent (Thiết bị ADB/AVD và Trình duyệt CDP) thực thi đúng hành động & kiểm chứng 100%
  /// - Tự động nạp Active Server khi chạy nền
  /// - Lưu checkpoint sau từng nhân vật
  /// - Timeout bảo vệ từng nhân vật (chỉ tính từ lúc nhận được khóa, không tính thời gian xếp hàng)
  /// - Chỉ đánh dấu `completed` khi 100% nhân vật được AI Agent xác nhận hoàn thành
  /// - Tự động thử lại phần lỗi (`retrying`) với backoff, hết lượt thì đánh dấu `partial`/`failed` và gửi cảnh báo
  Future<ScheduleTaskModel?> executeTaskNow(
    ScheduleTaskModel task, {
    ServerModel? defaultServer,
    bool resumeOnlyRemaining = true,
    VoidCallback? onFirstLockAttempted,
  }) async {
    if (task.id == null) {
      onFirstLockAttempted?.call();
      return null;
    }
    final taskId = task.id!;
    if (_activeTaskIds.contains(taskId)) {
      onFirstLockAttempted?.call();
      return getTaskById(taskId);
    }

    _activeTaskIds.add(taskId);
    _cancelledTaskIds.remove(taskId);

    bool firstLockNotified = false;
    void fireFirstLockOnce() {
      if (!firstLockNotified) {
        firstLockNotified = true;
        onFirstLockAttempted?.call();
      }
    }

    ScheduleTaskModel current = getTaskById(taskId) ?? task;
    final doneSet = resumeOnlyRemaining ? current.completedIps.toSet() : <String>{};
    final startedAt = DateTime.now();

    current = current.copyWith(
      status: 'running',
      completedIps: doneSet.toList(),
      failedIps: const [],
      startedAt: startedAt,
      clearNextRetryAt: true,
      resultNote: doneSet.isNotEmpty
          ? 'Đang chạy tiếp (đã xong ${doneSet.length}/${current.personaIps.length} nhân vật)...'
          : 'Đang chuẩn bị thực thi tác vụ cho ${current.personaIps.length} nhân vật...',
    );
    await _persistTask(current);

    try {
      final effectiveServer = await _resolveEffectiveServer(defaultServer);
      final personasMap = await _loadPersonasMap();
      final allTargetPersonas = current.personaIps
          .map((key) =>
              personasMap[key] ??
              personasMap[key.split('##').first] ??
              PersonaProfile(
                ip: key.split('##').first,
                entryKey: key,
                name: 'Nhân vật $key',
                age: 25,
                gender: 'Nam',
                bio: '',
                avatarPrompt: '',
              ))
          .toList();

      if (allTargetPersonas.isEmpty) {
        fireFirstLockOnce();
        const msg = 'Không tìm thấy thông tin nhân vật nào phù hợp với danh sách IP.';
        current = current.copyWith(
          status: 'failed',
          clearStartedAt: true,
          clearNextRetryAt: true,
          completedAt: DateTime.now(),
          resultNote: msg,
        );
        await _persistTask(current);
        await _sendFailureAlert(task: current, outcome: 'failed', reason: msg, completedIps: const [], failedDetails: [msg]);
        return current;
      }

      final remainingPersonas = allTargetPersonas.where((p) => !doneSet.contains(p.effectiveEntryKey)).toList();
      final List<String> failedKeys = [];
      final List<String> errorMessages = [];
      final List<String> verifiedEvidences = [];
      final isDeviceMode = current.executionMode == 'device';
      final maxDeviceSlots = isDeviceMode ? await _resolveMaxConcurrentDeviceSlots() : 1;

      if (remainingPersonas.isNotEmpty) {
        if (isDeviceMode && remainingPersonas.length > 1) {
          // Nhiều nhân vật ở chế độ Thiết bị: mỗi nhân vật đều đi qua khóa profile/thiết bị + semaphore slot toàn cục
          final futures = <Future<void>>[];
          for (int i = 0; i < remainingPersonas.length; i++) {
            final p = remainingPersonas[i];
            futures.add(_runSinglePersonaWithLock(
              taskId: taskId,
              taskSnapshot: current,
              persona: p,
              totalTargetCount: allTargetPersonas.length,
              effectiveServer: effectiveServer,
              doneSet: doneSet,
              failedKeys: failedKeys,
              errorMessages: errorMessages,
              verifiedEvidences: verifiedEvidences,
              maxDeviceSlots: maxDeviceSlots,
              onLockAttempted: i == 0 ? fireFirstLockOnce : null,
            ));
          }
          await Future.wait(futures);
        } else {
          // 1 nhân vật hoặc chế độ Trình duyệt: chạy tuần tự và vẫn đi qua hàng đợi khóa profile/thiết bị
          for (int i = 0; i < remainingPersonas.length; i++) {
            if (_cancelledTaskIds.contains(taskId)) break;
            final p = remainingPersonas[i];
            await _runSinglePersonaWithLock(
              taskId: taskId,
              taskSnapshot: current,
              persona: p,
              totalTargetCount: allTargetPersonas.length,
              effectiveServer: effectiveServer,
              doneSet: doneSet,
              failedKeys: failedKeys,
              errorMessages: errorMessages,
              verifiedEvidences: verifiedEvidences,
              maxDeviceSlots: maxDeviceSlots,
              onLockAttempted: i == 0 ? fireFirstLockOnce : null,
            );
          }
        }
      }
      fireFirstLockOnce();

      current = getTaskById(taskId) ?? current;

      // Nếu người dùng đã chủ động dừng/hủy giữa chừng
      if (_cancelledTaskIds.contains(taskId)) {
        final now = DateTime.now();
        current = current.copyWith(
          status: 'cancelled',
          completedIps: doneSet.toList(),
          failedIps: allTargetPersonas
              .map((p) => p.effectiveEntryKey)
              .where((k) => !doneSet.contains(k))
              .toList(),
          clearStartedAt: true,
          clearNextRetryAt: true,
          completedAt: now,
          resultNote: 'Đã hủy lúc ${_formatHm(now)} (đã xong ${doneSet.length}/${allTargetPersonas.length} nhân vật).',
        );
        await _persistTask(current);
        return current;
      }

      final now = DateTime.now();
      final timeStr = _formatHm(now);
      final totalCount = allTargetPersonas.length;
      final remainingKeys = allTargetPersonas
          .map((p) => p.effectiveEntryKey)
          .where((k) => !doneSet.contains(k))
          .toList();

      // CHỈ ĐÁNH DẤU HOÀN TẤT KHI 100% NHÂN VẬT THÀNH CÔNG
      if (remainingKeys.isEmpty && failedKeys.isEmpty) {
        final evidenceSummary = verifiedEvidences.isNotEmpty
            ? ' Bằng chứng: ${verifiedEvidences.join(' | ')}'
            : '';
        current = current.copyWith(
          status: 'completed',
          completedIps: doneSet.toList(),
          failedIps: const [],
          clearStartedAt: true,
          clearNextRetryAt: true,
          completedAt: now,
          resultNote: 'Hoàn tất 100% cho toàn bộ $totalCount/$totalCount nhân vật lúc $timeStr.$evidenceSummary',
        );
        await _persistTask(current);
        return current;
      }

      // CÓ NHÂN VẬT LỖI / CHƯA XONG -> THỬ LẠI TỰ ĐỘNG NẾU CÒN LƯỢT
      final errorSummary = errorMessages.isNotEmpty
          ? errorMessages.join('; ')
          : 'Không thể hoàn tất cho ${remainingKeys.length} nhân vật (${remainingKeys.join(', ')}).';

      if (current.retryCount < current.maxRetries) {
        final nextAttempt = current.retryCount + 1;
        final delay = _retryDelayForAttempt(nextAttempt);
        final nextTime = now.add(delay);
        current = current.copyWith(
          status: 'retrying',
          completedIps: doneSet.toList(),
          failedIps: remainingKeys,
          retryCount: nextAttempt,
          nextRetryAt: nextTime,
          clearStartedAt: true,
          resultNote:
              'Mới xong ${doneSet.length}/$totalCount nhân vật lúc $timeStr. '
              'Tự động chạy lại ${remainingKeys.length} nhân vật lỗi lúc ${_formatHm(nextTime)} '
              '(lần thử $nextAttempt/${current.maxRetries}). Chi tiết lỗi: $errorSummary',
        );
        await _persistTask(current);
        return current;
      }

      // ĐÃ HẾT LƯỢT THỬ LẠI -> ĐÁNH DẤU PARTIAL HOẶC FAILED & GỬI CẢNH BÁO
      final finalStatus = doneSet.isNotEmpty ? 'partial' : 'failed';
      final reason =
          'Đã hết ${current.maxRetries} lượt thử lại: chỉ hoàn thành ${doneSet.length}/$totalCount nhân vật '
          '(lỗi ${remainingKeys.length} nhân vật). Chi tiết: $errorSummary';
      final notifyResult = await _sendFailureAlert(
        task: current,
        outcome: finalStatus,
        reason: reason,
        completedIps: doneSet.toList(),
        failedDetails: errorMessages.isNotEmpty ? errorMessages : remainingKeys,
      );
      final alertSuffix = notifyResult != null ? ' | Cảnh báo: ${notifyResult.describe()}' : '';

      current = current.copyWith(
        status: finalStatus,
        completedIps: doneSet.toList(),
        failedIps: remainingKeys,
        clearStartedAt: true,
        clearNextRetryAt: true,
        completedAt: now,
        resultNote: '$reason$alertSuffix',
      );
      await _persistTask(current);
      return current;
    } catch (e) {
      fireFirstLockOnce();
      final now = DateTime.now();
      final remainingKeys = current.personaIps.where((k) => !doneSet.contains(k)).toList();
      if (current.retryCount < current.maxRetries) {
        final nextAttempt = current.retryCount + 1;
        final nextTime = now.add(_retryDelayForAttempt(nextAttempt));
        current = current.copyWith(
          status: 'retrying',
          completedIps: doneSet.toList(),
          failedIps: remainingKeys,
          retryCount: nextAttempt,
          nextRetryAt: nextTime,
          clearStartedAt: true,
          resultNote:
              'Gặp lỗi hệ thống giữa chừng ($e). Sẽ tự động chạy lại lúc ${_formatHm(nextTime)} '
              '(lần thử $nextAttempt/${current.maxRetries}).',
        );
        await _persistTask(current);
        return current;
      }

      final finalStatus = doneSet.isNotEmpty ? 'partial' : 'failed';
      final reason = 'Lỗi thực thi tác vụ hẹn giờ sau ${current.maxRetries} lượt thử: $e';
      final notifyResult = await _sendFailureAlert(
        task: current,
        outcome: finalStatus,
        reason: reason,
        completedIps: doneSet.toList(),
        failedDetails: ['$e'],
      );
      final alertSuffix = notifyResult != null ? ' | Cảnh báo: ${notifyResult.describe()}' : '';

      current = current.copyWith(
        status: finalStatus,
        completedIps: doneSet.toList(),
        failedIps: remainingKeys,
        clearStartedAt: true,
        clearNextRetryAt: true,
        completedAt: now,
        resultNote: '$reason$alertSuffix',
      );
      await _persistTask(current);
      return current;
    } finally {
      fireFirstLockOnce();
      _activeTaskIds.remove(taskId);
      _queuedTaskIds.remove(taskId);
      _cancelledTaskIds.remove(taskId);
    }
  }

  Future<TaskNotificationResult?> _sendFailureAlert({
    required ScheduleTaskModel task,
    required String outcome,
    required String reason,
    required List<String> completedIps,
    required List<String> failedDetails,
  }) async {
    try {
      return await _notifyService.notifyTaskFailure(
        userRequest:
            '[Lịch trình hẹn giờ #${task.id ?? '-'}] ${task.title} '
            '(loại: ${task.taskType}, chế độ: ${task.executionMode}, URL: ${task.targetUrl})',
        reason: reason,
        outcome: outcome,
        sessionId: 'schedule_${task.id ?? 'unknown'}',
        engine: 'scheduler_${task.executionMode}',
        personas: task.personaIps,
        recentSteps: [
          'Tiến độ đã hoàn thành: ${completedIps.length}/${task.personaIps.length} nhân vật',
          ...failedDetails.take(10),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  /// Kiểm tra các tác vụ đến hạn (`pending`), tác vụ đến giờ thử lại (`retrying`),
  /// và gỡ kẹt các tác vụ `running` bị treo quá ngưỡng.
  Future<void> checkAndRunDueTasks({bool bypassLoginCheck = false}) async {
    if (_isCheckingDueTasks) return;
    _isCheckingDueTasks = true;
    try {
      if (!bypassLoginCheck && !await StorageService().isLoggedIn()) return;
      await recoverInterruptedTasks(onlyExpiredThreshold: true);

      final now = DateTime.now();
      final dueTasks = _tasks.where((t) {
        if (t.id == null || _activeTaskIds.contains(t.id)) return false;
        if (t.status == 'pending' && !t.scheduledTime.isAfter(now)) return true;
        if (t.status == 'retrying' && (t.nextRetryAt == null || !t.nextRetryAt!.isAfter(now))) return true;
        return false;
      }).toList()
        ..sort((a, b) {
          final cmp = a.scheduledTime.compareTo(b.scheduledTime);
          if (cmp != 0) return cmp;
          return (a.id ?? 0).compareTo(b.id ?? 0);
        });

      // Đưa các tác vụ đến hạn vào hàng đợi theo thứ tự xác định (FIFO):
      // - Các tác vụ cùng profile / thiết bị sẽ tự xếp hàng chạy lần lượt và giữ ấm thiết bị giữa các lượt.
      // - Các tác vụ ở các profile / thiết bị độc lập có thể chạy song song (trong giới hạn slot thiết bị).
      final futures = <Future<ScheduleTaskModel?>>[];
      for (final task in dueTasks) {
        final lockAttempted = Completer<void>();
        futures.add(executeTaskNow(
          task,
          resumeOnlyRemaining: true,
          onFirstLockAttempted: () {
            if (!lockAttempted.isCompleted) lockAttempted.complete();
          },
        ));
        await lockAttempted.future;
      }
      await Future.wait(futures);
    } finally {
      _isCheckingDueTasks = false;
    }
  }
}
