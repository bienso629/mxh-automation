import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../models/attachment_item.dart';
import '../../models/chat_message.dart';
import '../../models/server_model.dart';
import 'adb_manager_service.dart';
import 'browser_cdp_service.dart';
import 'cli_automation_bridge_service.dart';
import 'task_notification_service.dart';
import 'database_service.dart';
import 'local_config_service.dart';
import 'persona_service.dart';
import 'socks5_proxy_service.dart';

class AiTaskExecutionResult {
  /// 'completed' | 'failed' | 'incomplete' | 'error' | 'cancelled' | 'chat'
  final String outcome;
  final String reply;
  final String? evidence;
  final String? failureReason;
  final List<ToolExecutionItem> executedTools;

  const AiTaskExecutionResult({
    required this.outcome,
    required this.reply,
    this.evidence,
    this.failureReason,
    this.executedTools = const [],
  });

  bool get isCompleted => outcome == 'completed';
}

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
   - BẮT BUỘC: Sau khi gọi hoặc thực thi bất kỳ công cụ (tool/function) nào, bạn PHẢI luôn luôn có câu trả lời bằng văn bản gửi cho người dùng để trình bày kết quả tự nhiên, ngắn gọn. Tuyệt đối KHÔNG được kết thúc cuộc hội thoại trong im lặng hoặc trả về nội dung rỗng.
   - TUYỆT ĐỐI KHÔNG in danh sách log kỹ thuật kiểu "Đã thực hiện xong các tác vụ:", không liệt kê tên hàm công cụ nội bộ (như `get_connected_devices`, `execute_adb_command`, `execute_terminal_command`, `list_profiles`) hay chuỗi JSON/lệnh shell thô vào câu trả lời cho người dùng.

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
     + Nếu bạn phát hiện tọa độ mới chính xác cho một thao tác đặc thù hoặc độ phân giải mới, hãy gọi `save_automation_macro` để nhân vật đó học và ghi nhớ cho các lần chạy tiếp theo.

7. ĐIỀU KHIỂN TRANG WEB THẬT TRONG TRÌNH DUYỆT (BROWSER AUTOMATION):
   - `open_profile_browser` CHỈ MỞ CỬA SỔ. Mở xong KHÔNG có nghĩa là đã làm xong việc. Phải tiếp tục thao tác bằng các công cụ:
     `browser_snapshot` (đọc trang + danh sách phần tử có element_id), `browser_click`, `browser_type`, `browser_upload_file`, `browser_press_key`, `browser_scroll`, `browser_wait`, `browser_navigate`, `browser_screenshot`.
   - Luôn gọi `browser_snapshot` trước khi bấm/gõ để lấy element_id mới nhất; sau mỗi thao tác quan trọng gọi lại `browser_snapshot` để kiểm chứng.
   - QUY TRÌNH ĐĂNG VIDEO LÊN FACEBOOK (trình duyệt): mở https://www.facebook.com -> snapshot (nếu thấy form đăng nhập: báo failed "chưa đăng nhập") -> bấm "Ảnh/video" (hoặc "Bạn đang nghĩ gì?" rồi "Ảnh/video") -> `browser_upload_file` với đường dẫn tệp local -> `browser_wait` chờ video tải lên/xử lý (có thể vài phút) -> nhập nội dung bài viết vào ô soạn thảo -> bấm "Tiếp"/"Next" nếu có -> bấm "Đăng"/"Post" -> `browser_wait` chờ khung soạn bài đóng -> snapshot kiểm chứng bài đã đăng (hoặc thông báo "Đang xử lý video") -> `browser_screenshot` làm bằng chứng.
   - Thiết bị Android: dùng `device_push_media` để chép video vào thư viện ảnh trước khi đăng trong app.

