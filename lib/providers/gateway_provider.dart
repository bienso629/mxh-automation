import 'package:flutter/material.dart';
import '../core/services/api_service.dart';
import '../core/services/storage_service.dart';

enum GatewayStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class GatewayProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final ApiService _api = ApiService();

  String _gatewayUrl = 'http://127.0.0.1:8888';
  String _secretToken = '';
  GatewayStatus _status = GatewayStatus.disconnected;
  String _errorMessage = '';
  int _pingMs = 0;

  String get gatewayUrl => _gatewayUrl;
  String get secretToken => _secretToken;
  GatewayStatus get status => _status;
  String get errorMessage => _errorMessage;
  int get pingMs => _pingMs;
  bool get isConnected => _status == GatewayStatus.connected;

  GatewayProvider() {
    init();
  }

  Future<void> init() async {
    _gatewayUrl = await _storage.getGatewayUrl();
    _secretToken = await _storage.getSecretToken();
    notifyListeners();
    await testConnection();
  }

  Future<bool> setGatewayConfig(String url, String token) async {
    _gatewayUrl = url.trim();
    _secretToken = token.trim();
    await _storage.setGatewayUrl(_gatewayUrl);
    await _storage.setSecretToken(_secretToken);
    notifyListeners();
    return await testConnection();
  }

  Future<bool> testConnection() async {
    _status = GatewayStatus.connecting;
    _errorMessage = '';
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    try {
      final healthy = await _api.checkHealth();
      stopwatch.stop();

      if (healthy) {
        _status = GatewayStatus.connected;
        _pingMs = stopwatch.elapsedMilliseconds;
        notifyListeners();
        return true;
      } else {
        _status = GatewayStatus.error;
        _errorMessage = 'Không thể kết nối đến Gateway API';
        notifyListeners();
        return false;
      }
    } catch (e) {
      stopwatch.stop();
      _status = GatewayStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }
}
