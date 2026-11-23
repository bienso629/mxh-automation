import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:agent_mxh_auto/core/services/cli_automation_bridge_service.dart';
import 'package:agent_mxh_auto/core/services/database_service.dart';
import 'package:agent_mxh_auto/core/services/native_ai_service.dart';
import 'package:agent_mxh_auto/core/services/task_notification_service.dart';
import 'package:agent_mxh_auto/models/persona_profile_model.dart';
import 'package:agent_mxh_auto/models/schedule_task_model.dart';
import 'package:agent_mxh_auto/providers/schedule_provider.dart';

void main() {
  final testUserKey = 'sched_recovery_${DateTime.now().millisecondsSinceEpoch}';
  final workDir = Directory(p.join(Directory.current.path, '.dart_tool', 'sched_recovery_test'));

  setUpAll(() async {
    if (workDir.existsSync()) workDir.deleteSync(recursive: true);
    workDir.createSync(recursive: true);
    await DatabaseService().switchUser(testUserKey);
  });

  tearDownAll(() async {
    await DatabaseService().closeForLogout();
    try {
      final dbPath = p.join(DatabaseService.resolveDefaultDataDir(), 'chat_history_$testUserKey.db');
      final f = File(dbPath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    try {
      if (workDir.existsSync()) workDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Khôi phục và xử lý lỗi giữa chừng cho tác vụ hẹn giờ (ScheduleProvider)', () {
    test('Lỗi 1 phần không bị đánh dấu hoàn tất giả; lưu checkpoint và chỉ chạy lại phần lỗi cho tới 100%', () async {
      final provider = ScheduleProvider(autoStart: false)
        ..serverResolverOverride = (() async => null)
        ..retryBackoffSteps = const [Duration(milliseconds: 50), Duration(milliseconds: 50)];

      final ok = await provider.createTask(
        title: 'Đăng bài 2 nhân vật',
        taskType: 'post',
        executionMode: 'browser',
        targetUrl: 'https://facebook.com',
        personaIps: const ['127.0.0.1', '127.0.0.1##2'],
        scheduledTime: DateTime.now().subtract(const Duration(minutes: 1)),
        maxRetries: 2,
      );
      expect(ok, isTrue);
      final task = provider.tasks.last;

      final calledKeys = <String>[];
      int attemptForSecond = 0;
      provider.browserLauncherOverride = (persona, t, srv) async {
        calledKeys.add(persona.effectiveEntryKey);
        if (persona.effectiveEntryKey == '127.0.0.1##2' && attemptForSecond == 0) {
          attemptForSecond++;
          throw Exception('Mất kết nối proxy tạm thời');
        }
        return true;
      };

      // Lượt 1: nhân vật 1 xong, nhân vật 2 lỗi -> phải chuyển sang retrying (KHÔNG được completed giả)
      final afterFirst = await provider.executeTaskNow(task);
      expect(afterFirst, isNotNull);
      expect(afterFirst!.status, 'retrying');
      expect(afterFirst.completedIps, ['127.0.0.1']);
      expect(afterFirst.failedIps, ['127.0.0.1##2']);
      expect(afterFirst.retryCount, 1);
      expect(afterFirst.nextRetryAt, isNotNull);

      // Chờ hết backoff và gọi checkAndRunDueTasks -> CHỈ chạy lại nhân vật 2 (không chạy lại nhân vật 1)
      await Future.delayed(const Duration(milliseconds: 100));
      calledKeys.clear();
      await provider.checkAndRunDueTasks(bypassLoginCheck: true);

      expect(calledKeys, ['127.0.0.1##2']);
      final afterRetry = provider.getTaskById(task.id)!;
      expect(afterRetry.status, 'completed');
      expect(afterRetry.completedIps.toSet(), {'127.0.0.1', '127.0.0.1##2'});
      expect(afterRetry.failedIps, isEmpty);
      provider.dispose();
    });

    test('Hết lượt thử lại -> chuyển trạng thái partial/failed và gửi cảnh báo về máy chủ', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final alerts = <Map<String, dynamic>>[];
      server.listen((req) async {
        final body = await utf8.decoder.bind(req).join();
        alerts.add(jsonDecode(body) as Map<String, dynamic>);
        req.response.statusCode = 200;
        await req.response.close();
      });

      final notify = TaskNotificationService()
        ..configOverride = {'notify_webhook_url': 'http://127.0.0.1:${server.port}/sched-alert'}
        ..logPathOverride = p.join(workDir.path, 'sched_fail.log')
        ..desktopNotifyEnabled = false;

      final provider = ScheduleProvider(autoStart: false)
        ..serverResolverOverride = (() async => null)
        ..retryBackoffSteps = const [Duration(milliseconds: 20)]
        ..browserLauncherOverride = (persona, t, srv) async {
          if (persona.effectiveEntryKey == '127.0.0.1') return true;
          return false; // luôn lỗi ở nhân vật 2
        };

      try {
        await provider.createTask(
          title: 'Tác vụ lỗi liên tục ở nhân vật 2',
          taskType: 'like',
          executionMode: 'browser',
          targetUrl: 'https://facebook.com/video/1',
          personaIps: const ['127.0.0.1', '127.0.0.1##2'],
          scheduledTime: DateTime.now().subtract(const Duration(minutes: 1)),
          maxRetries: 1,
        );
        final task = provider.tasks.last;

        // Lượt 1 -> retrying (1/1)
        final r1 = await provider.executeTaskNow(task);
        expect(r1!.status, 'retrying');
        expect(alerts, isEmpty);

        // Lượt 2 -> hết retry -> partial + bắn cảnh báo webhook
        await Future.delayed(const Duration(milliseconds: 50));
        await provider.checkAndRunDueTasks(bypassLoginCheck: true);

        final r2 = provider.getTaskById(task.id)!;
        expect(r2.status, 'partial');
        expect(r2.completedIps, ['127.0.0.1']);
        expect(r2.failedIps, ['127.0.0.1##2']);
        expect(alerts.length, 1);
        expect(alerts.first['event'], 'task_not_completed');
        expect(alerts.first['outcome'], 'partial');
        expect(alerts.first['user_request'], contains('Tác vụ lỗi liên tục ở nhân vật 2'));
      } finally {
        await server.close(force: true);
        notify
          ..configOverride = null
          ..logPathOverride = null
          ..desktopNotifyEnabled = true;
        provider.dispose();
      }
    });

    test('Tự động phát hiện và khôi phục task bị kẹt ở trạng thái running khi mở lại ứng dụng', () async {
      // Giả lập bản ghi bị bỏ kẹt ở trạng thái `running` trong SQLite do app tắt giữa chừng
      final stuckId = await DatabaseService().insertScheduleTask(
        ScheduleTaskModel(
          title: 'Task bị sập app giữa chừng',
          taskType: 'comment',
          executionMode: 'device',
          targetUrl: 'https://facebook.com/reel/999',
          personaIps: const ['127.0.0.1', '127.0.0.1##2', '127.0.0.1##3'],
          completedIps: const ['127.0.0.1'],
          scheduledTime: DateTime.now().subtract(const Duration(minutes: 10)),
          status: 'running',
          retryCount: 0,
          maxRetries: 3,
          startedAt: DateTime.now().subtract(const Duration(minutes: 10)),
        ),
      );
      expect(stuckId, greaterThan(0));

      final provider = ScheduleProvider(autoStart: false);
      await provider.loadTasks(recoverInterrupted: true);

      final recovered = provider.getTaskById(stuckId)!;
      expect(recovered.status, 'retrying');
      expect(recovered.completedIps, ['127.0.0.1']);
      expect(recovered.remainingIps, ['127.0.0.1##2', '127.0.0.1##3']);
      expect(recovered.retryCount, 1);
      expect(recovered.nextRetryAt, isNotNull);

      // Gỡ kẹt / đặt lại về pending thủ công
      final resetOk = await provider.cancelOrResetStuckTask(recovered, resetToPending: true);
      expect(resetOk, isTrue);
      final afterReset = provider.getTaskById(stuckId)!;
      expect(afterReset.status, 'pending');
      expect(afterReset.retryCount, 0);

      // Chỉnh sửa thông tin tác vụ và kiểm tra lưu bền vững
      final newTime = DateTime.now().add(const Duration(hours: 2));
      final editedOk = await provider.updateTask(
        existing: afterReset,
        title: 'Task đã tinh chỉnh giờ chạy',
        taskType: 'post',
        executionMode: 'browser',
        targetUrl: 'https://facebook.com/watch',
        commentContent: 'Caption mới',
        personaIps: const ['127.0.0.1', '127.0.0.1##2'],
        scheduledTime: newTime,
        resetToPending: true,
      );
      expect(editedOk, isTrue);
      final edited = provider.getTaskById(stuckId)!;
      expect(edited.title, 'Task đã tinh chỉnh giờ chạy');
      expect(edited.taskType, 'post');
      expect(edited.executionMode, 'browser');
      expect(edited.commentContent, 'Caption mới');
      expect(edited.personaIps, ['127.0.0.1', '127.0.0.1##2']);
      expect(edited.completedIps, isEmpty);
      expect(edited.status, 'pending');
      provider.dispose();
    });

    test('Khóa hàng đợi theo profile/thiết bị: bấm Chạy ngay 2 tác vụ cùng lúc trên cùng 1 profile vẫn chạy LẦN LƯỢT, không đụng nhau', () async {
      final provider = ScheduleProvider(autoStart: false)
        ..serverResolverOverride = (() async => null)
        ..maxConcurrentDeviceSlotsOverride = 2
        ..personasLoaderOverride = (() async => {
              '127.0.0.1': PersonaProfile(
                ip: '127.0.0.1',
                entryKey: '127.0.0.1',
                name: 'V',
                age: 26,
                gender: 'Nam',
                bio: 'Thích review video',
                avatarPrompt: '',
                avdName: 'Pixel_V',
              ),
            });

      final dueTime = DateTime.now().subtract(const Duration(minutes: 1));
      await provider.createTask(
        title: 'Bình luận',
        taskType: 'comment',
        executionMode: 'device',
        targetUrl: 'https://www.facebook.com/reel/1674895197482443',
        commentContent: 'Video ok lên rồi đó bạn!!!!',
        personaIps: const ['127.0.0.1'],
        scheduledTime: dueTime,
      );
      final task1 = provider.tasks.last;

      await provider.createTask(
        title: 'Thả tim',
        taskType: 'like',
        executionMode: 'device',
        targetUrl: 'https://www.facebook.com/reel/1674895197482443',
        personaIps: const ['127.0.0.1'],
        scheduledTime: dueTime,
      );
      final task2 = provider.tasks.last;

      final events = <String>[];
      int activeOnProfile = 0;
      int maxConcurrentOnProfile = 0;
      bool task2ObservedQueued = false;
      final task1Started = Completer<void>();
      final allowTask1Finish = Completer<void>();

      provider.aiTaskRunnerOverride = ({
        required persona,
        required task,
        required server,
        required prompt,
        required scopeWorkingDir,
        required onStatus,
        required isCancelled,
      }) async {
        activeOnProfile++;
        if (activeOnProfile > maxConcurrentOnProfile) {
          maxConcurrentOnProfile = activeOnProfile;
        }
        events.add('start:${task.title}');
        try {
          if (task.id == task1.id) {
            if (!task1Started.isCompleted) task1Started.complete();
            await allowTask1Finish.future;
          } else {
            await Future.delayed(const Duration(milliseconds: 25));
          }
          events.add('end:${task.title}');
          return AiTaskExecutionResult(
            outcome: 'completed',
            reply: 'Đã hoàn thành ${task.title}',
            evidence: 'Đã kiểm chứng ${task.title} trên màn hình thiết bị',
          );
        } finally {
          activeOnProfile--;
        }
      };

      // Giả lập bấm tay "Chạy ngay" liên tiếp trên cả 2 task
      final f1 = provider.executeTaskNow(task1);
      await task1Started.future;

      final lockAttemptedT2 = Completer<void>();
      final f2 = provider.executeTaskNow(
        task2,
        onFirstLockAttempted: () {
          if (!lockAttemptedT2.isCompleted) lockAttemptedT2.complete();
        },
      );
      await lockAttemptedT2.future;

      task2ObservedQueued = provider.isTaskQueuedForResource(task2.id);
      expect(task2ObservedQueued, isTrue);
      expect(provider.getTaskById(task2.id)!.resultNote, contains('Đang xếp hàng'));

      // Cho phép task 1 hoàn tất -> task 2 phải tự động chạy ngay sau đó
      allowTask1Finish.complete();
      final results = await Future.wait([f1, f2]);

      expect(maxConcurrentOnProfile, 1);
      expect(events, ['start:Bình luận', 'end:Bình luận', 'start:Thả tim', 'end:Thả tim']);
      expect(results[0]!.status, 'completed');
      expect(results[1]!.status, 'completed');
      expect(results[0]!.resultNote, contains('Bằng chứng:'));
      expect(provider.isTaskQueuedForResource(task2.id), isFalse);
      provider.dispose();
    });

    test('Hai profile khác nhau dùng chung thiết bị ngoại vi sẽ chạy lần lượt; dùng 2 thiết bị riêng chạy được song song', () async {
      final provider = ScheduleProvider(autoStart: false)
        ..serverResolverOverride = (() async => null)
        ..maxConcurrentDeviceSlotsOverride = 2
        ..personasLoaderOverride = (() async => {
              '10.0.0.1': PersonaProfile(
                ip: '10.0.0.1',
                entryKey: '10.0.0.1',
                name: 'NV A',
                age: 24,
                gender: 'Nữ',
                bio: '',
                avatarPrompt: '',
                useExternalDevice: true,
                externalDeviceAddress: '192.168.1.50:5555',
              ),
              '10.0.0.2': PersonaProfile(
                ip: '10.0.0.2',
                entryKey: '10.0.0.2',
                name: 'NV B',
                age: 25,
                gender: 'Nam',
                bio: '',
                avatarPrompt: '',
                useExternalDevice: true,
                externalDeviceAddress: '192.168.1.50:5555',
              ),
              '10.0.0.3': PersonaProfile(
                ip: '10.0.0.3',
                entryKey: '10.0.0.3',
                name: 'NV C',
                age: 27,
                gender: 'Nam',
                bio: '',
                avatarPrompt: '',
                avdName: 'Pixel_C',
              ),
            });

      final now = DateTime.now().subtract(const Duration(minutes: 1));
      await provider.createTask(
        title: 'Task NV A (chung máy ngoại vi)',
        taskType: 'like',
        executionMode: 'device',
        targetUrl: 'https://facebook.com/reel/1',
        personaIps: const ['10.0.0.1'],
        scheduledTime: now,
      );
      final taskA = provider.tasks.last;

      await provider.createTask(
        title: 'Task NV B (chung máy ngoại vi)',
        taskType: 'comment',
        executionMode: 'device',
        targetUrl: 'https://facebook.com/reel/1',
        commentContent: 'Tuyệt vời',
        personaIps: const ['10.0.0.2'],
        scheduledTime: now,
      );
      final taskB = provider.tasks.last;

      await provider.createTask(
        title: 'Task NV C (máy riêng)',
        taskType: 'like',
        executionMode: 'device',
        targetUrl: 'https://facebook.com/reel/2',
        personaIps: const ['10.0.0.3'],
        scheduledTime: now,
      );
      final taskC = provider.tasks.last;

      int activeSharedExt = 0;
      int maxActiveSharedExt = 0;
      int totalActive = 0;
      int maxTotalActive = 0;

      provider.aiTaskRunnerOverride = ({
        required persona,
        required task,
        required server,
        required prompt,
        required scopeWorkingDir,
        required onStatus,
        required isCancelled,
      }) async {
        totalActive++;
        if (totalActive > maxTotalActive) maxTotalActive = totalActive;
        final isShared = persona.effectiveEntryKey == '10.0.0.1' || persona.effectiveEntryKey == '10.0.0.2';
        if (isShared) {
          activeSharedExt++;
          if (activeSharedExt > maxActiveSharedExt) maxActiveSharedExt = activeSharedExt;
        }
        try {
          await Future.delayed(const Duration(milliseconds: 60));
          return const AiTaskExecutionResult(
            outcome: 'completed',
            reply: 'OK',
            evidence: 'Verified',
          );
        } finally {
          if (isShared) activeSharedExt--;
          totalActive--;
        }
      };

      await Future.wait([
        provider.executeTaskNow(taskA),
        provider.executeTaskNow(taskB),
        provider.executeTaskNow(taskC),
      ]);

      expect(maxActiveSharedExt, 1);
      expect(maxTotalActive, 2);
      expect(provider.getTaskById(taskA.id)!.status, 'completed');
      expect(provider.getTaskById(taskB.id)!.status, 'completed');
      expect(provider.getTaskById(taskC.id)!.status, 'completed');
      provider.dispose();
    });

    test('Hủy một tác vụ đang xếp hàng sẽ thoát ngay không chặn tác vụ phía sau', () async {
      final provider = ScheduleProvider(autoStart: false)
        ..serverResolverOverride = (() async => null)
        ..personasLoaderOverride = (() async => {
              '127.0.0.9': PersonaProfile(
                ip: '127.0.0.9',
                entryKey: '127.0.0.9',
                name: 'NV Queue',
                age: 25,
                gender: 'Nam',
                bio: '',
                avatarPrompt: '',
              ),
            });

      final t = DateTime.now().subtract(const Duration(minutes: 1));
      await provider.createTask(
        title: 'Task 1 giữ khóa',
        taskType: 'like',
        executionMode: 'device',
        targetUrl: 'https://facebook.com/reel/1',
        personaIps: const ['127.0.0.9'],
        scheduledTime: t,
      );
      final t1 = provider.tasks.last;

      await provider.createTask(
        title: 'Task 2 sẽ bị hủy khi xếp hàng',
        taskType: 'comment',
        executionMode: 'device',
        targetUrl: 'https://facebook.com/reel/1',
        personaIps: const ['127.0.0.9'],
        scheduledTime: t,
      );
      final t2 = provider.tasks.last;

      await provider.createTask(
        title: 'Task 3 đứng sau',
        taskType: 'like',
        executionMode: 'device',
        targetUrl: 'https://facebook.com/reel/1',
        personaIps: const ['127.0.0.9'],
        scheduledTime: t,
      );
      final t3 = provider.tasks.last;

      final ranTitles = <String>[];
      final t1Running = Completer<void>();
      final releaseT1 = Completer<void>();

      provider.aiTaskRunnerOverride = ({
        required persona,
        required task,
        required server,
        required prompt,
        required scopeWorkingDir,
        required onStatus,
        required isCancelled,
      }) async {
        ranTitles.add(task.title);
        if (task.id == t1.id) {
          if (!t1Running.isCompleted) t1Running.complete();
          await releaseT1.future;
        }
        return const AiTaskExecutionResult(outcome: 'completed', reply: 'OK', evidence: 'OK');
      };

      final f1 = provider.executeTaskNow(t1);
      await t1Running.future;

      final t2Queued = Completer<void>();
      final f2 = provider.executeTaskNow(t2, onFirstLockAttempted: () {
        if (!t2Queued.isCompleted) t2Queued.complete();
      });
      await t2Queued.future;

      final t3Queued = Completer<void>();
      final f3 = provider.executeTaskNow(t3, onFirstLockAttempted: () {
        if (!t3Queued.isCompleted) t3Queued.complete();
      });
      await t3Queued.future;

      // Hủy Task 2 ngay trong lúc Task 1 vẫn đang giữ khóa
      await provider.cancelOrResetStuckTask(t2, resetToPending: false);
      final res2 = await f2.timeout(const Duration(seconds: 2));
      expect(res2!.status, 'cancelled');

      // Cho Task 1 xong -> Task 3 chạy tiếp, Task 2 không bao giờ chạy
      releaseT1.complete();
      await Future.wait([f1, f3]);

      expect(ranTitles, ['Task 1 giữ khóa', 'Task 3 đứng sau']);
      expect(provider.getTaskById(t1.id)!.status, 'completed');
      expect(provider.getTaskById(t3.id)!.status, 'completed');
      provider.dispose();
    });

    test('AI Agent thực thi tác vụ hẹn giờ: chưa xác nhận 100% sẽ KHÔNG hoàn tất giả, tự thử lại đến khi xác nhận xong', () async {
      final provider = ScheduleProvider(autoStart: false)
        ..serverResolverOverride = (() async => null)
        ..retryBackoffSteps = const [Duration(milliseconds: 20)]
        ..personasLoaderOverride = (() async => {
              '127.0.0.1': PersonaProfile(
                ip: '127.0.0.1',
                entryKey: '127.0.0.1',
                name: 'V',
                age: 28,
                gender: 'Nam',
                bio: 'Người dùng thật',
                avatarPrompt: '',
              ),
            });

      await provider.createTask(
        title: 'Bình luận Reel',
        taskType: 'comment',
        executionMode: 'device',
        targetUrl: 'https://www.facebook.com/reel/1674895197482443',
        commentContent: 'Video ok lên rồi đó bạn!!!!',
        personaIps: const ['127.0.0.1'],
        scheduledTime: DateTime.now().subtract(const Duration(minutes: 1)),
        maxRetries: 2,
      );
      final task = provider.tasks.last;

      String? capturedPrompt;
      String? capturedScope;
      int attempts = 0;

      provider.aiTaskRunnerOverride = ({
        required persona,
        required task,
        required server,
        required prompt,
        required scopeWorkingDir,
        required onStatus,
        required isCancelled,
      }) async {
        attempts++;
        capturedPrompt = prompt;
        capturedScope = scopeWorkingDir;
        if (attempts == 1) {
          return const AiTaskExecutionResult(
            outcome: 'incomplete',
            reply: 'Chưa bấm gửi được bình luận',
            failureReason: 'Không tìm thấy nút Gửi trên màn hình lần đầu',
          );
        }
        return const AiTaskExecutionResult(
          outcome: 'completed',
          reply: 'Đã gửi bình luận thành công',
          evidence: 'Đã thấy bình luận "Video ok lên rồi đó bạn!!!!" hiển thị trong UI dump',
        );
      };

      // Lượt 1: AI Agent dừng giữa chừng (incomplete) -> phải sang retrying
      final r1 = await provider.executeTaskNow(task);
      expect(r1!.status, 'retrying');
      expect(r1.completedIps, isEmpty);
      expect(capturedPrompt, contains('Video ok lên rồi đó bạn!!!!'));
      expect(capturedPrompt, contains('https://www.facebook.com/reel/1674895197482443'));
      expect(capturedPrompt, contains('report_task_result'));
      expect(capturedScope, contains('ProfileKey: 127.0.0.1'));
      expect(capturedScope, contains('THIẾT BỊ / DEVICE'));

      // Lượt 2 qua auto-scheduler: AI Agent xác nhận completed -> đánh dấu 100% kèm bằng chứng
      await Future.delayed(const Duration(milliseconds: 40));
      await provider.checkAndRunDueTasks(bypassLoginCheck: true);

      final r2 = provider.getTaskById(task.id)!;
      expect(r2.status, 'completed');
      expect(r2.completedIps, ['127.0.0.1']);
      expect(r2.resultNote, contains('Video ok lên rồi đó bạn!!!!'));
      provider.dispose();
    });

    test('Auto-scheduler với 2 tác vụ trùng giờ 13:15 trên cùng 1 profile chạy đúng thứ tự FIFO và không chồng chéo', () async {
      final provider = ScheduleProvider(autoStart: false)
        ..serverResolverOverride = (() async => null)
        ..personasLoaderOverride = (() async => {
              '127.0.0.5': PersonaProfile(
                ip: '127.0.0.5',
                entryKey: '127.0.0.5',
                name: 'V',
                age: 26,
                gender: 'Nam',
                bio: '',
                avatarPrompt: '',
              ),
            });

      final exactSameTime = DateTime.now().subtract(const Duration(seconds: 30));
      await provider.createTask(
        title: 'Bình luận 13:15',
        taskType: 'comment',
        executionMode: 'device',
        targetUrl: 'https://www.facebook.com/reel/1674895197482443',
        commentContent: 'Video ok lên rồi đó bạn!!!!',
        personaIps: const ['127.0.0.5'],
        scheduledTime: exactSameTime,
      );
      await provider.createTask(
        title: 'Thả tim 13:15',
        taskType: 'like',
        executionMode: 'device',
        targetUrl: 'https://www.facebook.com/reel/1674895197482443',
        personaIps: const ['127.0.0.5'],
        scheduledTime: exactSameTime,
      );

      final trace = <String>[];
      int concurrent = 0;
      int maxConcurrent = 0;

      provider.aiTaskRunnerOverride = ({
        required persona,
        required task,
        required server,
        required prompt,
        required scopeWorkingDir,
        required onStatus,
        required isCancelled,
      }) async {
        concurrent++;
        if (concurrent > maxConcurrent) maxConcurrent = concurrent;
        trace.add('begin:${task.title}');
        await Future.delayed(const Duration(milliseconds: 35));
        trace.add('done:${task.title}');
        concurrent--;
        return const AiTaskExecutionResult(outcome: 'completed', reply: 'OK', evidence: 'Xác nhận thành công');
      };

      await provider.checkAndRunDueTasks(bypassLoginCheck: true);

      expect(maxConcurrent, 1);
      expect(trace, [
        'begin:Bình luận 13:15',
        'done:Bình luận 13:15',
        'begin:Thả tim 13:15',
        'done:Thả tim 13:15',
      ]);
      provider.dispose();
    });

    test('Sinh mxh-tool hợp lệ (ui-dump, adb-tap, adb-type, adb-screenshot) và trích xuất bằng chứng MXH_TASK_STATUS', () async {
      final helperPath = await CliAutomationBridgeService().ensureCliHelperInstalled();
      expect(File(helperPath).existsSync(), isTrue);

      final compileRes = await Process.run('python3', ['-m', 'py_compile', helperPath]);
      expect(compileRes.exitCode, 0, reason: 'mxh-tool phải biên dịch Python không lỗi: ${compileRes.stderr}');

      final helpRes = await Process.run('python3', [helperPath, '--help']);
      expect(helpRes.exitCode, 0);
      final helpText = helpRes.stdout.toString();
      expect(helpText, contains('ui-dump'));
      expect(helpText, contains('adb-tap'));
      expect(helpText, contains('adb-type'));
      expect(helpText, contains('adb-screenshot'));

      final parsed = NativeAiService.parseCliTaskStatus(
        'Đã hoàn tất thao tác.\nMXH_TASK_STATUS: COMPLETED: Nút Like đã chuyển sang selected=true trong ui-dump\n',
      );
      expect(parsed.status, 'completed');
      expect(parsed.evidence, 'Nút Like đã chuyển sang selected=true trong ui-dump');

      final persona = PersonaProfile(
        ip: '127.0.0.1',
        entryKey: '127.0.0.1##2',
        name: 'Vịnh Xuân Quyền',
        age: 25,
        gender: 'Nam',
        bio: '',
        avatarPrompt: '',
      );
      final prompt = ScheduleProvider.buildScheduledTaskPrompt(
        ScheduleTaskModel(
          title: 'Bình luận',
          taskType: 'comment',
          executionMode: 'device',
          targetUrl: 'https://www.facebook.com/reel/1674895197482443',
          commentContent: 'Video ok lên rồi đó bạn!!!!',
          personaIps: const ['127.0.0.1##2'],
          scheduledTime: DateTime.now(),
        ),
        persona,
        adbSerial: 'emulator-5554',
        adbPath: '/home/yenai/Android/Sdk/platform-tools/adb',
        mxhToolPath: helperPath,
      );
      expect(prompt, contains('emulator-5554'));
      expect(prompt, contains('ui-dump --serial emulator-5554'));
      expect(prompt, contains('adb-type --serial emulator-5554'));
      expect(prompt, contains('Video ok lên rồi đó bạn!!!!'));
      expect(prompt, contains('MXH_TASK_STATUS: COMPLETED:'));
    });
  });
}