8. NGUYÊN TẮC ĐẢM BẢO HOÀN THÀNH 100% (BẮT BUỘC TUYỆT ĐỐI):
   - Tự chia yêu cầu thành các bước, thực hiện LẦN LƯỢT TẤT CẢ các bước bằng công cụ. Không dừng giữa chừng, không hỏi lại người dùng khi đã đủ thông tin, không chỉ mô tả kế hoạch.
   - Gặp lỗi ở một bước: tự tìm phương án khác (snapshot lại, tải lại trang, chờ thêm, tìm nút có tên khác, cuộn trang...) rồi làm tiếp.
   - Chỉ khi đã kiểm chứng kết quả thực tế mới gọi `report_task_result(status="completed", evidence=...)`. Nếu đã thử mọi cách mà vẫn bất khả thi mới gọi `report_task_result(status="failed", failure_reason=...)` - hệ thống sẽ tự gửi cảnh báo Email/tin nhắn cho chủ máy.
   - Mọi lượt có thao tác thực tế đều PHẢI kết thúc bằng `report_task_result`. Nếu dừng mà không gọi, hệ thống giám sát sẽ buộc bạn làm tiếp.''';

  /// Thực thi một tác vụ tự động hóa hoàn chỉnh bằng AI Agent (hỗ trợ cả Proxy LLM lẫn Local CLI Agent)
  /// và trả về kết quả có cấu trúc (`AiTaskExecutionResult`) phục vụ bộ lập lịch hẹn giờ (`ScheduleProvider`).
  /// Mặc định không ghi đè lịch sử chat UI (`persistToChatDb: false`) và không gửi cảnh báo trùng
  /// (`suppressFailureNotification: true`, để bộ lập lịch chủ động retry và gửi cảnh báo tổng hợp).
  Future<AiTaskExecutionResult> runAutomatedTask({
    required String sessionId,
    required String prompt,
    String? model,
    String? workingDir,
    bool persistToChatDb = false,
    bool suppressFailureNotification = true,
    int? maxTurnsOverride,
    int? maxNudgesOverride,
    void Function(String status)? onStatus,
    void Function(ToolExecutionItem tool)? onTool,
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() == true) {
      return const AiTaskExecutionResult(
        outcome: 'cancelled',
        reply: 'Tác vụ đã bị hủy trước khi khởi chạy.',
        failureReason: 'Đã bị hủy bởi người dùng',
      );
    }

    final completer = Completer<AiTaskExecutionResult>();
    final executedTools = <ToolExecutionItem>[];
    AiTaskExecutionResult? structuredResult;
    StreamSubscription<String>? sub;
    Timer? cancelPoller;

    void finish(AiTaskExecutionResult res) {
      cancelPoller?.cancel();
      if (!completer.isCompleted) {
        completer.complete(res);
      }
    }

    void checkCancel() {
      if (isCancelled?.call() == true && !completer.isCompleted) {
        sub?.cancel();
        finish(AiTaskExecutionResult(
          outcome: 'cancelled',
          reply: 'Tác vụ đã bị hủy giữa chừng.',
          failureReason: 'Đã bị hủy bởi người dùng',
          executedTools: List<ToolExecutionItem>.from(executedTools),
        ));
      }
    }

    if (isCancelled != null) {
      cancelPoller = Timer.periodic(const Duration(milliseconds: 500), (_) => checkCancel());
    }

    sub = streamChatMessage(
      sessionId: sessionId,
      message: prompt,
      model: model,
      history: const [],
      workingDir: workingDir,
      persistToChatDb: persistToChatDb,
      suppressFailureNotification: suppressFailureNotification,
      maxTurnsOverride: maxTurnsOverride,
      maxNudgesOverride: maxNudgesOverride,
      onToken: (_) => checkCancel(),
      onStatus: (status) {
        checkCancel();
        if (!completer.isCompleted) {
          onStatus?.call(status);
        }
      },
      onTool: (tool) {
        checkCancel();
        executedTools.add(tool);
        if (!completer.isCompleted) {
          onTool?.call(tool);
        }
      },
      onResult: (res) {
        structuredResult = res;
      },
      onDone: (fullReply) {
        finish(
          structuredResult ??
              AiTaskExecutionResult(
                outcome: 'incomplete',
                reply: fullReply,
                failureReason: 'AI Agent kết thúc mà không trả về trạng thái xác nhận hoàn thành.',
                executedTools: List<ToolExecutionItem>.from(executedTools),
              ),
        );
      },
      onError: (err) {
        finish(
          structuredResult ??
              AiTaskExecutionResult(
                outcome: 'error',
                reply: err.toString(),
                failureReason: err.toString(),
                executedTools: List<ToolExecutionItem>.from(executedTools),
              ),
        );
      },
    );

    final result = await completer.future;
    cancelPoller?.cancel();
    await sub.cancel();
    return result;
  }

  StreamSubscription<String> streamChatMessage({
    required String sessionId,
    required String message,
    String? model,
    List<AttachmentItem>? attachments,
    List<Map<String, dynamic>>? history,
    String? workingDir,
    bool persistToChatDb = true,
    bool suppressFailureNotification = false,
    void Function(AiTaskExecutionResult result)? onResult,
    int? maxTurnsOverride,
    int? maxNudgesOverride,
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
        if (persistToChatDb) {
          final userMsg = ChatMessageModel(
            sessionId: sessionId,
            role: 'user',
            content: message,
            model: targetModel,
            attachments: attachments,
            createdAt: DateTime.now(),
          );
          await _dbService.insertMessage(userMsg);
        }

        final aiEngineType = cfg['ai_engine_type']?.toString() ?? 'proxy';
        final activeCliAgent = cfg['active_cli_agent']?.toString() ?? 'antigravity-cli';

        // Check if running Local CLI Agent mode or selected model is a CLI model
        final isCli = aiEngineType == 'cli' || _isCliModel(targetModel);
        if (isCli) {
          final chosenCli = (aiEngineType == 'cli' && !_isCliModel(targetModel))
              ? activeCliAgent
              : targetModel;
          String cliPrompt = message;
          if (attachments != null && attachments.isNotEmpty) {
            final attBuf = StringBuffer(message);
            attBuf.writeln('\n\n=== TỆP & ẢNH ĐÍNH KÈM TỪ NGƯỜI DÙNG ===');
            for (final att in attachments) {
              final localInfo = (att.path != null && att.path!.isNotEmpty)
                  ? ' (Đường dẫn local: ${att.path} - Dung lượng: ${att.formattedSize})'
                  : ' (Dung lượng: ${att.formattedSize})';
              attBuf.writeln('- [${att.name}$localInfo]');
            }
            cliPrompt = attBuf.toString();
          }
          await _runCliAgent(
            cliName: chosenCli,
            prompt: cliPrompt,
            sessionId: sessionId,
            maxAttempts: (int.tryParse('${cfg['agent_cli_max_attempts'] ?? ''}') ?? 3).clamp(1, 10),
            workingDir: workingDir,
            suppressFailureNotification: suppressFailureNotification,
            onResult: onResult,
            onToken: onToken,
            onStatus: onStatus,
            onTool: onTool,
            onDone: (reply) async {
              if (persistToChatDb) {
                final assistantMsg = ChatMessageModel(
                  sessionId: sessionId,
                  role: 'assistant',
                  content: reply,
                  model: chosenCli,
                  createdAt: DateTime.now(),
                );
                await _dbService.insertMessage(assistantMsg);
              }
              onDone(reply);
            },
            onError: onError,
            isCancelled: () => isCancelled,
          );
          return;
        }

        var baseUrl = cfg['proxy_base_url']?.toString() ?? 'https://api.mitom.ai/v1';
        if (!LocalConfigService.isValidMitomProxyUrl(baseUrl)) {
          const invalidMsg = 'Cấu hình Proxy Base URL không hợp lệ. Chỉ chấp nhận domain thuộc *.mitom.ai';
          onResult?.call(const AiTaskExecutionResult(
            outcome: 'error',
            reply: invalidMsg,
            failureReason: invalidMsg,
          ));
          onError(invalidMsg);
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
                '- Mỗi nhân vật được định danh duy nhất bởi `ProfileKey` (ví dụ `127.0.0.1`, `127.0.0.1##2`, `127.0.0.1##3`... khi nhiều nhân vật dùng chung 1 địa chỉ mạng IP). Khi gọi bất kỳ công cụ nào (`open_profile_browser`, `close_profile_browser`, `open_profile_device`, `close_profile_device`, `fast_social_action`, `save_automation_macro`), BẮT BUỘC truyền nguyên vẹn `ProfileKey` vào tham số `ip` / `ips` (TUYỆT ĐỐI KHÔNG cắt bỏ hậu tố `##n`!).\n'
                '- Bạn CHỈ ĐƯỢC PHÉP thao tác, tương tác, mở trình duyệt hoặc mở thiết bị Android cho DUY NHẤT các nhân vật nằm trong danh sách Scope trên.\n'
                '- ĐẶC BIỆT KHI SCOPE CHỈ CÓ 1 NHÂN VẬT (hoặc người dùng chỉ chọn 1 profile):\n'
                '  + BẮT BUỘC CHỈ MỞ ĐÚNG 1 TRÌNH DUYỆT HOẶC 1 THIẾT BỊ DUY NHẤT cho đúng `ProfileKey` của nhân vật đó. TUYỆT ĐỐI KHÔNG ĐƯỢC mở 2, 3 hay mở các nhân vật cùng IP khác!\n'
                '  + Khi gọi tool `open_profile_browser` hoặc `open_profile_device`: CHỈ truyền `ProfileKey` của nhân vật đó vào tham số `ip`, KHÔNG ĐƯỢC truyền mảng `ips` chứa nhiều khóa.\n'
                '  + TUYỆT ĐỐI KHÔNG được tự ý lấy các nhân vật ngoài danh sách Scope trên (dù có gọi `list_profiles` hay thấy lịch sử trước đó).\n'
                '- KHI SCOPE CÓ NHIỀU NHÂN VẬT (ví dụ người dùng chọn 2, 3 nhân vật trong Scope):\n'
                '  + MẶC ĐỊNH: Bất kỳ yêu cầu chung nào (mở video, xem link, lướt web, tương tác, seeding...) mà KHÔNG nêu đích danh một nhân vật cụ thể thì BẮT BUỘC PHẢI THỰC THI CHO TẤT CẢ các nhân vật trong Scope này. Truyền toàn bộ danh sách `ProfileKey` trong Scope vào tham số `ips` của tool `open_profile_browser` hoặc `open_profile_device`.\n'
                '  + TUYỆT ĐỐI KHÔNG ĐƯỢC gộp các nhân vật có cùng IP (như `127.0.0.1` và `127.0.0.1##2`) thành 1 mục duy nhất!\n'
                '  + CHỈ KHI người dùng gọi đích danh tên 1 nhân vật (hoặc yêu cầu rõ "chỉ mở cho X"): Mới truyền đúng 1 `ProfileKey` của nhân vật đó vào tham số `ip`.\n'
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
          // Bỏ tin nhắn user cuối nếu trùng câu lệnh hiện tại (tránh gửi lặp 2 lần cho AI)
          final trimmedHistory = List<Map<String, dynamic>>.from(history);
          if (trimmedHistory.isNotEmpty &&
              trimmedHistory.last['role'] == 'user' &&
              (trimmedHistory.last['content']?.toString().trim() ?? '') == message.trim()) {
            trimmedHistory.removeLast();
          }
          for (final h in trimmedHistory) {
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

        // Extract allowed Persona keys (entryKey / ProfileKey) if there is a Personas Scope specified
        final List<String> allowedScopeIps = [];
        if (workingDir != null &&
            (workingDir.contains('SCOPE PERSONAS') ||
                workingDir.contains('ProfileKey:') ||
                workingDir.contains('IP:'))) {
          final keyMatches = RegExp(r'ProfileKey:\s*([0-9a-zA-Z\.\:\_\-#]+)').allMatches(workingDir);
          for (final m in keyMatches) {
            final matchedKey = m.group(1)?.trim();
            if (matchedKey != null && matchedKey.isNotEmpty && !allowedScopeIps.contains(matchedKey)) {
              allowedScopeIps.add(matchedKey);
            }
          }
          if (allowedScopeIps.isEmpty) {
            final ipMatches = RegExp(r'IP:\s*([0-9a-zA-Z\.\:\_\-#]+)').allMatches(workingDir);
            for (final m in ipMatches) {
              final matchedIp = m.group(1)?.trim();
              if (matchedIp != null && matchedIp.isNotEmpty && !allowedScopeIps.contains(matchedIp)) {
                allowedScopeIps.add(matchedIp);
              }
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
          },
          {
            'type': 'function',
            'function': {
              'name': 'report_task_result',
              'description': 'BẮT BUỘC gọi ở cuối mọi yêu cầu có thao tác. Báo cáo kết quả cuối cùng cho hệ thống giám sát. status="completed" chỉ khi đã kiểm chứng xong 100% (kèm evidence cụ thể). status="failed" chỉ khi đã thử mọi phương án mà vẫn bất khả thi (kèm failure_reason) - hệ thống sẽ gửi cảnh báo Email/tin nhắn cho chủ máy.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'status': {'type': 'string', 'enum': ['completed', 'failed']},
                  'summary': {'type': 'string', 'description': 'Tóm tắt các bước đã làm'},
                  'evidence': {'type': 'string', 'description': 'Bằng chứng kiểm chứng (ví dụ: chữ hiển thị trên trang sau khi đăng, URL bài viết, đường dẫn ảnh chụp màn hình)'},
                  'failure_reason': {'type': 'string', 'description': 'Lý do cụ thể không thể hoàn thành'},
                },
                'required': ['status', 'summary'],
              }
            }
          },
          if (!isForcedDeviceMode) ...[
            {
              'type': 'function',
              'function': {
                'name': 'browser_navigate',
                'description': 'Điều hướng tab hiện tại của trình duyệt nhân vật tới URL (tự mở trình duyệt có thể điều khiển nếu chưa mở).',
                'parameters': {
                  'type': 'object',
                  'properties': {
                    'ip': {'type': 'string', 'description': 'ProfileKey của nhân vật'},
                    'url': {'type': 'string'},
                  },
                  'required': ['url'],
                }
              }
            },
            {
              'type': 'function',
              'function': {
                'name': 'browser_snapshot',
                'description': 'Đọc trạng thái trang hiện tại: URL, tiêu đề, hộp thoại đang mở, danh sách phần tử tương tác (element_id, nhãn, disabled, ô chọn tệp) và trích đoạn nội dung. Gọi trước mỗi lần bấm/gõ và sau mỗi bước để kiểm chứng.',
                'parameters': {
                  'type': 'object',
                  'properties': {
                    'ip': {'type': 'string', 'description': 'ProfileKey của nhân vật'},
                  },
                }
              }
            },
            {
              'type': 'function',
              'function': {
                'name': 'browser_click',
                'description': 'Bấm chuột thật vào phần tử theo element_id (từ browser_snapshot) hoặc theo chữ hiển thị / aria-label.',
                'parameters': {
                  'type': 'object',
                  'properties': {
                    'ip': {'type': 'string'},
                    'element_id': {'type': 'integer'},
                    'text': {'type': 'string', 'description': 'Chữ hoặc aria-label của nút nếu không có element_id'},
                  },
                }
              }
            },
            {
              'type': 'function',
              'function': {
                'name': 'browser_type',
                'description': 'Gõ văn bản vào ô nhập / ô soạn thảo (contenteditable) theo element_id hoặc target_text.',
                'parameters': {
                  'type': 'object',
                  'properties': {
                    'ip': {'type': 'string'},
                    'element_id': {'type': 'integer'},
                    'target_text': {'type': 'string', 'description': 'Placeholder/aria-label của ô nếu không có element_id'},
                    'text': {'type': 'string'},
                    'clear': {'type': 'boolean', 'description': 'Xóa nội dung cũ trước khi gõ'},
                  },
                  'required': ['text'],
                }
              }
            },
            {
              'type': 'function',
              'function': {
                'name': 'browser_upload_file',
                'description': 'Gắn tệp local (video/ảnh) vào ô chọn tệp input[type=file] của trang (ví dụ sau khi bấm "Ảnh/video" trên Facebook). Không cần hộp thoại chọn tệp của hệ điều hành.',
                'parameters': {
                  'type': 'object',
                  'properties': {
                    'ip': {'type': 'string'},
                    'file_path': {'type': 'string', 'description': 'Đường dẫn tuyệt đối tới tệp trên máy local'},
                    'element_id': {'type': 'integer', 'description': 'element_id của ô chọn tệp (tùy chọn)'},
                  },
                  'required': ['file_path'],
                }
              }
            },
            {
              'type': 'function',
              'function': {
                'name': 'browser_press_key',
                'description': 'Nhấn phím: Enter, Escape, Tab, Backspace, ArrowDown, ArrowUp, Space.',
                'parameters': {
                  'type': 'object',
                  'properties': {
                    'ip': {'type': 'string'},
                    'key': {'type': 'string'},
                  },
                  'required': ['key'],
                }
              }
            },
            {
              'type': 'function',
              'function': {
                'name': 'browser_scroll',
                'description': 'Cuộn trang theo pixel (delta_y dương: xuống, âm: lên).',
                'parameters': {
                  'type': 'object',
                  'properties': {
                    'ip': {'type': 'string'},
                    'delta_y': {'type': 'integer'},
                  },
                }
              }
            },
            {
              'type': 'function',
              'function': {
                'name': 'browser_wait',
                'description': 'Chờ tối đa seconds giây cho đến khi trang xuất hiện chữ text (hoặc chữ đó biến mất nếu until_gone=true). Dùng để chờ video tải lên / xử lý / đăng xong.',
                'parameters': {
                  'type': 'object',
                  'properties': {
                    'ip': {'type': 'string'},
                    'text': {'type': 'string'},
                    'until_gone': {'type': 'boolean'},
                    'seconds': {'type': 'integer', 'description': 'Tối đa 600'},
                  },
                }
              }
            },
            {
              'type': 'function',
              'function': {
                'name': 'browser_screenshot',
                'description': 'Chụp màn hình tab hiện tại, lưu file PNG làm bằng chứng hoàn thành.',
                'parameters': {
                  'type': 'object',
                  'properties': {
                    'ip': {'type': 'string'},
                  },
                }
              }
            },
          ],
          if (!isForcedBrowserMode)
            {
              'type': 'function',
              'function': {
                'name': 'device_push_media',
                'description': 'Chép tệp video/ảnh từ máy local vào thư viện ảnh (DCIM/Camera) của thiết bị Android nhân vật để đăng trong app.',
                'parameters': {
                  'type': 'object',
                  'properties': {
                    'ip': {'type': 'string', 'description': 'ProfileKey của nhân vật'},
                    'serial': {'type': 'string', 'description': 'Serial ADB (tùy chọn)'},
                    'file_path': {'type': 'string'},
                  },
                  'required': ['file_path'],
                }
              }
            },
        ];

        String finalReply = '';
        final streamedBuffer = StringBuffer();
        final allExecutedTools = <ToolExecutionItem>[];
        int turnCount = 0;
        final maxTurns = (maxTurnsOverride ?? (int.tryParse('${cfg['agent_max_turns'] ?? ''}') ?? 80)).clamp(10, 400);
        final maxNudges = (maxNudgesOverride ?? (int.tryParse('${cfg['agent_max_continue_nudges'] ?? ''}') ?? 6)).clamp(1, 30);
        int nudges = 0;
        int failureChallenges = 0;
        Map<String, String>? taskReport;
        String? fatalError;
        bool actionToolUsed = false;
        final looksActionable = _looksLikeActionRequest(message);
        const passiveTools = {
          'list_profiles',
          'get_connected_devices',
          'report_task_result',
          'browser_snapshot',
          'browser_screenshot',
        };

        while (turnCount < maxTurns && !isCancelled) {
          turnCount++;
          onStatus(turnCount == 1 ? 'Đang suy nghĩ...' : 'Đang xử lý bước tiếp theo ($turnCount/$maxTurns)...');

          // Gọi AI có tự động thử lại khi mạng/API chập chờn (nguyên nhân phổ biến khiến Agent dừng giữa chừng)
          _AiTurnResult? turn;
          Object? lastTurnError;
          for (int attempt = 1; attempt <= 4 && !isCancelled; attempt++) {
            try {
              turn = await _streamCompletionTurn(
                baseUrl: baseUrl,
                apiKey: apiKey,
                body: {
                  'model': targetModel,
                  'messages': messages,
                  'tools': tools,
                  'stream': true,
                },
                onToken: onToken,
              );
              break;
            } on _NonRetryableAiError catch (e) {
              lastTurnError = e;
              break;
            } catch (e) {
              lastTurnError = e;
              if (attempt < 4) {
                onStatus('Kết nối AI bị gián đoạn (lần $attempt/4), đang tự động thử lại...');
                await Future.delayed(Duration(seconds: 2 * attempt));
              }
            }
          }
          if (isCancelled) break;
          if (turn == null) {
            fatalError = 'Không gọi được AI API sau nhiều lần thử: $lastTurnError';
            break;
          }

          final String stepContent = turn.content;
          streamedBuffer.write(stepContent);
          final toolCallsMap = turn.toolCalls;

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
                      // Nếu có Scope personas được chọn, CHỈ trả về đúng các nhân vật trong Scope (theo effectiveEntryKey)
                      final filteredProfiles = allowedScopeIps.isNotEmpty
                          ? profiles.values
                              .where((p) => allowedScopeIps.contains(p.effectiveEntryKey))
                              .toList()
                          : profiles.values.toList();

                      final list = filteredProfiles.map((p) => {
                        'ip': p.effectiveEntryKey,
                        'entry_key': p.effectiveEntryKey,
                        'network_ip': p.ip,
                        'name': p.name,
                        'age': p.age,
                        'gender': p.gender,
                        'bio': p.bio,
                        'device_type': p.deviceType,
                        'avd_name': p.avdName,
                        'browser_profile_id': p.browserProfileId,
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

                    // Scope enforcement: Tuyệt đối không để lọt nhân vật ngoài Scope hoặc mở tràn lan
                    if (allowedScopeIps.isNotEmpty) {
                      if (allowedScopeIps.length == 1) {
                        // Scope chỉ có 1 nhân vật -> ÉP BUỘC chỉ mở duy nhất 1 nhân vật đó!
                        targetIps.clear();
                        targetIps.add(allowedScopeIps.first);
                      } else {
                        // Scope có nhiều nhân vật
                        // Kiểm tra xem người dùng có chỉ định đích danh nhân vật cụ thể trong nội dung prompt không
                        final lowerPrompt = message.toLowerCase();
                        final profilesMap = await _personaService.loadSavedPersonas();
                        final explicitlyNamedKeys = <String>[];
                        for (final scopeKey in allowedScopeIps) {
                          final p = profilesMap[scopeKey];
                          if (p != null) {
                            final pName = p.name.trim().toLowerCase();
                            if ((pName.isNotEmpty && lowerPrompt.contains(pName)) ||
                                lowerPrompt.contains(scopeKey.toLowerCase())) {
                              explicitlyNamedKeys.add(scopeKey);
                            }
                          }
                        }

                        if (explicitlyNamedKeys.isEmpty) {
                          // Người dùng không nêu đích danh 1 ai -> MẶC ĐỊNH áp dụng cho TẤT CẢ nhân vật trong Scope!
                          targetIps.clear();
                          targetIps.addAll(allowedScopeIps);
                        } else {
                          // Người dùng có nêu đích danh -> Giữ các khóa hợp lệ hoặc dùng đúng nhân vật được gọi tên
                          targetIps.retainWhere((k) => allowedScopeIps.contains(k));
                          if (targetIps.isEmpty) {
                            targetIps.addAll(explicitlyNamedKeys);
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
                        // Scope chỉ có 1 nhân vật -> ÉP BUỘC chỉ mở duy nhất 1 thiết bị cho nhân vật đó!
                        targetDevIps.clear();
                        targetDevIps.add(allowedScopeIps.first);
                      } else {
                        // Scope có nhiều nhân vật
                        // Kiểm tra xem người dùng có chỉ định đích danh nhân vật cụ thể trong prompt không
                        final lowerPrompt = message.toLowerCase();
                        final profilesMap = await _personaService.loadSavedPersonas();
                        final explicitlyNamedKeys = <String>[];
                        for (final scopeKey in allowedScopeIps) {
                          final p = profilesMap[scopeKey];
                          if (p != null) {
                            final pName = p.name.trim().toLowerCase();
                            if ((pName.isNotEmpty && lowerPrompt.contains(pName)) ||
                                lowerPrompt.contains(scopeKey.toLowerCase())) {
                              explicitlyNamedKeys.add(scopeKey);
                            }
                          }
                        }

                        if (explicitlyNamedKeys.isEmpty) {
                          // Người dùng không nêu đích danh -> Áp dụng cho TẤT CẢ nhân vật trong Scope
                          targetDevIps.clear();
                          targetDevIps.addAll(allowedScopeIps);
                        } else {
                          // Người dùng có nêu đích danh -> Giữ khóa hợp lệ hoặc dùng đúng nhân vật được gọi tên
                          targetDevIps.retainWhere((k) => allowedScopeIps.contains(k));
                          if (targetDevIps.isEmpty) {
                            targetDevIps.addAll(explicitlyNamedKeys);
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
                        // Kiểm tra xem thiết bị có đang dùng ADB Keyboard hay không để tránh gõ trùng 2 lần
                        bool usesAdbKeyboard = false;
                        try {
                          final imeRes = await Process.run(adbExe, [
                            '-s', serial, 'shell', 'settings', 'get', 'secure', 'default_input_method',
                          ]);
                          usesAdbKeyboard = imeRes.stdout.toString().toLowerCase().contains('adbkeyboard');
                        } catch (_) {}

                        if (usesAdbKeyboard) {
                          final encodedBase64 = base64Encode(utf8.encode(textToInput));
                          await Process.run(adbExe, [
                            '-s', serial, 'shell',
                            'am', 'broadcast', '-a', 'ADB_INPUT_B64', '--es', 'msg', encodedBase64
                          ]);
                        } else {
                          // Fallback gõ trực tiếp qua ADB nếu thiết bị chưa kích hoạt ADB Keyboard
                          final escaped = textToInput.replaceAll(' ', '%s').replaceAll("'", "\\'");
                          await Process.run(adbExe, ['-s', serial, 'shell', 'input', 'text', escaped]);
                        }

                        await Future.delayed(const Duration(milliseconds: 500));
                        // Bấm phím Enter hoặc nút Send
                        await Process.run(adbExe, ['-s', serial, 'shell', 'input', 'keyevent', '66']);
                      }

                      results.add('$pName ($targetIp): Đã thực hiện thao tác $actType (Tọa độ: $finalX, $finalY - Màn hình ${screenWidth}x$screenHeight). Hãy kiểm chứng lại trên màn hình bằng uiautomator dump trước khi xác nhận hoàn thành 100%.');
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

                  case 'report_task_result':
                    final reportStatus = parsedArgs['status']?.toString().trim().toLowerCase() ?? '';
                    final reportSummary = parsedArgs['summary']?.toString().trim() ?? '';
                    final reportEvidence = parsedArgs['evidence']?.toString().trim() ?? '';
                    final reportReason = parsedArgs['failure_reason']?.toString().trim() ?? '';
                    if (reportStatus == 'completed') {
                      if (reportEvidence.isEmpty) {
                        toolOutput = 'TỪ CHỐI XÁC NHẬN HOÀN THÀNH: status="completed" bắt buộc kèm evidence (bằng chứng kiểm chứng thực tế). Hãy kiểm tra lại trạng thái thật (browser_snapshot / browser_wait / browser_screenshot / uiautomator dump) rồi gọi lại.';
                      } else {
                        taskReport = {'status': 'completed', 'summary': reportSummary, 'evidence': reportEvidence};
                        toolOutput = 'ĐÃ GHI NHẬN HOÀN THÀNH 100%. Hãy trả lời người dùng ngắn gọn về kết quả.';
                      }
                    } else if (reportStatus == 'failed') {
                      if (reportReason.isEmpty) {
                        toolOutput = 'TỪ CHỐI: status="failed" bắt buộc kèm failure_reason cụ thể.';
                      } else if (failureChallenges < 1) {
                        failureChallenges++;
                        toolOutput = 'CHƯA CHẤP NHẬN KẾT LUẬN THẤT BẠI. Trước khi bỏ cuộc hãy thử ít nhất 1 phương án thay thế (browser_snapshot lại, tải lại trang bằng browser_navigate, chờ thêm bằng browser_wait, tìm nút có tên khác, cuộn trang, đóng hộp thoại che bằng phím Escape...). Nếu sau khi thử vẫn bất khả thi, gọi lại report_task_result(status="failed", failure_reason=...).';
                      } else {
                        taskReport = {'status': 'failed', 'summary': reportSummary, 'reason': reportReason};
                        toolOutput = 'ĐÃ GHI NHẬN KHÔNG THỂ HOÀN THÀNH. Hệ thống sẽ tự động gửi cảnh báo cho chủ máy. Hãy giải thích ngắn gọn cho người dùng.';
                      }
                    } else {
                      toolOutput = 'Lỗi: status chỉ nhận "completed" hoặc "failed".';
                    }
                    break;

                  case 'browser_navigate':
                  case 'browser_snapshot':
                  case 'browser_click':
                  case 'browser_type':
                  case 'browser_upload_file':
                  case 'browser_press_key':
                  case 'browser_scroll':
                  case 'browser_wait':
                  case 'browser_screenshot':
                    toolOutput = await _executeBrowserTool(funcName, parsedArgs, allowedScopeIps, cfg, onStatus);
                    break;

                  case 'device_push_media':
                    toolOutput = await _executeDevicePushMedia(parsedArgs, allowedScopeIps);
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
              if (!passiveTools.contains(funcName)) actionToolUsed = true;
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
              streamedBuffer.write('\n\n');
              onToken('\n\n');
            }

            // Agent đã báo cáo kết quả cuối cùng -> kết thúc vòng lặp, sang bước tổng hợp
            if (taskReport != null) break;
          } else {
            // Agent muốn dừng mà không gọi thêm công cụ.
            // GIÁM SÁT HOÀN THÀNH: nếu đây là tác vụ có thao tác mà chưa có report_task_result -> buộc làm tiếp.
            final requireReport = actionToolUsed || looksActionable;
            if (requireReport && taskReport == null && nudges < maxNudges && turnCount < maxTurns) {
              nudges++;
              messages.add({
                'role': 'assistant',
                'content': stepContent.isNotEmpty ? stepContent : '(Agent dừng lại nhưng chưa báo cáo kết quả)',
              });
              messages.add({
                'role': 'user',
                'content': _buildContinuationPrompt(nudges, maxNudges),
              });
              if (stepContent.isNotEmpty) {
                streamedBuffer.write('\n\n');
                onToken('\n\n');
              }
              onStatus('Giám sát hoàn thành: chưa xác nhận xong 100%, buộc Agent tiếp tục ($nudges/$maxNudges)...');
              continue;
            }

            // Finished generation without more tools
            finalReply = streamedBuffer.toString().trim();
            if (finalReply.isEmpty) {
              finalReply = stepContent.trim();
            }
            break;
          }
        }

        // Nếu vòng lặp dừng ngay sau khi chạy tool (ví dụ chạm maxTurns) hoặc chưa có lời kết tự nhiên,
        // gọi 1 lượt tổng hợp cuối cùng không đính kèm tools để Agent trả lời tự nhiên thay vì in log kỹ thuật.
        if (!isCancelled &&
            fatalError == null &&
            allExecutedTools.isNotEmpty &&
            (finalReply.isEmpty || (messages.isNotEmpty && messages.last['role'] == 'tool'))) {
          try {
            onStatus('Đang tổng hợp kết quả...');
            final summaryMessages = <Map<String, dynamic>>[
              ...messages,
              {
                'role': 'user',
                'content':
                    'Hãy báo cáo ngắn gọn kết quả thực hiện vừa rồi bằng ngôn ngữ tự nhiên cho người dùng. Tuyệt đối không liệt kê tên hàm công cụ kỹ thuật hay câu lệnh/JSON thô.',
              },
            ];
            final summaryClient = http.Client();
            final summaryReq = http.Request('POST', Uri.parse('$baseUrl/chat/completions'));
            summaryReq.headers.addAll({
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
            });
            summaryReq.body = jsonEncode({
              'model': targetModel,
              'messages': summaryMessages,
              'stream': true,
            });
            final summaryResp = await summaryClient.send(summaryReq);
            if (summaryResp.statusCode == 200) {
              final summaryCompleter = Completer<void>();
              summaryResp.stream
                  .transform(utf8.decoder)
                  .transform(const LineSplitter())
                  .listen(
                (line) {
                  final trimmed = line.trim();
                  if (!trimmed.startsWith('data:') || trimmed == 'data: [DONE]') return;
                  try {
                    final data = jsonDecode(trimmed.substring(5).trim());
                    final choices = data['choices'] as List<dynamic>?;
                    if (choices != null && choices.isNotEmpty) {
                      final delta = choices[0]['delta'] as Map<String, dynamic>?;
                      final token = delta?['content']?.toString();
                      if (token != null && token.isNotEmpty) {
                        streamedBuffer.write(token);
                        onToken(token);
                      }
                    }
                  } catch (_) {}
                },
                onError: (_) {
                  if (!summaryCompleter.isCompleted) summaryCompleter.complete();
                },
                onDone: () {
                  if (!summaryCompleter.isCompleted) summaryCompleter.complete();
                  summaryClient.close();
                },
                cancelOnError: true,
              );
              await summaryCompleter.future;
            } else {
              summaryClient.close();
            }
          } catch (_) {}
        }

        finalReply = ChatMessageModel.stripRawToolSummary(streamedBuffer.toString().trim());

        // Final reply fallback if not captured
        if (finalReply.isEmpty && messages.isNotEmpty && messages.last['role'] == 'assistant') {
          finalReply = ChatMessageModel.stripRawToolSummary(
            messages.last['content']?.toString().trim() ?? '',
          );
        }

        if (finalReply.isEmpty && fatalError != null) {
          finalReply = 'Lỗi: $fatalError';
          onToken(finalReply);
        } else if (finalReply.isEmpty && allExecutedTools.isNotEmpty) {
          finalReply = _buildCleanToolFallback(allExecutedTools);
          onToken(finalReply);
        } else if (finalReply.isEmpty) {
          finalReply = 'Đã hoàn tất thao tác.';
          onToken(finalReply);
        }

        // ===== GIÁM SÁT HOÀN THÀNH 100% & CẢNH BÁO KHI KHÔNG HOÀN THÀNH =====
        String finalOutcome = 'chat';
        String? finalFailureReason;
        if (!isCancelled) {
          if (fatalError != null) {
            finalOutcome = 'error';
            finalFailureReason = fatalError;
          } else if (taskReport?['status'] == 'completed') {
            finalOutcome = 'completed';
          } else if (taskReport?['status'] == 'failed') {
            finalOutcome = 'failed';
            finalFailureReason = taskReport!['reason'];
          } else if (actionToolUsed || looksActionable) {
            finalOutcome = 'incomplete';
            finalFailureReason = turnCount >= maxTurns
                ? 'Đã chạy hết giới hạn $maxTurns bước mà Agent vẫn chưa xác nhận hoàn thành.'
                : 'Agent dừng lại mà không xác nhận hoàn thành dù đã bị buộc tiếp tục $nudges lần.';
          }
          final monitorText = await _finalizeMonitoring(
            outcome: finalOutcome,
            failureReason: finalFailureReason,
            taskReport: taskReport,
            userRequest: message,
            sessionId: sessionId,
            engine: targetModel,
            scopeKeys: allowedScopeIps,
            executedTools: allExecutedTools,
            suppressFailureNotification: suppressFailureNotification,
            onStatus: onStatus,
          );
          if (monitorText.isNotEmpty) {
            finalReply = '$finalReply$monitorText';
            onToken(monitorText);
          }
        } else {
          finalOutcome = 'cancelled';
          finalFailureReason = 'Đã bị hủy giữa chừng';
        }

        // Save assistant message to Database
        if (persistToChatDb) {
          final assistantMsg = ChatMessageModel(
            sessionId: sessionId,
            role: 'assistant',
            content: finalReply,
            model: targetModel,
            toolExecutions: allExecutedTools,
            createdAt: DateTime.now(),
          );
          await _dbService.insertMessage(assistantMsg);
        }
        onResult?.call(AiTaskExecutionResult(
          outcome: finalOutcome,
          reply: finalReply,
          evidence: taskReport?['evidence'],
          failureReason: finalFailureReason,
          executedTools: List<ToolExecutionItem>.from(allExecutedTools),
        ));
        onDone(finalReply);
      } catch (e) {
        if (!isCancelled) {
          if (!suppressFailureNotification) {
            unawaited(TaskNotificationService()
                .notifyTaskFailure(
                  userRequest: message,
                  reason: 'Lỗi xử lý AI: $e',
                  outcome: 'error',
                  sessionId: sessionId,
                  engine: model,
                )
                .catchError((_) => const TaskNotificationResult(delivered: [], errors: {})));
          }
          final errMsg = 'Lỗi xử lý AI: $e';
          onResult?.call(AiTaskExecutionResult(
            outcome: 'error',
            reply: errMsg,
            failureReason: errMsg,
          ));
          onError(errMsg);
        }
      }
    }();

    controller.onCancel = () {
      isCancelled = true;
    };

    return controller.stream.listen((_) {});
  }

  /// Tạo phản hồi ngắn gọn, tự nhiên khi AI không sinh thêm văn bản mà không lộ tên hàm/log kỹ thuật
  String _buildCleanToolFallback(List<ToolExecutionItem> executedTools) {
    const friendlyTools = {
      'open_profile_browser',
      'close_profile_browser',
      'open_profile_device',
      'close_profile_device',
      'fast_social_action',
      'save_automation_macro',
    };
    final messages = <String>[];
    for (final item in executedTools) {
      if (friendlyTools.contains(item.tool)) {
        final out = item.output.trim();
        if (out.isNotEmpty && !out.startsWith('{') && !out.startsWith('[') && !messages.contains(out)) {
          messages.add(out);
        }
      }
    }
    if (messages.isNotEmpty) {
      return messages.join('\n');
    }
    return 'Đã hoàn tất thực hiện yêu cầu.';
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

  // ===================== GIÁM SÁT HOÀN THÀNH 100% =====================

  static const List<String> _actionKeywords = [
    'đăng', 'upload', 'tải lên', 'up video', 'like', 'thả tim', 'bình luận', 'comment', 'share', 'chia sẻ',
    'mở', 'xem', 'video', 'reel', 'livestream', 'follow', 'theo dõi', 'kết bạn', 'nhắn tin', 'gửi',
    'post', 'đọc', 'lướt', 'tương tác', 'đăng nhập', 'login', 'seeding', 'chạy', 'thực hiện', 'tự động',
  ];

  bool _looksLikeActionRequest(String message) => isActionRequest(message);

  String _buildContinuationPrompt(int nudge, int maxNudges) {
    return '[HỆ THỐNG GIÁM SÁT HOÀN THÀNH - lần nhắc $nudge/$maxNudges]\n'
        'Bạn vừa dừng lại nhưng CHƯA xác nhận yêu cầu của người dùng đã hoàn thành 100%.\n'
        '- Đối chiếu lại yêu cầu gốc, xác định các bước còn thiếu và TIẾP TỤC THỰC HIỆN NGAY bằng công cụ (không hỏi lại người dùng, không chỉ mô tả kế hoạch).\n'
        '- Kiểm tra trạng thái thực tế (browser_snapshot hoặc execute_adb_command "shell uiautomator dump") sau mỗi bước quan trọng.\n'
        '- Khi đã xong toàn bộ và kiểm chứng được kết quả: gọi report_task_result(status="completed", summary=..., evidence=<bằng chứng cụ thể>).\n'
        '- Nếu đã thử mọi phương án mà vẫn bất khả thi (chưa đăng nhập, tài khoản bị khóa/checkpoint, tệp không tồn tại...): gọi report_task_result(status="failed", failure_reason=...).\n'
        '- Nếu yêu cầu chỉ là hỏi đáp / lập kế hoạch không cần thao tác: gọi report_task_result(status="completed", summary=..., evidence="Đã trả lời đầy đủ nội dung được hỏi").';
  }

  /// Gọi 1 lượt chat completion dạng stream. Ném [_NonRetryableAiError] với lỗi không nên thử lại (400/401/403/404).
  Future<_AiTurnResult> _streamCompletionTurn({
    required String baseUrl,
    required String apiKey,
    required Map<String, dynamic> body,
    required void Function(String token) onToken,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse('$baseUrl/chat/completions'));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      });
      request.body = jsonEncode(body);
      final response = await client.send(request).timeout(const Duration(seconds: 90));
      if (response.statusCode != 200) {
        final errBody = await response.stream.bytesToString();
        final short = errBody.length > 500 ? '${errBody.substring(0, 500)}...' : errBody;
        final msg = 'AI API Error (${response.statusCode}): $short';
        if (response.statusCode == 408 || response.statusCode == 429 || response.statusCode >= 500) {
          throw Exception(msg);
        }
        throw _NonRetryableAiError(msg);
      }

      final content = StringBuffer();
      final toolCallsMap = <int, Map<String, dynamic>>{};
      await for (final line in response.stream
          .timeout(const Duration(seconds: 150))
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed == 'data: [DONE]' || !trimmed.startsWith('data:')) continue;
        try {
          final data = jsonDecode(trimmed.substring(5).trim());
          final choices = data['choices'] as List<dynamic>?;
          if (choices == null || choices.isEmpty) continue;
          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          if (delta == null) continue;
          if (delta['content'] != null) {
            final token = delta['content'].toString();
            content.write(token);
            onToken(token);
          }
          if (delta['tool_calls'] != null) {
            for (final tc in delta['tool_calls'] as List<dynamic>) {
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
        } catch (_) {}
      }
      return _AiTurnResult(content.toString(), toolCallsMap);
    } finally {
      client.close();
    }
  }

  /// Xác định ProfileKey mục tiêu cho công cụ, luôn tôn trọng phạm vi Scope
  String? _resolveTargetKey(Map<String, dynamic> args, List<String> scope) {
    final ip = args['ip']?.toString().trim() ?? '';
    if (scope.isNotEmpty) {
      if (ip.isNotEmpty && scope.contains(ip)) return ip;
      if (ip.isEmpty || scope.length == 1) return scope.first;
      return null;
    }
    return ip.isNotEmpty ? ip : null;
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  Future<String> _executeBrowserTool(
    String funcName,
    Map<String, dynamic> args,
    List<String> scope,
    Map<String, dynamic> cfg,
    void Function(String status) onStatus,
  ) async {
    final key = _resolveTargetKey(args, scope);
    if (key == null) {
      return 'LỖI: Thiếu hoặc sai tham số ip (ProfileKey) của nhân vật trong phạm vi Scope. Gọi list_profiles để lấy đúng ProfileKey.';
    }
    final cdp = BrowserCdpService();
    final cleanIp = Socks5ProxyService.extractCleanIp(key);

    // Bảo đảm trình duyệt đang mở VÀ điều khiển được (có cổng DevTools)
    var port = await cdp.getDebugPort(key);
    if (port == null) {
      if (_personaService.allPersonas.isEmpty) {
        try {
          await _personaService.loadSavedPersonas();
        } catch (_) {}
      }
      final persona = _personaService.getPersona(key);
      final sysProfile = persona?.browserProfileId?.trim() ?? '';
      if (sysProfile.isNotEmpty) {
        return 'LỖI: Nhân vật $key đang gắn profile trình duyệt hệ thống ($sysProfile) nên không thể điều khiển tự động. Cần bỏ gắn profile hệ thống trong hồ sơ nhân vật để dùng profile cô lập.';
      }
      onStatus('Đang chuẩn bị trình duyệt có thể điều khiển tự động cho $key...');
      if (_socks5Service.isBrowserRunningForIp(cleanIp, entryKey: key)) {
        await _socks5Service.closeBrowserForIp(cleanIp, entryKey: key);
        await Future.delayed(const Duration(seconds: 2));
      }
      final servers = await _configService.getServers();
      final server = servers.isEmpty
          ? ServerModel.fromJson(cfg)
          : servers.firstWhere((s) => s.isSelected, orElse: () => servers.first);
      final navUrl = args['url']?.toString().trim() ?? '';
      final startUrl = (funcName == 'browser_navigate' && navUrl.isNotEmpty) ? navUrl : 'https://www.facebook.com/';
      try {
        await _socks5Service.launchPersonaBrowser(ip: cleanIp, entryKey: key, server: server, startUrl: startUrl);
      } catch (e) {
        return 'LỖI: Không mở được trình duyệt cho $key: $e';
      }
      port = await cdp.waitForDebugPort(key);
      if (port == null) {
        return 'LỖI: Trình duyệt đã mở nhưng không bật được cổng điều khiển tự động (DevTools) cho $key.';
      }
      await Future.delayed(const Duration(seconds: 3));
    }

    try {
      switch (funcName) {
        case 'browser_navigate':
          final url = args['url']?.toString().trim() ?? '';
          if (url.isEmpty) return 'LỖI: Thiếu url.';
          return await cdp.navigate(key, url);
        case 'browser_snapshot':
          return await cdp.snapshot(key);
        case 'browser_click':
          return await cdp.click(key, elementId: _asInt(args['element_id']), text: args['text']?.toString());
        case 'browser_type':
          final text = args['text']?.toString() ?? '';
          if (text.isEmpty) return 'LỖI: Thiếu text cần gõ.';
          return await cdp.type(
            key,
            elementId: _asInt(args['element_id']),
            targetText: args['target_text']?.toString(),
            text: text,
            clear: args['clear'] == true,
          );
        case 'browser_upload_file':
          final path = args['file_path']?.toString().trim() ?? '';
          if (path.isEmpty) return 'LỖI: Thiếu file_path.';
          return await cdp.uploadFile(key, filePath: path, elementId: _asInt(args['element_id']));
        case 'browser_press_key':
          return await cdp.pressKey(key, args['key']?.toString() ?? 'Enter');
        case 'browser_scroll':
          return await cdp.scroll(key, _asInt(args['delta_y']) ?? 600);
        case 'browser_wait':
          return await cdp.waitFor(
            key,
            text: args['text']?.toString(),
            untilGone: args['until_gone'] == true,
            seconds: _asInt(args['seconds']) ?? 10,
          );
        case 'browser_screenshot':
          return await cdp.screenshot(key);
      }
    } on CdpUnavailableException catch (e) {
      return 'LỖI: $e';
    } catch (e) {
      await cdp.disconnect(key);
      return 'LỖI khi thao tác trình duyệt: $e. Hãy gọi browser_snapshot để kiểm tra lại trạng thái trang rồi thử lại.';
    }
    return 'LỖI: Công cụ $funcName không được hỗ trợ.';
  }

  Future<String> _executeDevicePushMedia(Map<String, dynamic> args, List<String> scope) async {
    final path = args['file_path']?.toString().trim() ?? '';
    if (path.isEmpty || !File(path).existsSync()) {
      return 'LỖI: Tệp không tồn tại trên máy local: $path';
    }
    var serial = args['serial']?.toString().trim() ?? '';
    if (serial.isEmpty) {
      final key = _resolveTargetKey(args, scope);
      if (key == null) return 'LỖI: Thiếu ip (ProfileKey) hoặc serial của thiết bị.';
      serial = await _socks5Service.getRunningDeviceSerialForIp(
            Socks5ProxyService.extractCleanIp(key),
            entryKey: key,
          ) ??
          '';
    }
    if (serial.isEmpty) {
      return 'LỖI: Thiết bị của nhân vật chưa chạy. Hãy gọi open_profile_device trước rồi thử lại.';
    }
    final adb = await _adbManagerService.resolveAdbPath();
    final baseName = path.split(Platform.pathSeparator).last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final remote = '/sdcard/DCIM/Camera/$baseName';
    await Process.run(adb, ['-s', serial, 'shell', 'mkdir', '-p', '/sdcard/DCIM/Camera']);
    final push = await Process.run(adb, ['-s', serial, 'push', path, remote]);
    if (push.exitCode != 0) {
      return 'LỖI: adb push thất bại: ${push.stderr.toString().trim()}';
    }
    await Process.run(adb, [
      '-s', serial, 'shell', 'am', 'broadcast', '-a', 'android.intent.action.MEDIA_SCANNER_SCAN_FILE', '-d', 'file://$remote',
    ]);
    return 'Đã chép tệp vào thư viện ảnh thiết bị $serial: $remote (đã quét media, tệp sẽ hiện trong Thư viện/Gallery của app).';
  }

  /// Tổng kết giám sát: trả về đoạn văn bản nối vào câu trả lời và gửi cảnh báo nếu không hoàn thành
  Future<String> _finalizeMonitoring({
    required String outcome,
    String? failureReason,
    Map<String, String>? taskReport,
    required String userRequest,
    String? sessionId,
    String? engine,
    List<String> scopeKeys = const [],
    List<ToolExecutionItem> executedTools = const [],
    List<String> extraSteps = const [],
    bool suppressFailureNotification = false,
    required void Function(String status) onStatus,
  }) async {
    if (outcome == 'chat') return '';
    if (outcome == 'completed') {
      final ev = taskReport?['evidence'] ?? '';
      return '\n\n---\n**Giám sát tác vụ: ĐÃ HOÀN THÀNH 100%**${ev.isNotEmpty ? '\n- Bằng chứng: $ev' : ''}';
    }

    final label = outcome == 'failed'
        ? 'KHÔNG THỂ HOÀN THÀNH'
        : (outcome == 'error' ? 'LỖI HỆ THỐNG - CHƯA HOÀN THÀNH' : 'CHƯA HOÀN THÀNH');
    if (suppressFailureNotification) {
      return '\n\n---\n**Giám sát tác vụ: $label**\n'
          '- Lý do: ${failureReason ?? 'Không rõ'}';
    }

    onStatus('Tác vụ chưa hoàn thành, đang gửi cảnh báo cho chủ máy...');
    final steps = <String>[
      ...executedTools.reversed.take(12).toList().reversed.map((t) {
        final out = t.output.replaceAll(RegExp(r'\s+'), ' ');
        return '${t.command} => ${out.length > 200 ? '${out.substring(0, 200)}...' : out}';
      }),
      ...extraSteps,
    ];
    TaskNotificationResult? res;
    try {
      res = await TaskNotificationService().notifyTaskFailure(
        userRequest: userRequest,
        reason: failureReason ?? 'Không rõ nguyên nhân',
        outcome: outcome,
        sessionId: sessionId,
        engine: engine,
        personas: scopeKeys,
        recentSteps: steps,
      );
    } catch (_) {}
    return '\n\n---\n**Giám sát tác vụ: $label**\n'
        '- Lý do: ${failureReason ?? 'Không rõ'}\n'
        '- Cảnh báo: ${res?.describe() ?? 'Gửi cảnh báo thất bại'}';
  }

  // ===================== LOCAL CLI AGENT =====================

  static final RegExp _cliStatusRegex =
      RegExp(r'MXH_TASK_STATUS\s*:\s*(COMPLETED|FAILED)\s*(?:[:|\-]\s*(.*))?', caseSensitive: false);

  static String _tail(String s, int max) => s.length <= max ? s : s.substring(s.length - max);

  /// Phân tích dòng trạng thái hoàn thành của Local CLI Agent.
  /// Trả về status = 'completed' | 'failed' | null, kèm reason (khi failed) hoặc evidence (khi completed có ghi chú).
  static ({String? status, String? reason, String? evidence}) parseCliTaskStatus(String output) {
    final matches = _cliStatusRegex.allMatches(output).toList();
    if (matches.isEmpty) return (status: null, reason: null, evidence: null);
    final m = matches.last;
    final detail = (m.group(2) ?? '').trim();
    if (m.group(1)!.toUpperCase() == 'COMPLETED') {
      return (status: 'completed', reason: null, evidence: detail.isNotEmpty ? detail : null);
    }
    return (
      status: 'failed',
      reason: detail.isNotEmpty ? detail : 'Agent báo thất bại nhưng không nêu lý do',
      evidence: null,
    );
  }

  /// Kiểm tra yêu cầu có chứa thao tác cần giám sát hoàn thành hay không
  static bool isActionRequest(String message) {
    final lower = message.toLowerCase();
    return _actionKeywords.any((k) => lower.contains(k));
  }

  Future<void> _runCliAgent({
    required String cliName,
    required String prompt,
    String? workingDir,
    String? sessionId,
    int maxAttempts = 3,
    bool suppressFailureNotification = false,
    void Function(AiTaskExecutionResult result)? onResult,
    required void Function(String token) onToken,
    required void Function(String status) onStatus,
    required void Function(ToolExecutionItem tool) onTool,
    required void Function(String fullReply) onDone,
    required void Function(dynamic error) onError,
    required bool Function() isCancelled,
  }) async {
    final exe = _findCliExecutable(cliName);
    onStatus('Đang khởi chạy $cliName agent...');

    final scopeKeys = workingDir == null
        ? <String>[]
        : RegExp(r'ProfileKey:\s*([0-9a-zA-Z\.\:\_\-#]+)')
            .allMatches(workingDir)
            .map((m) => m.group(1)!.trim())
            .toSet()
            .toList();

    try {
      final workDir = (workingDir != null && Directory(workingDir).existsSync())
          ? workingDir
          : (Platform.environment['HOME'] ?? Directory.current.path);

      // Cung cấp bộ vũ khí tự động hóa cho Local CLI Agent
      final bridgeService = CliAutomationBridgeService();
      final systemContext = await bridgeService.buildCliSystemContext(workingDir: workingDir);

      final basePrompt = '''$systemContext

