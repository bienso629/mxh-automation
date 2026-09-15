// ignore_for_file: use_null_aware_elements
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../../models/server_model.dart';
import '../../models/metrics_model.dart';
import '../../models/attachment_item.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import 'storage_service.dart';
import 'local_config_service.dart';
import 'database_service.dart';
import 'native_ai_service.dart';
import 'native_ssh_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final StorageService _storage = StorageService();
  final http.Client _client = http.Client();

  final LocalConfigService _localConfig = LocalConfigService();
  final DatabaseService _db = DatabaseService();
  final NativeAiService _ai = NativeAiService();
  final NativeSshService _ssh = NativeSshService();

  Future<bool> _isNativeMode() async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return true;
    }
    final gatewayUrl = await _storage.getGatewayUrl();
    // Use Native Mode if gateway is default localhost or empty
    return gatewayUrl.isEmpty ||
        gatewayUrl.contains('127.0.0.1:8888') ||
        gatewayUrl.contains('localhost:8888');
  }

  Future<Map<String, String>> _getHeaders({bool isJson = true}) async {
    final token = await _storage.getSecretToken();
    final userEmail = await _storage.getUserEmail();
    final headers = <String, String>{
      if (isJson) 'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
    };
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
      headers['X-Secret-Token'] = token;
    }
    if (userEmail != null && userEmail.isNotEmpty) {
      headers['X-User-Email'] = userEmail;
      final username = userEmail.split('@')[0];
      headers['X-User-Name'] = username;
    }
    return headers;
  }

  Future<String> _getBaseUrl() async {
    return await _storage.getGatewayUrl();
  }

  // 1. Connectivity & Ping Check
  Future<bool> checkHealth() async {
    if (await _isNativeMode()) {
      return true;
    }
    try {
      final baseUrl = await _getBaseUrl();
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epConfig}'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // 2. Config APIs
  Future<Map<String, dynamic>> getConfig() async {
    if (await _isNativeMode()) {
      return await _localConfig.loadConfig();
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.get(
      Uri.parse('$baseUrl${ApiConstants.epConfig}'),
      headers: await _getHeaders(),
    );
    if (res.statusCode == 200) {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    }
    throw Exception('Failed to load config: ${res.statusCode}');
  }

  Future<bool> saveConfig(Map<String, dynamic> config) async {
    if (await _isNativeMode()) {
      return await _localConfig.saveConfig(config);
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epConfig}'),
      headers: await _getHeaders(),
      body: jsonEncode(config),
    );
    return res.statusCode == 200;
  }

  // 3. Servers Management APIs
  Future<List<ServerModel>> getServers() async {
    if (await _isNativeMode()) {
      return await _localConfig.getServers();
    }
    final baseUrl = await _getBaseUrl();
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epServers}'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is List) {
          return data.map((e) => ServerModel.fromJson(e as Map<String, dynamic>)).toList();
        } else if (data is Map<String, dynamic> && data['servers'] is List) {
          final list = data['servers'] as List;
          return list.map((e) => ServerModel.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<bool> selectServer(String serverIp) async {
    if (await _isNativeMode()) {
      final servers = await _localConfig.getServers();
      final target = servers.firstWhere(
        (s) => s.serverIp == serverIp,
        orElse: () => ServerModel(id: serverIp, name: serverIp, serverIp: serverIp),
      );
      return await _localConfig.selectServer(target);
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epServersSelect}'),
      headers: await _getHeaders(),
      body: jsonEncode({'server_ip': serverIp}),
    );
    return res.statusCode == 200;
  }

  Future<bool> updateServer(ServerModel server) async {
    if (await _isNativeMode()) {
      return await _localConfig.addOrUpdateServer(server);
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epServersUpdate}'),
      headers: await _getHeaders(),
      body: jsonEncode(server.toJson()),
    );
    return res.statusCode == 200;
  }

  Future<bool> deleteServer(String serverIp) async {
    if (await _isNativeMode()) {
      return await _localConfig.deleteServer(serverIp);
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epServersDelete}'),
      headers: await _getHeaders(),
      body: jsonEncode({'server_ip': serverIp}),
    );
    return res.statusCode == 200;
  }

  // 4. System Metrics & Info
  Future<SystemMetricsModel> getSystemMetrics() async {
    if (await _isNativeMode()) {
      return await _ssh.getSystemMetrics();
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.get(
      Uri.parse('$baseUrl${ApiConstants.epSystemInfo}'),
      headers: await _getHeaders(),
    ).timeout(const Duration(seconds: 8));

    if (res.statusCode == 200) {
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return SystemMetricsModel.fromJson(json);
    }
    throw Exception('Failed to get metrics: ${res.statusCode}');
  }

  Future<Map<String, dynamic>> executeServiceAction(String service, String action) async {
    if (await _isNativeMode()) {
      return await _ssh.executeServiceAction(service, action);
    }
    final baseUrl = await _getBaseUrl();
    try {
      final res = await _client.post(
        Uri.parse('$baseUrl${ApiConstants.epServiceAction}'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'service': service,
          'action': action,
        }),
      );
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {'status': 'error', 'message': 'Không thể kết nối đến máy chủ'};
  }

  // 5. Service Logs API
  Future<String> getServerLogs({int lines = 100}) async {
    if (await _isNativeMode()) {
      return await _ssh.getServerLogs(lines: lines);
    }
    final baseUrl = await _getBaseUrl();
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epServerLogs}?lines=$lines'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return data['logs']?.toString() ?? 'Không có nhật ký.';
      }
    } catch (e) {
      return 'Lỗi kết nối nhật ký: $e';
    }
    return 'Không thể tải nhật ký.';
  }

  // 6. 1-Click Deploy Stream
  StreamSubscription<String> streamDeploy({
    required void Function(String step) onStep,
    required void Function() onDone,
    required void Function(dynamic error) onError,
  }) {
    final controller = StreamController<String>();

    () async {
      if (await _isNativeMode()) {
        try {
          await _ssh.streamDeploy(
            onStep: onStep,
            onDone: onDone,
            onError: onError,
          );
        } catch (e) {
          onError(e);
        }
        return;
      }

      http.Client? deployClient;
      try {
        final baseUrl = await _getBaseUrl();
        deployClient = http.Client();
        final request = http.Request('POST', Uri.parse('$baseUrl${ApiConstants.epServerDeploy}'));
        final headers = await _getHeaders();
        request.headers.addAll(headers);

        final streamedResponse = await deployClient.send(request);
        if (streamedResponse.statusCode != 200) {
          onError('Lỗi server: ${streamedResponse.statusCode}');
          return;
        }

        streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            final trimmed = line.trim();
            if (trimmed.startsWith('data:')) {
              final stepMsg = trimmed.substring(5).trim();
              if (stepMsg.isNotEmpty) {
                onStep(stepMsg);
              }
            }
          },
          onError: (e) => onError(e),
          onDone: () {
            onDone();
            deployClient?.close();
          },
          cancelOnError: true,
        );
      } catch (e) {
        onError(e);
        deployClient?.close();
      }
    }();

    return controller.stream.listen((_) {});
  }

  // 7. Chat & AI Sessions APIs
  Future<List<ChatSessionModel>> getChatSessions() async {
    if (await _isNativeMode()) {
      return await _db.getSessions();
    }
    final baseUrl = await _getBaseUrl();
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epChatSessions}'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is List) {
          return data.map((e) => ChatSessionModel.fromJson(e as Map<String, dynamic>)).toList();
        } else if (data is Map<String, dynamic> && data['sessions'] is List) {
          final list = data['sessions'] as List;
          return list.map((e) => ChatSessionModel.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<ChatSessionModel> createChatSession({String title = 'Cuộc hội thoại mới'}) async {
    if (await _isNativeMode()) {
      return await _db.createSession(title: title);
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epChatSessions}'),
      headers: await _getHeaders(),
      body: jsonEncode({'title': title}),
    );
    if (res.statusCode == 200) {
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return ChatSessionModel.fromJson(json);
    }
    throw Exception('Failed to create session');
  }

  Future<bool> renameChatSession(String sessionId, String newTitle) async {
    if (await _isNativeMode()) {
      return await _db.updateSessionTitle(sessionId, newTitle);
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.put(
      Uri.parse('$baseUrl${ApiConstants.epChatSessions}/$sessionId'),
      headers: await _getHeaders(),
      body: jsonEncode({'title': newTitle}),
    );
    return res.statusCode == 200;
  }

  Future<bool> deleteChatSession(String sessionId) async {
    if (await _isNativeMode()) {
      return await _db.deleteSession(sessionId);
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.delete(
      Uri.parse('$baseUrl${ApiConstants.epChatSessions}/$sessionId'),
      headers: await _getHeaders(),
    );
    return res.statusCode == 200;
  }

  Future<bool> togglePinSession(String sessionId, {bool? isPinned}) async {
    if (await _isNativeMode()) {
      return await _db.togglePinSession(sessionId, isPinned: isPinned);
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epChatSessions}/$sessionId/pin'),
      headers: await _getHeaders(),
      body: jsonEncode(isPinned != null ? {'is_pinned': isPinned} : {}),
    );
    return res.statusCode == 200;
  }

  Future<bool> pinChatSession(String sessionId, [bool? isPinned]) =>
      togglePinSession(sessionId, isPinned: isPinned);

  // 8. Chat History API
  Future<ChatHistoryResult> getChatHistory(
    String sessionId, {
    int limit = 50,
    int? beforeId,
    int? limitQuestions,
  }) async {
    final effectiveLimit = limitQuestions ?? limit;
    if (await _isNativeMode()) {
      return await _db.getMessages(sessionId, limit: effectiveLimit, beforeId: beforeId);
    }
    final baseUrl = await _getBaseUrl();
    final query = [
      'session_id=$sessionId',
      'limit=$effectiveLimit',
      if (beforeId != null) 'before_id=$beforeId',
    ].join('&');

    try {
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epChatHistory}?$query'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final rawMessages = (data['messages'] as List<dynamic>?) ?? [];
        final messages = rawMessages
            .map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>))
            .toList();
        final hasMore = data['has_more'] == true;
        final oldestId = int.tryParse(data['oldest_id']?.toString() ?? '0') ?? 0;

        return ChatHistoryResult(
          messages: messages,
          hasMore: hasMore,
          oldestId: oldestId,
        );
      }
    } catch (_) {}

    return ChatHistoryResult(messages: [], hasMore: false, oldestId: 0);
  }

  Future<int> insertChatMessage(ChatMessageModel message) async {
    if (await _isNativeMode()) {
      return await _db.insertMessage(message);
    }
    return 0;
  }

  Future<bool> clearChatHistory(String sessionId) async {
    if (await _isNativeMode()) {
      return await _db.clearChat(sessionId);
    }
    final baseUrl = await _getBaseUrl();
    final res = await _client.post(
      Uri.parse('$baseUrl${ApiConstants.epChatClear}'),
      headers: await _getHeaders(),
      body: jsonEncode({'session_id': sessionId}),
    );
    return res.statusCode == 200;
  }

  // 9. AI Agent Chat Stream
  StreamSubscription<String> streamChatMessage({
    required String sessionId,
    required String message,
    String? model,
    List<AttachmentItem>? attachments,
    List<Map<String, dynamic>>? history,
    String? workingDir,
    required void Function(String token) onToken,
    required void Function(String status) onStatus,
    required void Function(ToolExecutionItem tool) onTool,
    required void Function(String fullReply) onDone,
    required void Function(dynamic error) onError,
  }) {
    final controller = StreamController<String>();

    () async {
      if (await _isNativeMode()) {
        final sub = _ai.streamChatMessage(
          sessionId: sessionId,
          message: message,
          model: model,
          attachments: attachments,
          history: history,
          workingDir: workingDir,
          onToken: onToken,
          onStatus: onStatus,
          onTool: onTool,
          onDone: onDone,
          onError: onError,
        );
        controller.onCancel = () => sub.cancel();
        return;
      }

      http.Client? streamClient;
      StreamSubscription? responseSub;
      controller.onCancel = () {
        responseSub?.cancel();
        streamClient?.close();
      };
      try {
        final baseUrl = await _getBaseUrl();
        streamClient = http.Client();
        final request = http.Request('POST', Uri.parse('$baseUrl${ApiConstants.epChat}'));
        final headers = await _getHeaders();
        request.headers.addAll(headers);
        request.body = jsonEncode({
          'session_id': sessionId,
          'message': message,
          if (model != null && model.isNotEmpty) 'model': model,
          if (attachments != null && attachments.isNotEmpty)
            'attachments': attachments.map((e) => e.toJson()).toList(),
          if (history != null) 'history': history,
          if (workingDir != null) 'working_dir': workingDir,
        });

        final streamedResponse = await streamClient.send(request);
        if (streamedResponse.statusCode != 200) {
          onError('Server returned error: ${streamedResponse.statusCode}');
          return;
        }

        var accumulatedReply = '';

        responseSub = streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            final trimmed = line.trim();
            if (trimmed.startsWith('data:')) {
              final jsonStr = trimmed.substring(5).trim();
              if (jsonStr.isEmpty || jsonStr == '[DONE]') {
                onDone(accumulatedReply);
                return;
              }
              try {
                final Map<String, dynamic> data = jsonDecode(jsonStr);
                final type = data['type']?.toString();

                if (type == 'token' || type == 'content') {
                  final delta = data['delta']?.toString() ?? data['content']?.toString() ?? '';
                  accumulatedReply += delta;
                  onToken(delta);
                } else if (type == 'status') {
                  final msg = data['message']?.toString() ?? '';
                  onStatus(msg);
                } else if (type == 'tool' || type == 'tool_call') {
                  final toolData = data['tool'] is Map ? data['tool'] as Map<String, dynamic> : data;
                  final item = ToolExecutionItem.fromJson(toolData);
                  onTool(item);
                } else if (type == 'done') {
                  final finalReply = data['reply']?.toString() ?? accumulatedReply;
                  onDone(finalReply);
                } else if (type == 'error') {
                  onError(data['message'] ?? data['error'] ?? 'AI Error');
                }
              } catch (_) {}
            }
          },
          onError: (e) => onError(e),
          onDone: () {
            onDone(accumulatedReply);
            streamClient?.close();
          },
          cancelOnError: true,
        );
      } catch (e) {
        onError(e);
        streamClient?.close();
      }
    }();

    return controller.stream.listen((_) {});
  }

  // 10. File System Browser APIs
  Future<List<String>> listDirectories({String prefix = ''}) async {
    if (await _isNativeMode()) {
      return await _ssh.listRemoteDirs(prefix);
    }
    final baseUrl = await _getBaseUrl();
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epFsListDirs}?prefix=${Uri.encodeComponent(prefix)}'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is List) {
          return data.map((e) => e.toString()).toList();
        } else if (data is Map && data['directories'] is List) {
          return (data['directories'] as List).map((e) => e.toString()).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<List<String>> listRemoteDirectories({String prefix = ''}) =>
      listDirectories(prefix: prefix);

  Future<Map<String, dynamic>> uploadFile({
    required String fileName,
    Uint8List? bytes,
    String? localFilePath,
    String? targetDir,
    void Function(int sentBytes, int totalBytes, double progress)? onProgress,
  }) async {
    if (await _isNativeMode()) {
      return await _ssh.uploadFile(
        fileName: fileName,
        bytes: bytes,
        localFilePath: localFilePath,
        targetDir: targetDir,
        onProgress: onProgress,
      );
    }
    final baseUrl = await _getBaseUrl();
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl${ApiConstants.epFsUpload}'));
      final headers = await _getHeaders();
      request.headers.addAll(headers);
      if (targetDir != null && targetDir.isNotEmpty) {
        request.fields['target_dir'] = targetDir;
      }
      if (localFilePath != null && File(localFilePath).existsSync()) {
        request.files.add(await http.MultipartFile.fromPath('file', localFilePath, filename: fileName));
      } else if (bytes != null) {
        request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
      } else {
        return {'status': 'error', 'message': 'Không có dữ liệu tệp'};
      }

      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final fileLen = (bytes != null) ? bytes.length : (File(localFilePath!).lengthSync());
        if (onProgress != null) onProgress(fileLen, fileLen, 1.0);
        return data is Map<String, dynamic> ? data : {'status': 'success'};
      }
      return {'status': 'error', 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<Uint8List?> downloadFile({
    required String remotePath,
    void Function(int receivedBytes, int totalBytes, double progress)? onProgress,
  }) async {
    if (await _isNativeMode()) {
      return await _ssh.downloadFile(
        remotePath: remotePath,
        onProgress: onProgress,
      );
    }
    final baseUrl = await _getBaseUrl();
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl${ApiConstants.epFsDownload}?path=${Uri.encodeComponent(remotePath)}'),
        headers: await _getHeaders(),
      );
      if (res.statusCode == 200) {
        if (onProgress != null) onProgress(res.bodyBytes.length, res.bodyBytes.length, 1.0);
        return res.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  Future<List<String>> fetchMitomModels() async {
    try {
      final res = await _client.get(
        Uri.parse('https://api-vn-sg.mitom.ai/v1/models'),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic> && decoded['data'] is List) {
          final list = decoded['data'] as List;
          final models = <String>[];
          for (final item in list) {
            if (item is Map<String, dynamic> && item['id'] != null) {
              final idStr = item['id'].toString().trim();
              if (idStr.isNotEmpty && !models.contains(idStr)) {
                models.add(idStr);
              }
            }
          }
          return models;
        }
      }
    } catch (_) {}
    return [];
  }
}


