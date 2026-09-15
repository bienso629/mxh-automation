class ScheduleTaskModel {
  final int? id;
  final String title;
  final String taskType; // 'like' | 'comment' | 'livestream' | 'post'
  final String executionMode; // 'browser' | 'device'
  final String targetUrl;
  final String? commentContent;
  final List<String> personaIps;
  final DateTime scheduledTime;
  final String status; // 'pending' | 'running' | 'completed' | 'failed' | 'cancelled'
  final String? resultNote;
  final DateTime? completedAt;
  final DateTime createdAt;

  ScheduleTaskModel({
    this.id,
    required this.title,
    required this.taskType,
    this.executionMode = 'browser',
    required this.targetUrl,
    this.commentContent,
    required this.personaIps,
    required this.scheduledTime,
    this.status = 'pending',
    this.resultNote,
    this.completedAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'task_type': taskType,
      'execution_mode': executionMode,
      'target_url': targetUrl,
      'comment_content': commentContent,
      'persona_ips': personaIps.join(','),
      'scheduled_time': scheduledTime.toIso8601String(),
      'status': status,
      'result_note': resultNote,
      'completed_at': completedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ScheduleTaskModel.fromMap(Map<String, dynamic> map) {
    final ipsStr = map['persona_ips']?.toString() ?? '';
    final ips = ipsStr.isEmpty ? <String>[] : ipsStr.split(',').where((s) => s.trim().isNotEmpty).toList();

    return ScheduleTaskModel(
      id: map['id'] as int?,
      title: map['title']?.toString() ?? '',
      taskType: map['task_type']?.toString() ?? 'like',
      executionMode: map['execution_mode']?.toString() ?? 'browser',
      targetUrl: map['target_url']?.toString() ?? '',
      commentContent: map['comment_content']?.toString(),
      personaIps: ips,
      scheduledTime: DateTime.tryParse(map['scheduled_time']?.toString() ?? '') ?? DateTime.now(),
      status: map['status']?.toString() ?? 'pending',
      resultNote: map['result_note']?.toString(),
      completedAt: map['completed_at'] != null ? DateTime.tryParse(map['completed_at'].toString()) : null,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  ScheduleTaskModel copyWith({
    int? id,
    String? title,
    String? taskType,
    String? executionMode,
    String? targetUrl,
    String? commentContent,
    List<String>? personaIps,
    DateTime? scheduledTime,
    String? status,
    String? resultNote,
    DateTime? completedAt,
    DateTime? createdAt,
  }) {
    return ScheduleTaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      taskType: taskType ?? this.taskType,
      executionMode: executionMode ?? this.executionMode,
      targetUrl: targetUrl ?? this.targetUrl,
      commentContent: commentContent ?? this.commentContent,
      personaIps: personaIps ?? this.personaIps,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      status: status ?? this.status,
      resultNote: resultNote ?? this.resultNote,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
