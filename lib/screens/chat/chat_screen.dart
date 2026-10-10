import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/tadu_dialog.dart';
import '../../models/attachment_item.dart';
import '../../models/chat_message.dart';
import '../../models/persona_profile_model.dart';
import '../../core/services/persona_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/server_provider.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ApiService _apiService = ApiService();
  ApiService get _api => _apiService;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  bool _isRightSidebarOpen = true;
  List<PersonaProfile> _selectedPersonasScope = [];
  final List<AttachmentItem> _attachedFiles = [];
  bool _isDeviceExecutionMode = false; // false: Trình duyệt (Browser), true: Thiết bị (Device/AVD)
  final PersonaService _personaService = PersonaService();

  int _inputCharCount = 0;
  static const int _maxInputChars = 100000;

  String? _lastSessionId;
  String _lastTrackedContent = '';
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _textController.addListener(_onTextChanged);
    _inputFocusNode.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chat = context.read<ChatProvider>();
      final server = context.read<ServerProvider>();
      server.loadServers();
      _personaService.loadSavedPersonas().then((map) {
        if (mounted && _personaService.activeScopeIps.isNotEmpty && _selectedPersonasScope.isEmpty) {
          setState(() {
            _selectedPersonasScope = map.values
                .where((p) => _personaService.activeScopeIps.contains(p.ip))
                .toList();
          });
        }
      }).catchError((_) {});
      _api.getConfig().then((cfg) {
        if (cfg['default_execution_mode'] != null && mounted) {
          setState(() {
            _isDeviceExecutionMode = cfg['default_execution_mode'].toString() == 'device';
          });
        }
      }).catchError((_) {});
      chat.loadSessions().then((_) {
        if (chat.currentSession != null) {
          chat.selectSession(chat.currentSession!).then((_) {
            _safeScrollToBottom(instant: true);
          });
        } else if (chat.sessions.isNotEmpty) {
          chat.selectSession(chat.sessions.first).then((_) {
            _safeScrollToBottom(instant: true);
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _inputFocusNode.removeListener(_onFocusChanged);
    _textController.removeListener(_onTextChanged);
    _scrollController.removeListener(_onScroll);
    _inputFocusNode.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onTextChanged() {
    final text = _textController.text;
    if (_inputCharCount != text.length) {
      if ((text.length > 5000 && (_inputCharCount / 1000).floor() != (text.length / 1000).floor()) ||
          (text.length <= 5000 && (_inputCharCount == 0 || text.isEmpty || (_inputCharCount - text.length).abs() > 20))) {
        setState(() {
          _inputCharCount = text.length;
        });
      } else {
        _inputCharCount = text.length;
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels <= 60) {
      final chat = context.read<ChatProvider>();
      if (chat.hasMoreMessages && !chat.isLoadingMore && !chat.isLoading) {
        final oldMaxScroll = _scrollController.position.maxScrollExtent;
        final oldPixels = _scrollController.position.pixels;
        chat.loadMoreMessages().then((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              final newMaxScroll = _scrollController.position.maxScrollExtent;
              final diff = newMaxScroll - oldMaxScroll;
              if (diff > 0) {
                _scrollController.jumpTo(oldPixels + diff);
              }
            }
          });
        });
      }
    }
  }

  void _scrollToBottom({bool instant = false}) {
    if (!_scrollController.hasClients) return;
    try {
      final target = _scrollController.position.maxScrollExtent + 200;
      if (instant) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    } catch (_) {}
  }

  void _safeScrollToBottom({bool instant = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollToBottom(instant: instant);
        Future.delayed(const Duration(milliseconds: 60), () {
          if (_scrollController.hasClients) {
            _scrollToBottom(instant: instant);
          }
        });
      }
    });
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        for (final f in result.files) {
          AttachmentItem? item;
          if (f.path != null && File(f.path!).existsSync()) {
            item = await AttachmentItem.fromFile(File(f.path!), fileBytes: f.bytes, fileName: f.name);
          } else if (f.bytes != null) {
            item = AttachmentItem.fromBytes(
              name: f.name,
              bytes: f.bytes!,
              path: f.path,
            );
          }
          if (item != null) {
            _attachedFiles.add(item);
          }
        }
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Lỗi chọn tệp: $e');
      }
    }
  }

  Future<void> _downloadAttachment(AttachmentItem att) async {
    final remotePath = att.remotePath ?? '/opt/ai_agent/uploads/${att.name}';
    final homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final downloadsDir = Directory('$homeDir/Downloads');
    if (!downloadsDir.existsSync()) {
      downloadsDir.createSync(recursive: true);
    }
    final destFile = File('${downloadsDir.path}/${att.name}');

    double progress = 0.0;
    int received = 0;
    int total = att.size;
    bool isDone = false;
    String? errorMsg;
    StateSetter? dialogSetState;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) {
          dialogSetState = setDState;
          final pct = (progress * 100).toInt();
          final receivedFormatted = received < 1024 * 1024
              ? '${(received / 1024).toStringAsFixed(1)} KB'
              : '${(received / (1024 * 1024)).toStringAsFixed(1)} MB';
          final totalFormatted = total > 0
              ? (total < 1024 * 1024
                  ? '${(total / 1024).toStringAsFixed(1)} KB'
                  : '${(total / (1024 * 1024)).toStringAsFixed(1)} MB')
              : att.formattedSize;

          return TaduDialog(
            minWidth: 420,
            maxWidth: 500,
            onClose: () => Navigator.pop(ctx),
            title: Row(
              children: [
                Icon(
                  isDone
                      ? Icons.check_circle_rounded
                      : (errorMsg != null ? Icons.error_outline_rounded : Icons.download_rounded),
                  color: isDone ? AppColors.accent : (errorMsg != null ? AppColors.danger : AppColors.accentCyan),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isDone ? 'Tải xuống hoàn tất' : (errorMsg != null ? 'Lỗi tải xuống' : 'Đang tải xuống từ VPS'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(att.isImage ? Icons.image_rounded : Icons.insert_drive_file_rounded, size: 16, color: AppColors.warning),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          att.name,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: isDone ? 1.0 : (total > 0 ? progress : null),
                      minHeight: 8,
                      backgroundColor: AppColors.bgDark,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDone ? AppColors.accent : (errorMsg != null ? AppColors.danger : AppColors.accentCyan),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          isDone
                              ? 'Đã lưu: ${destFile.path}'
                              : (errorMsg ?? '$receivedFormatted / $totalFormatted'),
                          style: TextStyle(
                            fontSize: 11,
                            color: errorMsg != null ? AppColors.danger : AppColors.textMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!isDone && errorMsg == null)
                        Text(
                          '$pct%',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accentCyan),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              if (isDone)
                ElevatedButton.icon(
                  icon: const Icon(Icons.folder_open_rounded, size: 14),
                  label: const Text('Mở thư mục'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (Platform.isLinux) {
                      Process.run('xdg-open', [downloadsDir.path]);
                    } else if (Platform.isWindows) {
                      Process.run('explorer.exe', [downloadsDir.path]);
                    } else if (Platform.isMacOS) {
                      Process.run('open', [downloadsDir.path]);
                    }
                  },
                ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(isDone ? 'Đóng' : 'Huỷ'),
              ),
            ],
          );
        },
      ),
    );

    try {
      final bytes = await _api.downloadFile(
        remotePath: remotePath,
        onProgress: (rec, tot, prog) {
          received = rec;
          if (tot > 0) total = tot;
          progress = prog;
          dialogSetState?.call(() {});
        },
      );

      if (bytes != null && bytes.isNotEmpty) {
        await destFile.writeAsBytes(bytes);
        isDone = true;
        progress = 1.0;
        dialogSetState?.call(() {});
        if (mounted) {
          AppToast.success(context, 'Đã tải xuống: ${att.name}');
        }
      } else {
        errorMsg = 'Không tải được nội dung tệp từ server';
        dialogSetState?.call(() {});
      }
    } catch (e) {
      errorMsg = 'Lỗi: $e';
      dialogSetState?.call(() {});
    }
  }

  Future<void> _handleSend(ChatProvider chat, ServerProvider serverProvider) async {
    final text = _textController.text.trim();
    if ((text.isEmpty && _attachedFiles.isEmpty) || chat.isGenerating) return;

    if (text.length > _maxInputChars) {
      AppToast.error(context, 'Prompt quá dài (${text.length}/$_maxInputChars ký tự). Vui lòng rút gọn để tránh treo app!');
      return;
    }

    // Await any in-flight uploads if necessary (cho phép tối đa 600s = 10 phút cho tệp 5-10GB)
    if (_attachedFiles.any((a) => a.isUploading)) {
      int waitMs = 0;
      while (_attachedFiles.any((a) => a.isUploading) && waitMs < 600000 && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        waitMs += 500;
      }
    }

    final attachmentsToSend = _attachedFiles.isNotEmpty ? List<AttachmentItem>.from(_attachedFiles) : null;
    _textController.clear();
    setState(() {
      _attachedFiles.clear();
    });

    String? scopePayload;
    final buffer = StringBuffer();
    if (_selectedPersonasScope.isNotEmpty) {
      buffer.writeln('=== DANH SÁCH NHÂN VẬT ĐƯỢC CHỈ ĐỊNH (SCOPE PERSONAS) ===');
      for (final p in _selectedPersonasScope) {
        buffer.writeln('- IP: ${p.ip} | Họ tên: ${p.name} | Tuổi: ${p.age} | Giới tính: ${p.gender} | Bio: ${p.bio}');
      }
      buffer.writeln();
    }

    // Luôn đồng bộ cấu hình môi trường thực thi mới nhất từ LocalConfigService nếu chưa chọn thủ công
    bool effectiveDeviceMode = _isDeviceExecutionMode;
    try {
      final latestCfg = await _api.getConfig();
      if (latestCfg['default_execution_mode'] != null) {
        final cfgMode = latestCfg['default_execution_mode'].toString().trim().toLowerCase();
        if (cfgMode == 'device') {
          effectiveDeviceMode = true;
          if (!_isDeviceExecutionMode && mounted) {
            setState(() => _isDeviceExecutionMode = true);
          }
        } else if (cfgMode == 'browser') {
          // Chỉ fallback nếu người dùng chưa bật nút thiết bị
          if (!_isDeviceExecutionMode) {
            effectiveDeviceMode = false;
          }
        }
      }
    } catch (_) {}

    // Đính kèm chỉ thị môi trường thực thi được lựa chọn
    if (effectiveDeviceMode) {
      buffer.writeln('[YÊU CẦU MÔI TRƯỜNG THỰC THI: THIẾT BỊ / DEVICE / AVD / ANDROID]');
      buffer.writeln('- BẮT BUỘC thực hiện tác vụ trên thiết bị di động / máy ảo Android (sử dụng open_profile_device hoặc lệnh terminal mxh-tool open-device).');
      buffer.writeln('- TUYỆT ĐỐI KHÔNG mở trình duyệt Chrome/Chromium (open_profile_browser). Mọi thao tác phải chạy trên Thiết bị / Android Emulator.');
    } else {
      buffer.writeln('[YÊU CẦU MÔI TRƯỜNG THỰC THI: TRÌNH DUYỆT / BROWSER]');
      buffer.writeln('- BẮT BUỘC thực hiện tác vụ trên trình duyệt độc lập (sử dụng open_profile_browser hoặc lệnh terminal mxh-tool open-browser).');
      buffer.writeln('- TUYỆT ĐỐI KHÔNG mở máy ảo AVD / thiết bị Android (open_profile_device).');
    }

    scopePayload = buffer.toString().trim();

    chat.sendMessage(
      text,
      model: serverProvider.currentAiModel,
      attachments: attachmentsToSend,
      workingDir: scopePayload,
    );
    _safeScrollToBottom();
  }

  void _triggerScopePicker() async {
    showDialog(
      context: context,
      builder: (ctx) => _ScopePickerDialog(
        selectedPersonas: _selectedPersonasScope,
        onSelect: (selectedList) {
          setState(() {
            _selectedPersonasScope = selectedList;
          });
          _personaService.setActiveScopeIps(selectedList.map((p) => p.ip));
          if (selectedList.isNotEmpty) {
            AppToast.success(context, 'Đã chọn ${selectedList.length} nhân vật cho hội thoại');
          } else {
            AppToast.info(context, 'Đã xóa chọn nhân vật');
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final serverProvider = context.watch<ServerProvider>();

    if (_lastSessionId != chat.currentSession?.id) {
      _lastSessionId = chat.currentSession?.id;
      _lastTrackedContent = '';
      _lastMessageCount = chat.messages.length;
      _safeScrollToBottom(instant: true);
    } else if (chat.isGenerating) {
      _safeScrollToBottom();
    } else if (chat.messages.length != _lastMessageCount ||
        (chat.messages.isNotEmpty && _lastTrackedContent != chat.messages.last.content)) {
      final isNearBottom = !_scrollController.hasClients ||
          (_scrollController.position.maxScrollExtent - _scrollController.position.pixels < 300);
      final isNewUserMessage = chat.messages.isNotEmpty && chat.messages.last.role == 'user';
      _lastMessageCount = chat.messages.length;
      _lastTrackedContent = chat.messages.isNotEmpty ? chat.messages.last.content : '';
      if (isNearBottom || isNewUserMessage) {
        _safeScrollToBottom();
      }
    }

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          // 1. Topbar Header (Height 66px)
          Container(
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              color: AppColors.bgDark,
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.asset(
                            'assets/logo.jpg',
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.smart_toy_rounded, color: AppColors.primaryLight, size: 24),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.bgDark, width: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              chat.currentSession?.title ?? 'Trợ lý MXH tự động',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.view_sidebar_rounded,
                        color: _isRightSidebarOpen ? AppColors.primaryLight : AppColors.textDim,
                        size: 20,
                      ),
                      tooltip: 'Đóng/Mở danh sách hộp hội thoại',
                      onPressed: () {
                        setState(() {
                          _isRightSidebarOpen = !_isRightSidebarOpen;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Hội thoại mới', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => chat.createNewSession(),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Chat Center & Right Sidebar Split View
          Expanded(
            child: Row(
              children: [
                // 2.1 Chat Center Feed
                Expanded(
                  child: Column(
                    children: [
                      // Message Stream
                      Expanded(
                        child: chat.isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                addAutomaticKeepAlives: false,
                                addRepaintBoundaries: true,
                                // ignore: deprecated_member_use
                                cacheExtent: 400.0,
                                itemCount: chat.hasMoreMessages
                                    ? chat.messages.length + 1
                                    : (chat.messages.isEmpty ? 1 : chat.messages.length + 1),
                                findChildIndexCallback: (Key key) {
                                  if (key is ValueKey<String>) {
                                    final val = key.value;
                                    if (val.startsWith('msg_')) {
                                      final idStr = val.split('_')[1];
                                      final id = int.tryParse(idStr);
                                      if (id != null) {
                                        final idx = chat.messages.indexWhere((m) => m.id == id);
                                        if (idx != -1) return idx + 1;
                                      }
                                    }
                                  }
                                  return null;
                                },
                                itemBuilder: (context, idx) {
                                  if (idx == 0) {
                                    if (chat.hasMoreMessages) {
                                      return _buildLoadMoreBanner(chat);
                                    }
                                    return _buildGreetingBubble(chat, serverProvider);
                                  }
                                  final msg = chat.messages[idx - 1];
                                  return _buildMessageItem(msg, chat);
                                },
                              ),
                      ),

                      // Input Bar
                      _buildInputBar(chat, serverProvider),
                    ],
                  ),
                ),

                // 2.2 Right Sidebar: Sessions List
                if (_isRightSidebarOpen) _buildRightSessionsSidebar(chat),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadMoreBanner(ChatProvider chat) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      alignment: Alignment.center,
      child: chat.isLoadingMore
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.sidebarBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.borderDark),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Đang tải thêm 3 tin nhắn trước đó...',
                    style: TextStyle(fontSize: 11.5, color: AppColors.primaryLight),
                  ),
                ],
              ),
            )
          : InkWell(
              onTap: () => chat.loadMoreMessages(),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.borderDark),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_upward_rounded, size: 13, color: AppColors.textMuted),
                    SizedBox(width: 6),
                    Text(
                      'Cuộn lên hoặc bấm để tải thêm 3 tin nhắn cũ',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildGreetingBubble(ChatProvider chat, ServerProvider serverProvider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/logo.jpg',
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.cloud_sync_rounded, color: AppColors.primaryLight, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '👋 Xin chào! Tôi là MXH tự động (${serverProvider.currentAiModel})',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Tôi có thể hỗ trợ lên kế hoạch nội dung, điều khiển các nhân vật profile mở trình duyệt hoặc thiết bị để tự động hóa tác vụ theo yêu cầu!',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
          const Divider(height: 20),
          const Text(
            'GỢI Ý CÂU LỆNH MẪU:',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.textDim, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildActionPromptChip(
                icon: Icons.thumb_up_alt_rounded,
                iconColor: AppColors.accentCyan,
                label: 'Like video',
                taskTitle: 'Like video',
                defaultPrompt: 'Hãy điều khiển các nhân vật trong scope thực hiện tương tác like video này',
                chat: chat,
                serverProvider: serverProvider,
              ),
              _buildActionPromptChip(
                icon: Icons.comment_rounded,
                iconColor: AppColors.primaryLight,
                label: 'Viết comment',
                taskTitle: 'Viết comment',
                defaultPrompt: 'Hãy điều khiển các nhân vật trong scope viết bình luận phù hợp với tính cách và ngữ cảnh của video này',
                chat: chat,
                serverProvider: serverProvider,
              ),
              _buildActionPromptChip(
                icon: Icons.live_tv_rounded,
                iconColor: AppColors.danger,
                label: 'Xem livestream',
                taskTitle: 'Xem livestream',
                defaultPrompt: 'Hãy điều khiển các nhân vật trong scope vào xem livestream này và tương tác tự nhiên',
                chat: chat,
                serverProvider: serverProvider,
              ),
              _buildPromptChip(
                icon: Icons.post_add_rounded,
                iconColor: AppColors.accent,
                label: 'Đăng bài',
                prompt: 'Hãy soạn và đăng bài viết mới dựa trên phong cách của các nhân vật trong scope',
                chat: chat,
                serverProvider: serverProvider,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionPromptChip({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String taskTitle,
    required String defaultPrompt,
    required ChatProvider chat,
    required ServerProvider serverProvider,
  }) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.borderDark),
        backgroundColor: AppColors.inputBg,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      icon: Icon(icon, size: 14, color: iconColor),
      label: Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textBody)),
      onPressed: () {
        _openVideoTaskDialog(
          title: taskTitle,
          actionIcon: icon,
          actionColor: iconColor,
          baseInstruction: defaultPrompt,
          chat: chat,
          serverProvider: serverProvider,
        );
      },
    );
  }

  void _openVideoTaskDialog({
    required String title,
    required IconData actionIcon,
    required Color actionColor,
    required String baseInstruction,
    required ChatProvider chat,
    required ServerProvider serverProvider,
  }) {
    final linkController = TextEditingController();
    bool isDeviceMode = _isDeviceExecutionMode; // Kế thừa chế độ đang chọn từ thanh công cụ/cấu hình

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) => TaduDialog(
          minWidth: 460,
          maxWidth: 540,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(actionIcon, color: actionColor, size: 20),
              const SizedBox(width: 8),
              Text('Nhập link video ($title)'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nhập đường link video/livestream để các nhân vật trong scope thực hiện nhiệm vụ $title:',
                style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              Container(
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.borderDark, width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 10, right: 6),
                      child: Icon(Icons.link_rounded, size: 16, color: AppColors.textDim),
                    ),
                    Expanded(
                      child: Center(
                        child: TextField(
                          controller: linkController,
                          autofocus: true,
                          style: const TextStyle(fontSize: 12.5, color: AppColors.textWhite),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                            hintText: 'https://...',
                            hintStyle: TextStyle(fontSize: 12, color: AppColors.textDim),
                            fillColor: Colors.transparent,
                            filled: false,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Switch lựa chọn Trình duyệt hoặc Thiết bị (Device)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isDeviceMode
                      ? Colors.purpleAccent.withValues(alpha: 0.1)
                      : AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDeviceMode
                        ? Colors.purpleAccent.withValues(alpha: 0.3)
                        : AppColors.primaryLight.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isDeviceMode ? Icons.phone_android_rounded : Icons.open_in_browser_rounded,
                          size: 18,
                          color: isDeviceMode ? Colors.purpleAccent : AppColors.primaryLight,
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isDeviceMode ? 'Chạy trên Thiết bị (Device / AVD)' : 'Chạy trên Trình duyệt (Browser)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDeviceMode ? Colors.purpleAccent : AppColors.primaryLight,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isDeviceMode
                                  ? 'Kích hoạt máy ảo Android AVD hoặc thiết bị ngoại vi qua ADB'
                                  : 'Khởi chạy Chrome profile riêng biệt theo IP của từng nhân vật',
                              style: const TextStyle(fontSize: 10, color: AppColors.textDim),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 24,
                      child: Switch(
                        value: isDeviceMode,
                        activeThumbColor: Colors.purpleAccent,
                        activeTrackColor: Colors.purpleAccent.withValues(alpha: 0.3),
                        inactiveThumbColor: AppColors.primaryLight,
                        inactiveTrackColor: AppColors.primary.withValues(alpha: 0.3),
                        onChanged: (val) {
                          setModalState(() {
                            isDeviceMode = val;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),

              if (_selectedPersonasScope.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.people_alt_rounded, size: 13, color: AppColors.primaryLight),
                      const SizedBox(width: 6),
                      Text(
                        'Áp dụng cho ${_selectedPersonasScope.length} nhân vật đã chọn trong scope',
                        style: const TextStyle(fontSize: 11, color: AppColors.primaryLight, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: () {
                final rawLink = linkController.text.trim();
                if (rawLink.isEmpty) {
                  AppToast.warning(context, 'Vui lòng nhập đường link video!');
                  return;
                }
                Navigator.pop(ctx);

                String? scopePayload;
                if (_selectedPersonasScope.isNotEmpty) {
                  final buffer = StringBuffer();
                  buffer.writeln('=== DANH SÁCH NHÂN VẬT ĐƯỢC CHỈ ĐỊNH (SCOPE PERSONAS) ===');
                  for (final p in _selectedPersonasScope) {
                    buffer.writeln('- IP: ${p.ip} | Họ tên: ${p.name} | Tuổi: ${p.age} | Giới tính: ${p.gender} | Bio: ${p.bio}');
                  }
                  scopePayload = buffer.toString().trim();
                }

                final targetPlatformPrompt = isDeviceMode
                    ? '[MÔI TRƯỜNG: THIẾT BỊ/DEVICE/AVD] Hãy thực hiện trên thiết bị điện thoại/máy ảo Android của các nhân vật.'
                    : '[MÔI TRƯỜNG: TRÌNH DUYỆT/BROWSER] Hãy thực hiện trên trình duyệt của các nhân vật.';

                final fullMessage = '$baseInstruction\n$targetPlatformPrompt\nLink: $rawLink';
                chat.sendMessage(
                  fullMessage,
                  model: serverProvider.currentAiModel,
                  workingDir: scopePayload,
                );
                _safeScrollToBottom();
              },
              child: const Text('Xác nhận & Chạy'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptChip({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String prompt,
    required ChatProvider chat,
    required ServerProvider serverProvider,
  }) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.borderDark),
        backgroundColor: AppColors.inputBg,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      icon: Icon(icon, size: 14, color: iconColor),
      label: Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textBody)),
      onPressed: () {
        final buffer = StringBuffer();
        if (_selectedPersonasScope.isNotEmpty) {
          buffer.writeln('=== DANH SÁCH NHÂN VẬT ĐƯỢC CHỈ ĐỊNH (SCOPE PERSONAS) ===');
          for (final p in _selectedPersonasScope) {
            buffer.writeln('- IP: ${p.ip} | Họ tên: ${p.name} | Tuổi: ${p.age} | Giới tính: ${p.gender} | Bio: ${p.bio}');
          }
          buffer.writeln();
        }
        if (_isDeviceExecutionMode) {
          buffer.writeln('[YÊU CẦU MÔI TRƯỜNG THỰC THI: THIẾT BỊ / DEVICE / AVD / ANDROID]');
          buffer.writeln('- BẮT BUỘC thực hiện tác vụ trên thiết bị di động / máy ảo Android (sử dụng open_profile_device).');
          buffer.writeln('- TUYỆT ĐỐI KHÔNG mở trình duyệt Chrome/Chromium (open_profile_browser).');
        } else {
          buffer.writeln('[YÊU CẦU MÔI TRƯỜNG THỰC THI: TRÌNH DUYỆT / BROWSER]');
          buffer.writeln('- BẮT BUỘC thực hiện tác vụ trên trình duyệt độc lập (sử dụng open_profile_browser).');
          buffer.writeln('- TUYỆT ĐỐI KHÔNG mở máy ảo AVD / thiết bị Android (open_profile_device).');
        }
        final scopePayload = buffer.toString().trim();

        chat.sendMessage(
          prompt,
          model: serverProvider.currentAiModel,
          workingDir: scopePayload,
        );
        _safeScrollToBottom();
      },
    );
  }

  Widget _buildMessageItem(ChatMessageModel msg, ChatProvider chat) {
    return _MessageItemWidget(
      key: ValueKey('msg_${msg.id}_${msg.role}_${msg.isStreaming}'),
      msg: msg,
      onDownloadAttachment: _downloadAttachment,
      onRetry: (content) {
        chat.sendMessage(content);
        _safeScrollToBottom();
      },
    );
  }

  Widget _buildInputBar(ChatProvider chat, ServerProvider serverProvider) {
    final bool isFocused = _inputFocusNode.hasFocus;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.bgDark,
        border: Border(top: BorderSide(color: AppColors.borderDark, width: 1)),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.inputBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isFocused ? AppColors.primary : AppColors.borderDark,
            width: isFocused ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_selectedPersonasScope.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.people_alt_rounded, size: 14, color: AppColors.primaryLight),
                        const SizedBox(width: 6),
                        Text(
                          'Phạm vi Personas (${_selectedPersonasScope.length}):',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: _triggerScopePicker,
                          child: const Text(
                            'Thay đổi',
                            style: TextStyle(fontSize: 10.5, color: AppColors.accentCyan, decoration: TextDecoration.underline),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedPersonasScope.clear();
                            });
                            _personaService.clearActiveScope();
                          },
                          child: const Icon(Icons.close_rounded, size: 14, color: AppColors.danger),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: SingleChildScrollView(
                        child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _selectedPersonasScope.map((p) {
                        return Container(
                          padding: const EdgeInsets.only(left: 4, right: 10, top: 4, bottom: 4),
                          decoration: BoxDecoration(
                            color: AppColors.bgDark,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildPersonaAvatar(p, radius: 11, fontSize: 10),
                              const SizedBox(width: 7),
                              Text(
                                p.name,
                                style: const TextStyle(fontSize: 12.5, color: AppColors.textWhite, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedPersonasScope.removeWhere((item) => item.ip == p.ip);
                                  });
                                  _personaService.setActiveScopeIps(_selectedPersonasScope.map((e) => e.ip));
                                },
                                child: const Icon(Icons.close_rounded, size: 14, color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
            ],
            if (_attachedFiles.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _attachedFiles.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final att = entry.value;
                      final Color chipBorderColor = att.error != null
                          ? AppColors.danger.withValues(alpha: 0.5)
                          : (att.isUploaded
                              ? AppColors.accent.withValues(alpha: 0.5)
                              : AppColors.accentCyan.withValues(alpha: 0.5));
                      final Color chipBgColor = att.error != null
                          ? AppColors.danger.withValues(alpha: 0.12)
                          : (att.isUploaded
                              ? AppColors.accent.withValues(alpha: 0.12)
                              : AppColors.accentCyan.withValues(alpha: 0.12));

                      return Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: chipBgColor,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: chipBorderColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              att.isImage ? Icons.image_rounded : Icons.insert_drive_file_rounded,
                              size: 14,
                              color: att.isImage ? AppColors.accentCyan : AppColors.warning,
                            ),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                att.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textWhite),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '(${att.formattedSize})',
                              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                            ),
                            const SizedBox(width: 6),
                            const Tooltip(
                              message: 'Tệp lưu tại local',
                              child: Icon(Icons.folder_rounded, size: 14, color: AppColors.accentCyan),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _attachedFiles.removeAt(idx);
                                });
                              },
                              child: const Icon(Icons.close_rounded, size: 14, color: AppColors.danger),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
            TextField(
              controller: _textController,
              focusNode: _inputFocusNode,
              minLines: 2,
              maxLines: 8,
              maxLength: _maxInputChars,
              buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
                if (currentLength > 1000) {
                  final isNearLimit = currentLength > (_maxInputChars * 0.8);
                  return Container(
                    padding: const EdgeInsets.only(top: 2),
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$currentLength / $maxLength ký tự',
                      style: TextStyle(
                        fontSize: 10,
                        color: isNearLimit ? AppColors.danger : AppColors.textMuted,
                        fontWeight: isNearLimit ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                }
                return null;
              },
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSend(chat, serverProvider),
              decoration: const InputDecoration(
                hintText: 'Nhập tin nhắn hoặc yêu cầu cho AI Agent...',
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: _selectedPersonasScope.isNotEmpty ? AppColors.primaryLight : AppColors.borderDark,
                        ),
                        backgroundColor: _selectedPersonasScope.isNotEmpty ? AppColors.primary.withValues(alpha: 0.15) : null,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      icon: Icon(
                        Icons.people_alt_rounded,
                        size: 14,
                        color: _selectedPersonasScope.isNotEmpty ? AppColors.primaryLight : AppColors.warning,
                      ),
                      label: Text(
                        _selectedPersonasScope.isNotEmpty
                            ? 'Personas (${_selectedPersonasScope.length})'
                            : 'Personas',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: _selectedPersonasScope.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                          color: _selectedPersonasScope.isNotEmpty ? AppColors.primaryLight : AppColors.textBody,
                        ),
                      ),
                      onPressed: _triggerScopePicker,
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: _attachedFiles.isNotEmpty ? AppColors.accentCyan : AppColors.borderDark,
                        ),
                        backgroundColor: _attachedFiles.isNotEmpty ? AppColors.accentCyan.withValues(alpha: 0.1) : null,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      icon: Icon(
                        Icons.attach_file_rounded,
                        size: 14,
                        color: _attachedFiles.isNotEmpty ? AppColors.accentCyan : AppColors.accentCyan,
                      ),
                      label: Text(
                        _attachedFiles.isNotEmpty ? 'Attach (${_attachedFiles.length})' : 'Attach',
                        style: TextStyle(
                          fontSize: 11,
                          color: _attachedFiles.isNotEmpty ? AppColors.accentCyan : AppColors.textBody,
                          fontWeight: _attachedFiles.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      onPressed: _pickFiles,
                    ),
                    const SizedBox(width: 8),
                    // Quick Toggle Chế độ Thực thi: Thiết bị (Device / AVD) vs Trình duyệt (Browser)
                    Tooltip(
                      message: _isDeviceExecutionMode
                          ? 'Đang chọn: Thiết bị (Device / AVD). Bấm để chuyển sang Trình duyệt (Browser)'
                          : 'Đang chọn: Trình duyệt (Browser). Bấm để chuyển sang Thiết bị (Device / AVD)',
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: _isDeviceExecutionMode ? Colors.purpleAccent : AppColors.primaryLight.withValues(alpha: 0.5),
                          ),
                          backgroundColor: _isDeviceExecutionMode
                              ? Colors.purpleAccent.withValues(alpha: 0.18)
                              : AppColors.primary.withValues(alpha: 0.08),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        icon: Icon(
                          _isDeviceExecutionMode ? Icons.phone_android_rounded : Icons.open_in_browser_rounded,
                          size: 14,
                          color: _isDeviceExecutionMode ? Colors.purpleAccent : AppColors.primaryLight,
                        ),
                        label: Text(
                          _isDeviceExecutionMode ? 'Thiết bị (Device)' : 'Trình duyệt',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _isDeviceExecutionMode ? Colors.purpleAccent : AppColors.primaryLight,
                          ),
                        ),
                        onPressed: () async {
                          final nextVal = !_isDeviceExecutionMode;
                          setState(() {
                            _isDeviceExecutionMode = nextVal;
                          });
                          try {
                            final cfg = await _api.getConfig();
                            cfg['default_execution_mode'] = nextVal ? 'device' : 'browser';
                            await _api.saveConfig(cfg);
                            if (mounted) {
                              AppToast.info(context, nextVal ? 'Đã kích hoạt chế độ: Chạy trên Thiết bị (Device / AVD)' : 'Đã kích hoạt chế độ: Chạy trên Trình duyệt (Browser)');
                            }
                          } catch (_) {}
                        },
                      ),
                    ),
                  ],
                ),
                if (chat.isGenerating)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger.withValues(alpha: 0.18),
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger, width: 1),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    icon: const Icon(Icons.stop_rounded, size: 16, color: AppColors.danger),
                    label: const Text('Dừng', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () => chat.stopGenerating(),
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: const Color(0xFF070B14),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 14),
                    label: const Text('Gửi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () => _handleSend(chat, serverProvider),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatSessionTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }

  Widget _buildRightSessionsSidebar(ChatProvider chat) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: AppColors.sidebarBg,
        border: Border(left: BorderSide(color: AppColors.borderDark, width: 1)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.layers_rounded, size: 16, color: AppColors.primaryLight),
                    SizedBox(width: 8),
                    Text('Hộp Hội Thoại', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.add_rounded, size: 18, color: AppColors.primaryLight),
                  tooltip: 'Tạo hội thoại mới',
                  onPressed: () => chat.createNewSession(),
                ),
              ],
            ),
          ),
          Expanded(
            child: chat.sessions.isEmpty
                ? const Center(
                    child: Text('Chưa có hội thoại nào', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(6),
                    itemCount: chat.sessions.length,
                    itemBuilder: (context, idx) {
                      final sess = chat.sessions[idx];
                      final isSelected = sess.id == chat.currentSession?.id;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.15)
                              : (sess.isPinned ? AppColors.warning.withValues(alpha: 0.04) : Colors.transparent),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.5)
                                : (sess.isPinned ? AppColors.warning.withValues(alpha: 0.25) : Colors.transparent),
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () => chat.selectSession(sess).then((_) {
                              _scrollToBottom(instant: true);
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              child: Row(
                                children: [
                                  // Left Pin Button
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                                    icon: Transform.rotate(
                                      angle: sess.isPinned ? -0.5 : 0,
                                      child: Icon(
                                        sess.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                                        size: 13,
                                        color: sess.isPinned ? AppColors.warning : AppColors.textDim,
                                      ),
                                    ),
                                    tooltip: sess.isPinned ? 'Bỏ ghim hội thoại' : 'Ghim hội thoại lên đầu',
                                    onPressed: () => chat.pinSession(sess),
                                  ),
                                  const SizedBox(width: 4),
                                  // Session Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          sess.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            color: isSelected ? AppColors.primaryLight : AppColors.textBody,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            if (sess.isPinned)
                                              Container(
                                                margin: const EdgeInsets.only(right: 6),
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                                                decoration: BoxDecoration(
                                                  color: AppColors.warning.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(2),
                                                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                                                ),
                                                child: const Text(
                                                  'Ghim',
                                                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: AppColors.warning),
                                                ),
                                              ),
                                            Text(
                                              _formatSessionTime(sess.updatedAt),
                                              style: const TextStyle(fontSize: 10, color: AppColors.textDim),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Rename Button
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                    icon: const Icon(Icons.edit_outlined, size: 13, color: AppColors.textDim),
                                    tooltip: 'Đổi tên hội thoại',
                                    onPressed: () => _showRenameDialog(chat, sess),
                                  ),
                                  // Delete Button
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                    icon: const Icon(Icons.delete_outline_rounded, size: 13, color: AppColors.textDim),
                                    tooltip: 'Xóa hộp hội thoại này',
                                    onPressed: () => _showDeleteDialog(chat, sess),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${chat.sessions.length} hội thoại', style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
                TextButton(
                  onPressed: () => chat.clearHistory(),
                  child: const Text('Xoá chat', style: TextStyle(fontSize: 11, color: AppColors.danger)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(ChatProvider chat, dynamic sess) {
    final titleCtrl = TextEditingController(text: sess.title);
    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 460,
        maxWidth: 540,
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: AppColors.primaryLight, size: 22),
            SizedBox(width: 8),
            Text('Đổi Tên Hộp Hội Thoại'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nhập tiêu đề mới cho cuộc trò chuyện:', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Tiêu đề cuộc hội thoại',
                prefixIcon: Icon(Icons.chat_bubble_outline_rounded, size: 16),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final newTitle = titleCtrl.text.trim();
              if (newTitle.isNotEmpty) {
                chat.renameSession(sess, newTitle);
                AppToast.success(context, 'Đã đổi tên hộp hội thoại!');
              }
              Navigator.pop(ctx);
            },
            child: const Text('Lưu thay đổi'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(ChatProvider chat, dynamic sess) {
    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 420,
        maxWidth: 500,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 22),
            SizedBox(width: 8),
            Text('Xác Nhận Xóa Hội Thoại'),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa vĩnh viễn cuộc hội thoại "${sess.title}" và toàn bộ tin nhắn liên quan không?',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              chat.deleteSession(sess.id);
              AppToast.info(context, 'Đã xóa hộp hội thoại!');
              Navigator.pop(ctx);
            },
            child: const Text('Xóa vĩnh viễn'),
          ),
        ],
      ),
    );
  }

  static Widget _buildPersonaAvatar(PersonaProfile p, {required double radius, required double fontSize}) {
    final hasImg = p.avatarUrl != null && p.avatarUrl!.trim().isNotEmpty;
    final isFemale = p.gender.toLowerCase() == 'nữ';
    final fallbackColor = isFemale ? Colors.pinkAccent : AppColors.accentCyan;

    Widget fallbackWidget() {
      return CircleAvatar(
        radius: radius,
        backgroundColor: fallbackColor.withValues(alpha: 0.25),
        child: Text(
          p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: fallbackColor,
          ),
        ),
      );
    }

    if (!hasImg) return fallbackWidget();

    final avatarPath = p.avatarUrl!.trim();
    final isNetwork = avatarPath.startsWith('http://') || avatarPath.startsWith('https://');

    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: isNetwork
            ? Image.network(
                avatarPath,
                key: ValueKey(avatarPath),
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, stack) => fallbackWidget(),
              )
            : Image.file(
                File(avatarPath),
                key: ValueKey(avatarPath),
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, stack) => fallbackWidget(),
              ),
      ),
    );
  }
}

