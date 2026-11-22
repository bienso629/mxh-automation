import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:agent_mxh_auto/core/services/browser_cdp_service.dart';
import 'package:agent_mxh_auto/core/services/native_ai_service.dart';
import 'package:agent_mxh_auto/core/services/task_notification_service.dart';

/// Kiểm thử cơ chế "hoàn thành 100% hoặc cảnh báo":
/// 1. Điều khiển trình duyệt thật qua CDP: đọc trang, bấm nút, gõ nội dung, tải tệp video lên, chờ, kiểm chứng.
/// 2. Gửi cảnh báo về máy chủ (webhook) + ghi nhật ký khi tác vụ không hoàn thành.
/// 3. Nhận diện dòng trạng thái hoàn thành của Local CLI Agent.
/// Toàn bộ tệp tạm nằm trong .dart_tool/mxh_test của dự án.
void main() {
  final workDir = Directory(p.join(Directory.current.path, '.dart_tool', 'mxh_test'));

  setUpAll(() {
    if (workDir.existsSync()) workDir.deleteSync(recursive: true);
    workDir.createSync(recursive: true);
  });

  tearDownAll(() {
    try {
      if (workDir.existsSync()) workDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Nhận diện trạng thái hoàn thành của CLI Agent', () {
    test('COMPLETED, FAILED kèm lý do và thiếu dòng trạng thái', () {
      final ok = NativeAiService.parseCliTaskStatus('Đã đăng video.\nMXH_TASK_STATUS: COMPLETED\n');
      expect(ok.status, 'completed');

      final fail = NativeAiService.parseCliTaskStatus('...\nMXH_TASK_STATUS: FAILED: Tài khoản chưa đăng nhập Facebook');
      expect(fail.status, 'failed');
      expect(fail.reason, 'Tài khoản chưa đăng nhập Facebook');

      final missing = NativeAiService.parseCliTaskStatus('Đã mở trình duyệt, đang chuẩn bị tải video...');
      expect(missing.status, isNull);

      // Dòng trạng thái cuối cùng mới có hiệu lực
      final last = NativeAiService.parseCliTaskStatus('MXH_TASK_STATUS: FAILED: tạm thời\n...\nMXH_TASK_STATUS: COMPLETED');
      expect(last.status, 'completed');
    });

    test('Yêu cầu đăng video được xem là tác vụ cần giám sát', () {
      expect(NativeAiService.isActionRequest('Upload video này lên Facebook cho nhân vật'), isTrue);
      expect(NativeAiService.isActionRequest('Đăng video lên trang cá nhân'), isTrue);
    });
  });

  group('Cảnh báo khi tác vụ không hoàn thành', () {
    test('Gửi webhook về máy chủ và ghi nhật ký cục bộ', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = <Map<String, dynamic>>[];
      String? authHeader;
      server.listen((req) async {
        authHeader = req.headers.value('authorization');
        final body = await utf8.decoder.bind(req).join();
        received.add(jsonDecode(body) as Map<String, dynamic>);
        req.response.statusCode = 200;
        await req.response.close();
      });

      final logPath = p.join(workDir.path, 'task_failures.log');
      final svc = TaskNotificationService()
        ..configOverride = {
          'notify_webhook_url': 'http://127.0.0.1:${server.port}/alert',
          'notify_webhook_secret': 'bi-mat-123',
        }
        ..logPathOverride = logPath
        ..desktopNotifyEnabled = false;

      final res = await svc.notifyTaskFailure(
        userRequest: 'Upload video demo.mp4 lên Facebook',
        reason: 'Agent dừng lại mà không xác nhận hoàn thành',
        outcome: 'incomplete',
        sessionId: 's_test',
        engine: 'glm-5.3',
        personas: ['127.0.0.1##2'],
        recentSteps: ['open_profile_browser => Đã mở trình duyệt'],
      );
      await server.close(force: true);

      expect(res.delivered, containsAll(['Nhật ký cục bộ', 'Webhook máy chủ']));
      expect(res.errors, isEmpty);
      expect(res.anyRemoteDelivered, isTrue);
      expect(received.length, 1);
      expect(received.first['event'], 'task_not_completed');
      expect(received.first['outcome'], 'incomplete');
      expect(received.first['personas'], ['127.0.0.1##2']);
      expect(authHeader, 'Bearer bi-mat-123');

      final logLines = File(logPath).readAsLinesSync();
      expect(logLines.length, 1);
      expect(jsonDecode(logLines.first)['reason'], 'Agent dừng lại mà không xác nhận hoàn thành');

      svc
        ..configOverride = null
        ..logPathOverride = null
        ..desktopNotifyEnabled = true;
    });

    test('Không cấu hình kênh nào vẫn ghi nhật ký và báo rõ cần cấu hình', () async {
      final svc = TaskNotificationService()
        ..configOverride = {}
        ..logPathOverride = p.join(workDir.path, 'only_log.log')
        ..desktopNotifyEnabled = false;
      final res = await svc.notifyTaskFailure(userRequest: 'x', reason: 'y', outcome: 'failed');
      expect(res.delivered, ['Nhật ký cục bộ']);
      expect(res.anyRemoteDelivered, isFalse);
      expect(res.describe(), contains('Chưa cấu hình kênh'));
      svc
        ..configOverride = null
        ..logPathOverride = null
        ..desktopNotifyEnabled = true;
    });
  });

  group('Điều khiển trình duyệt thật qua DevTools (CDP)', () {
    String? chrome;
    for (final c in ['/usr/bin/google-chrome', '/usr/bin/google-chrome-stable', '/usr/bin/chromium', '/usr/bin/chromium-browser']) {
      if (File(c).existsSync()) {
        chrome = c;
        break;
      }
    }

    test('Mô phỏng đăng video: bấm Ảnh/video -> tải tệp -> nhập nội dung -> Đăng -> kiểm chứng', () async {
      final profileDir = Directory(p.join(workDir.path, 'profile'))..createSync(recursive: true);
      final videoFile = File(p.join(workDir.path, 'demo video.mp4'))..writeAsBytesSync(List<int>.filled(4096, 7));
      final page = File(p.join(workDir.path, 'composer.html'))
        ..writeAsStringSync('''<!doctype html><html><head><meta charset="utf-8"><title>Composer</title></head><body>
<button id="open" aria-label="Ảnh/video" onclick="document.getElementById('box').style.display='block'">Ảnh/video</button>
<div id="box" style="display:none">
  <input id="file" type="file" accept="video/*,image/*" style="display:none" onchange="document.getElementById('st').innerText='Đã tải lên: '+this.files[0].name; document.getElementById('post').disabled=false;">
  <div id="editor" contenteditable="true" aria-label="Bạn đang nghĩ gì?" style="min-height:40px;border:1px solid #000"></div>
  <button id="post" disabled onclick="document.body.innerHTML='<h1>Bài viết đã được đăng: '+document.getElementById('editor').innerText+'</h1>'">Đăng</button>
  <p id="st">Chưa có tệp</p>
</div></body></html>''');

      const key = 'test-key##1';
      final cdp = BrowserCdpService();
      cdp.profileDirOverrides[key] = profileDir;

      final proc = await Process.start(chrome!, [
        '--headless=new',
        '--no-first-run',
        '--no-default-browser-check',
        '--disable-gpu',
        '--user-data-dir=${profileDir.path}',
        '--remote-debugging-port=0',
        Uri.file(page.path).toString(),
      ]);
      proc.stdout.drain();
      proc.stderr.drain();

      try {
        final port = await cdp.waitForDebugPort(key, timeout: const Duration(seconds: 25));
        expect(port, isNotNull, reason: 'Chrome phải ghi DevToolsActivePort');
        await Future.delayed(const Duration(seconds: 1));

        final snap1 = jsonDecode(await cdp.snapshot(key)) as Map<String, dynamic>;
        expect(snap1['title'], 'Composer');
        final els = (snap1['elements'] as List).cast<Map<String, dynamic>>();
        final openBtn = els.firstWhere((e) => e['label'] == 'Ảnh/video');

        // Trước khi chọn tệp: chưa có ô tải lên hiển thị => upload phải báo lỗi rõ ràng hoặc gắn vào input ẩn
        expect(await cdp.click(key, elementId: openBtn['id'] as int), contains('Ảnh/video'));

        // Nút Đăng đang disabled -> bấm phải báo lỗi chứ không "giả vờ" thành công
        expect(await cdp.click(key, text: 'Đăng'), contains('vô hiệu hóa'));

        final up = await cdp.uploadFile(key, filePath: videoFile.path);
        expect(up, contains('demo video.mp4'));
        expect(await cdp.waitFor(key, text: 'Đã tải lên: demo video.mp4', seconds: 10), contains('Đã thấy'));

        final snap2 = jsonDecode(await cdp.snapshot(key)) as Map<String, dynamic>;
        final editor = (snap2['elements'] as List).cast<Map<String, dynamic>>().firstWhere((e) => e['editable'] == true);
        expect(await cdp.type(key, elementId: editor['id'] as int, text: 'Video mới của tôi'), contains('Đã nhập'));

        expect(await cdp.click(key, text: 'Đăng'), contains('Đăng'));
        final verify = await cdp.waitFor(key, text: 'Bài viết đã được đăng: Video mới của tôi', seconds: 10);
        expect(verify, contains('Đã thấy'));

        // Tệp không tồn tại phải bị từ chối
        expect(await cdp.uploadFile(key, filePath: '/khong/ton/tai.mp4'), startsWith('LỖI'));
      } finally {
        await cdp.disconnect(key);
        cdp.profileDirOverrides.remove(key);
        proc.kill(ProcessSignal.sigterm);
        await proc.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          return -1;
        });
      }
    }, skip: chrome == null ? 'Máy không có Chrome/Chromium' : false, timeout: const Timeout(Duration(minutes: 2)));
  });
}
