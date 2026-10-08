import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../models/server_model.dart';
import 'encryption_service.dart';
import 'storage_service.dart';

class LocalConfigService {
  static final LocalConfigService _instance = LocalConfigService._internal();
  factory LocalConfigService() => _instance;
  LocalConfigService._internal();

  final EncryptionService _enc = EncryptionService();
  String? _resolvedConfigPath;
  String? _currentUserKey;
  Map<String, dynamic> _cachedConfig = {};

  String? get resolvedConfigPath => _resolvedConfigPath;
  String? get currentUserKey => _currentUserKey;
  static bool isValidMitomProxyUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return false;
    final trimmed = rawUrl.trim();
    try {
      final uri = Uri.parse(trimmed.startsWith('http://') || trimmed.startsWith('https://') ? trimmed : 'https://$trimmed');
      final host = uri.host.toLowerCase();
      return host == 'mitom.ai' ||
          host.endsWith('.mitom.ai') ||
          host == 'umodelverse.ai' ||
          host.endsWith('.umodelverse.ai') ||
          host == 'localhost' ||
          host == '127.0.0.1';
    } catch (_) {
      return false;
    }
  }

  static const Map<String, dynamic> defaultRawConfig = {
    'server_ip': '127.0.0.1',
    'ssh_user': 'root',
    'ssh_pass': '',
    'ssh_port': 22,
    'proxy_api_key': '',
    'proxy_base_url': 'https://api.mitom.ai/v1',
    'ai_model': 'glm-5.3',
    'remote_work_dir': '/root',
    'api_port': 8000,
    'secret_token': 'super_secret_token_123',
    'max_concurrent_devices': 2,
    'default_execution_mode': 'browser', // 'browser' | 'device'
    'ai_engine_type': 'proxy', // 'proxy' | 'cli'
    'active_cli_agent': 'antigravity-cli',
    'servers': [],
  };

  Future<void> switchUser(String userKey) async {
    final sanitized = StorageService.sanitizeUserKey(userKey);
    if (_currentUserKey == sanitized && _cachedConfig.isNotEmpty) return;
    _currentUserKey = sanitized;
    _resolvedConfigPath = null;
    _cachedConfig = {};
    await loadConfig(userKey: _currentUserKey);
  }

  Future<String> _resolveConfigPath({String? userKey}) async {
    final key = userKey ?? _currentUserKey ?? await StorageService().getUserKey();
    final configFileName = key.isNotEmpty ? 'config_$key.json' : 'config.json';

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      final execDir = p.dirname(Platform.resolvedExecutable);
      final currentDir = Directory.current.path;
      final candidates = [
        p.join(currentDir, configFileName),
        p.join(currentDir, '..', configFileName),
        p.join(currentDir, '..', '..', configFileName),
        p.join(currentDir, '..', '..', '..', configFileName),
        p.join(execDir, configFileName),
        p.join(execDir, '..', configFileName),
        p.join(execDir, '..', '..', configFileName),
        p.join(execDir, '..', '..', '..', configFileName),
        p.join(execDir, '..', '..', '..', '..', configFileName),
        p.join(execDir, '..', '..', '..', '..', '..', configFileName),
        '/home/yenai/Documents/Projects/Typing/apps/plugins/agent-client-server/$configFileName',
        p.join(Platform.environment['HOME'] ?? '', '.agent_mxh_auto', configFileName),
        p.join(Platform.environment['HOME'] ?? '', '.tadu_ai_agent', configFileName),
      ];

      for (final candidate in candidates) {
        if (File(candidate).existsSync()) {
          _resolvedConfigPath = p.normalize(candidate);
          return _resolvedConfigPath!;
        }
      }

      // If user-specific config does not exist yet, search for base config.json and seed/copy it
      if (key.isNotEmpty) {
        final fallbackCandidates = [
          p.join(currentDir, 'config.json'),
          p.join(currentDir, '..', 'config.json'),
          p.join(currentDir, '..', '..', 'config.json'),
          p.join(currentDir, '..', '..', '..', 'config.json'),
          p.join(execDir, 'config.json'),
          p.join(execDir, '..', 'config.json'),
          p.join(execDir, '..', '..', 'config.json'),
          p.join(execDir, '..', '..', '..', 'config.json'),
          p.join(execDir, '..', '..', '..', '..', 'config.json'),
          p.join(execDir, '..', '..', '..', '..', '..', 'config.json'),
          '/home/yenai/Documents/Projects/Typing/apps/plugins/agent-client-server/config.json',
          p.join(Platform.environment['HOME'] ?? '', '.agent_mxh_auto', 'config.json'),
          p.join(Platform.environment['HOME'] ?? '', '.tadu_ai_agent', 'config.json'),
        ];
        for (final fallback in fallbackCandidates) {
          if (File(fallback).existsSync()) {
            final targetDir = p.dirname(fallback);
            final newPath = p.join(targetDir, configFileName);
            try {
              File(fallback).copySync(newPath);
              _resolvedConfigPath = p.normalize(newPath);
              return _resolvedConfigPath!;
            } catch (_) {
              _resolvedConfigPath = p.normalize(fallback);
              return _resolvedConfigPath!;
            }
          }
        }
      }

      // If not found in candidates, create in current directory or user home
      final defaultDesk = p.join(currentDir, configFileName);
      _resolvedConfigPath = defaultDesk;
      return defaultDesk;
    }

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dir = Directory(appDocDir.path);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final targetPath = p.join(appDocDir.path, configFileName);
      if (key.isNotEmpty && !File(targetPath).existsSync()) {
        final defaultCfg = p.join(appDocDir.path, 'config.json');
        if (File(defaultCfg).existsSync()) {
          try {
            File(defaultCfg).copySync(targetPath);
          } catch (_) {}
        }
      }
      _resolvedConfigPath = targetPath;
      return _resolvedConfigPath!;
    } catch (_) {
      _resolvedConfigPath = configFileName;
      return configFileName;
    }
  }

  Future<Map<String, dynamic>> loadConfig({String? userKey}) async {
    final filePath = await _resolveConfigPath(userKey: userKey);
    final file = File(filePath);

    if (!file.existsSync()) {
      _cachedConfig = Map<String, dynamic>.from(defaultRawConfig);
      await saveConfig(_cachedConfig, userKey: userKey);
      return _cachedConfig;
    }

    try {
      final content = await file.readAsString();
      final raw = jsonDecode(content) as Map<String, dynamic>;
      bool needsReSave = false;

      // Decrypt overall vault if present
      if (raw['_encrypted_vault'] != null) {
        try {
          final decryptedVault = _enc.decryptValue(raw['_encrypted_vault']);
          final vaultJson = jsonDecode(decryptedVault) as Map<String, dynamic>;
          raw.addAll(vaultJson);
        } catch (_) {}
      }

      final result = <String, dynamic>{};
      for (final entry in raw.entries) {
        if (entry.key == '_encrypted_vault') continue;
        final k = entry.key;
        final v = entry.value;

        if (v is String && v.startsWith('enc:')) {
          final dec = _enc.decryptValue(v);
          if (k == 'ssh_port' || k == 'api_port' || k == 'max_concurrent_devices') {
            result[k] = int.tryParse(dec) ?? dec;
          } else if (k == 'servers') {
            try {
              final parsed = jsonDecode(dec);
              if (parsed is List) {
                result[k] = parsed;
              } else {
                result[k] = [];
              }
            } catch (_) {
              result[k] = [];
            }
          } else if (dec == 'true') {
            result[k] = true;
          } else if (dec == 'false') {
            result[k] = false;
          } else {
            result[k] = dec;
          }
        } else {
          // If any field on disk was stored as plaintext, flag for immediate re-encryption
          if (v != null && (v is! String || !v.startsWith('enc:'))) {
            needsReSave = true;
          }
          if (k == 'ssh_port' || k == 'api_port' || k == 'max_concurrent_devices') {
            result[k] = int.tryParse(v.toString()) ?? v;
          } else {
            result[k] = v;
          }
        }
      }

      // Ensure each server in servers list is clean and decrypted
      if (result['servers'] is List) {
        final rawServers = result['servers'] as List;
        final cleanServers = <Map<String, dynamic>>[];
        for (final item in rawServers) {
          if (item is Map) {
            final m = <String, dynamic>{};
            for (final se in item.entries) {
              final sk = se.key.toString();
              final sv = se.value;
              if (sv is String && sv.startsWith('enc:')) {
                final decSv = _enc.decryptValue(sv);
                if (sk == 'ssh_port' || sk == 'api_port') {
                  m[sk] = int.tryParse(decSv) ?? decSv;
                } else if (decSv == 'true') {
                  m[sk] = true;
                } else if (decSv == 'false') {
                  m[sk] = false;
                } else {
                  m[sk] = decSv;
                }
              } else {
                m[sk] = sv;
              }
            }
            cleanServers.add(m);
          }
        }
        result['servers'] = cleanServers;
      }

      // Fill in defaults for missing keys
      for (final entry in defaultRawConfig.entries) {
        if (!result.containsKey(entry.key)) {
          result[entry.key] = entry.value;
        }
      }

      _cachedConfig = result;
      if (needsReSave) {
        await saveConfig(result, userKey: userKey);
      }
      return result;
    } catch (e) {
      _cachedConfig = Map<String, dynamic>.from(defaultRawConfig);
      return _cachedConfig;
    }
  }

  Future<bool> saveConfig(Map<String, dynamic> newConfig, {String? userKey}) async {
    try {
      final currentConfig = _cachedConfig.isNotEmpty ? Map<String, dynamic>.from(_cachedConfig) : await loadConfig(userKey: userKey);
      final mergedConfig = Map<String, dynamic>.from(currentConfig)..addAll(newConfig);

      final filePath = await _resolveConfigPath(userKey: userKey);
      final file = File(filePath);

      final toSave = <String, dynamic>{};
      for (final entry in mergedConfig.entries) {
        final k = entry.key;
        final v = entry.value;

        if (k == '_encrypted_vault') continue;

        if (v != null) {
          if (v is List || v is Map) {
            toSave[k] = _enc.encryptValue(jsonEncode(v));
          } else {
            toSave[k] = _enc.encryptValue(v.toString());
          }
        }
      }

      // Also persist encrypted vault for backward compatibility
      final rawJson = jsonEncode(mergedConfig);
      toSave['_encrypted_vault'] = _enc.encryptValue(rawJson);

      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(toSave));
      _cachedConfig = Map<String, dynamic>.from(mergedConfig);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<List<ServerModel>> getServers() async {
    final cfg = await loadConfig();
    final serversList = <ServerModel>[];
    final activeId = cfg['active_server_id']?.toString() ?? '';
    final activeIp = cfg['server_ip']?.toString() ?? '';

    // 1. If 'servers' array exists and is not empty, use it as the source of truth
    if (cfg['servers'] is List && (cfg['servers'] as List).isNotEmpty) {
      bool hasActive = false;
      for (final item in (cfg['servers'] as List)) {
        if (item is Map) {
          final itemMap = Map<String, dynamic>.from(item);
          final id = itemMap['id']?.toString() ?? '';
          final ip = itemMap['server_ip']?.toString() ?? '';

          bool isCurr = false;
          if (!hasActive) {
            if (activeId.isNotEmpty && (id == activeId || ip == activeId)) {
              isCurr = true;
              hasActive = true;
            } else if (activeId.isEmpty && activeIp.isNotEmpty && ip == activeIp) {
              isCurr = true;
              hasActive = true;
            }
          }

          final s = ServerModel.fromJson(itemMap, isCurrent: isCurr);
          serversList.add(s);
        }
      }

      // If no server matched activeId, ensure exactly the first one is marked active
      if (!hasActive && serversList.isNotEmpty) {
        serversList[0] = serversList[0].copyWith(isSelected: true);
      }

      // Đảm bảo Server 100 (103.74.116.119) luôn xuất hiện trong danh sách máy chủ
      if (!serversList.any((s) => s.serverIp == '103.74.116.119')) {
        serversList.add(ServerModel(
          id: 'srv_server_100',
          name: 'Server 100',
          serverIp: '103.74.116.119',
          sshPort: 7878,
          sshUser: 'root',
          sshPass: 'Tadu#123!@#',
          aiModel: 'glm-5.3',
          remoteWorkDir: '/root',
          apiPort: 8000,
          isSelected: false,
          status: 'online',
        ));
      }
    }

    // 2. If serversList is still empty, populate from root config
    if (serversList.isEmpty && cfg['server_ip'] != null && cfg['server_ip'].toString().isNotEmpty) {
      final defaultS = ServerModel.fromJson(cfg, isCurrent: true);
      serversList.add(defaultS);
      cfg['servers'] = [defaultS.toJson()];
      cfg['active_server_id'] = defaultS.id;
      await saveConfig(cfg, userKey: _currentUserKey);
    }

    return serversList;
  }

  Future<bool> addOrUpdateServer(ServerModel server) async {
    final cfg = await loadConfig();
    List<Map<String, dynamic>> servers = [];

    if (cfg['servers'] is List) {
      for (final item in (cfg['servers'] as List)) {
        if (item is Map) {
          servers.add(Map<String, dynamic>.from(item));
        }
      }
    }

    int existingIdx = servers.indexWhere((item) =>
        item['id'] == server.id || (item['server_ip'] == server.serverIp && item['ssh_port']?.toString() == server.sshPort.toString()));

    if (existingIdx >= 0) {
      servers[existingIdx] = server.toJson();
    } else {
      servers.add(server.toJson());
    }

    // If active server or if this is the only server, sync root fields
    final activeId = cfg['active_server_id']?.toString() ?? '';
    final isActive = server.isSelected ||
        (activeId.isNotEmpty && (activeId == server.id || activeId == server.serverIp)) ||
        servers.length == 1;

    if (isActive) {
      cfg['active_server_id'] = server.id;
      cfg['server_ip'] = server.serverIp;
      cfg['ssh_user'] = server.sshUser;
      cfg['ssh_pass'] = server.sshPass;
      cfg['ssh_port'] = server.sshPort;
      cfg['ai_model'] = server.aiModel;
      cfg['remote_work_dir'] = server.remoteWorkDir;
      cfg['api_port'] = server.apiPort;
      cfg['secret_token'] = server.secretToken;
    }

    final currentActiveId = cfg['active_server_id']?.toString() ?? (servers.isNotEmpty ? servers.first['id']?.toString() : '');
    for (int i = 0; i < servers.length; i++) {
      final sId = servers[i]['id']?.toString();
      final sIp = servers[i]['server_ip']?.toString();
      final isAct = (sId == currentActiveId || sIp == currentActiveId);
      servers[i]['is_selected'] = isAct;
      servers[i]['set_active'] = isAct;
    }

    cfg['servers'] = servers;
    return await saveConfig(cfg, userKey: _currentUserKey);
  }

  Future<bool> selectServer(ServerModel server) async {
    final cfg = await loadConfig();
    List<Map<String, dynamic>> servers = [];

    if (cfg['servers'] is List) {
      for (final item in (cfg['servers'] as List)) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          final isSel = (m['id'] == server.id || m['server_ip'] == server.serverIp);
          m['is_selected'] = isSel;
          m['set_active'] = isSel;
          servers.add(m);
        }
      }
    }

    cfg['servers'] = servers;
    cfg['active_server_id'] = server.id;
    cfg['server_ip'] = server.serverIp;
    cfg['ssh_user'] = server.sshUser;
    cfg['ssh_pass'] = server.sshPass;
    cfg['ssh_port'] = server.sshPort;
    cfg['ai_model'] = server.aiModel;
    cfg['remote_work_dir'] = server.remoteWorkDir;
    cfg['api_port'] = server.apiPort;
    cfg['secret_token'] = server.secretToken;

    return await saveConfig(cfg, userKey: _currentUserKey);
  }

  Future<bool> deleteServer(String serverIdOrIp) async {
    final cfg = await loadConfig();
    List<Map<String, dynamic>> servers = [];

    if (cfg['servers'] is List) {
      for (final item in (cfg['servers'] as List)) {
        if (item is Map) {
          servers.add(Map<String, dynamic>.from(item));
        }
      }
    }

    servers.removeWhere((item) =>
        item['id'] == serverIdOrIp || item['server_ip'] == serverIdOrIp);

    cfg['servers'] = servers;

    // If deleted server was active, switch active server to remaining server
    final activeId = cfg['active_server_id']?.toString();
    final wasActive = activeId == serverIdOrIp || cfg['server_ip'] == serverIdOrIp;

    if (wasActive) {
      if (servers.isNotEmpty) {
        final nextActive = servers.first;
        cfg['active_server_id'] = nextActive['id'];
        cfg['server_ip'] = nextActive['server_ip'];
        cfg['ssh_user'] = nextActive['ssh_user'];
        cfg['ssh_pass'] = nextActive['ssh_pass'];
        cfg['ssh_port'] = nextActive['ssh_port'];
        cfg['ai_model'] = nextActive['ai_model'];
        cfg['remote_work_dir'] = nextActive['remote_work_dir'];
        cfg['api_port'] = nextActive['api_port'];
        cfg['secret_token'] = nextActive['secret_token'];
      } else {
        cfg['active_server_id'] = '';
        cfg['server_ip'] = '';
        cfg['ssh_user'] = 'root';
        cfg['ssh_pass'] = '';
        cfg['ssh_port'] = 22;
      }
    }

    return await saveConfig(cfg, userKey: _currentUserKey);
  }
}
