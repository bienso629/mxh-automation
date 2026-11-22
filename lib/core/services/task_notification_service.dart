import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:mailer/mailer.dart' as mailer;
import 'package:mailer/smtp_server.dart' as smtp;
import 'package:path/path.dart' as p;
import 'local_config_service.dart';

/// Kết quả gửi cảnh báo qua các kênh
class TaskNotificationResult {
  final List<String> delivered;
  final Map<String, String> errors;

  const TaskNotificationResult({required this.delivered, required this.errors});

  bool get anyRemoteDelivered => delivered.any((c) => c != 'Nhật ký cục bộ' && c != 'Thông báo desktop');

  String describe() {
    final parts = <String>[];
    if (delivered.isNotEmpty) parts.add('Đã gửi qua: ${delivered.join(', ')}');
    if (errors.isNotEmpty) {
      parts.add('Lỗi kênh: ${errors.entries.map((e) => '${e.key} (${e.value})').join('; ')}');
    }
    if (!anyRemoteDelivered) {
      parts.add('Chưa cấu hình kênh Email / Telegram / Webhook máy chủ trong Cài đặt > mục 6');
    }
    return parts.join('. ');
  }
}

/// Dịch vụ cảnh báo khi AI Agent KHÔNG hoàn thành được tác vụ.
/// Kênh hỗ trợ:
/// - Webhook máy chủ (POST JSON) - `notify_webhook_url`, `notify_webhook_secret`
/// - Telegram Bot - `notify_telegram_bot_token`, `notify_telegram_chat_id`
/// - Email SMTP - `notify_email_to`, `notify_smtp_host`, `notify_smtp_port`, `notify_smtp_user`, `notify_smtp_pass`, `notify_smtp_ssl`
/// - Luôn ghi nhật ký cục bộ `~/.agent_mxh_auto/task_failures.log` và thông báo desktop (Linux notify-send)
class TaskNotificationService {
  static final TaskNotificationService _instance = TaskNotificationService._internal();
  factory TaskNotificationService() => _instance;
  TaskNotificationService._internal();

  final LocalConfigService _configService = LocalConfigService();

  /// Chỉ dùng cho kiểm thử: ghi đè cấu hình kênh và đường dẫn nhật ký
  Map<String, dynamic>? configOverride;
  String? logPathOverride;
  bool desktopNotifyEnabled = true;

  static String _str(Map<String, dynamic> cfg, String key) => (cfg[key] ?? '').toString().trim();

  static bool _bool(Map<String, dynamic> cfg, String key, {bool fallback = true}) {
    final v = cfg[key];
    if (v == null) return fallback;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    if (s.isEmpty) return fallback;
    return s == 'true' || s == '1' || s == 'yes';
  }