=== YÊU CẦU TỪ NGƯỜI DÙNG ===
$prompt

=== HỢP ĐỒNG HOÀN THÀNH 100% (BẮT BUỘC) ===
- Phải thực hiện TRỌN VẸN mọi bước của yêu cầu trên bằng lệnh terminal thực tế, không dừng giữa chừng, không chỉ mô tả kế hoạch, không hỏi lại người dùng.
- TUYỆT ĐỐI KHÔNG báo COMPLETED chỉ vì đã mở được app/link hay gửi lệnh chạm mù. Sau khi thao tác PHẢI kiểm chứng lại trạng thái thật trên màn hình (`mxh-tool ui-dump`, `mxh-tool adb-screenshot`, hoặc đọc lại DOM qua DevTools).
- Dòng CUỐI CÙNG của câu trả lời BẮT BUỘC là đúng một trong hai dạng:
  MXH_TASK_STATUS: COMPLETED: <bằng chứng cụ thể đã đọc/thấy sau khi kiểm chứng>
  MXH_TASK_STATUS: FAILED: <lý do cụ thể không thể hoàn thành>
- Chỉ ghi COMPLETED khi đã kiểm chứng xong 100%. Nếu thiếu dòng này, hệ thống coi là CHƯA HOÀN THÀNH và sẽ buộc chạy tiếp; hết lượt sẽ gửi cảnh báo cho chủ máy.

