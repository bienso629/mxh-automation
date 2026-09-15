class ChatSessionModel {
  final String id;
  final String title;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;

  ChatSessionModel({
    required this.id,
    required this.title,
    this.isPinned = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.messageCount = 0,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory ChatSessionModel.fromJson(Map<String, dynamic> json) {
    return ChatSessionModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Cuộc hội thoại',
      isPinned: json['is_pinned'] == true || json['is_pinned'] == 1,
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? (DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      messageCount: int.tryParse(json['message_count']?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'is_pinned': isPinned,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'message_count': messageCount,
      };
}