  String _logFilePath() {
    if (logPathOverride != null) return logPathOverride!;
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final dir = Directory(p.join(home, '.agent_mxh_auto'));
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {}
    }
    return p.join(dir.path, 'task_failures.log');
  }

  /// Gửi cảnh báo tác vụ không hoàn thành
  Future<TaskNotificationResult> notifyTaskFailure({
    required String userRequest,
    required String reason,
    required String outcome,
    String? sessionId,
    String? engine,
    List<String> personas = const [],
    List<String> recentSteps = const [],
  }) async {
    final now = DateTime.now();
    final host = Platform.localHostname;
    final payload = <String, dynamic>{
      'event': 'task_not_completed',
      'outcome': outcome,
      'reason': reason,
      'user_request': userRequest,
      'session_id': sessionId,
      'engine': engine,
      'personas': personas,
      'recent_steps': recentSteps,
      'machine': host,
      'time': now.toIso8601String(),
    };

    final title = '[MXH Tự Động] Tác vụ KHÔNG hoàn thành trên máy $host';
    final body = StringBuffer()
      ..writeln(title)
      ..writeln('Thời gian: ${now.toIso8601String()}')
      ..writeln('Kết quả: $outcome')
      ..writeln('Lý do: $reason')
      ..writeln('Nhân vật: ${personas.isEmpty ? '(không chỉ định)' : personas.join(', ')}')
      ..writeln('Engine: ${engine ?? '-'}')
      ..writeln('Phiên chat: ${sessionId ?? '-'}')
      ..writeln('')
      ..writeln('Yêu cầu của người dùng:')
      ..writeln(_truncate(userRequest, 1500));
    if (recentSteps.isNotEmpty) {
      body
        ..writeln('')
        ..writeln('Các bước gần nhất:');
      for (final s in recentSteps) {
        body.writeln('- ${_truncate(s, 300)}');
      }
    }

    return _dispatch(title: title, text: body.toString(), payload: payload);
  }

  /// Gửi thử cảnh báo để kiểm tra cấu hình kênh
  Future<TaskNotificationResult> sendTest() {
    final title = '[MXH Tự Động] Kiểm tra kênh cảnh báo';
    final text = '$title\nNếu bạn nhận được tin này, kênh cảnh báo đã cấu hình đúng.\nMáy: ${Platform.localHostname}\nThời gian: ${DateTime.now().toIso8601String()}';
    return _dispatch(
      title: title,
      text: text,
      payload: {'event': 'test', 'machine': Platform.localHostname, 'time': DateTime.now().toIso8601String()},
    );
  }

  Future<TaskNotificationResult> _dispatch({
    required String title,
    required String text,
    required Map<String, dynamic> payload,
  }) async {
    final delivered = <String>[];
    final errors = <String, String>{};

    Map<String, dynamic> cfg = {};
    try {
      cfg = configOverride ?? await _configService.loadConfig();
    } catch (_) {}

    // 1. Nhật ký cục bộ (luôn ghi)
    try {
      await File(_logFilePath()).writeAsString('${jsonEncode(payload)}\n', mode: FileMode.append, flush: true);
      delivered.add('Nhật ký cục bộ');
    } catch (e) {
      errors['Nhật ký cục bộ'] = e.toString();
    }

    final futures = <Future<void>>[];

    // 2. Webhook máy chủ
    final webhookUrl = _str(cfg, 'notify_webhook_url');
    if (webhookUrl.isNotEmpty) {
      futures.add(() async {
        try {
          final secret = _str(cfg, 'notify_webhook_secret');
          final res = await http
              .post(
                Uri.parse(webhookUrl),
                headers: {
                  'Content-Type': 'application/json; charset=utf-8',
                  if (secret.isNotEmpty) 'Authorization': 'Bearer $secret',
                  if (secret.isNotEmpty) 'X-MXH-Secret': secret,
                },
                body: jsonEncode({...payload, 'title': title, 'text': text}),
              )
              .timeout(const Duration(seconds: 15));
          if (res.statusCode >= 200 && res.statusCode < 300) {
            delivered.add('Webhook máy chủ');
          } else {
            errors['Webhook máy chủ'] = 'HTTP ${res.statusCode}';
          }
        } catch (e) {
          errors['Webhook máy chủ'] = e.toString();
        }
      }());
    }

    // 3. Telegram
    final tgToken = _str(cfg, 'notify_telegram_bot_token');
    final tgChat = _str(cfg, 'notify_telegram_chat_id');
    if (tgToken.isNotEmpty && tgChat.isNotEmpty) {
      futures.add(() async {
        try {
          final res = await http
              .post(
                Uri.parse('https://api.telegram.org/bot$tgToken/sendMessage'),
                headers: {'Content-Type': 'application/json; charset=utf-8'},
                body: jsonEncode({'chat_id': tgChat, 'text': _truncate(text, 3900), 'disable_web_page_preview': true}),
              )
              .timeout(const Duration(seconds: 15));
          if (res.statusCode == 200) {
            delivered.add('Telegram');
          } else {
            errors['Telegram'] = 'HTTP ${res.statusCode}: ${_truncate(res.body, 200)}';
          }
        } catch (e) {
          errors['Telegram'] = e.toString();
        }
      }());
    }

    // 4. Email SMTP
    final emailTo = _str(cfg, 'notify_email_to');
    final smtpHost = _str(cfg, 'notify_smtp_host');
    if (emailTo.isNotEmpty && smtpHost.isNotEmpty) {
      futures.add(() async {
        try {
          final smtpUser = _str(cfg, 'notify_smtp_user');
          final smtpPass = _str(cfg, 'notify_smtp_pass');
          final useSsl = _bool(cfg, 'notify_smtp_ssl', fallback: true);
          final port = int.tryParse(_str(cfg, 'notify_smtp_port')) ?? (useSsl ? 465 : 587);
          final server = smtp.SmtpServer(
            smtpHost,
            port: port,
            ssl: useSsl,
            username: smtpUser.isNotEmpty ? smtpUser : null,
            password: smtpPass.isNotEmpty ? smtpPass : null,
            allowInsecure: !useSsl,
          );
          final fromAddr = smtpUser.contains('@') ? smtpUser : emailTo.split(',').first.trim();
          final msg = mailer.Message()
            ..from = mailer.Address(fromAddr, 'MXH Tự Động')
            ..recipients.addAll(emailTo.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty))
            ..subject = title
            ..text = text;
          await mailer.send(msg, server, timeout: const Duration(seconds: 25));
          delivered.add('Email');
        } catch (e) {
          errors['Email'] = _truncate(e.toString(), 300);
        }
      }());
    }

    // 5. Thông báo desktop (best-effort)
    if (Platform.isLinux && desktopNotifyEnabled) {
      futures.add(() async {
        try {
          final r = await Process.run('notify-send', ['-u', 'critical', title, _truncate(text, 500)])
              .timeout(const Duration(seconds: 3));
          if (r.exitCode == 0) delivered.add('Thông báo desktop');
        } catch (_) {}
      }());
    }

    await Future.wait(futures);
    return TaskNotificationResult(delivered: delivered, errors: errors);
  }

  static String _truncate(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}...';
}
