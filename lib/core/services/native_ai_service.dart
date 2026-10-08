import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../models/attachment_item.dart';
import '../../models/chat_message.dart';
import '../../models/server_model.dart';
import 'adb_manager_service.dart';
import 'cli_automation_bridge_service.dart';
import 'database_service.dart';
import 'local_config_service.dart';
import 'persona_service.dart';
import 'socks5_proxy_service.dart';

class NativeAiService {
  static final NativeAiService _instance = NativeAiService._internal();
  factory NativeAiService() => _instance;
  NativeAiService._internal();

  final LocalConfigService _configService = LocalConfigService();
  final DatabaseService _dbService = DatabaseService();
  final PersonaService _personaService = PersonaService();
  final Socks5ProxyService _socks5Service = Socks5ProxyService();
  final AdbManagerService _adbManagerService = AdbManagerService();

  static const String systemPromptBase = '''Bạn là AI Agent MXH Tự Động - Chuyên gia lên kế hoạch và tự động hóa quy trình nuôi nick, tương tác mạng xã hội trên máy local.
Bạn có quyền hạn điều khiển trực tiếp các hồ sơ nhân vật (profiles), khởi chạy/đóng trình duyệt độc lập theo từng IP/nhân vật, kết nối và điều khiển thiết bị di động (Android AVD / thiết bị ngoại vi qua ADB) để thực thi các kịch bản tự động hóa mà không phụ thuộc vào SSH hay máy chủ từ xa.

CÁC NGUYÊN TẮC HOẠT ĐỘNG:
1. MÔI TRƯỜNG THỰC THI MẶC ĐỊNH LÀ TRÌNH DUYỆT (BROWSER FIRST):
   - MẶC ĐỊNH MỌI TÁC VỤ (lướt bài, like, tương tác, xem video, kiểm tra tài khoản, đăng nhập...) ĐỀU PHẢI SỬ DỤNG TRÌNH DUYỆT (`open_profile_browser`).
   - TUYỆT ĐỐI KHÔNG TỰ Ý KHỞI CHẠY THIẾT BỊ / MÁY ẢO ANDROID (`open_profile_device`).
   - BẠN CHỈ ĐƯỢC PHÉP mở thiết bị Android (`open_profile_device`) KHI VÀ CHỈ KHI người dùng có yêu cầu cụ thể bằng lời nói nhắc đến máy ảo, điện thoại, thiết bị, mobile, adb, avd hoặc giả lập (ví dụ: "chạy trên điện thoại", "mở máy ảo", "mở device", "chạy giả lập"). Nếu người dùng chỉ nói chung chung hoặc không nói gì về thiết bị, LUÔN LUÔN DÙNG TRÌNH DUYỆT.

2. GIỚI HẠN TỐI ĐA 2 THIẾT BỊ / DEVICES CÙNG LÚC & ĐẢM BẢO HOÀN THÀNH MỚI ĐỔI THIẾT BỊ:
   - Khi có bất kỳ yêu cầu tự động hóa nào trên thiết bị (Android / AVD / Mobile), BẮT BUỘC CHỈ ĐƯỢC PHÉP mở tối đa 2 thiết bị cùng lúc trên toàn hệ thống để chống treo máy.
   - TUYỆT ĐỐI KHÔNG mở cùng lúc từ 3 thiết bị trở lên.
   - VÌ MỖI LỆNH CHẠY AUTO CÓ THỂ KÉO DÀI RẤT LÂU: Bạn PHẢI đảm bảo tác vụ auto trên thiết bị đang chạy phải hoàn thành trọn vẹn 100% (hoặc có kết quả xác nhận) rồi mới đóng/tắt thiết bị đó bằng `close_profile_device`, sau đó mới mở thiết bị kế tiếp.
   - Khi người dùng yêu cầu chạy 10, 50 hay 100 thiết bị: Bạn phải triển khai cơ chế hàng đợi xử lý tuần tự (mỗi đợt tối đa 2 thiết bị -> thực hiện xong auto -> đóng lại -> lấy thiết bị tiếp theo trong danh sách cho đến khi xử lý hết toàn bộ 100 thiết bị mà không bị sót).

3. LẬP KẾ HOẠCH & ĐIỀU PHỐI LOCAL PROFILE:
   - Quản lý và tra cứu danh sách nhân vật/profile với IP và cấu hình riêng biệt.
   - Điều khiển mở trình duyệt với profile riêng để thực hiện các tác vụ tự động hóa như lướt bài, like, tương tác, xem video.

4. TẬP TRUNG TÁC VỤ TỰ ĐỘNG HÓA MXH:
   - Sử dụng các công cụ nội bộ để tương tác trực tiếp với trình duyệt cục bộ.
   - BẮT BUỘC: Sau khi gọi hoặc thực thi bất kỳ công cụ (tool/function) nào, bạn PHẢI luôn luôn có câu trả lời bằng văn bản gửi cho người dùng để trình bày chi tiết kết quả, giải thích các bước đã thực hiện hoặc đưa ra phân tích tiếp theo. Tuyệt đối KHÔNG được kết thúc cuộc hội thoại trong im lặng hoặc trả về nội dung rỗng.

5. QUY TẮC ĐỌC BÀI BÁO & XEM VIDEO TRÊN WEBSITE (AGENT RULES):
   - Khi có yêu cầu đọc bài báo, xem tin tức hoặc xem video trên website bất kỳ:
     + Luôn khởi chạy trình duyệt bằng profile độc lập theo IP của nhân vật (`open_profile_browser`).
     + Quy trình đọc bài báo: Đợi trang tải xong, đóng pop-up quảng cáo nếu có, cuộn trang từng đoạn từ tốn mô phỏng tốc độ đọc thật của con người (dwell time 3-8 giây mỗi đoạn), cuộn tối thiểu 70% chiều dài trang; trích xuất tiêu đề chính và các luận điểm cốt lõi.
     + Quy trình xem video: Tìm phần tử video hoặc iframe nhúng, cuộn trình phát vào giữa màn hình, bấm Play, xem tối thiểu 45 giây đến 2 phút (hoặc 80% thời lượng với video ngắn), không tắt trình duyệt ngay sau khi vừa mở; đọc hiểu tiêu đề, mô tả và nội dung video.
     + Luôn giữ tính nhất quán theo đúng giọng văn, độ tuổi và tiểu sử của nhân vật khi tóm tắt hoặc viết bình luận tương tác.''';

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
    bool isCancelled = false;

