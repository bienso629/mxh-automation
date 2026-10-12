import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/attachment_item.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../models/persona_profile_model.dart';
import '../../models/schedule_task_model.dart';
import 'encryption_service.dart';
import 'storage_service.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;
  final EncryptionService _enc = EncryptionService();
  String? _resolvedPath;
  String? _currentUserKey;

  String? get resolvedPath => _resolvedPath;
  String? get currentUserKey => _currentUserKey;

  Future<void> switchUser(String userKey) async {
    final sanitized = StorageService.sanitizeUserKey(userKey);
    if (_currentUserKey == sanitized && _db != null && _db!.isOpen) return;
    _currentUserKey = sanitized;
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
    _resolvedPath = null;
    await init(userKey: _currentUserKey);
  }

  Future<void> init({String? userKey}) async {
    if (userKey != null && userKey.isNotEmpty) {
      final sanitized = StorageService.sanitizeUserKey(userKey);
      if (_currentUserKey != sanitized && _db != null && _db!.isOpen) {
        await _db!.close();
        _db = null;
      }
      _currentUserKey = sanitized;
    }

    if (_db != null && _db!.isOpen) return;

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    _resolvedPath = await _resolveDbPath(userKey: _currentUserKey);
    _db = await openDatabase(
      _resolvedPath!,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS chat_sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            is_pinned INTEGER DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS chat_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT DEFAULT 'default',
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            attachments_json TEXT,
            tool_calls_json TEXT,
            model TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS persona_profiles (
            ip TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            age INTEGER DEFAULT 25,
            gender TEXT DEFAULT 'Nam',
            bio TEXT,
            avatar_prompt TEXT,
            external_device_address TEXT,
            use_external_device INTEGER DEFAULT 0,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ''');
      },
    );

    // Đảm bảo bảng persona_profiles tồn tại nếu DB đã tạo từ trước
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS persona_profiles (
        ip TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        age INTEGER DEFAULT 25,
        gender TEXT DEFAULT 'Nam',
        bio TEXT,
        avatar_prompt TEXT,
        external_device_address TEXT,
        use_external_device INTEGER DEFAULT 0,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Bảng quản lý kế hoạch lịch trình (Calendar schedule tasks)
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS schedule_tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        task_type TEXT NOT NULL,
        execution_mode TEXT DEFAULT 'browser',
        target_url TEXT NOT NULL,
        comment_content TEXT,
        persona_ips TEXT NOT NULL,
        scheduled_time TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        result_note TEXT,
        completed_at TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Migration: Thêm cột nếu bảng cũ chưa có
    try {
      await _db!.execute("ALTER TABLE schedule_tasks ADD COLUMN execution_mode TEXT DEFAULT 'browser'");
    } catch (_) {}
    try {
      await _db!.execute('ALTER TABLE persona_profiles ADD COLUMN external_device_address TEXT');
    } catch (_) {}
    try {
      await _db!.execute('ALTER TABLE persona_profiles ADD COLUMN use_external_device INTEGER DEFAULT 0');
    } catch (_) {}
    try {
      await _db!.execute('ALTER TABLE persona_profiles ADD COLUMN avatar_url TEXT');
    } catch (_) {}
    try {
      await _db!.execute('ALTER TABLE persona_profiles ADD COLUMN avd_name TEXT');
    } catch (_) {}
    try {
      await _db!.execute("ALTER TABLE persona_profiles ADD COLUMN device_type TEXT DEFAULT 'mobile'");
    } catch (_) {}
    try {
      await _db!.execute('ALTER TABLE persona_profiles ADD COLUMN agent_info TEXT');
    } catch (_) {}
    try {
      await _db!.execute('ALTER TABLE persona_profiles ADD COLUMN email TEXT');
    } catch (_) {}
    try {
      await _db!.execute('ALTER TABLE persona_profiles ADD COLUMN phone_number TEXT');
    } catch (_) {}
    try {
      await _db!.execute('ALTER TABLE persona_profiles ADD COLUMN auto_sync_phone_to_device INTEGER DEFAULT 0');
    } catch (_) {}
    try {
      await _db!.execute('ALTER TABLE persona_profiles ADD COLUMN sms_order_id TEXT');
    } catch (_) {}
    try {
      await _db!.execute('ALTER TABLE persona_profiles ADD COLUMN device_resolution TEXT');
    } catch (_) {}
    try {
      await _db!.execute('ALTER TABLE persona_profiles ADD COLUMN automation_macros_json TEXT');
    } catch (_) {}
    try {
      await _db!.execute('ALTER TABLE chat_sessions ADD COLUMN cli_conv_id TEXT');
    } catch (_) {}
  }

  Future<String> _resolveDbPath({String? userKey}) async {
    final key = userKey ?? _currentUserKey ?? await StorageService().getUserKey();
    final dbFileName = key.isNotEmpty ? 'chat_history_$key.db' : 'chat_history.db';

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      final execDir = p.dirname(Platform.resolvedExecutable);
      final currentDir = Directory.current.path;
      final userProfile = Platform.environment['USERPROFILE']?.trim();
      final homeEnv = Platform.environment['HOME']?.trim();
      final appDataEnv = Platform.environment['APPDATA']?.trim();
      final homeDir = (userProfile != null && userProfile.isNotEmpty)
          ? userProfile
          : ((homeEnv != null && homeEnv.isNotEmpty)
              ? homeEnv
              : ((appDataEnv != null && appDataEnv.isNotEmpty) ? appDataEnv : Directory.systemTemp.path));

      final candidates = [
        p.join(currentDir, dbFileName),
        p.join(currentDir, '..', dbFileName),
        p.join(currentDir, '..', '..', dbFileName),
        p.join(currentDir, '..', '..', '..', dbFileName),
        p.join(homeDir, '.agent_mxh_auto', dbFileName),
        p.join(homeDir, '.tadu_ai_agent', dbFileName),
        if (appDataEnv != null && appDataEnv.isNotEmpty) p.join(appDataEnv, 'AgentMXHAuto', dbFileName),
        p.join(execDir, dbFileName),
        p.join(execDir, '..', dbFileName),
        p.join(execDir, '..', '..', dbFileName),
        p.join(execDir, '..', '..', '..', dbFileName),
        p.join(execDir, '..', '..', '..', '..', dbFileName),
        p.join(execDir, '..', '..', '..', '..', '..', dbFileName),
        '/home/yenai/Documents/Projects/Typing/apps/plugins/agent-client-server/$dbFileName',
      ];

      for (final candidate in candidates) {
        if (File(candidate).existsSync()) {
          return p.normalize(candidate);
        }
      }

      // Luôn lưu trữ DB của user mới vào ~/.agent_mxh_auto/ (đảm bảo quyền ghi cả trên Windows/Linux/macOS)
      final homeDataDir = Directory(p.join(homeDir, '.agent_mxh_auto'));
      if (!homeDataDir.existsSync()) {
        try {
          homeDataDir.createSync(recursive: true);
        } catch (_) {}
      }
      return p.join(homeDataDir.path, dbFileName);
    }

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dir = Directory(appDocDir.path);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final targetPath = p.join(appDocDir.path, dbFileName);

      return targetPath;
    } catch (_) {
      return dbFileName;
    }
  }

  Future<Database> _getDb() async {
    await init();
    return _db!;
  }

  Future<List<ChatSessionModel>> getSessions() async {
    try {
      final db = await _getDb();
      final rows = await db.rawQuery(
        'SELECT id, title, is_pinned, created_at, updated_at FROM chat_sessions ORDER BY is_pinned DESC, updated_at DESC, id DESC',
      );

      if (rows.isEmpty) {
        final defaultId = 'default';
        final encTitle = _enc.encryptValue('Cuộc hội thoại mới');
        await db.insert('chat_sessions', {
          'id': defaultId,
          'title': encTitle,
          'is_pinned': 0,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        return [
          ChatSessionModel(
            id: defaultId,
            title: 'Cuộc hội thoại mới',
            isPinned: false,
          ),
        ];
      }

      final result = <ChatSessionModel>[];
      for (final row in rows) {
        final id = row['id']?.toString() ?? '';
        final rawTitle = row['title']?.toString() ?? '';
        final decTitle = _enc.decryptValue(rawTitle);

        // Count messages
        final countRows = await db.rawQuery(
          'SELECT COUNT(*) as count FROM chat_messages WHERE session_id = ?',
          [id],
        );
        final msgCount = (countRows.isNotEmpty && countRows.first['count'] != null)
            ? int.tryParse(countRows.first['count'].toString()) ?? 0
            : 0;

        result.add(
          ChatSessionModel(
            id: id,
            title: decTitle.isNotEmpty ? decTitle : 'Cuộc hội thoại',
            isPinned: row['is_pinned'] == 1 || row['is_pinned'] == true,
            createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
            updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
            messageCount: msgCount,
          ),
        );
      }
      return result;
    } catch (e) {
      return [];
    }
  }

  Future<ChatSessionModel> createSession({String? id, String title = 'Cuộc hội thoại mới'}) async {
    final db = await _getDb();
    final sessId = id ?? 's_${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
    final encTitle = _enc.encryptValue(title);
    final now = DateTime.now().toIso8601String();

    await db.insert(
      'chat_sessions',
      {
        'id': sessId,
        'title': encTitle,
        'is_pinned': 0,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return ChatSessionModel(
      id: sessId,
      title: title,
      isPinned: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<bool> updateSessionTitle(String id, String title) async {
    try {
      final db = await _getDb();
      final encTitle = _enc.encryptValue(title);
      final now = DateTime.now().toIso8601String();
      await db.update(
        'chat_sessions',
        {
          'title': encTitle,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> togglePinSession(String id, {bool? isPinned}) async {
    try {
      final db = await _getDb();
      int newPin = 1;
      if (isPinned != null) {
        newPin = isPinned ? 1 : 0;
      } else {
        final row = await db.query('chat_sessions', columns: ['is_pinned'], where: 'id = ?', whereArgs: [id]);
        if (row.isNotEmpty) {
          final current = row.first['is_pinned'];
          newPin = (current == 1) ? 0 : 1;
        }
      }
      await db.update('chat_sessions', {'is_pinned': newPin}, where: 'id = ?', whereArgs: [id]);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteSession(String id) async {
    try {
      final db = await _getDb();
      await db.delete('chat_messages', where: 'session_id = ?', whereArgs: [id]);
      await db.delete('chat_sessions', where: 'id = ?', whereArgs: [id]);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> getCliConversationId(String sessionId) async {
    try {
      final db = await _getDb();
      final rows = await db.query(
        'chat_sessions',
        columns: ['cli_conv_id'],
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      if (rows.isNotEmpty && rows.first['cli_conv_id'] != null) {
        final val = rows.first['cli_conv_id']?.toString().trim() ?? '';
        return val.isNotEmpty ? val : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> setCliConversationId(String sessionId, String cliConvId) async {
    try {
      final db = await _getDb();
      await db.update(
        'chat_sessions',
        {'cli_conv_id': cliConvId.trim()},
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    } catch (_) {}
  }

  Future<ChatHistoryResult> getMessages(
    String sessionId, {
    int limit = 50,
    int? beforeId,
  }) async {
    try {
      final db = await _getDb();
      String query = 'SELECT id, session_id, role, content, attachments_json, tool_calls_json, model, created_at FROM chat_messages WHERE session_id = ?';
      final args = <dynamic>[sessionId];

      if (beforeId != null && beforeId > 0) {
        query += ' AND id < ?';
        args.add(beforeId);
      }

      query += ' ORDER BY id DESC LIMIT ?';
      args.add(limit + 1);

      final rows = await db.rawQuery(query, args);
      final hasMore = rows.length > limit;
      final displayRows = hasMore ? rows.sublist(0, limit) : rows;

      final messages = <ChatMessageModel>[];
      int oldestId = 0;

      for (final r in displayRows.reversed) {
        final id = int.tryParse(r['id']?.toString() ?? '0') ?? 0;
        if (oldestId == 0 || (id > 0 && id < oldestId)) {
          oldestId = id;
        }

        final rawContent = r['content']?.toString() ?? '';
        final decContent = _enc.decryptValue(rawContent);

        final rawToolCalls = r['tool_calls_json']?.toString();
        List<ToolExecutionItem> toolExecs = [];
        if (rawToolCalls != null && rawToolCalls.isNotEmpty) {
          final decTools = _enc.decryptValue(rawToolCalls);
          try {
            final parsed = jsonDecode(decTools);
            if (parsed is List) {
              toolExecs = parsed
                  .whereType<Map<String, dynamic>>()
                  .map((e) => ToolExecutionItem.fromJson(e))
                  .toList();
            }
          } catch (_) {}
        }

        final rawAttachments = r['attachments_json']?.toString();
        List<AttachmentItem> attachments = [];
        if (rawAttachments != null && rawAttachments.isNotEmpty) {
          final decAtt = _enc.decryptValue(rawAttachments);
          try {
            final parsed = jsonDecode(decAtt);
            if (parsed is List) {
              attachments = parsed
                  .whereType<Map<String, dynamic>>()
                  .map((e) => AttachmentItem.fromJson(e))
                  .toList();
            }
          } catch (_) {}
        }

        messages.add(
          ChatMessageModel(
            id: id,
            sessionId: r['session_id']?.toString() ?? sessionId,
            role: r['role']?.toString() ?? 'assistant',
            content: decContent,
            model: r['model']?.toString() ?? 'glm-5.3',
            createdAt: DateTime.tryParse(r['created_at']?.toString() ?? ''),
            toolExecutions: toolExecs,
            attachments: attachments,
          ),
        );
      }

      return ChatHistoryResult(
        messages: messages,
        hasMore: hasMore,
        oldestId: oldestId,
      );
    } catch (e) {
      return ChatHistoryResult(messages: [], hasMore: false, oldestId: 0);
    }
  }

  Future<int> insertMessage(ChatMessageModel msg) async {
    try {
      final db = await _getDb();
      final encContent = _enc.encryptValue(msg.content);
      String? encTools;
      if (msg.toolExecutions.isNotEmpty) {
        final toolsJson = jsonEncode(msg.toolExecutions.map((e) => e.toJson()).toList());
        encTools = _enc.encryptValue(toolsJson);
      }
      String? encAttachments;
      if (msg.attachments.isNotEmpty) {
        final attJson = jsonEncode(msg.attachments.map((e) => e.toJson()).toList());
        encAttachments = _enc.encryptValue(attJson);
      }

      final id = await db.insert('chat_messages', {
        'session_id': msg.sessionId,
        'role': msg.role,
        'content': encContent,
        'attachments_json': encAttachments,
        'tool_calls_json': encTools,
        'model': msg.model,
        'created_at': msg.createdAt.toIso8601String(),
      });

      // Update session updated_at
      final now = DateTime.now().toIso8601String();
      await db.update(
        'chat_sessions',
        {'updated_at': now},
        where: 'id = ?',
        whereArgs: [msg.sessionId],
      );

      // Auto update title if session title is still default
      if (msg.role == 'user') {
        final sessRows = await db.query(
          'chat_sessions',
          columns: ['title'],
          where: 'id = ?',
          whereArgs: [msg.sessionId],
        );
        if (sessRows.isNotEmpty) {
          final curTitle = _enc.decryptValue(sessRows.first['title']);
          if (curTitle == 'Cuộc hội thoại mới' || curTitle.isEmpty) {
            String smartTitle = msg.content.trim().split('\n').first.trim();
            if (smartTitle.length > 60) {
              smartTitle = '${smartTitle.substring(0, 60)}...';
            }
            if (smartTitle.isNotEmpty) {
              await updateSessionTitle(msg.sessionId, smartTitle);
            }
          }
        }
      }

      return id;
    } catch (e) {
      return 0;
    }
  }

  Future<bool> clearChat(String sessionId) async {
    try {
      final db = await _getDb();
      await db.delete('chat_messages', where: 'session_id = ?', whereArgs: [sessionId]);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ================= PERSONA PROFILES CRUD =================

  /// Lấy toàn bộ danh sách nhân vật đã lưu trong database local
  Future<Map<String, PersonaProfile>> getPersonaProfiles() async {
    try {
      final db = await _getDb();
      final rows = await db.query('persona_profiles');
      final result = <String, PersonaProfile>{};
      for (final r in rows) {
        final ip = r['ip']?.toString() ?? '';
        if (ip.isNotEmpty) {
          result[ip] = PersonaProfile(
            ip: ip,
            name: _enc.decryptValue(r['name']?.toString() ?? ''),
            age: (r['age'] is num) ? (r['age'] as num).toInt() : 25,
            gender: r['gender']?.toString() ?? 'Nam',
            bio: _enc.decryptValue(r['bio']?.toString() ?? ''),
            avatarPrompt: _enc.decryptValue(r['avatar_prompt']?.toString() ?? ''),
            avatarUrl: r['avatar_url'] != null && r['avatar_url'].toString().isNotEmpty
                ? _enc.decryptValue(r['avatar_url'].toString())
                : null,
            externalDeviceAddress: r['external_device_address'] != null && r['external_device_address'].toString().isNotEmpty
                ? _enc.decryptValue(r['external_device_address'].toString())
                : null,
            useExternalDevice: r['use_external_device'] == 1,
            avdName: r['avd_name']?.toString(),
            deviceType: r['device_type']?.toString() ?? 'mobile',
            agentInfo: r['agent_info'] != null && r['agent_info'].toString().isNotEmpty
                ? _enc.decryptValue(r['agent_info'].toString())
                : null,
            email: r['email'] != null && r['email'].toString().isNotEmpty
                ? _enc.decryptValue(r['email'].toString())
                : null,
            phoneNumber: r['phone_number'] != null && r['phone_number'].toString().isNotEmpty
                ? _enc.decryptValue(r['phone_number'].toString())
                : null,
            autoSyncPhoneToDevice: r['auto_sync_phone_to_device'] == 1,
            smsOrderId: r['sms_order_id']?.toString(),
            deviceResolution: r['device_resolution']?.toString(),
            automationMacros: () {
              final raw = r['automation_macros_json']?.toString();
              if (raw != null && raw.isNotEmpty) {
                try {
                  final dec = _enc.decryptValue(raw);
                  final parsed = jsonDecode(dec);
                  if (parsed is Map) return Map<String, dynamic>.from(parsed);
                } catch (_) {}
              }
              return null;
            }(),
          );
        }
      }
      return result;
    } catch (e) {
      return {};
    }
  }

  /// Thêm mới hoặc cập nhật thông tin nhân vật cho 1 IP
  Future<bool> upsertPersonaProfile(PersonaProfile profile) async {
    try {
      final db = await _getDb();
      final row = {
        'ip': profile.ip,
        'name': _enc.encryptValue(profile.name),
        'age': profile.age,
        'gender': profile.gender,
        'bio': _enc.encryptValue(profile.bio),
        'avatar_prompt': _enc.encryptValue(profile.avatarPrompt),
        'avatar_url': profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty
            ? _enc.encryptValue(profile.avatarUrl!)
            : null,
        'external_device_address': profile.externalDeviceAddress != null && profile.externalDeviceAddress!.isNotEmpty
            ? _enc.encryptValue(profile.externalDeviceAddress!)
            : null,
        'use_external_device': profile.useExternalDevice ? 1 : 0,
        'avd_name': profile.avdName,
        'device_type': profile.deviceType,
        'agent_info': profile.agentInfo != null && profile.agentInfo!.isNotEmpty
            ? _enc.encryptValue(profile.agentInfo!)
            : null,
        'email': profile.email != null && profile.email!.isNotEmpty
            ? _enc.encryptValue(profile.email!)
            : null,
        'phone_number': profile.phoneNumber != null && profile.phoneNumber!.isNotEmpty
            ? _enc.encryptValue(profile.phoneNumber!)
            : null,
        'auto_sync_phone_to_device': profile.autoSyncPhoneToDevice ? 1 : 0,
        'sms_order_id': profile.smsOrderId,
        'device_resolution': profile.deviceResolution,
        'automation_macros_json': profile.automationMacros != null
            ? _enc.encryptValue(jsonEncode(profile.automationMacros))
            : null,
        'updated_at': DateTime.now().toIso8601String(),
      };
      await db.insert(
        'persona_profiles',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Cập nhật hàng loạt danh sách nhân vật vào database local
  Future<void> batchUpsertPersonaProfiles(List<PersonaProfile> profiles) async {
    try {
      final db = await _getDb();
      final batch = db.batch();
      for (final p in profiles) {
        batch.insert(
          'persona_profiles',
          {
            'ip': p.ip,
            'name': _enc.encryptValue(p.name),
            'age': p.age,
            'gender': p.gender,
            'bio': _enc.encryptValue(p.bio),
            'avatar_prompt': _enc.encryptValue(p.avatarPrompt),
            'avatar_url': p.avatarUrl != null && p.avatarUrl!.isNotEmpty
                ? _enc.encryptValue(p.avatarUrl!)
                : null,
            'external_device_address': p.externalDeviceAddress != null && p.externalDeviceAddress!.isNotEmpty
                ? _enc.encryptValue(p.externalDeviceAddress!)
                : null,
            'use_external_device': p.useExternalDevice ? 1 : 0,
            'avd_name': p.avdName,
            'device_type': p.deviceType,
            'agent_info': p.agentInfo != null && p.agentInfo!.isNotEmpty
                ? _enc.encryptValue(p.agentInfo!)
                : null,
            'email': p.email != null && p.email!.isNotEmpty
                ? _enc.encryptValue(p.email!)
                : null,
            'phone_number': p.phoneNumber != null && p.phoneNumber!.isNotEmpty
                ? _enc.encryptValue(p.phoneNumber!)
                : null,
            'auto_sync_phone_to_device': p.autoSyncPhoneToDevice ? 1 : 0,
            'sms_order_id': p.smsOrderId,
            'device_resolution': p.deviceResolution,
            'automation_macros_json': p.automationMacros != null
                ? _enc.encryptValue(jsonEncode(p.automationMacros))
                : null,
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (_) {}
  }

  // ==================== SCHEDULE TASKS (CALENDAR) ====================

  /// Lấy toàn bộ danh sách tác vụ lịch trình
  Future<List<ScheduleTaskModel>> getScheduleTasks() async {
    try {
      final db = await _getDb();
      final maps = await db.query(
        'schedule_tasks',
        orderBy: 'scheduled_time ASC',
      );
      return maps.map((m) => ScheduleTaskModel.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Thêm một tác vụ lịch trình mới
  Future<int> insertScheduleTask(ScheduleTaskModel task) async {
    try {
      final db = await _getDb();
      await db.execute('''
        CREATE TABLE IF NOT EXISTS schedule_tasks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          task_type TEXT NOT NULL,
          target_url TEXT NOT NULL,
          comment_content TEXT,
          persona_ips TEXT NOT NULL,
          scheduled_time TEXT NOT NULL,
          status TEXT DEFAULT 'pending',
          result_note TEXT,
          completed_at TEXT,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      return await db.insert('schedule_tasks', task.toMap());
    } catch (e) {
      debugPrint('Lỗi insertScheduleTask: $e');
      return -1;
    }
  }

  /// Cập nhật tác vụ lịch trình
  Future<bool> updateScheduleTask(ScheduleTaskModel task) async {
    if (task.id == null) return false;
    try {
      final db = await _getDb();
      final count = await db.update(
        'schedule_tasks',
        task.toMap(),
        where: 'id = ?',
        whereArgs: [task.id],
      );
      return count > 0;
    } catch (_) {
      return false;
    }
  }

  /// Xóa tác vụ lịch trình theo ID
  Future<bool> deleteScheduleTask(int id) async {
    try {
      final db = await _getDb();
      final count = await db.delete(
        'schedule_tasks',
        where: 'id = ?',
        whereArgs: [id],
      );
      return count > 0;
    } catch (_) {
      return false;
    }
  }
}

