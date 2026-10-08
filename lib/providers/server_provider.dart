import 'package:flutter/material.dart';
import '../core/services/api_service.dart';
import '../core/services/native_ssh_service.dart';
import '../core/services/storage_service.dart';
import '../models/server_model.dart';

import '../core/services/persona_service.dart';

class ServerProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();
  final NativeSshService _ssh = NativeSshService();
  final PersonaService _persona = PersonaService();

  List<ServerModel> _servers = [];
  ServerModel? _selectedServer;
  String _cloudAiModel = 'glm-5.3';
  List<String> _mitomModels = [];
  bool _isLoading = false;
  bool _isLoadingMitomModels = false;
  String? _error;
  final Map<String, List<String>> _serverIpsMap = {};
  final Set<String> _loadingIpsServerIds = {};

  List<ServerModel> get servers => _servers;
  ServerModel? get selectedServer => _selectedServer;
  String get globalAiModel => _cloudAiModel;
  String get cloudAiModel => _cloudAiModel;
  String get activeAgent => _cloudAiModel;
  List<String> get mitomModels => _mitomModels;
  bool get isLoadingMitomModels => _isLoadingMitomModels;
  Map<String, List<String>> get serverIpsMap => _serverIpsMap;

  List<String> getIpsForServer(ServerModel server) {
    final Set<String> ipSet = {};

    if (_serverIpsMap.containsKey(server.id)) {
      ipSet.addAll(_serverIpsMap[server.id]!);
    } else if (server.serverIp.isNotEmpty) {
      ipSet.add(server.serverIp);
    }

    // Kết hợp các IP của nhân vật (personas) thuộc dải IP của server này
    final allPersonas = _persona.allPersonas;
    final serverPrefix = server.serverIp.contains('.')
        ? server.serverIp.substring(0, server.serverIp.lastIndexOf('.'))
        : '';

    for (final personaIp in allPersonas.keys) {
      if (personaIp == server.serverIp) {
        ipSet.add(personaIp);
      } else if (serverPrefix.isNotEmpty && personaIp.startsWith('$serverPrefix.')) {
        ipSet.add(personaIp);
      } else if (server.serverIp.startsWith('103.74.116.') && personaIp.startsWith('103.74.117.')) {
        // Cùng cụm IP dải Server 100
        ipSet.add(personaIp);
      }
    }

    return ipSet.toList();
  }

  bool isLoadingIps(String serverId) => _loadingIpsServerIds.contains(serverId);

  String get currentAiModel {
    if (_cloudAiModel.isNotEmpty) {
      return _cloudAiModel;
    }
    if (_selectedServer != null && _selectedServer!.aiModel.isNotEmpty) {
      return _selectedServer!.aiModel;
    }
    return 'glm-5.3';
  }

  bool get isLoading => _isLoading;
  String? get error => _error;

  ServerProvider() {
    loadServers();
    loadGlobalConfig();
    fetchMitomModels();
  }

  Future<void> fetchMitomModels({bool forceRefresh = false}) async {
    if (_mitomModels.isNotEmpty && !forceRefresh) return;
    _isLoadingMitomModels = true;
    notifyListeners();

    try {
      final list = await _api.fetchMitomModels();
      if (list.isNotEmpty) {
        _mitomModels = list;
      }
    } catch (_) {} finally {
      _isLoadingMitomModels = false;
      notifyListeners();
    }
  }

  Future<void> loadGlobalConfig() async {
    try {
      final cfg = await _api.getConfig();
      if (cfg['ai_model'] != null && cfg['ai_model'].toString().isNotEmpty) {
        _cloudAiModel = cfg['ai_model'].toString();
      } else if (cfg['active_agent_engine'] != null && cfg['active_agent_engine'].toString().isNotEmpty) {
        _cloudAiModel = cfg['active_agent_engine'].toString();
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setActiveAgent(String agent) async {
    if (agent.isEmpty) return;
    await setCloudAiModel(agent);
  }

  Future<void> setCloudAiModel(String model) async {
    if (model.isNotEmpty) {
      _cloudAiModel = model;
      notifyListeners();
      try {
        await _storage.setDefaultModel(model);
        await _api.saveConfig({
          'ai_model': model,
          'engine_mode': 'cloud',
          'active_agent_engine': model,
        });
      } catch (_) {}
    }
  }

  void setGlobalAiModel(String model) {
    setCloudAiModel(model);
  }

  Future<void> loadServers() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final list = await _api.getServers();
      final savedId = await _storage.getActiveServerId();
      if (list.isNotEmpty) {
        if (savedId != null && savedId.isNotEmpty) {
          _selectedServer = list.firstWhere(
            (s) => s.id == savedId || s.serverIp == savedId,
            orElse: () => list.firstWhere((s) => s.isSelected, orElse: () => list.first),
          );
        } else {
          _selectedServer = list.firstWhere((s) => s.isSelected, orElse: () => list.first);
        }
        _servers = list.map((s) => s.copyWith(isSelected: s.id == _selectedServer!.id)).toList();
      } else {
        _servers = [];
        _selectedServer = null;
      }
      await loadGlobalConfig();
      try {
        await _persona.loadSavedPersonas();
      } catch (_) {}
      // Asynchronously fetch pointing IPs for all servers
      _fetchServerIpsForAll();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _fetchServerIpsForAll() {
    for (final server in _servers) {
      fetchIpsForServer(server);
    }
  }

  Future<void> fetchIpsForServer(ServerModel server, {bool force = false}) async {
    if (!force && _serverIpsMap.containsKey(server.id) && _serverIpsMap[server.id]!.isNotEmpty) {
      return;
    }
    if (_loadingIpsServerIds.contains(server.id)) return;

    _loadingIpsServerIds.add(server.id);
    notifyListeners();

    try {
      final ips = await _ssh.getServerIps(
        host: server.serverIp,
        port: server.sshPort,
        user: server.sshUser,
        pass: server.sshPass,
        key: server.sshKey,
      );
      if (ips.isNotEmpty) {
        _serverIpsMap[server.id] = ips;
      } else if (server.serverIp.isNotEmpty) {
        _serverIpsMap[server.id] = [server.serverIp];
      }
    } catch (_) {
      if (server.serverIp.isNotEmpty) {
        _serverIpsMap[server.id] = [server.serverIp];
      }
    } finally {
      _loadingIpsServerIds.remove(server.id);
      notifyListeners();
    }
  }

  Future<bool> selectServer(ServerModel server) async {
    _selectedServer = server;
    await _storage.setActiveServerId(server.id);
    notifyListeners();

    try {
      final ok = await _api.selectServer(server.serverIp);
      if (ok) {
        await loadServers();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> addOrUpdateServer(ServerModel server) async {
    try {
      final ok = await _api.updateServer(server);
      if (ok) {
        await loadServers();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteServer(String serverIp) async {
    try {
      final ok = await _api.deleteServer(serverIp);
      if (ok) {
        await loadServers();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }
}
