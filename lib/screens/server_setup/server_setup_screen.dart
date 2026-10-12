import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/tadu_dialog.dart';
import '../../providers/metrics_provider.dart';
import '../../providers/server_provider.dart';

class ServerSetupScreen extends StatefulWidget {
  const ServerSetupScreen({super.key});

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  final ApiService _api = ApiService();
  bool _isPrivacyMode = true;
  bool _isDeploying = false;
  final List<String> _deployLogs = [];
  final ScrollController _deployScrollCtrl = ScrollController();
  StreamSubscription? _deploySub;

  @override
  void dispose() {
    _deploySub?.cancel();
    _deployScrollCtrl.dispose();
    super.dispose();
  }

  void _handleServiceAction(String action) async {
    final actionLabel = action == 'start'
        ? 'khởi động'
        : action == 'restart'
            ? 'khởi động lại'
            : action == 'stop'
                ? 'tắt'
                : 'kiểm tra chi tiết';
    AppToast.info(context, 'Đang gửi lệnh $actionLabel dịch vụ...');

    final res = await _api.executeServiceAction('ai-agent', action);
    final output = res['output']?.toString() ?? res['message']?.toString() ?? 'Không có phản hồi từ Sân khấu';
    final msg = res['message']?.toString() ?? output;

    if (action == 'status') {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => TaduDialog(
          minWidth: 640,
          maxWidth: 820,
          maxHeight: 520,
          title: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: AppColors.primaryLight, size: 22),
              SizedBox(width: 8),
              Text('Chi Tiết Trạng Thái Service & Tiến Trình'),
            ],
          ),
          content: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.terminalBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderDark),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                output,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.terminalGreen, height: 1.4),
              ),
            ),
          ),
          actions: [
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          ],
        ),
      );
    } else {
      if (mounted) {
        if (res['status'] == 'error') {
          AppToast.error(context, msg);
        } else {
          AppToast.success(context, msg);
        }
        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) {
          context.read<MetricsProvider>().fetchMetrics(silent: true);
        }
      }
    }
  }

  void _startDeploy() {
    if (_isDeploying) return;
    setState(() {
      _isDeploying = true;
      _deployLogs.clear();
      _deployLogs.add('⚡ Bắt đầu tự động thiết lập & Deploy Agent lên Sân khấu...');
    });

    _deploySub?.cancel();
    _deploySub = _api.streamDeploy(
      onStep: (step) {
        setState(() {
          _deployLogs.add(step);
        });
        if (_deployScrollCtrl.hasClients) {
          _deployScrollCtrl.animateTo(
            _deployScrollCtrl.position.maxScrollExtent + 40,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      },
      onDone: () {
        setState(() {
          _isDeploying = false;
          _deployLogs.add('✔ Quá trình thiết lập hoàn tất!');
        });
        context.read<MetricsProvider>().fetchMetrics();
      },
      onError: (err) {
        setState(() {
          _isDeploying = false;
          _deployLogs.add('❌ Lỗi thiết lập: $err');
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final metricsProvider = context.watch<MetricsProvider>();
    final serverProvider = context.watch<ServerProvider>();
    final m = metricsProvider.metrics;
    final s = serverProvider.selectedServer;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          // Topbar Header (Height 66px)
          Container(
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: const BoxDecoration(
              color: AppColors.bgDark,
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.dns_rounded, color: AppColors.primaryLight, size: 24),
                    SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quản Lý Sân Khấu & Dịch Vụ Systemd',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                        ),
                        Text(
                          'Triển khai code lên VPS/Server và giám sát tài nguyên thời gian thực',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.borderDark),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      icon: Icon(
                        Icons.shield_rounded,
                        size: 15,
                        color: _isPrivacyMode ? AppColors.accent : AppColors.textDim,
                      ),
                      label: Text(
                        _isPrivacyMode ? 'Bảo Mật: BẬT' : 'Bảo Mật: TẮT',
                        style: TextStyle(
                          fontSize: 12,
                          color: _isPrivacyMode ? AppColors.accent : AppColors.textDim,
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _isPrivacyMode = !_isPrivacyMode;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cardBg,
                        side: const BorderSide(color: AppColors.borderDark),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Cập nhật', style: TextStyle(fontSize: 12)),
                      onPressed: () => metricsProvider.fetchMetrics(),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Four Server Status Cards Grid
                  Row(
                    children: [
                      Expanded(
                        child: () {
                          final st = m.serviceStatus.toLowerCase().trim();
                          String label = 'Chưa bật';
                          Color color = AppColors.warning;
                          if (st == 'active') {
                            label = 'Đang chạy';
                            color = AppColors.accent;
                          } else if (st == 'failed') {
                            label = 'Bị lỗi (Failed)';
                            color = AppColors.danger;
                          } else if (st == 'activating') {
                            label = 'Đang bật...';
                            color = AppColors.warning;
                          } else if (st == 'deactivating') {
                            label = 'Đang tắt...';
                            color = AppColors.textDim;
                          }
                          return _buildStatusCard(
                            title: 'Trạng thái Service',
                            icon: Icons.shield_rounded,
                            iconColor: color,
                            value: label,
                            valueColor: color,
                            subtitle: 'ai-agent.service',
                            hasDot: true,
                          );
                        }(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatusCard(
                          title: 'Địa chỉ Sân Khấu',
                          icon: Icons.public_rounded,
                          iconColor: AppColors.accentCyan,
                          value: _isPrivacyMode ? '103.***.***.***' : (s?.serverIp ?? '127.0.0.1'),
                          valueColor: AppColors.textWhite,
                          subtitle: 'Cổng API: ${s?.apiPort ?? 8000}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatusCard(
                          title: 'Mô hình AI',
                          icon: Icons.memory_rounded,
                          iconColor: AppColors.primaryLight,
                          value: serverProvider.currentAiModel,
                          valueColor: AppColors.textWhite,
                          subtitle: 'Function Calling',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatusCard(
                          title: 'Thời gian chạy (Uptime)',
                          icon: Icons.schedule_rounded,
                          iconColor: AppColors.accent,
                          value: m.uptime,
                          valueColor: AppColors.textWhite,
                          subtitle: m.os,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 2. Service Action Buttons Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Điều Khiển Dịch Vụ AI Agent (Systemd)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Builder(
                          builder: (context) {
                            final isRunning = m.serviceStatus.toLowerCase().trim() == 'active';
                            if (!isRunning) {
                              return SizedBox(
                                width: 160,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF16A34A),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                                  label: const Text('Khởi Động', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  onPressed: () => _handleServiceAction('start'),
                                ),
                              );
                            }
                            return Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                SizedBox(
                                  width: 160,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.warning,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                    icon: const Icon(Icons.rotate_right_rounded, size: 16),
                                    label: const Text('Khởi Động Lại', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    onPressed: () => _handleServiceAction('restart'),
                                  ),
                                ),
                                SizedBox(
                                  width: 160,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.danger,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                    icon: const Icon(Icons.stop_rounded, size: 16),
                                    label: const Text('Tắt', style: TextStyle(fontSize: 12)),
                                    onPressed: () => _handleServiceAction('stop'),
                                  ),
                                ),
                                SizedBox(
                                  width: 160,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.inputBg,
                                      side: const BorderSide(color: AppColors.borderDark),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                    icon: const Icon(Icons.info_outline_rounded, size: 16),
                                    label: const Text('Chi Tiết Status', style: TextStyle(fontSize: 12)),
                                    onPressed: () => _handleServiceAction('status'),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. 1-Click Deploy Section
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.cloud_upload_rounded, size: 18, color: AppColors.accentCyan),
                                    SizedBox(width: 8),
                                    Text(
                                      '1-Click Deploy & Tự Động Thiết Lập Trọn Gói',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Tự động cài đặt nhị phân, cấu hình Systemd service và kết nối Agent trên VPS',
                                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                              icon: _isDeploying
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.rocket_launch_rounded, size: 16),
                              label: Text(_isDeploying ? 'Đang thiết lập...' : 'Bắt đầu thiết lập'),
                              onPressed: _isDeploying ? null : _startDeploy,
                            ),
                          ],
                        ),
                        if (_deployLogs.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Container(
                            height: 160,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.terminalBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.borderDark),
                            ),
                            child: ListView.builder(
                              controller: _deployScrollCtrl,
                              itemCount: _deployLogs.length,
                              itemBuilder: (context, idx) {
                                return Text(
                                  _deployLogs[idx],
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: AppColors.terminalGreen,
                                    height: 1.4,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4. Server Resource Metrics (CPU, RAM, DISK, NETWORK)
                  const Text(
                    'Tài Nguyên Sân Khấu Đám Mây',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // CPU Card
                      Expanded(
                        child: _buildMetricProgressCard(
                          title: 'Vi xử lý (CPU Usage)',
                          icon: Icons.memory_rounded,
                          iconColor: AppColors.warning,
                          badgeText: '${m.cpuPercent.toStringAsFixed(1)}%',
                          badgeColor: AppColors.warning,
                          labelLeft: 'Tải hệ thống (1m, 5m, 15m)',
                          labelRight: 'Load: ${m.loadAvg}',
                          percent: m.cpuPercent / 100,
                          progressColor: AppColors.warning,
                          footerLeft: 'Chế độ: On-Demand',
                          footerRight: '✔ Siêu nhẹ',
                        ),
                      ),
                      const SizedBox(width: 12),

                      // RAM Card
                      Expanded(
                        child: _buildMetricProgressCard(
                          title: 'Bộ nhớ RAM (Memory)',
                          icon: Icons.storage_rounded,
                          iconColor: AppColors.accent,
                          badgeText: '${m.ramPercent.toStringAsFixed(1)}%',
                          badgeColor: AppColors.accent,
                          labelLeft: 'Đã dùng / Tổng RAM',
                          labelRight: '${m.ramUsed} / ${m.ramTotal}',
                          percent: m.ramPercent / 100,
                          progressColor: AppColors.accent,
                          footerLeft: 'Khả dụng: ${m.ramAvail}',
                          footerRight: 'Bộ nhớ đệm: OK',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Disk Card
                      Expanded(
                        child: _buildMetricProgressCard(
                          title: 'Ổ đĩa hệ thống (Disk)',
                          icon: Icons.disc_full_rounded,
                          iconColor: AppColors.primaryLight,
                          badgeText: '${m.diskPercent}%',
                          badgeColor: AppColors.primaryLight,
                          labelLeft: 'Đã dùng / Tổng dung lượng',
                          labelRight: '${m.diskUsed} / ${m.diskTotal}',
                          percent: m.diskPercent / 100,
                          progressColor: AppColors.primaryLight,
                          footerLeft: 'Còn trống: ${m.diskAvail}',
                          footerRight: 'SSD NVMe',
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Network Card
                      Expanded(
                        child: _buildMetricProgressCard(
                          title: 'Băng thông mạng (Network I/O)',
                          icon: Icons.speed_rounded,
                          iconColor: AppColors.accentCyan,
                          badgeText: m.netRxSpeed,
                          badgeColor: AppColors.accentCyan,
                          labelLeft: 'Tải về (Rx) / Tải lên (Tx)',
                          labelRight: '${m.netRxSpeed} | ${m.netTxSpeed}',
                          percent: (m.netPercent / 100).clamp(0.0, 1.0),
                          progressColor: AppColors.accentCyan,
                          footerLeft: 'Tổng: ${m.netRxTotal}',
                          footerRight: 'Cổng 1Gbps',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String value,
    required Color valueColor,
    required String subtitle,
    bool hasDot = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (hasDot) ...[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(title, style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
                ],
              ),
              Icon(icon, size: 16, color: iconColor),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: valueColor),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
        ],
      ),
    );
  }

  Widget _buildMetricProgressCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String badgeText,
    required Color badgeColor,
    required String labelLeft,
    required String labelRight,
    required double percent,
    required Color progressColor,
    required String footerLeft,
    required String footerRight,
  }) {
    final clamped = percent.clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: iconColor),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(labelLeft, style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
              Text(labelRight, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textWhite)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: clamped,
              backgroundColor: AppColors.inputBg,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(footerLeft, style: const TextStyle(fontSize: 10, color: AppColors.textDim)),
              Text(footerRight, style: const TextStyle(fontSize: 10, color: AppColors.accent)),
            ],
          ),
        ],
      ),
    );
  }
}