(Yêu cầu thực thi: Nếu người dùng yêu cầu mở/đóng trình duyệt, xem link hay auto thiết bị, hãy sử dụng lệnh terminal được cấp ở trên để thực thi ngay lập tức. Tuyệt đối không dùng emoji hay icon trong câu trả lời, trình bày kết quả rõ ràng)''';

      // Augmented PATH environment so subprocesses (mxh-tool, adb, node, git, etc.) are always found
      final env = Map<String, String>.from(Platform.environment);
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      final pathSep = Platform.isWindows ? ';' : ':';
      final pathKey = Platform.isWindows && env.containsKey('Path') && !env.containsKey('PATH') ? 'Path' : 'PATH';
      final currentPath = env[pathKey] ?? '';
      final resolvedAdbPath = await _adbManagerService.resolveAdbPath();
      final adbDir = File(resolvedAdbPath).parent.path;
      final extraPaths = <String>[
        if (home.isNotEmpty) '$home${Platform.pathSeparator}.agent_mxh_auto${Platform.pathSeparator}bin',
        if (home.isNotEmpty) '$home${Platform.pathSeparator}.tadu_ai_agent${Platform.pathSeparator}bin',
        if (adbDir.isNotEmpty && adbDir != '.') adbDir,
        if (Platform.isWindows && localAppData.isNotEmpty) '$localAppData\\Android\\Sdk\\platform-tools',
        if (home.isNotEmpty) '$home${Platform.pathSeparator}Android${Platform.pathSeparator}Sdk${Platform.pathSeparator}platform-tools',
        if (!Platform.isWindows && home.isNotEmpty) '$home/.local/bin',
        if (!Platform.isWindows && home.isNotEmpty) '$home/bin',
        if (!Platform.isWindows) '/usr/local/bin',
        if (!Platform.isWindows) '/snap/bin',
      ];
      if (!Platform.isWindows && home.isNotEmpty) {
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
      }
      env[pathKey] = '${extraPaths.join(pathSep)}$pathSep$currentPath';

      final allOutputs = StringBuffer();
      String lastOutput = '';
      String? status;
      String? reason;
      String? evidence;
      String? lastProcessError;
      int failureChallenges = 0;

      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        if (isCancelled()) return;
        String attemptPrompt = basePrompt;
        if (attempt > 1) {
          final directive = reason != null
              ? 'Lần trước bạn kết luận thất bại với lý do: $reason. Trước khi kết luận lại, hãy thử ít nhất một phương án thay thế.'
              : 'Lần chạy trước CHƯA xác nhận hoàn thành 100% (không có dòng MXH_TASK_STATUS: COMPLETED).';
          attemptPrompt = '''$basePrompt

