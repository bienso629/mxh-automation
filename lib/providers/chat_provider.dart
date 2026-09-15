import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/api_service.dart';
import '../models/attachment_item.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  List<ChatSessionModel> _sessions = [];
  ChatSessionModel? _currentSession;
  List<ChatMessageModel> _messages = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = false;
  int _oldestMessageId = 0;
  bool _isGenerating = false;
  String _currentStatus = '';
  StreamSubscription? _streamSub;

  List<ChatSessionModel> get sessions => _sessions;
  ChatSessionModel? get currentSession => _currentSession;
  List<ChatMessageModel> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMoreMessages => _hasMoreMessages;
  int get oldestMessageId => _oldestMessageId;
  bool get isGenerating => _isGenerating;
  String get currentStatus => _currentStatus;

  // Quick Action Chips
  final List<String> quickPrompts = [
    'Lên kế hoạch đăng bài tuần này cho các nhân vật',
    'Mở trình duyệt cho nhân vật đang chọn',
    'Khởi chạy thiết bị device thực hiện tương tác',
    'Kịch bản tương tác like và comment video tự động',
    'Kiểm tra trạng thái hoạt động của các profiles',
    'Tạo nội dung bình luận tự nhiên theo tính cách nhân vật',
  ];

  ChatProvider() {
    initChat();
  }

  Future<void> initChat() async {
    await loadSessions(silent: true);
    if (_sessions.isNotEmpty) {
      final target = (_currentSession != null && _sessions.any((s) => s.id == _currentSession!.id))
          ? _sessions.firstWhere((s) => s.id == _currentSession!.id)
          : _sessions.first;
      await selectSession(target);
    } else {
      await createNewSession();
    }
  }

  Future<void> loadSessions({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      final list = await _api.getChatSessions();
      _sessions = list;
      if (_currentSession != null) {
        final match = _sessions.where((s) => s.id == _currentSession!.id);
        if (match.isNotEmpty) {
          _currentSession = match.first;
        }
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
  }

  Future<void> createNewSession({String title = 'Cuộc hội thoại mới'}) async {
    try {
      final newSess = await _api.createChatSession(title: title);
      _sessions.insert(0, newSess);
      await selectSession(newSess);
    } catch (_) {
      final fallbackSess = ChatSessionModel(
        id: 'sess_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
      );
      _sessions.insert(0, fallbackSess);
      await selectSession(fallbackSess);
    }
  }

  Future<void> selectSession(ChatSessionModel session) async {
    _currentSession = session;
    _messages = [];
    _hasMoreMessages = false;
    _isLoadingMore = false;
    _oldestMessageId = 0;
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _api.getChatHistory(session.id, limitQuestions: 3, beforeId: 0);
      _messages = result.messages;
      _hasMoreMessages = result.hasMore;
      _oldestMessageId = result.oldestId;
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages || _currentSession == null || _oldestMessageId <= 0) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final result = await _api.getChatHistory(
        _currentSession!.id,
        limitQuestions: 3,
        beforeId: _oldestMessageId,
      );

      if (result.messages.isNotEmpty) {
        _messages.insertAll(0, result.messages);
        _hasMoreMessages = result.hasMore;
        if (result.oldestId > 0) {
          _oldestMessageId = result.oldestId;
        }
      } else {
        _hasMoreMessages = false;
      }
    } catch (_) {
      _hasMoreMessages = false;
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> pinSession(ChatSessionModel session) async {
    final newPinState = !session.isPinned;
    // 1. Optimistic local update
    final idx = _sessions.indexWhere((s) => s.id == session.id);
    if (idx != -1) {
      final updated = ChatSessionModel(
        id: session.id,
        title: session.title,
        isPinned: newPinState,
        createdAt: session.createdAt,
        updatedAt: session.updatedAt,
        messageCount: session.messageCount,
      );
      _sessions[idx] = updated;
      _sessions.sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
      if (_currentSession?.id == session.id) {
        _currentSession = updated;
      }
      notifyListeners();
    }

    // 2. Sync with API
    await _api.pinChatSession(session.id, newPinState);
    await loadSessions(silent: true);
  }

  Future<void> renameSession(ChatSessionModel session, String newTitle) async {
    final cleanTitle = newTitle.trim();
    if (cleanTitle.isEmpty) return;

    // 1. Optimistic local update
    final idx = _sessions.indexWhere((s) => s.id == session.id);
    if (idx != -1) {
      final updated = ChatSessionModel(
        id: session.id,
        title: cleanTitle,
        isPinned: session.isPinned,
        createdAt: session.createdAt,
        updatedAt: DateTime.now(),
        messageCount: session.messageCount,
      );
      _sessions[idx] = updated;
      if (_currentSession?.id == session.id) {
        _currentSession = updated;
      }
      notifyListeners();
    }

    // 2. Sync with API
    await _api.renameChatSession(session.id, cleanTitle);
    await loadSessions(silent: true);
  }

  Future<void> deleteSession(String sessionId) async {
    await _api.deleteChatSession(sessionId);
    _sessions.removeWhere((s) => s.id == sessionId);
    if (_currentSession?.id == sessionId) {
      if (_sessions.isNotEmpty) {
        await selectSession(_sessions.first);
      } else {
        await createNewSession();
      }
    } else {
      notifyListeners();
    }
  }

  Future<void> clearHistory() async {
    if (_currentSession == null) return;
    await _api.clearChatHistory(_currentSession!.id);
    _messages.clear();
    _hasMoreMessages = false;
    _oldestMessageId = 0;
    notifyListeners();
  }

  Future<void> sendMessage(
    String text, {
    String? model,
    List<AttachmentItem>? attachments,
    String? workingDir,
  }) async {
    final query = text.trim();
    if ((query.isEmpty && (attachments == null || attachments.isEmpty)) || _isGenerating) return;

    if (_currentSession == null) {
      await createNewSession();
    }

    final sessionId = _currentSession!.id;

    // 1. Add User Message
    final userMsg = ChatMessageModel(
      sessionId: sessionId,
      role: 'user',
      content: query.isNotEmpty ? query : 'Đã đính kèm ${attachments?.length ?? 0} tệp',
      model: model ?? 'glm-5.3',
      attachments: attachments,
    );
    _messages.add(userMsg);

    // 2. Add Placeholder Assistant Message
    final assistantMsg = ChatMessageModel(
      sessionId: sessionId,
      role: 'assistant',
      content: '',
      model: model ?? 'glm-5.3',
      isStreaming: true,
      statusMessage: 'Đang kết nối AI...',
    );
    _messages.add(assistantMsg);

    _isGenerating = true;
    _currentStatus = 'Đang suy nghĩ...';
    notifyListeners();

    // Prepare history snapshot
    final historySnap = _messages
        .where((m) => m.content.isNotEmpty && m != assistantMsg)
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    _streamSub?.cancel();
    _streamSub = _api.streamChatMessage(
      sessionId: sessionId,
      message: query.isNotEmpty ? query : 'Vui lòng đọc và phân tích các tệp đính kèm.',
      model: model,
      attachments: attachments,
      history: historySnap,
      workingDir: workingDir,
      onToken: (token) {
        assistantMsg.content += token;
        assistantMsg.statusMessage = null;
        notifyListeners();
      },
      onStatus: (status) {
        _currentStatus = status;
        assistantMsg.statusMessage = status;
        notifyListeners();
      },
      onTool: (tool) {
        assistantMsg.toolExecutions.add(tool);
        assistantMsg.statusMessage = 'Đã chạy lệnh: ${tool.command}';
        notifyListeners();
      },
      onDone: (fullReply) {
        assistantMsg.isStreaming = false;
        assistantMsg.statusMessage = null;
        if (fullReply.isNotEmpty && assistantMsg.content.isEmpty) {
          assistantMsg.content = fullReply;
        }
        _isGenerating = false;
        _currentStatus = '';
        notifyListeners();
        loadSessions(silent: true); // Refresh session list & titles
      },
      onError: (err) {
        assistantMsg.isStreaming = false;
        assistantMsg.statusMessage = null;
        if (assistantMsg.content.isEmpty) {
          assistantMsg.content = 'Lỗi: $err';
        }
        _isGenerating = false;
        _currentStatus = '';
        notifyListeners();
        // Persist error message to SQLite database so user always sees the status
        _api.insertChatMessage(assistantMsg).catchError((_) => 0);
      },
    );
  }

  void stopGenerating() {
    if (!_isGenerating) return;
    _streamSub?.cancel();
    _streamSub = null;
    _isGenerating = false;
    _currentStatus = '';

    if (_messages.isNotEmpty) {
      final last = _messages.last;
      if (last.role == 'assistant') {
        last.isStreaming = false;
        last.statusMessage = null;
        if (last.content.isEmpty) {
          last.content = 'Đã dừng phản hồi theo yêu cầu.';
        }
      }
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }
}