class _ScopePickerDialog extends StatefulWidget {
  final List<PersonaProfile> selectedPersonas;
  final ValueChanged<List<PersonaProfile>> onSelect;

  const _ScopePickerDialog({
    required this.selectedPersonas,
    required this.onSelect,
  });

  @override
  State<_ScopePickerDialog> createState() => _ScopePickerDialogState();
}

class _ScopePickerDialogState extends State<_ScopePickerDialog> {
  final PersonaService _personaService = PersonaService();
  final TextEditingController _searchController = TextEditingController();
  List<PersonaProfile> _allPersonas = [];
  final Set<String> _selectedIps = {};
  bool _isLoading = true;

  int _currentPage = 1;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    final initialIps = widget.selectedPersonas.map((p) => p.ip);
    _selectedIps.addAll(initialIps);
    _loadPersonas();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPersonas() async {
    setState(() => _isLoading = true);
    final map = await _personaService.loadSavedPersonas();
    if (mounted) {
      setState(() {
        _allPersonas = map.values.toList();
        _isLoading = false;
      });
    }
  }

  List<PersonaProfile> get _filteredPersonas {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _allPersonas;
    return _allPersonas.where((p) {
      return p.name.toLowerCase().contains(query) ||
          p.ip.toLowerCase().contains(query) ||
          p.gender.toLowerCase().contains(query) ||
          p.bio.toLowerCase().contains(query);
    }).toList();
  }

