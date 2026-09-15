import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/database_service.dart';
import '../core/services/persona_service.dart';
import '../core/services/socks5_proxy_service.dart';
import '../models/persona_profile_model.dart';
import '../models/schedule_task_model.dart';
import '../models/server_model.dart';

class ScheduleProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  final PersonaService _personaService = PersonaService();
  final Socks5ProxyService _socks5Service = Socks5ProxyService();

  List<ScheduleTaskModel> _tasks = [];
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now();
  String _filterType = 'all'; // 'all' | 'like' | 'comment' | 'livestream' | 'post'
  String _filterStatus = 'all'; // 'all' | 'pending' | 'completed' | 'failed'
  Timer? _schedulerTimer;

  List<ScheduleTaskModel> get tasks => _tasks;
  bool get isLoading => _isLoading;
  DateTime get selectedDate => _selectedDate;
  String get filterType => _filterType;
  String get filterStatus => _filterStatus;

  ScheduleProvider() {
    loadTasks();
    _startBackgroundTicker();
  }

  @override
  void dispose() {
    _schedulerTimer?.cancel();
    super.dispose();
  }

  void _startBackgroundTicker() {
    _schedulerTimer?.cancel();
    // Quét mỗi 30 giây để kích hoạt tác vụ đến hạn
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

  Future<void> loadTasks() async {
    _isLoading = true;
    notifyListeners();
    try {
      _tasks = await _dbService.getScheduleTasks();
    } catch (_) {
      _tasks = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createTask({
    required String title,
    required String taskType,
    String executionMode = 'browser',
    required String targetUrl,
    String? commentContent,
    required List<String> personaIps,
    required DateTime scheduledTime,
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

  Future<bool> deleteTask(int id) async {
    final success = await _dbService.deleteScheduleTask(id);
    if (success) {
      _tasks.removeWhere((t) => t.id == id);
      notifyListeners();
    }
    return success;
  }

  Future<bool> updateTaskStatus(ScheduleTaskModel task, String newStatus, {String? note}) async {
    final updated = task.copyWith(
      status: newStatus,
      resultNote: note ?? task.resultNote,
      completedAt: (newStatus == 'completed' || newStatus == 'failed') ? DateTime.now() : task.completedAt,
    );
    final ok = await _dbService.updateScheduleTask(updated);
    if (ok) {
      final idx = _tasks.indexWhere((t) => t.id == task.id);
      if (idx != -1) {
        _tasks[idx] = updated;
        notifyListeners();
      }
    }
    return ok;
  }

  /// Kích hoạt và thực thi ngay lập tức một tác vụ
  Future<void> executeTaskNow(ScheduleTaskModel task, {ServerModel? defaultServer}) async {
    if (task.id == null) return;
    await updateTaskStatus(task, 'running', note: 'Đang thực thi tác vụ...');

    try {
      final personasMap = await _personaService.loadSavedPersonas();
      final targetPersonas = task.personaIps
          .map((ip) => personasMap[ip] ?? PersonaProfile(
                ip: ip,
                name: 'Nhân vật $ip',
                age: 25,
                gender: 'Nam',
                bio: '',
                avatarPrompt: '',
              ))
          .toList();

      if (targetPersonas.isEmpty) {
        await updateTaskStatus(task, 'failed', note: 'Không tìm thấy thông tin nhân vật nào phù hợp với danh sách IP.');
        return;
      }

      int successCount = 0;
      final List<String> errorMessages = [];

      final isDeviceMode = task.executionMode == 'device';

      if (isDeviceMode) {
        // CHẾ ĐỘ THIẾT BỊ: Áp dụng Hàng đợi thiết bị an toàn (Device Task Queue)
        // - Giới hạn tối đa 2 devices chạy đồng thời (chống treo máy)
        // - Đảm bảo tác vụ auto trên từng device chạy XONG HOÀN TOÀN mới tắt máy
        // - Tắt xong mới mở thiết bị tiếp theo, đảm bảo xử lý hết tất cả devices (kể cả 100 devices)
        final personaMap = {for (final p in targetPersonas) p.ip: p};
        final ips = targetPersonas.map((p) => p.ip).toList();

        final queueResult = await _socks5Service.runDeviceTaskQueue(
          ips: ips,
          maxConcurrent: 2,
          taskRunner: (ip) async {
            final p = personaMap[ip]!;
            await _socks5Service.launchPersonaDevice(
              ip: p.ip,
              server: defaultServer,
              deviceType: p.deviceType,
              avdName: p.avdName,
              remoteDeviceAddress: p.useExternalDevice ? p.externalDeviceAddress : null,
              startUrl: task.targetUrl,
            );

            // Thời gian thực thi auto tác vụ trên thiết bị:
            // Đảm bảo tác vụ chạy đủ thời lượng (hoặc chờ theo tiến trình auto) trước khi hoàn tất
            await Future.delayed(const Duration(seconds: 15));
          },
        );

        final List<String> completedSuccess = List<String>.from(queueResult['success'] ?? []);
        final Map<String, dynamic> failedMap = Map<String, dynamic>.from(queueResult['failed'] ?? {});

        successCount = completedSuccess.length;
        for (final entry in failedMap.entries) {
          final p = personaMap[entry.key];
          final name = p?.name ?? entry.key;
          errorMessages.add('$name (${entry.key}): ${entry.value}');
        }
      } else {
        // CHẾ ĐỘ TRÌNH DUYỆT: Mở trình duyệt độc lập với Profile IP
        for (final p in targetPersonas) {
          try {
            await _socks5Service.launchPersonaBrowser(
              ip: p.ip,
              server: defaultServer,
              startUrl: task.targetUrl,
            );
            successCount++;
          } catch (err) {
            errorMessages.add('${p.name} (${p.ip}): $err');
          }
        }
      }

      final timeStr = '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
      if (successCount > 0) {
        String note = 'Đã tự động kích hoạt cho $successCount/${targetPersonas.length} nhân vật thành công vào lúc $timeStr.';
        if (errorMessages.isNotEmpty) {
          note += ' (Lỗi một số profile: ${errorMessages.join('; ')})';
        }
        await updateTaskStatus(task, 'completed', note: note);
      } else {
        final errorDetail = errorMessages.isNotEmpty ? errorMessages.join('; ') : 'Không thể khởi động trình duyệt hoặc thiết bị.';
        await updateTaskStatus(task, 'failed', note: 'Thất bại ($timeStr): $errorDetail');
      }
    } catch (e) {
      await updateTaskStatus(task, 'failed', note: 'Lỗi thực thi tác vụ: $e');
    }
  }

  /// Kiểm tra các tác vụ đã đến thời hạn (due) để thực thi
  Future<void> checkAndRunDueTasks() async {
    final now = DateTime.now();
    final dueTasks = _tasks.where((t) {
      return t.status == 'pending' && t.scheduledTime.isBefore(now);
    }).toList();

    for (final task in dueTasks) {
      await executeTaskNow(task);
    }
  }
}
