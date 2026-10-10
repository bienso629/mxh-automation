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
     + Luôn giữ tính nhất quán theo đúng giọng văn, độ tuổi và tiểu sử của nhân vật khi tóm tắt hoặc viết bình luận tương tác.

6. HỆ THỐNG MACRO TỰ ĐỘNG HÓA SIÊU TỐC CHO THIẾT BỊ (FAST ACTION & MACROS):
   - MỖI NHÂN VẬT ĐƯỢC GẮN VỚI MỘT BỘ MACRO TỌA ĐỘ VÀ HÀNH VI TỰ ĐỘNG HÓA RIÊNG BIỆT (theo IP, thiết bị và độ phân giải màn hình).
   - Khi người dùng yêu cầu thực hiện tương tác trên Thiết bị Android (Like, Thả tim, Viết bình luận, Mở video) cho Facebook hoặc TikTok:
     + BẮT BUỘC ƯU TIÊN SỬ DỤNG TOOL `fast_social_action` thay vì tự chạy hàng chục lệnh `execute_adb_command` (như dump xml, grep, sleep...) gây chậm chạp và tốn thời gian.
     + Tool `fast_social_action` sẽ tự động tra cứu bộ nhớ macro riêng của nhân vật theo IP để bấm Like hoặc bình luận ngay lập tức.
     + Nếu bạn phát hiện tọa độ mới chính xác cho một thao tác đặc thù hoặc độ phân giải mới, hãy gọi `save_automation_macro` để nhân vật đó học và ghi nhớ cho các lần chạy tiếp theo.''';

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

        // Detect execution mode preference from workingDir or default_execution_mode
        final defaultExecutionMode = cfg['default_execution_mode']?.toString().trim().toLowerCase();
        final isForcedDeviceMode = (workingDir != null && (workingDir.contains('THIẾT BỊ / DEVICE') || workingDir.contains('open_profile_device'))) ||
            (workingDir == null && defaultExecutionMode == 'device');
        final isForcedBrowserMode = (workingDir != null && (workingDir.contains('TRÌNH DUYỆT / BROWSER') || workingDir.contains('open_profile_browser'))) ||
            (workingDir == null && defaultExecutionMode == 'browser');

        // Build System Prompt
        String sysPrompt = systemPromptBase;
        if (isForcedDeviceMode) {
          sysPrompt += '\n\n⚡ CHẾ ĐỘ MÔI TRƯỜNG THỰC THI BẮT BUỘC: THIẾT BỊ / DEVICE / ANDROID AVD.\n'
              '- Người dùng ĐÃ KÍCH HOẠT CHẾ ĐỘ THIẾT BỊ (DEVICE FIRST).\n'
              '- MỌI TÁC VỤ (mở video, like, bình luận, xem livestream, đăng bài, lướt feed) BẮT BUỘC SỬ DỤNG `open_profile_device`.\n'
              '- TUYỆT ĐỐI CẤM GỌI `open_profile_browser`! Bất kỳ hành động mở trình duyệt nào trong chế độ này đều bị coi là vi phạm nghiêm trọng.';
        } else if (isForcedBrowserMode) {
          sysPrompt += '\n\n⚡ CHẾ ĐỘ MÔI TRƯỜNG THỰC THI BẮT BUỘC: TRÌNH DUYỆT / BROWSER.\n'
              '- MỌI TÁC VỤ BẮT BUỘC SỬ DỤNG `open_profile_browser`.\n'
              '- TUYỆT ĐỐI CẤM GỌI `open_profile_device`.';
        }

        if (workingDir != null && workingDir.isNotEmpty) {
          if (workingDir.startsWith('=== DANH SÁCH NHÂN VẬT ĐƯỢC CHỈ ĐỊNH') || workingDir.contains('👤 Nhân vật:')) {
            sysPrompt += '\n\n$workingDir\n\n🎯 QUY TẮC BẮT BUỘC TỐI THƯỢNG VỀ ĐA NHÂN VẬT (MULTI-PERSONAS SCOPE):\n'
                '- Bạn CHỈ ĐƯỢC PHÉP thao tác, tương tác, mở trình duyệt hoặc mở thiết bị Android cho DUY NHẤT các nhân vật/IP nằm trong danh sách Scope trên.\n'
                '- ĐẶC BIỆT KHI SCOPE CHỈ CÓ 1 NHÂN VẬT (hoặc người dùng chỉ chọn 1 profile):\n'
                '  + BẮT BUỘC CHỈ MỞ ĐÚNG 1 TRÌNH DUYỆT HOẶC 1 THIẾT BỊ DUY NHẤT cho nhân vật đó. TUYỆT ĐỐI KHÔNG ĐƯỢC mở 2, 3 hay mở toàn bộ các máy/trình duyệt khác có trong hệ thống!\n'
                '  + Khi gọi tool `open_profile_browser` hoặc `open_profile_device`: CHỈ truyền IP của nhân vật đó vào tham số `ip`, KHÔNG ĐƯỢC truyền mảng `ips` chứa nhiều IP.\n'
                '  + TUYỆT ĐỐI KHÔNG được tự ý lấy các IP ngoài danh sách Scope trên (dù có gọi `list_profiles` hay thấy lịch sử trước đó).\n'
                '- KHI SCOPE CÓ NHIỀU NHÂN VẬT (ví dụ người dùng chọn 2, 3 nhân vật trong Scope):\n'
                '  + MẶC ĐỊNH: Bất kỳ yêu cầu chung nào (mở video, xem link, lướt web, tương tác, seeding...) mà KHÔNG nêu đích danh một nhân vật cụ thể thì BẮT BUỘC PHẢI THỰC THI CHO TẤT CẢ các nhân vật trong Scope này. Truyền toàn bộ danh sách IP trong Scope vào tham số `ips` của tool `open_profile_browser` hoặc `open_profile_device`.\n'
                '  + TUYỆT ĐỐI KHÔNG ĐƯỢC chỉ chọn 1 nhân vật duy nhất rồi bỏ quên các nhân vật còn lại trong Scope khi người dùng không chỉ định riêng ai.\n'
                '  + CHỈ KHI người dùng gọi đích danh tên 1 nhân vật (hoặc yêu cầu rõ "chỉ mở cho X"): Mới truyền đúng 1 IP của nhân vật đó vào tham số `ip`.\n'
                '- MỖI LẦN NHẬN YÊU CẦU MỚI: Phải tuân thủ đúng phạm vi Scope đã được cung cấp phía trên.';
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

        // Dự phòng 1: Nếu workingDir không có Scope nhưng trong PersonaService đang có activeScopeIps
        if (allowedScopeIps.isEmpty && _personaService.activeScopeIps.isNotEmpty) {
          allowedScopeIps.addAll(_personaService.activeScopeIps);
        }

        // Dự phòng 2: Phân tích số lượng nhân vật từ câu prompt (ví dụ: "chọn 3 nhân vật", "3 personas", "mở 2 máy"...)
        int? requestedCountFromPrompt;
        final countMatch = RegExp(r'(\d+)\s*(?:nhân vật|persona|profile|máy|acc|tài khoản|con|người)', caseSensitive: false).firstMatch(message);
        if (countMatch != null) {
          final parsed = int.tryParse(countMatch.group(1) ?? '');
          if (parsed != null && parsed > 0) {
            requestedCountFromPrompt = parsed;
          }
        }

        if (allowedScopeIps.isNotEmpty) {
          fullUserPrompt += '\n\n[LƯU Ý QUAN TRỌNG VỀ PHẠM VI NHÂN VẬT]: Hiện tại người dùng ĐANG CHỌN ĐÚNG ${allowedScopeIps.length} nhân vật trong Scope (danh sách IP: ${allowedScopeIps.join(", ")}). Bạn BẮT BUỘC chỉ được mở trình duyệt/thiết bị cho đúng ${allowedScopeIps.length} nhân vật này. TUYỆT ĐỐI KHÔNG mở cho các nhân vật ngoài danh sách Scope này!';
        } else if (requestedCountFromPrompt != null) {
          fullUserPrompt += '\n\n[LƯU Ý QUAN TRỌNG VỀ SỐ LƯỢNG NHÂN VẬT]: Người dùng yêu cầu thực thi cho ĐÚNG $requestedCountFromPrompt nhân vật. BẮT BUỘC chỉ mở trình duyệt/thiết bị cho đúng $requestedCountFromPrompt nhân vật, TUYỆT ĐỐI KHÔNG mở toàn bộ hệ thống!';
        }

        if (isForcedDeviceMode) {
          fullUserPrompt += '\n\n[CHỈ THỊ MÔI TRƯỜNG THỰC THI BẮT BUỘC]: Người dùng YÊU CẦU CHẠY TRÊN THIẾT BỊ / MÁY ẢO ANDROID. BẮT BUỘC sử dụng tool `open_profile_device`. TUYỆT ĐỐI KHÔNG ĐƯỢC GỌI TOOL `open_profile_browser`!';
        } else if (isForcedBrowserMode) {
          fullUserPrompt += '\n\n[CHỈ THỊ MÔI TRƯỜNG THỰC THI BẮT BUỘC]: Người dùng YÊU CẦU CHẠY TRÊN TRÌNH DUYỆT. BẮT BUỘC sử dụng tool `open_profile_browser`. TUYỆT ĐỐI KHÔNG ĐƯỢC GỌI TOOL `open_profile_device`!';
        }

        // Add current user message
        messages.add({'role': 'user', 'content': fullUserPrompt});

        final tools = <Map<String, dynamic>>[
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
          if (!isForcedDeviceMode)
            {
              'type': 'function',
              'function': {
                'name': 'open_profile_browser',
                'description': allowedScopeIps.isNotEmpty
                    ? 'Mở trình duyệt riêng biệt cho hồ sơ/nhân vật theo IP. QUY TẮC BẮT BUỘC TỐI THƯỢNG: Hiện tại người dùng đã chọn Phạm vi Scope gồm đúng ${allowedScopeIps.length} nhân vật (danh sách IP: ${allowedScopeIps.join(", ")}). TUYỆT ĐỐI CHỈ ĐƯỢC mở trình duyệt cho đúng ${allowedScopeIps.length} IP này bằng cách truyền mảng ["${allowedScopeIps.join('", "')}"] vào tham số "ips". CẤM MỞ BẤT KỲ IP NÀO NGOÀI SCOPE!'
                    : (requestedCountFromPrompt != null
                        ? 'Mở trình duyệt riêng biệt cho hồ sơ/nhân vật theo IP. QUY TẮC BẮT BUỘC: Người dùng yêu cầu mở cho đúng $requestedCountFromPrompt nhân vật. CHỈ truyền mảng $requestedCountFromPrompt IP vào tham số "ips". TUYỆT ĐỐI KHÔNG mở cho toàn bộ các nhân vật!'
                        : 'Mở trình duyệt riêng biệt cho hồ sơ/nhân vật theo IP để tự động hóa tương tác mạng xã hội trên web. QUY TẮC: Chỉ mở cho các nhân vật được người dùng chỉ định. Khi người dùng chỉ định rõ tên một nhân vật, chỉ truyền 1 IP vào "ip".'),
                'parameters': {
                  'type': 'object',
                  'properties': {
                    'ip': {
                      'type': 'string',
                      'description': 'Địa chỉ IP của một nhân vật duy nhất khi người dùng chỉ định rõ đích danh 1 nhân vật.'
                    },
                    'ips': {
                      'type': 'array',
                      'items': {'type': 'string'},
                      'description': allowedScopeIps.isNotEmpty
                          ? 'Danh sách IP của ĐÚNG ${allowedScopeIps.length} nhân vật trong Scope: [${allowedScopeIps.map((e) => '"$e"').join(', ')}]. BẮT BUỘC truyền chính xác mảng này!'
                          : 'Danh sách các địa chỉ IP của các nhân vật cần mở trình duyệt.'
                    },
                    'url': {
                      'type': 'string',
                      'description': 'Đường dẫn trang web mạng xã hội muốn mở (ví dụ: https://facebook.com, https://tiktok.com, https://youtube.com)'
                    }
                  }
                }
              }
            },
          if (!isForcedDeviceMode)
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
              'description': isForcedBrowserMode
                  ? '[VÔ HIỆU HÓA TẠM THỜI]: Chế độ hiện tại là TRÌNH DUYỆT / BROWSER. CẤM GỌI CÔNG CỤ NÀY, hãy gọi open_profile_browser thay thế!'
                  : (allowedScopeIps.isNotEmpty
                      ? 'Khởi chạy hoặc kết nối thiết bị Android cho nhân vật theo IP. QUY TẮC BẮT BUỘC TỐI THƯỢNG: Hiện tại Scope đã chọn đúng ${allowedScopeIps.length} nhân vật (${allowedScopeIps.join(", ")}). TUYỆT ĐỐI CHỈ ĐƯỢC mở thiết bị cho các IP trong Scope này. CẤM MỞ BẤT KỲ IP NÀO NGOÀI SCOPE!'
                      : (requestedCountFromPrompt != null
                          ? 'Khởi chạy thiết bị Android cho nhân vật theo IP. QUY TẮC BẮT BUỘC: Người dùng yêu cầu chạy cho đúng $requestedCountFromPrompt nhân vật. CHỈ truyền $requestedCountFromPrompt IP vào ips. CẤM MỞ TOÀN BỘ HỆ THỐNG!'
                          : 'Khởi chạy hoặc kết nối thiết bị Android (máy ảo AVD local hoặc thiết bị ngoại vi qua WiFi/USB) cho nhân vật theo IP. QUY TẮC BẮT BUỘC: (1) Mặc định làm việc trên Trình duyệt, chỉ dùng thiết bị khi người dùng yêu cầu rõ ràng; (2) GIỚI HẠN TỐI ĐA 2 THIẾT BỊ MỞ CÙNG LÚC TRÊN TOÀN HỆ THỐNG ĐỂ TRÁNH TREO MÁY. Tuyệt đối không mở từ 3 thiết bị trở lên cùng lúc; (3) Với yêu cầu chạy nhiều thiết bị (kể cả 100 devices): Phải đảm bảo từng thiết bị chạy XONG XUÔI tác vụ auto rồi mới đóng bằng close_profile_device, sau đó mới mở thiết bị tiếp theo cho đến khi hoàn tất toàn bộ danh sách.')),
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
                    'description': allowedScopeIps.isNotEmpty
                        ? 'Danh sách IP của đúng ${allowedScopeIps.length} nhân vật trong Scope: [${allowedScopeIps.map((e) => '"$e"').join(', ')}]'
                        : 'Danh sách IP của các nhân vật cần khởi chạy thiết bị Android.'
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
              'name': 'fast_social_action',
              'description': 'Thực thi nhanh thao tác mạng xã hội (Like, Thả tim, Viết bình luận, Mở video) trên thiết bị Android theo Macro tự động hóa riêng biệt của từng nhân vật. Tự động dùng macro tọa độ đã học của nhân vật để bấm Like/Comment trong tích tắc mà không cần gọi nhiều vòng ADB chậm chạp.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'ip': {
                    'type': 'string',
                    'description': 'Địa chỉ IP của nhân vật thực hiện thao tác (bắt buộc để nạp macro riêng của nhân vật đó)'
                  },
                  'ips': {
                    'type': 'array',
                    'items': {'type': 'string'},
                    'description': 'Danh sách IP của các nhân vật nếu muốn chạy đồng loạt'
                  },
                  'platform': {
                    'type': 'string',
                    'enum': ['facebook', 'tiktok', 'youtube'],
                    'description': 'Nền tảng mạng xã hội: facebook, tiktok hoặc youtube'
                  },
                  'action': {
                    'type': 'string',
                    'enum': ['like', 'comment', 'like_and_comment', 'open_video'],
                    'description': 'Loại hành vi tương tác cần thực thi: like (thả tim/like), comment (bình luận), like_and_comment (vừa like vừa bình luận), open_video (chỉ mở video)'
                  },
                  'video_url': {
                    'type': 'string',
                    'description': 'Đường dẫn link video/reel/post mạng xã hội (tùy chọn)'
                  },
                  'comment_text': {
                    'type': 'string',
                    'description': 'Nội dung bình luận nếu action là comment hoặc like_and_comment'
                  }
                },
                'required': ['platform', 'action']
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'save_automation_macro',
              'description': 'Học và lưu trữ tọa độ/selector hoặc tham số hành vi tự động hóa vào bộ nhớ macro riêng biệt của nhân vật theo IP.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'ip': {
                    'type': 'string',
                    'description': 'Địa chỉ IP của nhân vật'
                  },
                  'action_key': {
                    'type': 'string',
                    'description': 'Khóa định danh macro (ví dụ: facebook_reel_like, tiktok_heart, facebook_comment_box)'
                  },
                  'macro_data': {
                    'type': 'object',
                    'description': 'Dữ liệu macro (ví dụ: {"x": 1017, "y": 1145, "x_percent": 0.941, "y_percent": 0.596, "delay_ms": 3000})'
                  },
                  'resolution': {
                    'type': 'string',
                    'description': 'Độ phân giải màn hình tương ứng (ví dụ: "1080x1920")'
                  }
                },
                'required': ['ip', 'action_key', 'macro_data']
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

            // Tool execution loop
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
                      // Nếu có Scope personas được chọn, CHỈ trả về đúng các nhân vật trong Scope
                      final filteredProfiles = allowedScopeIps.isNotEmpty
                          ? profiles.values.where((p) => allowedScopeIps.contains(p.ip)).toList()
                          : profiles.values.toList();

                      final list = filteredProfiles.map((p) => {
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

                    // Scope enforcement: Tuyệt đối không để lọt IP ngoài Scope hoặc mở tràn lan
                    if (allowedScopeIps.isNotEmpty) {
                      if (allowedScopeIps.length == 1) {
                        // Scope chỉ có 1 nhân vật -> ÉP BUỘC chỉ mở duy nhất 1 nhân vật đó!
                        targetIps.clear();
                        targetIps.add(allowedScopeIps.first);
                      } else {
                        // Scope có nhiều nhân vật
                        // Kiểm tra xem người dùng có chỉ định đích danh 1 nhân vật trong nội dung prompt không
                        final lowerPrompt = message.toLowerCase();
                        final profilesMap = await _personaService.loadSavedPersonas();
                        bool userExplicitlyPickedSingle = false;
                        for (final scopeIp in allowedScopeIps) {
                          final p = profilesMap[scopeIp];
                          if (p != null) {
                            final pName = p.name.trim().toLowerCase();
                            if (pName.isNotEmpty && (lowerPrompt.contains(pName) || lowerPrompt.contains(p.ip))) {
                              userExplicitlyPickedSingle = true;
                              break;
                            }
                          }
                        }

                        if (!userExplicitlyPickedSingle) {
                          // Người dùng không nêu đích danh 1 ai -> MẶC ĐỊNH áp dụng cho TẤT CẢ nhân vật trong Scope!
                          targetIps.clear();
                          targetIps.addAll(allowedScopeIps);
                        } else {
                          // Người dùng có nêu đích danh -> Lọc bỏ bất kỳ IP nào không nằm trong danh sách Scope
                          targetIps.retainWhere((ip) => allowedScopeIps.contains(ip));
                          if (targetIps.isEmpty) {
                            targetIps.addAll(allowedScopeIps);
                          }
                        }
                      }
                    } else if (requestedCountFromPrompt != null && targetIps.length > requestedCountFromPrompt) {
                      // Nếu không có Scope cụ thể nhưng người dùng yêu cầu N nhân vật, chỉ lấy đúng N IP
                      final capped = targetIps.take(requestedCountFromPrompt).toList();
                      targetIps.clear();
                      targetIps.addAll(capped);
                    }

                    final url = parsedArgs['url']?.toString().trim();
                    if (targetIps.isEmpty) {
                      toolOutput = 'Lỗi: Thiếu tham số IP nhân vật hợp lệ trong phạm vi (Scope).';
                      break;
                    }

                    // ĐÁNH CHẶN CỨNG: Nếu đang ở chế độ Thiết bị (Device / AVD), tự động chuyển hướng sang mở thiết bị
                    if (isForcedDeviceMode) {
                      onStatus('Đang tự động chuyển hướng sang khởi chạy Thiết bị / AVD Android cho ${targetIps.length} nhân vật (${targetIps.join(', ')})...');
                      final serversDevRedirect = await _configService.getServers();
                      final activeServerDevRedirect = serversDevRedirect.firstWhere(
                        (s) => s.isSelected,
                        orElse: () => serversDevRedirect.isNotEmpty
                            ? serversDevRedirect.first
                            : ServerModel.fromJson(cfg),
                      );

                      final List<String> devSuccessList = [];
                      final List<String> devFailList = [];
                      for (final tip in targetIps) {
                        await _socks5Service.ensureDeviceCapacity(exemptIps: [tip]);
                        onStatus('Đang khởi chạy thiết bị cho IP: $tip...');
                        final success = await _socks5Service.launchDeviceWithSocks5(
                          server: activeServerDevRedirect,
                          ip: tip,
                          deviceType: 'mobile',
                        );
                        if (success) {
                          devSuccessList.add(tip);
                        } else {
                          devFailList.add(tip);
                        }
                      }
                      if (devFailList.isEmpty) {
                        toolOutput = 'Đã khởi chạy thiết bị Android thành công cho ${devSuccessList.length} nhân vật (${devSuccessList.join(', ')}).';
                      } else if (devSuccessList.isEmpty) {
                        toolOutput = 'Không thể khởi chạy thiết bị Android cho các IP: ${devFailList.join(', ')}.';
                      } else {
                        toolOutput = 'Đã mở thiết bị cho: ${devSuccessList.join(', ')}. Thất bại tại: ${devFailList.join(', ')}.';
                      }
                      break;
                    }

                    final servers = await _configService.getServers();
                    final activeServer = servers.firstWhere(
                      (s) => s.isSelected,
                      orElse: () => servers.isNotEmpty
                          ? servers.first
                          : ServerModel.fromJson(cfg),
                    );

                    // Mở trình duyệt song song cho tất cả các nhân vật được chọn thay vì tuần tự
                    onStatus('Đang mở trình duyệt đồng thời cho ${targetIps.length} nhân vật (${targetIps.join(', ')})...');
                    final launchResults = await Future.wait(targetIps.map((tip) async {
                      final success = await _socks5Service.launchBrowserWithSocks5(
                        server: activeServer,
                        ip: tip,
                        startUrl: url,
                      );
                      return MapEntry(tip, success);
                    }));

                    final List<String> successList = [];
                    final List<String> failList = [];
                    for (final res in launchResults) {
                      if (res.value) {
                        successList.add(res.key);
                      } else {
                        failList.add(res.key);
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
                        // Scope có nhiều nhân vật
                        // Kiểm tra xem người dùng có chỉ định đích danh 1 nhân vật trong prompt không
                        final lowerPrompt = message.toLowerCase();
                        final profilesMap = await _personaService.loadSavedPersonas();
                        bool userExplicitlyPickedSingle = false;
                        for (final scopeIp in allowedScopeIps) {
                          final p = profilesMap[scopeIp];
                          if (p != null) {
                            final pName = p.name.trim().toLowerCase();
                            if (pName.isNotEmpty && (lowerPrompt.contains(pName) || lowerPrompt.contains(p.ip))) {
                              userExplicitlyPickedSingle = true;
                              break;
                            }
                          }
                        }

                        if (!userExplicitlyPickedSingle) {
                          // Người dùng không nêu đích danh -> Áp dụng cho TẤT CẢ nhân vật trong Scope
                          targetDevIps.clear();
                          targetDevIps.addAll(allowedScopeIps);
                        } else {
                          // Người dùng có nêu đích danh -> Lọc bỏ bất kỳ IP nào ngoài Scope
                          targetDevIps.retainWhere((ip) => allowedScopeIps.contains(ip));
                          if (targetDevIps.isEmpty) {
                            targetDevIps.addAll(allowedScopeIps);
                          }
                        }
                      }
                    } else if (requestedCountFromPrompt != null && targetDevIps.length > requestedCountFromPrompt) {
                      final cappedDev = targetDevIps.take(requestedCountFromPrompt).toList();
                      targetDevIps.clear();
                      targetDevIps.addAll(cappedDev);
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

                  case 'save_automation_macro':
                    final mIp = parsedArgs['ip']?.toString().trim() ?? '';
                    final mKey = parsedArgs['action_key']?.toString().trim() ?? '';
                    final mData = parsedArgs['macro_data'] is Map ? Map<String, dynamic>.from(parsedArgs['macro_data'] as Map) : null;
                    final mRes = parsedArgs['resolution']?.toString().trim();

                    if (mIp.isEmpty || mKey.isEmpty || mData == null) {
                      toolOutput = 'Lỗi: Thiếu tham số ip, action_key hoặc macro_data.';
                      break;
                    }

                    final savedOk = await _personaService.saveMacroForPersona(
                      ip: mIp,
                      actionKey: mKey,
                      macroData: mData,
                      resolution: mRes,
                    );
                    if (savedOk) {
                      toolOutput = 'Đã lưu thành công bộ nhớ macro "$mKey" cho nhân vật có IP $mIp: ${jsonEncode(mData)} (Độ phân giải: ${mRes ?? "Mặc định"}). Lần sau nhân vật này sẽ thực thi ngay lập tức mà không cần dò lại giao diện!';
                    } else {
                      toolOutput = 'Không tìm thấy hồ sơ nhân vật với IP $mIp để lưu macro.';
                    }
                    break;

                  case 'fast_social_action':
                    final actionPlatform = parsedArgs['platform']?.toString().trim().toLowerCase() ?? 'facebook';
                    final actType = parsedArgs['action']?.toString().trim().toLowerCase() ?? 'like';
                    final vUrl = parsedArgs['video_url']?.toString().trim();
                    final cText = parsedArgs['comment_text']?.toString().trim();

                    final List<String> actionTargetIps = [];
                    if (parsedArgs['ips'] is List) {
                      for (final item in parsedArgs['ips']) {
                        final s = item?.toString().trim() ?? '';
                        if (s.isNotEmpty && !actionTargetIps.contains(s)) actionTargetIps.add(s);
                      }
                    }
                    final sActIp = parsedArgs['ip']?.toString().trim() ?? '';
                    if (sActIp.isNotEmpty && !actionTargetIps.contains(sActIp)) {
                      actionTargetIps.add(sActIp);
                    }

                    if (actionTargetIps.isEmpty && allowedScopeIps.isNotEmpty) {
                      actionTargetIps.addAll(allowedScopeIps);
                    }

                    if (actionTargetIps.isEmpty) {
                      toolOutput = 'Lỗi: Không tìm thấy IP nhân vật hợp lệ để thực thi macro.';
                      break;
                    }

                    final adbExe = await _adbManagerService.resolveAdbPath();
                    final List<String> results = [];

                    for (final targetIp in actionTargetIps) {
                      final persona = _personaService.getPersona(targetIp);
                      final pName = persona?.name ?? targetIp;
                      onStatus('Đang thực thi nhanh macro $actType ($actionPlatform) cho nhân vật $pName ($targetIp)...');

                      var serial = await _socks5Service.getRunningDeviceSerialForIp(targetIp);
                      if (serial == null || serial.isEmpty) {
                        onStatus('Đang khởi động thiết bị Android cho $pName ($targetIp)...');
                        final serversDev = await _configService.getServers();
                        final activeServerDev = serversDev.firstWhere(
                          (s) => s.isSelected,
                          orElse: () => serversDev.isNotEmpty
                              ? serversDev.first
                              : ServerModel.fromJson(cfg),
                        );
                        await _socks5Service.ensureDeviceCapacity(exemptIps: [targetIp]);
                        await _socks5Service.launchDeviceWithSocks5(
                          server: activeServerDev,
                          ip: targetIp,
                        );
                        // Chờ thiết bị sẵn sàng tối đa 30s
                        for (int w = 0; w < 15; w++) {
                          await Future.delayed(const Duration(seconds: 2));
                          serial = await _socks5Service.getRunningDeviceSerialForIp(targetIp);
                          if (serial != null && serial.isNotEmpty) {
                            final bootRes = await Process.run(adbExe, ['-s', serial, 'shell', 'getprop', 'sys.boot_completed']);
                            if (bootRes.stdout.toString().trim() == '1') break;
                          }
                        }
                      }

                      if (serial == null || serial.isEmpty) {
                        results.add('$pName ($targetIp): Thiết bị chưa kết nối hoặc không thể khởi chạy');
                        continue;
                      }

                      // 1. Lấy kích thước màn hình thiết bị thực tế
                      int screenWidth = 1080;
                      int screenHeight = 1920;
                      try {
                        final sizeRes = await Process.run(adbExe, ['-s', serial, 'shell', 'wm', 'size']);
                        final sizeMatch = RegExp(r'(\d+)x(\d+)').firstMatch(sizeRes.stdout.toString());
                        if (sizeMatch != null) {
                          screenWidth = int.parse(sizeMatch.group(1)!);
                          screenHeight = int.parse(sizeMatch.group(2)!);
                        }
                      } catch (_) {}

                      // 2. Mở URL hoặc App nếu có video_url
                      if (vUrl != null && vUrl.isNotEmpty) {
                        if (actionPlatform == 'facebook') {
                          // Thử mở deep link Facebook Reel
                          await Process.run(adbExe, ['-s', serial, 'shell', 'am', 'start', '-a', 'android.intent.action.VIEW', '-d', vUrl, 'com.facebook.katana']);
                        } else if (actionPlatform == 'tiktok') {
                          await Process.run(adbExe, ['-s', serial, 'shell', 'am', 'start', '-a', 'android.intent.action.VIEW', '-d', vUrl, 'com.zhiliaoapp.musically']);
                        } else {
                          await Process.run(adbExe, ['-s', serial, 'shell', 'am', 'start', '-a', 'android.intent.action.VIEW', '-d', vUrl]);
                        }
                        // Chờ mở app và tự xử lý pop-up "Always / Open with" nếu có
                        await Future.delayed(const Duration(milliseconds: 1500));
                        try {
                          // Nếu có hộp thoại chọn app (ResolverActivity), bấm Always hoặc chọn app
                          final topWin = await Process.run(adbExe, ['-s', serial, 'shell', 'dumpsys', 'window']);
                          if (topWin.stdout.toString().contains('ResolverActivity')) {
                            // Chạm vào nút Always (khoảng 70% X, 65% Y)
                            final alwaysX = (screenWidth * 0.75).toInt();
                            final alwaysY = (screenHeight * 0.65).toInt();
                            await Process.run(adbExe, ['-s', serial, 'shell', 'input', 'tap', '$alwaysX', '$alwaysY']);
                            await Future.delayed(const Duration(milliseconds: 500));
                          }
                        } catch (_) {}
                      }

                      // 3. Tra cứu macro đã lưu của riêng nhân vật này
                      final macroKey = '${actionPlatform}_$actType';
                      final existingMacro = _personaService.getMacroForPersona(targetIp, macroKey) ??
                          _personaService.getMacroForPersona(targetIp, '${actionPlatform}_like');

                      int tapX;
                      int tapY;

                      if (existingMacro != null && existingMacro['x_percent'] != null && existingMacro['y_percent'] != null) {
                        // Tính toán tọa độ theo tỉ lệ màn hình của nhân vật
                        final xp = (existingMacro['x_percent'] as num).toDouble();
                        final yp = (existingMacro['y_percent'] as num).toDouble();
                        tapX = (screenWidth * xp).toInt();
                        tapY = (screenHeight * yp).toInt();
                      } else {
                        // Tọa độ chuẩn hóa mặc định cho Facebook / TikTok Reel
                        if (actionPlatform == 'facebook') {
                          // Nút Like của Facebook Reel thường ở cạnh phải, khoảng 94% X và 59% Y
                          tapX = (screenWidth * 0.941).toInt();
                          tapY = (screenHeight * 0.596).toInt();
                        } else if (actionPlatform == 'tiktok') {
                          // Nút Thả tim TikTok ở cạnh phải khoảng 93% X và 54% Y (hoặc double tap ở giữa màn hình)
                          tapX = (screenWidth * 0.930).toInt();
                          tapY = (screenHeight * 0.540).toInt();
                        } else {
                          tapX = (screenWidth * 0.5).toInt();
                          tapY = (screenHeight * 0.5).toInt();
                        }

                        // Tự động lưu luôn macro mặc định này cho nhân vật để lần sau có sẵn
                        await _personaService.saveMacroForPersona(
                          ip: targetIp,
                          actionKey: macroKey,
                          macroData: {
                            'x_percent': double.parse((tapX / screenWidth).toStringAsFixed(3)),
                            'y_percent': double.parse((tapY / screenHeight).toStringAsFixed(3)),
                            'base_x': tapX,
                            'base_y': tapY,
                            'dwell_delay_ms': 2500,
                          },
                          resolution: '${screenWidth}x$screenHeight',
                        );
                      }

                      // Thêm chút jitter ngẫu nhiên (+/- 4px) để tránh bot detection
                      final jitter = (DateTime.now().millisecond % 9) - 4;
                      final finalX = tapX + jitter;
                      final finalY = tapY + jitter;

                      if (actType == 'like' || actType == 'like_and_comment') {
                        // Nếu là TikTok có thể double tap giữa màn hình hoặc tap nút tim
                        if (actionPlatform == 'tiktok') {
                          final centerX = (screenWidth * 0.5).toInt();
                          final centerY = (screenHeight * 0.5).toInt();
                          await Process.run(adbExe, ['-s', serial, 'shell', 'input', 'tap', '$centerX', '$centerY']);
                          await Future.delayed(const Duration(milliseconds: 100));
                          await Process.run(adbExe, ['-s', serial, 'shell', 'input', 'tap', '$centerX', '$centerY']);
                        } else {
                          await Process.run(adbExe, ['-s', serial, 'shell', 'input', 'tap', '$finalX', '$finalY']);
                        }
                        await Future.delayed(const Duration(milliseconds: 800));
                      }

                      if (actType == 'comment' || actType == 'like_and_comment') {
                        // Tọa độ nút mở bình luận (thường ngay dưới nút Like khoảng 68% Y)
                        final commentBtnX = (screenWidth * 0.941).toInt();
                        final commentBtnY = (screenHeight * 0.685).toInt();
                        await Process.run(adbExe, ['-s', serial, 'shell', 'input', 'tap', '$commentBtnX', '$commentBtnY']);
                        await Future.delayed(const Duration(milliseconds: 1200));

                        // Chạm vào ô nhập bình luận
                        final inputX = (screenWidth * 0.4).toInt();
                        final inputY = (screenHeight * 0.95).toInt();
                        await Process.run(adbExe, ['-s', serial, 'shell', 'input', 'tap', '$inputX', '$inputY']);
                        await Future.delayed(const Duration(milliseconds: 600));

                        final textToInput = (cText != null && cText.isNotEmpty) ? cText : 'Video hay quá bạn ơi!';
                        // Dùng am broadcast hoặc input text an toàn
                        final encodedBase64 = base64Encode(utf8.encode(textToInput));
                        await Process.run(adbExe, [
                          '-s', serial, 'shell',
                          'am', 'broadcast', '-a', 'ADB_INPUT_B64', '--es', 'msg', encodedBase64
                        ]);
                        // Fallback gõ trực tiếp qua ADB nếu thiết bị chưa cài ADB Keyboard
                        final escaped = textToInput.replaceAll(' ', '%s').replaceAll("'", "\\'");
                        await Process.run(adbExe, ['-s', serial, 'shell', 'input', 'text', escaped]);

                        await Future.delayed(const Duration(milliseconds: 500));
                        // Bấm phím Enter hoặc nút Send
                        await Process.run(adbExe, ['-s', serial, 'shell', 'input', 'keyevent', '66']);
                      }

                      results.add('$pName ($targetIp): Đã bấm $actType siêu tốc (Tọa độ: $finalX, $finalY - Màn hình ${screenWidth}x$screenHeight)');
                    }

                    toolOutput = results.join('\n');
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