  void _togglePersona(PersonaProfile p) {
    setState(() {
      if (_selectedIps.contains(p.ip)) {
        _selectedIps.remove(p.ip);
      } else {
        _selectedIps.add(p.ip);
      }
    });
  }

  void _selectAllFiltered() {
    final filtered = _filteredPersonas;
    setState(() {
      for (final p in filtered) {
        _selectedIps.add(p.ip);
      }
    });
  }

  void _selectPage() {
    final filtered = _filteredPersonas;
    final totalPages = (filtered.length / _pageSize).ceil();
    final safePage = totalPages == 0 ? 1 : _currentPage.clamp(1, totalPages);
    final startIndex = (safePage - 1) * _pageSize;
    final pageItems = filtered.skip(startIndex).take(_pageSize).toList();

    setState(() {
      for (final p in pageItems) {
        _selectedIps.add(p.ip);
      }
    });
  }

  void _clearAll() {
    setState(() {
      _selectedIps.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredPersonas;
    final totalSelected = _selectedIps.length;
    final totalPages = (filtered.length / _pageSize).ceil();
    final safePage = totalPages == 0 ? 1 : _currentPage.clamp(1, totalPages);
    final startIndex = (safePage - 1) * _pageSize;
    final pageItems = filtered.skip(startIndex).take(_pageSize).toList();

    return TaduDialog(
      minWidth: 580,
      maxWidth: 680,
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_alt_rounded, color: AppColors.primaryLight, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Chọn Nhân Vật (Profiles)',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chọn các nhân vật (persona profiles) để AI Agent quản lý và hành động trong hội thoại này (không giới hạn số lượng):',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.inputBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderDark, width: 1),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 10, right: 6),
                          child: Icon(Icons.search_rounded, size: 16, color: AppColors.textDim),
                        ),
                        Expanded(
                          child: Center(
                            child: TextField(
                              controller: _searchController,
                              style: const TextStyle(fontSize: 12.5, color: AppColors.textWhite),
                              onChanged: (_) => setState(() {
                                _currentPage = 1;
                              }),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 8),
                                hintText: 'Tìm theo tên, IP, giới tính...',
                                hintStyle: TextStyle(fontSize: 12, color: AppColors.textDim),
                                fillColor: Colors.transparent,
                                filled: false,
                              ),
                            ),
                          ),
                        ),
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            icon: const Icon(Icons.close_rounded, size: 14, color: AppColors.textDim),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _currentPage = 1;
                              });
                            },
                          )
                        else
                          const SizedBox(width: 6),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _selectAllFiltered,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.6), width: 1.2),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.done_all_rounded, size: 16, color: AppColors.primaryLight),
                        SizedBox(width: 6),
                        Text(
                          'Chọn tất cả',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _selectPage,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3), width: 1),
                    ),
                    child: const Text(
                      'Chọn trang',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.primaryLight),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _clearAll,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderDark, width: 1),
                    ),
                    child: const Text(
                      'Bỏ chọn',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.textMuted),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 320,
              decoration: BoxDecoration(
                color: AppColors.bgDark,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.borderDark),
              ),
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                    )
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            _allPersonas.isEmpty
                                ? 'Chưa có nhân vật nào. Hãy vào mục Profiles để tạo.'
                                : 'Không tìm thấy nhân vật nào phù hợp.',
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        )
                      : ListView.separated(
                          itemCount: pageItems.length,
                          separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.borderDark),
                          itemBuilder: (context, idx) {
                            final persona = pageItems[idx];
                            final isSelected = _selectedIps.contains(persona.ip);

                            return InkWell(
                              onTap: () => _togglePersona(persona),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: isSelected,
                                      activeColor: AppColors.primary,
                                      onChanged: (_) => _togglePersona(persona),
                                    ),
                                    _ChatScreenState._buildPersonaAvatar(persona, radius: 16, fontSize: 12),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                persona.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  color: AppColors.textWhite,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: AppColors.cardBg,
                                                  borderRadius: BorderRadius.circular(3),
                                                  border: Border.all(color: AppColors.borderDark),
                                                ),
                                                child: Text(
                                                  '${persona.gender}, ${persona.age}t',
                                                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            persona.bio.isNotEmpty ? persona.bio : 'Không có tiểu sử',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.cardBg,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: AppColors.borderDark),
                                      ),
                                      child: Text(
                                        persona.ip,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 11,
                                          color: AppColors.accentCyan,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            if (totalPages > 1) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  InkWell(
                    onTap: safePage > 1
                        ? () => setState(() => _currentPage = safePage - 1)
                        : null,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: safePage > 1 ? AppColors.cardBg : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: safePage > 1 ? AppColors.borderDark : AppColors.borderDark.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Icon(
                        Icons.chevron_left_rounded,
                        size: 16,
                        color: safePage > 1 ? AppColors.textBody : AppColors.textDim,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 4,
                    children: List.generate(totalPages, (index) {
                      final pNum = index + 1;
                      final isCur = pNum == safePage;
                      return InkWell(
                        onTap: () => setState(() => _currentPage = pNum),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isCur ? AppColors.primary : AppColors.cardBg,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isCur ? AppColors.primaryLight : AppColors.borderDark,
                            ),
                          ),
                          child: Text(
                            '$pNum',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isCur ? FontWeight.bold : FontWeight.w500,
                              color: isCur ? const Color(0xFF070B14) : AppColors.textBody,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: safePage < totalPages
                        ? () => setState(() => _currentPage = safePage + 1)
                        : null,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: safePage < totalPages ? AppColors.cardBg : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: safePage < totalPages ? AppColors.borderDark : AppColors.borderDark.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: safePage < totalPages ? AppColors.textBody : AppColors.textDim,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onSelect([]);
            Navigator.pop(context);
          },
          child: const Text('Bỏ chọn tất cả', style: TextStyle(color: AppColors.danger)),
        ),
        ElevatedButton(
          onPressed: () {
            final selected = _allPersonas.where((p) => _selectedIps.contains(p.ip)).toList();
            widget.onSelect(selected);
            Navigator.pop(context);
          },
          child: Text('Áp dụng ($totalSelected)'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// High-Performance Virtualized Message Item Widget
// ---------------------------------------------------------------------------

class _MessageItemWidget extends StatelessWidget {
  final ChatMessageModel msg;
  final void Function(AttachmentItem) onDownloadAttachment;
  final void Function(String) onRetry;

  const _MessageItemWidget({
    super.key,
    required this.msg,
    required this.onDownloadAttachment,
    required this.onRetry,
  });

  static final MarkdownStyleSheet _sharedStyleSheet = MarkdownStyleSheet(
    p: const TextStyle(fontSize: 13.5, color: AppColors.textWhite, height: 1.55),
    pPadding: const EdgeInsets.only(bottom: 6),
    strong: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textWhite),
    em: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.textBody),
    h1: const TextStyle(fontSize: 15.0, fontWeight: FontWeight.bold, color: AppColors.textWhite, height: 1.35),
    h1Padding: const EdgeInsets.only(top: 10, bottom: 5),
    h2: const TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold, color: AppColors.textWhite, height: 1.35),
    h2Padding: const EdgeInsets.only(top: 9, bottom: 4),
    h3: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppColors.primaryLight, height: 1.3),
    h3Padding: const EdgeInsets.only(top: 7, bottom: 4),
    h4: const TextStyle(fontSize: 13.0, fontWeight: FontWeight.w600, color: AppColors.textWhite, height: 1.3),
    h4Padding: const EdgeInsets.only(top: 6, bottom: 3),
    h5: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textWhite, height: 1.3),
    h5Padding: const EdgeInsets.only(top: 4, bottom: 2),
    h6: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.w600, color: AppColors.textMuted, height: 1.3),
    h6Padding: const EdgeInsets.only(top: 4, bottom: 2),
    blockSpacing: 8.0,
    listBullet: const TextStyle(fontSize: 13.5, color: AppColors.primaryLight),
    listBulletPadding: const EdgeInsets.only(right: 6, top: 1),
    listIndent: 20.0,
    code: const TextStyle(
      fontFamily: 'monospace',
      backgroundColor: AppColors.codeBg,
      color: AppColors.terminalGreen,
      fontSize: 12,
    ),
    codeblockPadding: const EdgeInsets.all(10),
    codeblockDecoration: BoxDecoration(
      color: AppColors.codeBg,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppColors.borderDark),
    ),
    blockquote: const TextStyle(fontSize: 13, color: AppColors.textBody, fontStyle: FontStyle.italic),
    blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    blockquoteDecoration: BoxDecoration(
      color: AppColors.inputBg,
      borderRadius: BorderRadius.circular(4),
      border: const Border(
        left: BorderSide(color: AppColors.primaryLight, width: 3),
      ),
    ),
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.borderDark, width: 1)),
    ),
    tableBorder: TableBorder.all(
      color: AppColors.borderDark,
      width: 1.0,
      borderRadius: BorderRadius.circular(4),
    ),
    tableHead: const TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.bold,
      color: AppColors.textWhite,
    ),
    tableBody: const TextStyle(
      fontSize: 12,
      color: AppColors.textBody,
    ),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    tableCellsDecoration: const BoxDecoration(
      color: AppColors.inputBg,
    ),
  );

  String _formatSessionTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isUser) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/logo.jpg',
                  width: 30,
                  height: 30,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.smart_toy_rounded, size: 16, color: AppColors.primaryLight),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUser
                          ? AppColors.primary.withValues(alpha: 0.12)
                          : AppColors.cardBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isUser
                            ? AppColors.primary.withValues(alpha: 0.4)
                            : AppColors.borderDark,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (msg.attachments.isNotEmpty) ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: msg.attachments.map((att) {
                              return Material(
                                color: AppColors.bgDark,
                                borderRadius: BorderRadius.circular(4),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(4),
                                  onTap: () => onDownloadAttachment(att),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          att.isImage ? Icons.image_rounded : Icons.insert_drive_file_rounded,
                                          size: 14,
                                          color: att.isImage ? AppColors.accentCyan : AppColors.warning,
                                        ),
                                        const SizedBox(width: 6),
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 160),
                                          child: Text(
                                            att.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 11.5, color: AppColors.textWhite, fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '(${att.formattedSize})',
                                          style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                                        ),
                                        const SizedBox(width: 6),
                                        const Icon(
                                          Icons.download_rounded,
                                          size: 14,
                                          color: AppColors.accentCyan,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          if (msg.content.isNotEmpty) const SizedBox(height: 8),
                        ],
                        if (msg.content.isNotEmpty)
                          MarkdownBody(
                            data: msg.content,
                            selectable: true,
                            styleSheet: _sharedStyleSheet,
                          )
                        else if (!msg.isStreaming)
                          const Text(
                            'Đã hoàn tất tác vụ.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
                              fontStyle: FontStyle.italic,
                            ),
                          ),

                        if (msg.content.isEmpty && msg.isStreaming)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(strokeWidth: 1.8, color: AppColors.primaryLight),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                (msg.statusMessage != null && msg.statusMessage!.isNotEmpty)
                                    ? msg.statusMessage!
                                    : 'Đang xử lý...',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),

                  // Message Action Bar (Timestamp, Copy, Retry, PDF)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 2, right: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule_rounded, size: 11, color: AppColors.textDim),
                        const SizedBox(width: 3),
                        Text(
                          _formatSessionTime(msg.createdAt),
                          style: const TextStyle(fontSize: 10.5, color: AppColors.textDim, fontFamily: 'monospace'),
                        ),
                        const SizedBox(width: 10),
                        InkWell(
                          borderRadius: BorderRadius.circular(3),
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: msg.content));
                            AppToast.success(context, 'Đã sao chép nội dung vào bộ nhớ tạm!');
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              children: [
                                Icon(Icons.copy_rounded, size: 11, color: AppColors.textDim),
                                SizedBox(width: 3),
                                Text('Sao chép', style: TextStyle(fontSize: 10.5, color: AppColors.textDim)),
                              ],
                            ),
                          ),
                        ),

                        if (isUser) ...[
                          const SizedBox(width: 8),
                          InkWell(
                            borderRadius: BorderRadius.circular(3),
                            onTap: () => onRetry(msg.content),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.rotate_right_rounded, size: 12, color: AppColors.primaryLight),
                                  SizedBox(width: 3),
                                  Text('Hỏi lại', style: TextStyle(fontSize: 10.5, color: AppColors.primaryLight, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (isUser) ...[
              const SizedBox(width: 10),
              Builder(
                builder: (ctx) {
                  final auth = ctx.watch<AuthProvider>();
                  final letter = (auth.userEmail?.isNotEmpty == true)
                      ? auth.userEmail![0].toUpperCase()
                      : 'U';
                  return Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      letter,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

