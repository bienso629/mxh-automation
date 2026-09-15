class SystemMetricsModel {
  final String status;
  final String uptime;
  final int uptimeSeconds;
  final String os;
  final String serverIp;
  final String serviceStatus; // 'active' | 'inactive'
  
  // CPU / Loadavg
  final String loadAvg;
  final double cpuPercent;
  final String procs;

  // RAM
  final String ramTotal;
  final String ramUsed;
  final String ramAvail;
  final double ramPercent;
  final int ramTotalMb;
  final int ramUsedMb;

  // Disk
  final String diskTotal;
  final String diskUsed;
  final String diskAvail;
  final int diskPercent;

  // Network
  final String netRxSpeed;
  final String netTxSpeed;
  final String netRxTotal;
  final String netTxTotal;
  final double netPercent;

  final String lastSync;

  SystemMetricsModel({
    this.status = 'unknown',
    this.uptime = '--',
    this.uptimeSeconds = 0,
    this.os = 'Linux',
    this.serverIp = '',
    this.serviceStatus = 'inactive',
    this.loadAvg = '0.00 0.00 0.00',
    this.cpuPercent = 0.0,
    this.procs = '0',
    this.ramTotal = '0 GB',
    this.ramUsed = '0 MB',
    this.ramAvail = '0 GB',
    this.ramPercent = 0.0,
    this.ramTotalMb = 0,
    this.ramUsedMb = 0,
    this.diskTotal = '0 GB',
    this.diskUsed = '0 GB',
    this.diskAvail = '0 GB',
    this.diskPercent = 0,
    this.netRxSpeed = '0 KB/s',
    this.netTxSpeed = '0 KB/s',
    this.netRxTotal = '0 MB',
    this.netTxTotal = '0 MB',
    this.netPercent = 0.0,
    this.lastSync = '--:--',
  });

  factory SystemMetricsModel.fromJson(Map<String, dynamic> json) {
    final metrics = (json['metrics'] as Map<String, dynamic>?) ?? {};
    
    // Calculate pseudo CPU% from 1-min load average if not explicitly given
    final loadStr = metrics['loadavg']?.toString() ?? json['loadavg']?.toString() ?? '0.00';
    double calcCpu = 0.0;
    final loadParts = loadStr.split(' ');
    if (loadParts.isNotEmpty) {
      final firstLoad = double.tryParse(loadParts[0]) ?? 0.0;
      calcCpu = (firstLoad * 25.0).clamp(0.0, 100.0); // estimated rough CPU load
    }

    return SystemMetricsModel(
      status: json['status']?.toString() ?? 'success',
      uptime: json['uptime']?.toString() ?? '--',
      uptimeSeconds: int.tryParse(metrics['uptime_seconds']?.toString() ?? '0') ?? 0,
      os: json['os']?.toString() ?? 'Linux',
      serverIp: json['server_ip']?.toString() ?? '',
      serviceStatus: json['service_status']?.toString() ?? json['service_active']?.toString() ?? 'inactive',
      loadAvg: loadStr,
      cpuPercent: calcCpu,
      procs: metrics['procs']?.toString() ?? '0',
      ramTotal: metrics['ram_total']?.toString() ?? '0 GB',
      ramUsed: metrics['ram_used']?.toString() ?? '0 MB',
      ramAvail: metrics['ram_avail']?.toString() ?? '0 GB',
      ramPercent: (metrics['ram_percent'] is num) ? (metrics['ram_percent'] as num).toDouble() : (double.tryParse(metrics['ram_percent']?.toString() ?? '0') ?? 0.0),
      ramTotalMb: int.tryParse(metrics['ram_total_mb']?.toString() ?? '0') ?? 0,
      ramUsedMb: int.tryParse(metrics['ram_used_mb']?.toString() ?? '0') ?? 0,
      diskTotal: metrics['disk_total']?.toString() ?? '0 GB',
      diskUsed: metrics['disk_used']?.toString() ?? '0 GB',
      diskAvail: metrics['disk_avail']?.toString() ?? '0 GB',
      diskPercent: int.tryParse(metrics['disk_percent']?.toString() ?? '0') ?? 0,
      netRxSpeed: metrics['net_rx_kbs']?.toString() ?? '0 KB/s',
      netTxSpeed: metrics['net_tx_kbs']?.toString() ?? '0 KB/s',
      netRxTotal: metrics['net_rx_total']?.toString() ?? '0 MB',
      netTxTotal: metrics['net_tx_total']?.toString() ?? '0 MB',
      netPercent: (metrics['net_percent'] is num) ? (metrics['net_percent'] as num).toDouble() : 0.0,
      lastSync: json['last_sync']?.toString() ?? metrics['last_sync']?.toString() ?? DateTime.now().toString().substring(11, 16),
    );
  }
}