=== KẾT QUẢ LẦN CHẠY TRƯỚC (lần ${attempt - 1}) ===
${_tail(lastOutput, 4000)}

=== CHỈ THỊ GIÁM SÁT HOÀN THÀNH ===
$directive Kiểm tra trạng thái thực tế hiện tại, làm NỐT các bước còn thiếu (không lặp lại bước đã xong và đã kiểm chứng), rồi kết thúc bằng dòng MXH_TASK_STATUS.''';
          final note = '\n\n---\n*Giám sát hoàn thành: lần chạy ${attempt - 1} chưa xác nhận xong, tự động chạy tiếp (lần $attempt/$maxAttempts)...*\n\n';
          allOutputs.write(note);
          onToken(note);
          onStatus('Giám sát hoàn thành: buộc $cliName tiếp tục (lần $attempt/$maxAttempts)...');
        }

        final run = await _runCliProcessOnce(
          exe: exe,
          cliName: cliName,
          prompt: attemptPrompt,
          workDir: workDir,
          env: env,
          onToken: onToken,
          onStatus: onStatus,
          isCancelled: isCancelled,
        );
        if (isCancelled()) return;
        lastOutput = run.output;
        allOutputs.write(run.output);

        final parsed = parseCliTaskStatus(run.output);
        if (parsed.status != null) {
          if (parsed.status == 'completed') {
            status = 'completed';
            reason = null;
            evidence = parsed.evidence;
            break;
          }
          reason = parsed.reason;
          if (failureChallenges >= 1 || attempt >= maxAttempts) {
            status = 'failed';
            break;
          }
          failureChallenges++;
          continue;
        }
        if (run.exitCode != 0 && run.output.trim().isEmpty) {
          lastProcessError = 'mã thoát ${run.exitCode}: ${run.stderr.isNotEmpty ? run.stderr : "không có phản hồi"}';
        }
      }

      final cleaned = allOutputs
          .toString()
          .replaceAll(RegExp(r'^.*MXH_TASK_STATUS.*$', multiLine: true), '')
          .trim();

      String outcome;
      String? failureReason;
      if (status == 'completed') {
        outcome = 'completed';
      } else if (status == 'failed') {
        outcome = 'failed';
        failureReason = reason;
      } else if (cleaned.isEmpty && lastProcessError != null) {
        outcome = 'error';
        failureReason = 'Agent $cliName báo lỗi ($lastProcessError)';
      } else {
        outcome = 'incomplete';
        failureReason =
            'CLI Agent $cliName đã chạy $maxAttempts lần nhưng không xác nhận hoàn thành 100%${reason != null ? ' (lý do gần nhất: $reason)' : ''}.';
      }

      final monitor = await _finalizeMonitoring(
        outcome: outcome,
        failureReason: failureReason,
        taskReport: evidence != null ? {'status': 'completed', 'evidence': evidence} : null,
        userRequest: prompt,
        sessionId: sessionId,
        engine: cliName,
        scopeKeys: scopeKeys,
        extraSteps: lastOutput.trim().isEmpty ? const [] : ['Đầu ra cuối của CLI: ${_tail(lastOutput.trim(), 600)}'],
        suppressFailureNotification: suppressFailureNotification,
        onStatus: onStatus,
      );
      if (monitor.isNotEmpty) onToken(monitor);
      final base = cleaned.isNotEmpty ? cleaned : 'Đã chạy tác vụ với $cliName.';
      final fullText = '$base$monitor';
      onResult?.call(AiTaskExecutionResult(
        outcome: outcome,
        reply: fullText,
        evidence: outcome == 'completed' ? (evidence ?? _tail(base, 300)) : null,
        failureReason: failureReason,
      ));
      onDone(fullText);
    } catch (e) {
      if (isCancelled()) return;
      if (!suppressFailureNotification) {
        try {
          await TaskNotificationService().notifyTaskFailure(
            userRequest: prompt,
            reason: 'Không thể chạy CLI $cliName: $e',
            outcome: 'error',
            sessionId: sessionId,
            engine: cliName,
            personas: scopeKeys,
          );
        } catch (_) {}
      }
      final errMsg = 'Không thể chạy CLI $cliName: $e. Hãy kiểm tra đường dẫn hoặc quyền thực thi.';
      onResult?.call(AiTaskExecutionResult(
        outcome: 'error',
        reply: errMsg,
        failureReason: errMsg,
      ));
      onError(suppressFailureNotification ? errMsg : '$errMsg Đã gửi cảnh báo cho chủ máy.');
    }
  }

  /// Chạy CLI Agent 1 lần, stream token ra giao diện và trả về toàn bộ đầu ra
  Future<_CliRunResult> _runCliProcessOnce({
    required String exe,
    required String cliName,
    required String prompt,
    required String workDir,
    required Map<String, String> env,
    required void Function(String token) onToken,
    required void Function(String status) onStatus,
    required bool Function() isCancelled,
  }) async {
    List<String> args;
    final m = cliName.toLowerCase();
    if (m.contains('claude')) {
      args = ['-p', prompt, '--output-format', 'stream-json', '--verbose', '--dangerously-skip-permissions'];
    } else if (m.contains('antigravity') || m == 'agy') {
      args = ['--print', prompt, '--output-format', 'stream-json', '--dangerously-skip-permissions'];
    } else if (m.contains('gemini')) {
      args = ['-p', prompt];
    } else {
      args = ['-p', prompt, '--dangerously-skip-permissions'];
    }

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

    final cancelWatcher = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (isCancelled()) {
        t.cancel();
        try {
          process.kill();
        } catch (_) {}
      }
    });

    final fullOutput = StringBuffer();
    final errOutput = StringBuffer();
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();

    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
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

        fullOutput.writeln(line);
        onToken('$line\n');
      },
      onDone: () {
        if (!stdoutDone.isCompleted) stdoutDone.complete();
      },
      onError: (_) {
        if (!stdoutDone.isCompleted) stdoutDone.complete();
      },
    );

    process.stderr.transform(utf8.decoder).listen(
      (data) {
        if (!isCancelled()) errOutput.write(data);
      },
      onDone: () {
        if (!stderrDone.isCompleted) stderrDone.complete();
      },
      onError: (_) {
        if (!stderrDone.isCompleted) stderrDone.complete();
      },
    );

    final exitCode = await process.exitCode;
    cancelWatcher.cancel();
    try {
      await Future.wait([stdoutDone.future, stderrDone.future]).timeout(const Duration(seconds: 5));
    } catch (_) {}
    return _CliRunResult(exitCode, fullOutput.toString(), errOutput.toString().trim());
  }
}

class _AiTurnResult {
  final String content;
  final Map<int, Map<String, dynamic>> toolCalls;
  _AiTurnResult(this.content, this.toolCalls);
}

class _NonRetryableAiError implements Exception {
  final String message;
  _NonRetryableAiError(this.message);
  @override
  String toString() => message;
}

class _CliRunResult {
  final int exitCode;
  final String output;
  final String stderr;
  _CliRunResult(this.exitCode, this.output, this.stderr);
}