    () async {
      try {
        final cfg = await _configService.loadConfig();
        final defaultModel = cfg['ai_model']?.toString() ?? 'glm-5.3';
        final targetModel = (model != null && model.isNotEmpty) ? model : defaultModel;

        // Save user message to database
        final userMsg = ChatMessageModel(
          sessionId: sessionId,
          role: 'user',
          content: message,
          model: targetModel,
          attachments: attachments,
          createdAt: DateTime.now(),
        );
        await _dbService.insertMessage(userMsg);

        final aiEngineType = cfg['ai_engine_type']?.toString() ?? 'proxy';
        final activeCliAgent = cfg['active_cli_agent']?.toString() ?? 'antigravity-cli';

        // Check if running Local CLI Agent mode or selected model is a CLI model
        final isCli = aiEngineType == 'cli' || _isCliModel(targetModel);
        if (isCli) {
          final chosenCli = (aiEngineType == 'cli' && !_isCliModel(targetModel))
              ? activeCliAgent
              : targetModel;
          await _runCliAgent(
            cliName: chosenCli,
            prompt: message,
            workingDir: workingDir,
            onToken: onToken,
            onStatus: onStatus,
            onTool: onTool,
            onDone: (reply) async {
              final assistantMsg = ChatMessageModel(
                sessionId: sessionId,
                role: 'assistant',
                content: reply,
                model: chosenCli,
                createdAt: DateTime.now(),
              );
              await _dbService.insertMessage(assistantMsg);
              onDone(reply);
            },
            onError: onError,
            isCancelled: () => isCancelled,
          );
          return;
        }

        var baseUrl = cfg['proxy_base_url']?.toString() ?? 'https://api.mitom.ai/v1';
        if (!LocalConfigService.isValidMitomProxyUrl(baseUrl)) {
          onError('Cấu hình Proxy Base URL không hợp lệ. Chỉ chấp nhận domain thuộc *.mitom.ai');
          return;
        }
        final apiKey = cfg['proxy_api_key']?.toString() ?? '';

        if (baseUrl.endsWith('/')) {
          baseUrl = baseUrl.substring(0, baseUrl.length - 1);
        }

        // Build System Prompt
        String sysPrompt = systemPromptBase;
        if (workingDir != null && workingDir.isNotEmpty) {
          if (workingDir.startsWith('=== DANH SÁCH NHÂN VẬT ĐƯỢC CHỈ ĐỊNH') || workingDir.contains('👤 Nhân vật:')) {
            sysPrompt += '\n\n$workingDir\n\n🎯 QUY TẮC BẮT BUỘC TỐI THƯỢNG VỀ ĐA NHÂN VẬT (MULTI-PERSONAS SCOPE):\n'
                '- Bạn CHỈ ĐƯỢC PHÉP thao tác, tương tác, mở trình duyệt hoặc mở thiết bị Android cho DUY NHẤT các nhân vật/IP nằm trong danh sách Scope trên.\n'
                '- ĐẶC BIỆT KHI SCOPE CHỈ CÓ 1 NHÂN VẬT (hoặc người dùng chỉ chọn 1 profile):\n'
                '  + BẮT BUỘC CHỈ MỞ ĐÚNG 1 TRÌNH DUYỆT HOẶC 1 THIẾT BỊ DUY NHẤT cho nhân vật đó. TUYỆT ĐỐI KHÔNG ĐƯỢC mở 2, 3 hay mở toàn bộ các máy/trình duyệt khác có trong hệ thống!\n'
                '  + Khi gọi tool `open_profile_browser` hoặc `open_profile_device`: CHỈ truyền IP của nhân vật đó vào tham số `ip`, KHÔNG ĐƯỢC truyền mảng `ips` chứa nhiều IP.\n'
                '  + TUYỆT ĐỐI KHÔNG được tự ý lấy các IP ngoài danh sách Scope trên (dù có gọi `list_profiles` hay thấy lịch sử trước đó).\n'
                '- KHI SCOPE CÓ NHIỀU NHÂN VẬT:\n'
                '  + Nếu người dùng yêu cầu 1 trình duyệt / 1 thiết bị cụ thể: Chỉ chọn đúng 1 IP và truyền vào `ip`.\n'
                '  + Chỉ khi người dùng yêu cầu chạy tất cả/đồng loạt cho scope này: Mới truyền danh sách các IP trong scope vào `ips`.\n'
                '- MỖI LẦN NHẬN YÊU CẦU MỚI: Phải đánh giá lại chính xác người dùng muốn làm việc trên bao nhiêu trình duyệt/thiết bị trong yêu cầu hiện tại, KHÔNG ĐƯỢC mang trạng thái mở 3 thiết bị của phiên trước áp đặt vào phiên hiện tại.';
          } else {
            sysPrompt += '\n\n🎯 PHẠM VI LÀM VIỆC MỤC TIÊU: `$workingDir`\nMọi tác vụ terminal/tài khoản phải tuân thủ phạm vi này.';
          }
        }

        final messages = <Map<String, dynamic>>[
          {'role': 'system', 'content': sysPrompt},
        ];

        // Append recent history
        if (history != null && history.isNotEmpty) {
          for (final h in history) {
            messages.add({
              'role': h['role'] ?? 'user',
              'content': h['content'] ?? '',
            });
          }
        } else {
          // Fetch last 10 messages from DB
          final dbHistory = await _dbService.getMessages(sessionId, limit: 10);
          for (final m in dbHistory.messages) {
            if (m.content != message) {
              messages.add({
                'role': m.role,
                'content': m.content,
              });
            }
          }
        }

        // Format user message with attachments
        String fullUserPrompt = message;
        if (attachments != null && attachments.isNotEmpty) {
          fullUserPrompt += '\n\n=== TỆP & ẢNH ĐÍNH KÈM TỪ NGƯỜI DÙNG ===';
          for (final att in attachments) {
            final localInfo = (att.path != null && att.path!.isNotEmpty)
                ? ' (Đường dẫn local: ${att.path} - Dung lượng: ${att.formattedSize})'
                : ' (Dung lượng: ${att.formattedSize})';
            if (att.isImage) {
              fullUserPrompt += '\n\n--- [Ảnh: ${att.name}$localInfo] --- (Người dùng đính kèm ảnh local)';
            } else {
              fullUserPrompt += '\n\n--- [Tệp: ${att.name}$localInfo] ---\n${att.content}';
            }
          }
        }

        // Add current user message
        messages.add({'role': 'user', 'content': fullUserPrompt});

        final tools = [
          {
            'type': 'function',
            'function': {
              'name': 'list_profiles',
              'description': 'Lấy danh sách các nhân vật/hồ sơ (profiles) nuôi nick hiện có cùng IP, thông tin avatar, thiết bị cấu hình.',
              'parameters': {
                'type': 'object',
                'properties': {},
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'open_profile_browser',
              'description': 'Mở trình duyệt riêng biệt cho hồ sơ/nhân vật theo IP để tự động hóa tương tác mạng xã hội trên web. CHÚ Ý QUAN TRỌNG: Nếu người dùng yêu cầu 1 trình duyệt hoặc 1 nhân vật cụ thể, CHỈ ĐƯỢC truyền 1 IP vào tham số "ip" (để trống hoặc không dùng "ips"). Chỉ khi nào người dùng yêu cầu mở cho tất cả/nhiều nhân vật đồng loạt thì mới truyền danh sách vào tham số "ips".',
              'parameters': {
                'type': 'object',
                'properties': {
                  'ip': {
                    'type': 'string',
                    'description': 'Địa chỉ IP hoặc định danh của một nhân vật duy nhất khi thao tác trên 1 trình duyệt.'
                  },
                  'ips': {
                    'type': 'array',
                    'items': {'type': 'string'},
                    'description': 'Danh sách các địa chỉ IP của toàn bộ nhân vật cần mở trình duyệt đồng loạt (chỉ dùng khi người dùng yêu cầu nhiều trình duyệt cùng lúc).'
                  },
                  'url': {
                    'type': 'string',
                    'description': 'Đường dẫn trang web mạng xã hội muốn mở (ví dụ: https://facebook.com, https://tiktok.com, https://youtube.com)'
                  }
                }
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'close_profile_browser',
              'description': 'Đóng cửa sổ trình duyệt của một hoặc nhiều nhân vật theo IP.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'ip': {
                    'type': 'string',
                    'description': 'Địa chỉ IP của nhân vật cần đóng trình duyệt'
                  },
                  'ips': {
                    'type': 'array',
                    'items': {'type': 'string'},
                    'description': 'Danh sách IP của các nhân vật cần đóng trình duyệt đồng loạt'
                  }
                }
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'open_profile_device',
              'description': 'Khởi chạy hoặc kết nối thiết bị Android (máy ảo AVD local hoặc thiết bị ngoại vi qua WiFi/USB) cho nhân vật theo IP. QUY TẮC BẮT BUỘC: (1) Mặc định làm việc trên Trình duyệt, chỉ dùng thiết bị khi người dùng yêu cầu rõ ràng; (2) GIỚI HẠN TỐI ĐA 2 THIẾT BỊ MỞ CÙNG LÚC TRÊN TOÀN HỆ THỐNG ĐỂ TRÁNH TREO MÁY. Tuyệt đối không mở từ 3 thiết bị trở lên cùng lúc; (3) Với yêu cầu chạy nhiều thiết bị (kể cả 100 devices): Phải đảm bảo từng thiết bị chạy XONG XUÔI tác vụ auto rồi mới đóng bằng close_profile_device, sau đó mới mở thiết bị tiếp theo cho đến khi hoàn tất toàn bộ danh sách.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'ip': {
                    'type': 'string',
                    'description': 'Địa chỉ IP của nhân vật cần chạy thiết bị duy nhất'
                  },
                  'ips': {
                    'type': 'array',
                    'items': {'type': 'string'},
                    'description': 'Danh sách IP của các nhân vật cần khởi chạy thiết bị Android đồng loạt (chỉ dùng khi người dùng yêu cầu chạy tất cả hoặc nhiều thiết bị)'
                  },
                  'device_type': {
                    'type': 'string',
                    'description': 'Loại thiết bị: "mobile" hoặc "tablet"',
                    'default': 'mobile'
                  },
                  'avd_name': {
                    'type': 'string',
                    'description': 'Tên máy ảo AVD nếu muốn chỉ định cụ thể'
                  },
                  'remote_address': {
                    'type': 'string',
                    'description': 'Địa chỉ IP:port của điện thoại thật nếu kết nối ngoại vi qua WiFi (ví dụ: 192.168.1.50:5555)'
                  }
                }
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'close_profile_device',
              'description': 'Đóng máy ảo hoặc ngắt kết nối thiết bị Android của nhân vật theo IP.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'ip': {
                    'type': 'string',
                    'description': 'Địa chỉ IP của nhân vật cần đóng thiết bị'
                  }
                },
                'required': ['ip']
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'get_connected_devices',
              'description': 'Lấy danh sách các thiết bị Android (máy ảo AVD, USB hoặc WiFi) đang kết nối nội bộ.',
              'parameters': {
                'type': 'object',
                'properties': {},
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'execute_adb_command',
              'description': 'Thực thi lệnh ADB trực tiếp trên máy local để điều khiển thiết bị Android (ví dụ tap, swipe, input text, mở app).',
              'parameters': {
                'type': 'object',
                'properties': {
                  'serial': {
                    'type': 'string',
                    'description': 'Số serial hoặc địa chỉ thiết bị (ví dụ emulator-5554 hoặc 192.168.1.50:5555). Để trống nếu chỉ có 1 thiết bị.'
                  },
                  'command': {
                    'type': 'string',
                    'description': 'Lệnh adb cần thực thi (ví dụ: "shell input tap 500 1000", "shell input text hello", "shell am start ...")'
                  }
                },
                'required': ['command']
              }
            }
          }
        ];

        String finalReply = '';
        final allExecutedTools = <ToolExecutionItem>[];
        int turnCount = 0;
        const maxTurns = 20;

        while (turnCount < maxTurns && !isCancelled) {
          turnCount++;
          final client = http.Client();
          final request = http.Request('POST', Uri.parse('$baseUrl/chat/completions'));
          request.headers.addAll({
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
          });

          final requestBody = {
            'model': targetModel,
            'messages': messages,
            'tools': tools,
            'stream': true,
          };
          request.body = jsonEncode(requestBody);

          onStatus(turnCount == 1 ? 'Đang suy nghĩ...' : 'Đang xử lý bước tiếp theo...');
          final response = await client.send(request);

          if (response.statusCode != 200) {
            final errBody = await response.stream.bytesToString();
            onError('AI API Error (${response.statusCode}): $errBody');
            client.close();
            return;
          }

          String stepContent = '';
          final toolCallsMap = <int, Map<String, dynamic>>{};

          final streamCompleter = Completer<void>();

          response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen(
            (line) {
              final trimmed = line.trim();
              if (trimmed.isEmpty) return;
              if (trimmed == 'data: [DONE]') {
                return;
              }
              if (trimmed.startsWith('data:')) {
                final jsonStr = trimmed.substring(5).trim();
                try {
                  final data = jsonDecode(jsonStr);
                  final choices = data['choices'] as List<dynamic>?;
                  if (choices != null && choices.isNotEmpty) {
                    final delta = choices[0]['delta'] as Map<String, dynamic>?;
                    if (delta != null) {
                      // Text content delta
                      if (delta['content'] != null) {
                        final token = delta['content'].toString();
                        stepContent += token;
                        onToken(token);
                      }

                      // Tool calls delta
                      if (delta['tool_calls'] != null) {
                        final tcs = delta['tool_calls'] as List<dynamic>;
                        for (final tc in tcs) {
                          final idx = tc['index'] as int? ?? 0;
                          toolCallsMap.putIfAbsent(idx, () => {
                            'id': tc['id'] ?? '',
                            'name': tc['function']?['name'] ?? '',
                            'arguments': '',
                          });
                          if (tc['id'] != null && tc['id'].toString().isNotEmpty) {
                            toolCallsMap[idx]!['id'] = tc['id'];
                          }
                          if (tc['function']?['name'] != null) {
                            toolCallsMap[idx]!['name'] = tc['function']['name'];
                          }
                          if (tc['function']?['arguments'] != null) {
                            toolCallsMap[idx]!['arguments'] =
                                (toolCallsMap[idx]!['arguments'] as String) + tc['function']['arguments'].toString();
                          }
                        }
                      }
                    }
                  }
                } catch (_) {}
              }
            },
            onError: (err) {
              if (!streamCompleter.isCompleted) streamCompleter.completeError(err);
            },
            onDone: () {
              if (!streamCompleter.isCompleted) streamCompleter.complete();
              client.close();
            },
            cancelOnError: true,
          );

          await streamCompleter.future;

          // Check if tools were called
          if (toolCallsMap.isNotEmpty) {
            final formattedToolCalls = <Map<String, dynamic>>[];
            final executedToolResults = <Map<String, dynamic>>[];

            // Extract allowed IPs if there is a Personas Scope specified
            final List<String> allowedScopeIps = [];
            if (workingDir != null && (workingDir.contains('SCOPE PERSONAS') || workingDir.contains('IP:'))) {
              final ipMatches = RegExp(r'IP:\s*([0-9a-zA-Z\.\:\_\-]+)').allMatches(workingDir);
              for (final m in ipMatches) {
                final matchedIp = m.group(1)?.trim();
                if (matchedIp != null && matchedIp.isNotEmpty && !allowedScopeIps.contains(matchedIp)) {
                  allowedScopeIps.add(matchedIp);
                }
              }
            }

            for (final entry in toolCallsMap.entries) {
              final tc = entry.value;
              final toolCallId = tc['id']?.toString() ?? 'call_${entry.key}';
              final funcName = tc['name']?.toString() ?? 'execute_terminal_command';
              final rawArgs = tc['arguments']?.toString() ?? '{}';

              formattedToolCalls.add({
                'id': toolCallId,
                'type': 'function',
                'function': {
                  'name': funcName,
                  'arguments': rawArgs,
                }
              });

              // Parse tool arguments
              Map<String, dynamic> parsedArgs = {};
              try {
                final decoded = jsonDecode(rawArgs);
                if (decoded is Map<String, dynamic>) {
                  parsedArgs = decoded;
                }
              } catch (_) {}

              String cmdLabel = funcName;
              if (parsedArgs.containsKey('ip')) {
                cmdLabel += ' [IP: ${parsedArgs['ip']}]';
              }
              if (parsedArgs.containsKey('url')) {
                cmdLabel += ' -> ${parsedArgs['url']}';
              }
              if (parsedArgs.containsKey('command')) {
                cmdLabel += ': ${parsedArgs['command']}';
              }

              onStatus('Đang thực thi: $cmdLabel');

              final toolItem = ToolExecutionItem(
                tool: funcName,
                command: cmdLabel,
                output: 'Đang thực thi...',
              );
              onTool(toolItem);

              String toolOutput = '';
              try {
                switch (funcName) {
                  case 'list_profiles':
                    final profiles = await _personaService.loadSavedPersonas();
                    if (profiles.isEmpty) {
                      toolOutput = 'Chưa có hồ sơ nhân vật nào được tạo.';
                    } else {
                      final list = profiles.values.map((p) => {
                        'ip': p.ip,
                        'name': p.name,
                        'age': p.age,
                        'gender': p.gender,
                        'bio': p.bio,
                        'device_type': p.deviceType,
                        'avd_name': p.avdName,
                        'use_external_device': p.useExternalDevice,
                        'external_device_address': p.externalDeviceAddress,
                      }).toList();
                      toolOutput = jsonEncode(list);
                    }
                    break;

                  case 'open_profile_browser':
                    final List<String> targetIps = [];
                    if (parsedArgs['ips'] is List) {
                      for (final item in parsedArgs['ips']) {
                        final s = item?.toString().trim() ?? '';
                        if (s.isNotEmpty && !targetIps.contains(s)) targetIps.add(s);
                      }
                    }
                    final singleIp = parsedArgs['ip']?.toString().trim() ?? '';
                    if (singleIp.isNotEmpty && !targetIps.contains(singleIp)) {
                      targetIps.add(singleIp);
                    }

                    // Scope enforcement
                    if (allowedScopeIps.isNotEmpty) {
                      if (allowedScopeIps.length == 1) {
                        // Scope chỉ có 1 nhân vật -> ÉP BUỘC chỉ mở duy nhất 1 nhân vật đó!
                        targetIps.clear();
                        targetIps.add(allowedScopeIps.first);
                      } else {
                        // Lọc bỏ bất kỳ IP nào không nằm trong danh sách Scope
                        targetIps.retainWhere((ip) => allowedScopeIps.contains(ip));
                        if (targetIps.isEmpty) {
                          targetIps.addAll(allowedScopeIps);
                        }
                      }
                    }

                    final url = parsedArgs['url']?.toString().trim();
                    if (targetIps.isEmpty) {
                      toolOutput = 'Lỗi: Thiếu tham số IP nhân vật hợp lệ trong phạm vi (Scope).';
                      break;
                    }
                    final servers = await _configService.getServers();
                    final activeServer = servers.firstWhere(
                      (s) => s.isSelected,
                      orElse: () => servers.isNotEmpty
                          ? servers.first
                          : ServerModel.fromJson(cfg),
                    );

                    final List<String> successList = [];
                    final List<String> failList = [];
                    for (final tip in targetIps) {
                      onStatus('Đang mở trình duyệt cho IP: $tip...');
                      final success = await _socks5Service.launchBrowserWithSocks5(
                        server: activeServer,
                        ip: tip,
                        startUrl: url,
                      );
                      if (success) {
                        successList.add(tip);
                      } else {
                        failList.add(tip);
                      }
                    }
                    if (failList.isEmpty) {
                      toolOutput = 'Đã mở trình duyệt thành công cho toàn bộ ${successList.length} nhân vật (${successList.join(', ')})${url != null ? ' tại $url' : ''}.';
                    } else if (successList.isEmpty) {
                      toolOutput = 'Không thể khởi chạy trình duyệt cho các IP: ${failList.join(', ')}.';
                    } else {
                      toolOutput = 'Đã mở trình duyệt cho: ${successList.join(', ')}. Thất bại tại: ${failList.join(', ')}.';
                    }
                    break;

                  case 'close_profile_browser':
                    final List<String> closeIps = [];
                    if (parsedArgs['ips'] is List) {
                      for (final item in parsedArgs['ips']) {
                        final s = item?.toString().trim() ?? '';
                        if (s.isNotEmpty && !closeIps.contains(s)) closeIps.add(s);
                      }
                    }
                    final sCloseIp = parsedArgs['ip']?.toString().trim() ?? '';
                    if (sCloseIp.isNotEmpty && !closeIps.contains(sCloseIp)) {
                      closeIps.add(sCloseIp);
                    }
                    if (closeIps.isEmpty) {
                      toolOutput = 'Lỗi: Thiếu tham số IP nhân vật.';
                      break;
                    }
                    for (final tip in closeIps) {
                      await _socks5Service.closeBrowserForIp(tip);
                    }
                    toolOutput = 'Đã đóng trình duyệt cho các profile IP: ${closeIps.join(', ')}.';
                    break;

                  case 'open_profile_device':
                    final List<String> targetDevIps = [];
                    if (parsedArgs['ips'] is List) {
                      for (final item in parsedArgs['ips']) {
                        final s = item?.toString().trim() ?? '';
                        if (s.isNotEmpty && !targetDevIps.contains(s)) targetDevIps.add(s);
                      }
                    }
                    final singleDevIp = parsedArgs['ip']?.toString().trim() ?? '';
                    if (singleDevIp.isNotEmpty && !targetDevIps.contains(singleDevIp)) {
                      targetDevIps.add(singleDevIp);
                    }

                    // Scope enforcement
                    if (allowedScopeIps.isNotEmpty) {
                      if (allowedScopeIps.length == 1) {
                        // Scope chỉ có 1 nhân vật -> ÉP BUỘC chỉ mở duy nhất 1 thiết bị cho IP đó!
                        targetDevIps.clear();
                        targetDevIps.add(allowedScopeIps.first);
                      } else {
                        // Lọc bỏ bất kỳ IP nào không nằm trong danh sách Scope
                        targetDevIps.retainWhere((ip) => allowedScopeIps.contains(ip));
                        if (targetDevIps.isEmpty) {
                          targetDevIps.addAll(allowedScopeIps);
                        }
                      }
                    }

                    final devType = parsedArgs['device_type']?.toString().trim() ?? 'mobile';
                    final avdName = parsedArgs['avd_name']?.toString().trim();
                    final remoteAddr = parsedArgs['remote_address']?.toString().trim();
                    if (targetDevIps.isEmpty) {
                      toolOutput = 'Lỗi: Thiếu tham số IP nhân vật hợp lệ trong phạm vi (Scope).';
                      break;
                    }
                    final serversDev = await _configService.getServers();
                    final activeServerDev = serversDev.firstWhere(
                      (s) => s.isSelected,
                      orElse: () => serversDev.isNotEmpty
                          ? serversDev.first
                          : ServerModel.fromJson(cfg),
                    );

                    final List<String> devSuccessList = [];
                    final List<String> devFailList = [];
                    for (final tip in targetDevIps) {
                      // Đảm bảo không bao giờ vượt quá số lượng thiết bị chạy đồng thời theo cấu hình
                      await _socks5Service.ensureDeviceCapacity(exemptIps: [tip]);

                      onStatus('Đang khởi chạy thiết bị cho IP: $tip...');
                      final success = await _socks5Service.launchDeviceWithSocks5(
                        server: activeServerDev,
                        ip: tip,
                        deviceType: devType,
                        avdName: avdName,
                        remoteDeviceAddress: remoteAddr,
                      );
                      if (success) {
                        devSuccessList.add(tip);
                      } else {
                        devFailList.add(tip);
                      }
                    }
                    if (devFailList.isEmpty) {
                      toolOutput = 'Đã khởi chạy thiết bị Android thành công cho toàn bộ ${devSuccessList.length} nhân vật (${devSuccessList.join(', ')}, loại: $devType).';
                    } else if (devSuccessList.isEmpty) {
                      toolOutput = 'Không thể khởi chạy thiết bị Android cho các IP: ${devFailList.join(', ')}.';
                    } else {
                      toolOutput = 'Đã mở thiết bị cho: ${devSuccessList.join(', ')}. Thất bại tại: ${devFailList.join(', ')}.';
                    }
                    break;

                  case 'close_profile_device':
                    final List<String> closeDevIps = [];
                    if (parsedArgs['ips'] is List) {
                      for (final item in parsedArgs['ips']) {
                        final s = item?.toString().trim() ?? '';
                        if (s.isNotEmpty && !closeDevIps.contains(s)) closeDevIps.add(s);
                      }
                    }
                    final sCloseDevIp = parsedArgs['ip']?.toString().trim() ?? '';
                    if (sCloseDevIp.isNotEmpty && !closeDevIps.contains(sCloseDevIp)) {
                      closeDevIps.add(sCloseDevIp);
                    }
                    if (closeDevIps.isEmpty) {
                      toolOutput = 'Lỗi: Thiếu tham số IP nhân vật.';
                      break;
                    }
                    for (final tip in closeDevIps) {
                      await _socks5Service.closeDeviceForIp(tip);
                    }
                    toolOutput = 'Đã đóng thiết bị Android cho các profile IP: ${closeDevIps.join(', ')}.';
                    break;

                  case 'get_connected_devices':
                    final devs = await _socks5Service.getConnectedAdbDevices();
                    toolOutput = devs.isEmpty ? 'Không có thiết bị Android nào đang kết nối.' : jsonEncode(devs);
                    break;

                  case 'execute_adb_command':
                    final adbCmd = parsedArgs['command']?.toString().trim() ?? '';
                    final serial = parsedArgs['serial']?.toString().trim();
                    if (adbCmd.isEmpty) {
                      toolOutput = 'Lỗi: Lệnh ADB rỗng.';
                      break;
                    }
                    final adbBin = await _adbManagerService.resolveAdbPath();
                    final List<String> args = [];
                    if (serial != null && serial.isNotEmpty) {
                      args.addAll(['-s', serial]);
                    }
                    final parts = adbCmd.split(RegExp(r'\s+'));
                    if (parts.isNotEmpty && parts.first.toLowerCase() == 'adb') {
                      parts.removeAt(0);
                    }
                    args.addAll(parts);
                    final procRes = await Process.run(adbBin, args);
                    final stdoutStr = procRes.stdout.toString().trim();
                    final stderrStr = procRes.stderr.toString().trim();
                    toolOutput = stdoutStr.isNotEmpty ? stdoutStr : (stderrStr.isNotEmpty ? stderrStr : 'Lệnh thực thi thành công (Exit code: ${procRes.exitCode}).');
                    break;

                  default:
                    toolOutput = 'Công cụ $funcName không được hỗ trợ.';
                    break;
                }
              } catch (e) {
                toolOutput = 'Lỗi thực thi công cụ $funcName: $e';
              }

              final finishedTool = ToolExecutionItem(
                tool: funcName,
                command: cmdLabel,
                output: toolOutput,
              );
              allExecutedTools.add(finishedTool);
              onTool(finishedTool);

              executedToolResults.add({
                'tool_call_id': toolCallId,
                'content': toolOutput,
              });
            }

            // Properly append single assistant message containing all tool_calls for this turn
            messages.add({
              'role': 'assistant',
              'content': stepContent.isNotEmpty ? stepContent : null,
              'tool_calls': formattedToolCalls,
            });

            // Append each tool response
            for (final res in executedToolResults) {
              messages.add({
                'role': 'tool',
                'tool_call_id': res['tool_call_id'],
                'content': res['content'],
              });
            }

            // Add spacing token if there was narration
            if (stepContent.isNotEmpty) {
              onToken('\n\n');
            }
          } else {
            // Finished generation without more tools
            finalReply = stepContent;
            break;
          }
        }

        // Final reply fallback if not captured
        if (finalReply.isEmpty && messages.isNotEmpty && messages.last['role'] == 'assistant') {
          finalReply = messages.last['content']?.toString() ?? '';
        }

        // If tools were executed but AI didn't emit text narrative, synthesize clear report
        if (finalReply.isEmpty && allExecutedTools.isNotEmpty) {
          final buffer = StringBuffer();
          buffer.writeln('Đã thực hiện xong các tác vụ:');
          for (final t in allExecutedTools) {
            buffer.writeln('- **${t.command}**');
            if (t.output.isNotEmpty) {
              final cleanOut = t.output.length > 200 ? '${t.output.substring(0, 200)}...' : t.output;
              buffer.writeln('  > $cleanOut');
            }
          }
          finalReply = buffer.toString().trim();
          onToken(finalReply);
        } else if (finalReply.isEmpty) {
          finalReply = 'Đã hoàn tất thao tác.';
          onToken(finalReply);
        }

        // Save assistant message to Database
        final assistantMsg = ChatMessageModel(
          sessionId: sessionId,
          role: 'assistant',
          content: finalReply,
          model: targetModel,
          toolExecutions: allExecutedTools,
          createdAt: DateTime.now(),
        );
        await _dbService.insertMessage(assistantMsg);
        onDone(finalReply);
      } catch (e) {
        if (!isCancelled) {
          onError('Lỗi xử lý AI: $e');
        }
      }
    }();

    controller.onCancel = () {
      isCancelled = true;
    };

    return controller.stream.listen((_) {});
  }

  bool _isCliModel(String model) {
    final m = model.toLowerCase();
    return m.contains('antigravity') ||
        m == 'agy' ||
        m.contains('claude') ||
        m.contains('gemini') ||
        m.contains('ollama') ||
        m.contains('sgpt') ||
        m.contains('aichat');
  }

  String _findCliExecutable(String cliName) {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final m = cliName.toLowerCase();

    if (m.contains('antigravity') || m == 'agy') {
      final localBin = '$home/.local/bin/agy';
      if (File(localBin).existsSync()) return localBin;
      final localBinAlt = '$home/.local/bin/antigravity';
      if (File(localBinAlt).existsSync()) return localBinAlt;
      return 'agy';
    }

    if (m.contains('claude')) {
      final nvmDir = '$home/.nvm/versions/node';
      if (Directory(nvmDir).existsSync()) {
        try {
          final entries = Directory(nvmDir).listSync();
          for (final e in entries) {
            final claudePath = '${e.path}/bin/claude';
            if (File(claudePath).existsSync()) return claudePath;
          }
        } catch (_) {}
      }
      final localBin = '$home/.local/bin/claude';
      if (File(localBin).existsSync()) return localBin;
      return 'claude';
    }

    if (m.contains('gemini')) {
      final localBin = '$home/.local/bin/gemini';
      if (File(localBin).existsSync()) return localBin;
      return 'gemini';
    }

    if (m.contains('ollama')) {
      return 'ollama';
    }

    return cliName;
  }

  Future<void> _runCliAgent({
    required String cliName,
    required String prompt,
    String? workingDir,
    required void Function(String token) onToken,
    required void Function(String status) onStatus,
    required void Function(ToolExecutionItem tool) onTool,
    required void Function(String fullReply) onDone,
    required void Function(dynamic error) onError,
    required bool Function() isCancelled,
  }) async {
    final exe = _findCliExecutable(cliName);
    onStatus('Đang khởi chạy $cliName agent...');

    try {
      final workDir = (workingDir != null && Directory(workingDir).existsSync())
          ? workingDir
          : (Platform.environment['HOME'] ?? Directory.current.path);

      // Cung cấp bộ vũ khí tự động hóa cho Local CLI Agent
      final bridgeService = CliAutomationBridgeService();
      final systemContext = await bridgeService.buildCliSystemContext(workingDir: workingDir);

      final cleanPrompt = '''$systemContext

=== YÊU CẦU TỪ NGƯỜI DÙNG ===
$prompt

(Yêu cầu thực thi: Nếu người dùng yêu cầu mở/đóng trình duyệt, xem link hay auto thiết bị, hãy sử dụng lệnh terminal được cấp ở trên để thực thi ngay lập tức. Tuyệt đối không dùng emoji hay icon trong câu trả lời, trình bày kết quả rõ ràng)''';

      List<String> args;
      final m = cliName.toLowerCase();
      if (m.contains('claude')) {
        args = ['-p', cleanPrompt, '--output-format', 'stream-json', '--verbose', '--dangerously-skip-permissions'];
      } else if (m.contains('antigravity') || m == 'agy') {
        args = ['--print', cleanPrompt, '--output-format', 'stream-json', '--dangerously-skip-permissions'];
      } else if (m.contains('gemini')) {
        args = ['-p', cleanPrompt];
      } else {
        args = ['-p', cleanPrompt, '--dangerously-skip-permissions'];
      }

      // Augmented PATH environment so subprocesses (mxh-tool, node, git, etc.) are always found
      final env = Map<String, String>.from(Platform.environment);
      final home = Platform.environment['HOME'] ?? '';
      final currentPath = env['PATH'] ?? '';
      final extraPaths = <String>[
        '$home/.agent_mxh_auto/bin',
        '$home/.tadu_ai_agent/bin',
        '$home/.local/bin',
        '$home/bin',
        '/usr/local/bin',
        '/snap/bin',
      ];
      final nvmDir = Directory('$home/.nvm/versions/node');
      if (nvmDir.existsSync()) {
        try {
          for (final dir in nvmDir.listSync()) {
            final binPath = '${dir.path}/bin';
            if (Directory(binPath).existsSync()) {
              extraPaths.add(binPath);
            }
          }
        } catch (_) {}
      }
      env['PATH'] = '${extraPaths.join(':')}:$currentPath';

      onStatus('AI Agent $cliName đang phân tích và thực thi tác vụ...');
      final process = await Process.start(
        exe,
        args,
        workingDirectory: workDir,
        environment: env,
        runInShell: false,
      );

      // Close stdin immediately so CLI doesn't wait for input
      try {
        await process.stdin.close();
      } catch (_) {}

      final fullOutput = StringBuffer();
      final errOutput = StringBuffer();

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (isCancelled()) return;
        final trimmed = line.trim();
        if (trimmed.isEmpty) return;

        try {
          final json = jsonDecode(trimmed);
          if (json is Map<String, dynamic>) {
            // 1. Antigravity CLI (agy) streaming protocol
            if (json.containsKey('event')) {
              final event = json['event'];
              if (event == 'step_update') {
                final step = json['step_update'] as Map<String, dynamic>?;
                final stepType = step?['step_type']?.toString();
                final textDelta = step?['text_delta']?.toString();

                if (textDelta != null && textDelta.isNotEmpty) {
                  fullOutput.write(textDelta);
                  onToken(textDelta);
                } else if (stepType == 'tool_call') {
                  final toolName = step?['tool_name'] ?? 'công cụ';
                  onStatus('Antigravity CLI đang gọi: $toolName...');
                }
              } else if (event == 'result') {
                final res = json['result'] as Map<String, dynamic>?;
                final resp = res?['response']?.toString();
                if (resp != null && fullOutput.isEmpty) {
                  fullOutput.write(resp);
                  onToken(resp);
                }
              }
              return;
            }

            // 2. Claude Code CLI streaming protocol
            if (json.containsKey('type')) {
              final type = json['type'];
              if (type == 'content_block_delta') {
                final delta = json['delta'] as Map<String, dynamic>?;
                final text = delta?['text']?.toString();
                if (text != null && text.isNotEmpty) {
                  fullOutput.write(text);
                  onToken(text);
                }
              } else if (type == 'result') {
                final result = json['result']?.toString();
                if (result != null && fullOutput.isEmpty) {
                  fullOutput.write(result);
                  onToken(result);
                }
              } else if (type == 'assistant') {
                final msg = json['message'] as Map<String, dynamic>?;
                final contents = msg?['content'] as List<dynamic>?;
                if (contents != null) {
                  for (final c in contents) {
                    if (c is Map && c['type'] == 'text') {
                      final t = c['text']?.toString();
                      if (t != null && fullOutput.isEmpty) {
                        fullOutput.write(t);
                        onToken(t);
                      }
                    }
                  }
                }
              }
              return;
            }
          }
        } catch (_) {
          // Not JSON -> handle as plain text stream
        }

        // Plain text fallback line
        fullOutput.writeln(line);
        onToken('$line\n');
      });

      process.stderr.transform(utf8.decoder).listen((data) {
        if (!isCancelled()) {
          errOutput.write(data);
        }
      });

      final exitCode = await process.exitCode;
      if (exitCode == 0 || fullOutput.isNotEmpty) {
        final result = fullOutput.toString().trim();
        onDone(result.isNotEmpty ? result : 'Đã hoàn tất tác vụ với $cliName.');
      } else {
        final errStr = errOutput.toString().trim();
        onError('Agent $cliName báo lỗi (mã $exitCode): ${errStr.isNotEmpty ? errStr : "Không có phản hồi"}');
      }
    } catch (e) {
      onError('Không thể chạy CLI $cliName: $e. Hãy kiểm tra đường dẫn hoặc quyền thực thi.');
    }
  }
}
