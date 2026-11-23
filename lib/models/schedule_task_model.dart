class ScheduleTaskModel {
  final int? id;
  final String title;
  final String taskType; // 'like' | 'comment' | 'livestream' | 'post'
  final String executionMode; // 'browser' | 'device'
  final String targetUrl;
  final String? commentContent;
  final List<String> personaIps;
  final List<String> completedIps;
  final List<String> failedIps;
  final DateTime scheduledTime;
  final String status; // 'pending' | 'running' | 'retrying' | 'partial' | 'completed' | 'failed' | 'cancelled'
  final String? resultNote;
  final int retryCount;
  final int maxRetries;
  final DateTime? nextRetryAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;

  ScheduleTaskModel({
    this.id,
    required this.title,
    required this.taskType,
    this.executionMode = 'device',
    required this.targetUrl,
    this.commentContent,
    required this.personaIps,
    this.completedIps = const [],
    this.failedIps = const [],
    required this.scheduledTime,
    this.status = 'pending',
    this.resultNote,
    this.retryCount = 0,
    this.maxRetries = 3,
    this.nextRetryAt,
    this.startedAt,
    this.completedAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Danh sách các nhân vật chưa hoàn thành (dùng cho cơ chế chạy tiếp / resume)
  List<String> get remainingIps {
    final doneSet = completedIps.toSet();
    return personaIps.where((ip) => !doneSet.contains(ip)).toList();
  }

  bool get hasCheckpointProgress => completedIps.isNotEmpty && remainingIps.isNotEmpty;

  bool get needsAttention => status == 'failed' || status == 'partial' || status == 'retrying';

  static List<String> _parseCsvList(dynamic raw) {
    final str = raw?.toString() ?? '';
    if (str.trim().isEmpty) return const [];
    return str.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'task_type': taskType,
      'execution_mode': executionMode,
      'target_url': targetUrl,
      'comment_content': commentContent,
      'persona_ips': personaIps.join(','),
      'completed_ips': completedIps.join(','),
      'failed_ips': failedIps.join(','),
      'scheduled_time': scheduledTime.toIso8601String(),
      'status': status,
      'result_note': resultNote,
      'retry_count': retryCount,
      'max_retries': maxRetries,
      'next_retry_at': nextRetryAt?.toIso8601String(),
      'started_at': startedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ScheduleTaskModel.fromMap(Map<String, dynamic> map) {
    final parsedRetry = int.tryParse(map['retry_count']?.toString() ?? '') ?? 0;
    final parsedMax = int.tryParse(map['max_retries']?.toString() ?? '') ?? 3;

    return ScheduleTaskModel(
      id: map['id'] as int?,
      title: map['title']?.toString() ?? '',
      taskType: map['task_type']?.toString() ?? 'like',
      executionMode: (map['execution_mode']?.toString().trim().isNotEmpty ?? false)
          ? map['execution_mode']!.toString().trim()
          : 'device',
      targetUrl: map['target_url']?.toString() ?? '',
      commentContent: map['comment_content']?.toString(),
      personaIps: _parseCsvList(map['persona_ips']),
      completedIps: _parseCsvList(map['completed_ips']),
      failedIps: _parseCsvList(map['failed_ips']),
      scheduledTime: DateTime.tryParse(map['scheduled_time']?.toString() ?? '') ?? DateTime.now(),
      status: map['status']?.toString() ?? 'pending',
      resultNote: map['result_note']?.toString(),
      retryCount: parsedRetry < 0 ? 0 : parsedRetry,
      maxRetries: parsedMax <= 0 ? 3 : parsedMax,
      nextRetryAt: map['next_retry_at'] != null ? DateTime.tryParse(map['next_retry_at'].toString()) : null,
      startedAt: map['started_at'] != null ? DateTime.tryParse(map['started_at'].toString()) : null,
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
    List<String>? completedIps,
    List<String>? failedIps,
    DateTime? scheduledTime,
    String? status,
    String? resultNote,
    int? retryCount,
    int? maxRetries,
    DateTime? nextRetryAt,
    bool clearNextRetryAt = false,
    DateTime? startedAt,
    bool clearStartedAt = false,
    DateTime? completedAt,
    bool clearCompletedAt = false,
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
      completedIps: completedIps ?? this.completedIps,
      failedIps: failedIps ?? this.failedIps,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      status: status ?? this.status,
      resultNote: resultNote ?? this.resultNote,
      retryCount: retryCount ?? this.retryCount,
      maxRetries: maxRetries ?? this.maxRetries,
      nextRetryAt: clearNextRetryAt ? null : (nextRetryAt ?? this.nextRetryAt),
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
