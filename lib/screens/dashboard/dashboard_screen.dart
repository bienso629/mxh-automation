import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/metrics_provider.dart';
import '../../providers/server_provider.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final metricsProvider = context.watch<MetricsProvider>();
    final serverProvider = context.watch<ServerProvider>();
    final m = metricsProvider.metrics;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Giám Sát Hệ Thống', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              serverProvider.selectedServer != null
                  ? '${serverProvider.selectedServer!.name} (${serverProvider.selectedServer!.serverIp})'
                  : 'Chưa kết nối máy chủ',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: metricsProvider.isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Làm mới',
            onPressed: () => metricsProvider.fetchMetrics(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => metricsProvider.fetchMetrics(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Server Summary Card
              _buildServerSummaryCard(context, m, serverProvider),
              const SizedBox(height: 16),

              // 2. Metrics Gauge Cards (CPU, RAM, DISK)
              Row(
                children: [
                  Expanded(
                    child: _buildGaugeCard(
                      title: 'CPU Load',
                      valueStr: '${m.cpuPercent.toStringAsFixed(1)}%',
                      percent: m.cpuPercent / 100,
                      subtitle: m.loadAvg,
                      color: AppColors.primaryLight,
                      icon: Icons.memory,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildGaugeCard(
                      title: 'Bộ Nhớ RAM',
                      valueStr: '${m.ramPercent.toStringAsFixed(1)}%',
                      percent: m.ramPercent / 100,
                      subtitle: '${m.ramUsed} / ${m.ramTotal}',
                      color: AppColors.accent,
                      icon: Icons.storage_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildGaugeCard(
                      title: 'Ổ Cứng (Disk)',
                      valueStr: '${m.diskPercent}%',
                      percent: m.diskPercent / 100,
                      subtitle: '${m.diskUsed} / ${m.diskTotal}',
                      color: AppColors.warning,
                      icon: Icons.disc_full_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildGaugeCard(
                      title: 'Băng Thông Mạng',
                      valueStr: 'Rx: ${m.netRxSpeed}',
                      percent: (m.netPercent / 100).clamp(0.0, 1.0),
                      subtitle: 'Tx: ${m.netTxSpeed}',
                      color: AppColors.accentCyan,
                      icon: Icons.speed_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 3. Realtime Performance Line Chart
              _buildChartCard(context, metricsProvider),
              const SizedBox(height: 16),

              // 4. Managed Services Status
              _buildServicesCard(context, metricsProvider),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerSummaryCard(BuildContext context, dynamic m, ServerProvider serverProvider) {
    final isOnline = m.status == 'success' || m.serviceStatus == 'active';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.computer_rounded, color: AppColors.primaryLight, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        serverProvider.selectedServer?.name ?? 'Máy Chủ Linux',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        m.os.toString(),
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isOnline ? AppColors.accent : AppColors.danger).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isOnline ? AppColors.accent : AppColors.danger),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isOnline ? AppColors.accent : AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOnline ? 'ONLINE' : 'OFFLINE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isOnline ? AppColors.accent : AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildInfoItem('Thời gian chạy', m.uptime.toString()),
              _buildInfoItem('Số tiến trình', '${m.procs} procs'),
              _buildInfoItem('Lần đồng bộ', m.lastSync.toString()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textWhite)),
      ],
    );
  }

  Widget _buildGaugeCard({
    required String title,
    required String valueStr,
    required double percent,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    final clamped = percent.clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
              Icon(icon, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 10),
          Text(valueStr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: clamped,
              backgroundColor: AppColors.surfaceDark,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: AppColors.textDim),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(BuildContext context, MetricsProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Biểu Đồ Tài Nguyên Thời Gian Thực',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Icon(Icons.circle, size: 8, color: AppColors.primaryLight),
                  SizedBox(width: 4),
                  Text('CPU', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                  SizedBox(width: 10),
                  Icon(Icons.circle, size: 8, color: AppColors.accent),
                  SizedBox(width: 4),
                  Text('RAM', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 130,
            child: provider.cpuHistory.isEmpty
                ? const Center(child: Text('Đang thu thập dữ liệu...', style: TextStyle(color: AppColors.textDim)))
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.borderDark, strokeWidth: 0.5),
                      ),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      minY: 0,
                      maxY: 100,
                      lineBarsData: [
                        LineChartBarData(
                          spots: provider.cpuHistory,
                          isCurved: true,
                          color: AppColors.primaryLight,
                          barWidth: 2,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppColors.primaryLight.withValues(alpha: 0.1),
                          ),
                        ),
                        LineChartBarData(
                          spots: provider.ramHistory,
                          isCurved: true,
                          color: AppColors.accent,
                          barWidth: 2,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppColors.accent.withValues(alpha: 0.1),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesCard(BuildContext context, MetricsProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quản Lý Dịch Vụ Hệ Thống',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildServiceRow(context, 'Nginx Web Server', 'nginx', provider),
          const Divider(height: 16),
          _buildServiceRow(context, 'Docker Engine', 'docker', provider),
          const Divider(height: 16),
          _buildServiceRow(context, 'MySQL / MariaDB', 'mysql', provider),
          const Divider(height: 16),
          _buildServiceRow(context, 'Tadu AI Agent Service', 'ai-agent', provider),
        ],
      ),
    );
  }

  Widget _buildServiceRow(BuildContext context, String name, String serviceKey, MetricsProvider provider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Icon(Icons.dns_rounded, size: 16, color: AppColors.primaryLight),
            const SizedBox(width: 8),
            Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.restart_alt_rounded, size: 18, color: AppColors.warning),
              tooltip: 'Khởi động lại',
              onPressed: () async {
                final ok = await provider.restartService(serviceKey);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok ? 'Đã gửi lệnh khởi động lại $name' : 'Lỗi khởi động lại'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}
