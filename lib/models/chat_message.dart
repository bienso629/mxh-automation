import 'attachment_item.dart';

class ToolExecutionItem {
  final String tool;
  final String command;
  final String output;

  ToolExecutionItem({
    required this.tool,
    required this.command,
    required this.output,
  });

  factory ToolExecutionItem.fromJson(Map<String, dynamic> json) {
    return ToolExecutionItem(
      tool: json['tool']?.toString() ?? '',
      command: json['command']?.toString() ?? '',
      output: json['output']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'tool': tool,
    'command': command,
    'output': output,
  };
}

class ChatMessageModel {
  final int? id;
  final String sessionId;
  final String role; // 'user' | 'assistant' | 'system'
  String content;
  final String model;
  final DateTime createdAt;
  final List<ToolExecutionItem> toolExecutions;
  final List<AttachmentItem> attachments;
  bool isStreaming;
  String? statusMessage;

  ChatMessageModel({
    this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    this.model = 'glm-5.3',
    DateTime? createdAt,
    List<ToolExecutionItem>? toolExecutions,
    List<AttachmentItem>? attachments,
    this.isStreaming = false,
    this.statusMessage,
  })  : createdAt = createdAt ?? DateTime.now(),
        toolExecutions = toolExecutions ?? [],
        attachments = attachments ?? [];

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    List<AttachmentItem> atts = [];
    if (json['attachments'] is List) {
      atts = (json['attachments'] as List)
          .whereType<Map<String, dynamic>>()
          .map((e) => AttachmentItem.fromJson(e))
          .toList();
    }

    return ChatMessageModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? ''),
      sessionId: json['session_id']?.toString() ?? '',
      role: json['role']?.toString() ?? 'assistant',
      content: json['content']?.toString() ?? '',
      model: json['model']?.toString() ?? 'glm-5.3',
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
      toolExecutions: ((json['tool_calls'] ?? json['tools']) as List<dynamic>?)
          ?.map((e) => ToolExecutionItem.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      attachments: atts,
      isStreaming: false,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'session_id': sessionId,
    'role': role,
    'content': content,
    'model': model,
    'created_at': createdAt.toIso8601String(),
    'tools': toolExecutions.map((e) => e.toJson()).toList(),
    if (attachments.isNotEmpty) 'attachments': attachments.map((e) => e.toJson()).toList(),
  };
}

class ChatHistoryResult {
  final List<ChatMessageModel> messages;
  final bool hasMore;
  final int oldestId;

  ChatHistoryResult({
    required this.messages,
    required this.hasMore,
    required this.oldestId,
  });
}

