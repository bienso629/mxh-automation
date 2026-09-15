import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/services/api_service.dart';
import '../models/metrics_model.dart';

class MetricsProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  SystemMetricsModel _metrics = SystemMetricsModel();
  bool _isLoading = false;
  String? _error;
  Timer? _timer;

  // Real-time History for Charts (max 15 points)
  final List<FlSpot> _cpuHistory = [];
  final List<FlSpot> _ramHistory = [];
  int _pointIndex = 0;

  SystemMetricsModel get metrics => _metrics;
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<FlSpot> get cpuHistory => _cpuHistory;
  List<FlSpot> get ramHistory => _ramHistory;

  MetricsProvider() {
    fetchMetrics();
  }

  void startPolling() {
    _timer?.cancel();
    _timer = null;
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> fetchMetrics({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }

    try {
      final data = await _api.getSystemMetrics();
      _metrics = data;
      _error = null;

      // Update Chart History
      _pointIndex++;
      _cpuHistory.add(FlSpot(_pointIndex.toDouble(), data.cpuPercent));
      _ramHistory.add(FlSpot(_pointIndex.toDouble(), data.ramPercent));

      if (_cpuHistory.length > 15) _cpuHistory.removeAt(0);
      if (_ramHistory.length > 15) _ramHistory.removeAt(0);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> restartService(String service) async {
    try {
      final res = await _api.executeServiceAction(service, 'restart');
      final ok = res['status'] == 'success' || res['status'] == 'ok';
      if (ok) {
        await Future.delayed(const Duration(seconds: 1));
        await fetchMetrics(silent: true);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
