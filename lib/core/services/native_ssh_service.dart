import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../../models/metrics_model.dart';
import 'local_config_service.dart';

class NativeSshService {
  static final NativeSshService _instance = NativeSshService._internal();
  factory NativeSshService() => _instance;
  NativeSshService._internal();

  final LocalConfigService _configService = LocalConfigService();

  Future<SSHClient> getClient({Map<String, dynamic>? overrideConfig}) async {
    final cfg = overrideConfig ?? await _configService.loadConfig();
    final host = cfg['server_ip']?.toString() ?? '127.0.0.1';
    final port = int.tryParse(cfg['ssh_port']?.toString() ?? '22') ?? 22;
    final user = cfg['ssh_user']?.toString() ?? 'root';
    final pass = cfg['ssh_pass']?.toString() ?? '';
    final key = cfg['ssh_key']?.toString();

    final socket = await SSHSocket.connect(host, port, timeout: const Duration(seconds: 10));
    return SSHClient(
      socket,
      username: user,
      onPasswordRequest: () => pass,
      identities: (key != null && key.isNotEmpty)
          ? SSHKeyPair.fromPem(key)
          : null,
    );
  }

  Future<bool> testConnection({
    String? host,
    int? port,
    String? user,
    String? pass,
    String? key,
  }) async {
    try {
      final cfg = await _configService.loadConfig();
      final targetHost = host ?? cfg['server_ip']?.toString() ?? '127.0.0.1';
      final targetPort = port ?? int.tryParse(cfg['ssh_port']?.toString() ?? '22') ?? 22;
      final targetUser = user ?? cfg['ssh_user']?.toString() ?? 'root';
      final targetPass = pass ?? cfg['ssh_pass']?.toString() ?? '';

      final socket = await SSHSocket.connect(targetHost, targetPort, timeout: const Duration(seconds: 7));
      final client = SSHClient(
        socket,
        username: targetUser,
        onPasswordRequest: () => targetPass,
        identities: (key != null && key.isNotEmpty) ? SSHKeyPair.fromPem(key) : null,
      );
      await client.authenticated;
      client.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Kiểm tra trạng thái dịch vụ multi-ip-socks5.service trên máy chủ
  Future<bool> getMultiIpSocks5Status({
    required String host,
    required int port,
    required String user,
    required String pass,
    String? key,
  }) async {
    try {
      final socket = await SSHSocket.connect(host, port, timeout: const Duration(seconds: 7));
      final client = SSHClient(
        socket,
        username: user,
        onPasswordRequest: () => pass,
        identities: (key != null && key.isNotEmpty) ? SSHKeyPair.fromPem(key) : null,
      );
      await client.authenticated;
      final res = await client.run("systemctl is-active multi-ip-socks5.service 2>/dev/null").timeout(const Duration(seconds: 6));
      client.close();
      final status = utf8.decode(res).trim();
      return status == 'active';
    } catch (_) {
      return false;
    }
  }

  /// Bật / Tắt dịch vụ multi-ip-socks5.service trên máy chủ
  Future<bool> toggleMultiIpSocks5Service({
    required String host,
    required int port,
    required String user,
    required String pass,
    required bool enable,
    String? key,
  }) async {
    try {
      final socket = await SSHSocket.connect(host, port, timeout: const Duration(seconds: 8));
      final client = SSHClient(
        socket,
        username: user,
        onPasswordRequest: () => pass,
        identities: (key != null && key.isNotEmpty) ? SSHKeyPair.fromPem(key) : null,
      );
      await client.authenticated;

      if (enable) {
        // Nếu enable, đảm bảo script và file unit đã tồn tại, sau đó enable và start
        const installCmd = '''
if [ ! -f /usr/local/bin/multi_ip_socks5.py ]; then
cat << 'EOF' > /usr/local/bin/multi_ip_socks5.py
#!/usr/bin/env python3
import asyncio
import struct
import socket
import sys

def get_all_ips():
    import subprocess
    cmd = "ip -4 -o addr show scope global 2>/dev/null | awk '{print \$4}' | cut -d/ -f1"
    out = subprocess.check_output(cmd, shell=True).decode()
    return [line.strip() for line in out.splitlines() if line.strip()]

async def handle_socks5(reader, writer, bind_ip):
    try:
        ver, nmethods = await reader.readexactly(2)
        methods = await reader.readexactly(nmethods)
        writer.write(bytes([0x05, 0x00]))
        await writer.drain()

        ver, cmd, rsv, atyp = await reader.readexactly(4)
        if cmd != 1:
            writer.close()
            return

        if atyp == 1:
            dst_ip = socket.inet_ntoa(await reader.readexactly(4))
        elif atyp == 3:
            domain_len = (await reader.readexactly(1))[0]
            dst_ip = (await reader.readexactly(domain_len)).decode()
        elif atyp == 4:
            dst_ip = socket.inet_ntop(socket.AF_INET6, await reader.readexactly(16))
        else:
            writer.close()
            return
        dst_port = struct.unpack('>H', await reader.readexactly(2))[0]

        try:
            remote_reader, remote_writer = await asyncio.wait_for(
                asyncio.open_connection(dst_ip, dst_port, local_addr=(bind_ip, 0)),
                timeout=15
            )
        except Exception:
            writer.write(bytes([0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0]))
            await writer.drain()
            writer.close()
            return

        bind_addr = remote_writer.get_extra_info('sockname')
        bind_ip_raw = socket.inet_aton(bind_addr[0])
        bind_port_raw = struct.pack('>H', bind_addr[1])
        writer.write(bytes([0x05, 0x00, 0x00, 0x01]) + bind_ip_raw + bind_port_raw)
        await writer.drain()

        async def forward(src, dst):
            try:
                while True:
                    data = await src.read(65536)
                    if not data:
                        break
                    dst.write(data)
                    await dst.drain()
            except Exception:
                pass
            finally:
                try:
                    dst.close()
                except Exception:
                    pass

        await asyncio.gather(forward(reader, remote_writer), forward(remote_reader, writer))
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass

def ip_to_port(ip):
    parts = [int(p) for p in ip.split('.')]
    return 20000 + (parts[2] * 256 + parts[3]) % 10000

async def main():
    ips = get_all_ips()
    servers = []
    for ip in ips:
        port = ip_to_port(ip)
        srv = await asyncio.start_server(
            lambda r, w, target_ip=ip: handle_socks5(r, w, target_ip),
            '127.0.0.1',
            port
        )
        servers.append(srv)
    await asyncio.gather(*(srv.serve_forever() for srv in servers))

if __name__ == '__main__':
    asyncio.run(main())
EOF
chmod +x /usr/local/bin/multi_ip_socks5.py
fi

if [ ! -f /etc/systemd/system/multi-ip-socks5.service ]; then
cat << 'EOF' > /etc/systemd/system/multi-ip-socks5.service
[Unit]
Description=Multi-IP SOCKS5 Proxy Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/multi_ip_socks5.py
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
fi
systemctl enable --now multi-ip-socks5.service
''';
        await client.run(installCmd).timeout(const Duration(seconds: 15));
      } else {
        // Tắt và vô hiệu hóa service
        await client.run("systemctl stop multi-ip-socks5.service; systemctl disable multi-ip-socks5.service").timeout(const Duration(seconds: 10));
      }

      // Kiểm tra lại trạng thái sau khi thao tác
      final checkRes = await client.run("systemctl is-active multi-ip-socks5.service 2>/dev/null").timeout(const Duration(seconds: 5));
      client.close();
      final status = utf8.decode(checkRes).trim();
      return enable ? (status == 'active') : (status != 'active');
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> getServerIps({
    String? host,
    int? port,
    String? user,
    String? pass,
    String? key,
  }) async {
    try {
      final cfg = await _configService.loadConfig();
      final targetHost = host ?? cfg['server_ip']?.toString() ?? '127.0.0.1';
      final targetPort = port ?? int.tryParse(cfg['ssh_port']?.toString() ?? '22') ?? 22;
      final targetUser = user ?? cfg['ssh_user']?.toString() ?? 'root';
      final targetPass = pass ?? cfg['ssh_pass']?.toString() ?? '';

      final socket = await SSHSocket.connect(targetHost, targetPort, timeout: const Duration(seconds: 7));
      final client = SSHClient(
        socket,
        username: targetUser,
        onPasswordRequest: () => targetPass,
        identities: (key != null && key.isNotEmpty) ? SSHKeyPair.fromPem(key) : null,
      );
      await client.authenticated;

      final res = await client.run(
        r"ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1"
      ).timeout(const Duration(seconds: 8));
      client.close();

      final output = utf8.decode(res).trim();
      final Set<String> ipSet = {};
      if (targetHost.isNotEmpty && targetHost != '127.0.0.1' && targetHost != 'localhost') {
        ipSet.add(targetHost);
      }
      for (final line in output.split('\n')) {
        final clean = line.trim();
        if (clean.isNotEmpty &&
            !clean.startsWith('127.') &&
            !clean.startsWith('172.17.') &&
            !clean.startsWith('172.18.') &&
            !clean.startsWith('172.19.') &&
            !clean.startsWith('172.20.')) {
          ipSet.add(clean);
        }
      }
      return ipSet.toList();
    } catch (_) {
      final fallback = (host != null && host.isNotEmpty) ? [host] : <String>[];
      return fallback;
    }
  }

  Future<String> executeCommand(String command, {String? workingDir, int timeoutSeconds = 60}) async {
    try {
      final client = await getClient();
      String fullCmd = command;
      if (workingDir != null && workingDir.isNotEmpty) {
        fullCmd = 'cd "$workingDir" 2>/dev/null; $command';
      }
      final result = await client.run(fullCmd).timeout(Duration(seconds: timeoutSeconds));
      client.close();
      final output = utf8.decode(result).trim();
      return output.isNotEmpty ? output : 'Lệnh chạy thành công, không có output.';
    } catch (e) {
      return 'Lỗi thực thi lệnh: $e';
    }
  }

  Future<SystemMetricsModel> getSystemMetrics() async {
    final cfg = await _configService.loadConfig();
    final serverIp = cfg['server_ip']?.toString() ?? '127.0.0.1';
    final apiPort = int.tryParse(cfg['api_port']?.toString() ?? '8000') ?? 8000;

    try {
      final client = await getClient();
      final result = await client.run(
        "cat /proc/uptime 2>/dev/null; echo '---'; "
        "cat /proc/loadavg 2>/dev/null; echo '---'; "
        "free -m 2>/dev/null; echo '---'; "
        "df -h / 2>/dev/null; echo '---'; "
        "ps -e | wc -l 2>/dev/null; echo '---'; "
        "(systemctl is-active ai-agent.service 2>/dev/null || "
        "(export XDG_RUNTIME_DIR=/run/user/\$(id -u); export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus; systemctl --user is-active ai-agent.service 2>/dev/null) || "
        "(curl -s -m 2 http://127.0.0.1:$apiPort/health >/dev/null 2>&1 && echo 'active') || "
        "(fuser $apiPort/tcp >/dev/null 2>&1 && echo 'active') || "
        "(pgrep -f ai_agent_service >/dev/null 2>&1 && echo 'active') || "
        "systemctl is-failed ai-agent.service 2>/dev/null || "
        "echo 'inactive'); echo '---'; "
        "cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' 2>/dev/null || uname -s; echo '---'; "
        "cat /proc/net/dev 2>/dev/null"
      ).timeout(const Duration(seconds: 10));
      client.close();

      final output = utf8.decode(result);
      final parts = output.split('---');

      final uptimeRaw = parts.isNotEmpty ? parts[0].trim() : '';
      final loadavgRaw = parts.length > 1 ? parts[1].trim() : '';
      final freeRaw = parts.length > 2 ? parts[2].trim() : '';
      final dfRaw = parts.length > 3 ? parts[3].trim() : '';
      final procsRaw = parts.length > 4 ? parts[4].trim() : '';
      final serviceStatus = parts.length > 5 ? parts[5].trim() : 'inactive';
      final osName = parts.length > 6 ? parts[6].trim() : 'Linux';

      // Parse Disk
      String diskTotal = '40 GB';
      String diskUsed = '20 GB';
      String diskAvail = '20 GB';
      int diskPercent = 50;

      final dfLines = dfRaw.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (dfLines.length >= 2) {
        final cols = dfLines.last.split(RegExp(r'\s+'));
        if (cols.length >= 5) {
          diskTotal = cols[1];
          diskUsed = cols[2];
          diskAvail = cols[3];
          diskPercent = int.tryParse(cols[4].replaceAll('%', '')) ?? 50;
        }
      }

      // Parse RAM
      String ramTotal = '2.0 GB';
      String ramUsed = '1.0 GB';
      String ramAvail = '1.0 GB';
      double ramPercent = 50.0;
      int ramTotalMb = 2048;
      int ramUsedMb = 1024;
      int ramAvailMb = 1024;

      final freeLines = freeRaw.split('\n').where((l) => l.trim().isNotEmpty).toList();
      for (final line in freeLines) {
        if (line.startsWith('Mem:')) {
          final cols = line.split(RegExp(r'\s+'));
          if (cols.length >= 7) {
            ramTotalMb = int.tryParse(cols[1]) ?? 2048;
            ramUsedMb = int.tryParse(cols[2]) ?? 1024;
            ramAvailMb = int.tryParse(cols[6]) ?? (ramTotalMb - ramUsedMb);
            ramPercent = (ramUsedMb / ramTotalMb) * 100.0;
            ramTotal = '${(ramTotalMb / 1024).toStringAsFixed(1)} GB';
            ramUsed = '${(ramUsedMb / 1024).toStringAsFixed(1)} GB';
            ramAvail = '${(ramAvailMb / 1024).toStringAsFixed(1)} GB';
          }
        }
      }

      // Parse Uptime
      String uptimeHuman = '0h 0m';
      int uptimeSeconds = 0;
      if (uptimeRaw.isNotEmpty) {
        final sec = double.tryParse(uptimeRaw.split(' ').first) ?? 0.0;
        uptimeSeconds = sec.toInt();
        final days = uptimeSeconds ~/ 86400;
        final hours = (uptimeSeconds % 86400) ~/ 3600;
        final mins = (uptimeSeconds % 3600) ~/ 60;
        if (days > 0) {
          uptimeHuman = '${days}d ${hours}h ${mins}m';
        } else {
          uptimeHuman = '${hours}h ${mins}m';
        }
      }

      final now = DateTime.now();
      final lastSync = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      double calcCpu = 0.0;
      final loadParts = loadavgRaw.split(' ');
      if (loadParts.isNotEmpty) {
        final firstLoad = double.tryParse(loadParts[0]) ?? 0.0;
        calcCpu = (firstLoad * 25.0).clamp(0.0, 100.0);
      }

      return SystemMetricsModel(
        status: 'online',
        uptime: uptimeHuman,
        uptimeSeconds: uptimeSeconds,
        os: osName,
        serverIp: serverIp,
        serviceStatus: serviceStatus,
        loadAvg: loadavgRaw,
        cpuPercent: calcCpu,
        procs: procsRaw,
        ramTotal: ramTotal,
        ramUsed: ramUsed,
        ramAvail: ramAvail,
        ramPercent: ramPercent,
        ramTotalMb: ramTotalMb,
        ramUsedMb: ramUsedMb,
        diskTotal: diskTotal,
        diskUsed: diskUsed,
        diskAvail: diskAvail,
        diskPercent: diskPercent,
        netRxSpeed: '0 KB/s',
        netTxSpeed: '0 KB/s',
        netRxTotal: '0 MB',
        netTxTotal: '0 MB',
        netPercent: 10.0,
        lastSync: lastSync,
      );
    } catch (e) {
      return SystemMetricsModel(
        status: 'offline',
        uptime: 'Offline',
        uptimeSeconds: 0,
        os: 'Linux (Offline)',
        serverIp: serverIp,
        serviceStatus: 'inactive',
        loadAvg: '0.00 0.00 0.00',
        cpuPercent: 0.0,
        procs: '0',
        ramTotal: '0 GB',
        ramUsed: '0 MB',
        ramAvail: '0 GB',
        ramPercent: 0.0,
        ramTotalMb: 0,
        ramUsedMb: 0,
        diskTotal: '0 GB',
        diskUsed: '0 GB',
        diskAvail: '0 GB',
        diskPercent: 0,
        netRxSpeed: '0 KB/s',
        netTxSpeed: '0 KB/s',
        netRxTotal: '0 MB',
        netTxTotal: '0 MB',
        netPercent: 0.0,
        lastSync: 'N/A',
      );
    }
  }

  Future<String> getServerLogs({int lines = 100}) async {
    try {
      final client = await getClient();
      final res = await client.run(
        "journalctl -u ai-agent.service -n $lines --no-pager 2>/dev/null || "
        "tail -n $lines /var/log/syslog 2>/dev/null || "
        "dmesg | tail -n $lines"
      );
      client.close();
      final logStr = utf8.decode(res).trim();
      return logStr.isNotEmpty ? logStr : 'Không tìm thấy nhật ký hệ thống.';
    } catch (e) {
      return 'Lỗi tải log SSH: $e';
    }
  }

  Future<Map<String, dynamic>> executeServiceAction(String service, String action) async {
    try {
      final cfg = await _configService.loadConfig();
      final apiPort = int.tryParse(cfg['api_port']?.toString() ?? '8000') ?? 8000;
      final remoteDir = cfg['remote_work_dir']?.toString() ?? '/opt/ai_agent';
      final proxyKey = cfg['proxy_api_key']?.toString() ?? '';
      final proxyBase = cfg['proxy_base_url']?.toString() ?? 'https://api-us-ca.umodelverse.ai/v1';
      final aiModel = cfg['ai_model']?.toString() ?? 'glm-5.3';
      final secretToken = cfg['secret_token']?.toString() ?? 'super_secret_token_123';

      final client = await getClient();
      String cmd;
      String friendlyMsg;

      switch (action) {
        case 'start':
          cmd = '''
sudo systemctl daemon-reload 2>/dev/null || true
(sudo systemctl enable --now $service.service 2>&1 || sudo systemctl start $service.service 2>&1 || (export XDG_RUNTIME_DIR=/run/user/\$(id -u); export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus; systemctl --user enable --now $service.service 2>&1 || systemctl --user start $service.service 2>&1) || true)
sleep 1
if ! (systemctl is-active $service.service >/dev/null 2>&1 || pgrep -f ai_agent_service >/dev/null 2>&1 || fuser $apiPort/tcp >/dev/null 2>&1); then
  if [ -f "$remoteDir/ai_agent_service" ]; then
    nohup env AGENT_PORT=$apiPort PORT=$apiPort PROXY_API_KEY="$proxyKey" OPENROUTER_API_KEY="$proxyKey" PROXY_BASE_URL="$proxyBase" OPENROUTER_BASE_URL="$proxyBase" AI_MODEL="$aiModel" SECRET_TOKEN="$secretToken" AGENT_SECRET_TOKEN="$secretToken" $remoteDir/ai_agent_service > $remoteDir/agent.log 2>&1 &
    sleep 1
  fi
fi
systemctl status $service.service --no-pager 2>&1 || ps aux | grep -E '[a]i_agent_service|[u]vicorn' || true
''';
          friendlyMsg = 'Đã gửi lệnh khởi động dịch vụ $service thành công';
          break;

        case 'restart':
          cmd = '''
sudo systemctl daemon-reload 2>/dev/null || true
(sudo systemctl restart $service.service 2>&1 || (export XDG_RUNTIME_DIR=/run/user/\$(id -u); export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus; systemctl --user restart $service.service 2>&1) || true)
sleep 1
if ! (systemctl is-active $service.service >/dev/null 2>&1 || pgrep -f ai_agent_service >/dev/null 2>&1 || fuser $apiPort/tcp >/dev/null 2>&1); then
  fuser -k -9 $apiPort/tcp 2>/dev/null || pkill -9 -f ai_agent_service 2>/dev/null || true
  if [ -f "$remoteDir/ai_agent_service" ]; then
    nohup env AGENT_PORT=$apiPort PORT=$apiPort PROXY_API_KEY="$proxyKey" OPENROUTER_API_KEY="$proxyKey" PROXY_BASE_URL="$proxyBase" OPENROUTER_BASE_URL="$proxyBase" AI_MODEL="$aiModel" SECRET_TOKEN="$secretToken" AGENT_SECRET_TOKEN="$secretToken" $remoteDir/ai_agent_service > $remoteDir/agent.log 2>&1 &
    sleep 1
  fi
fi
systemctl status $service.service --no-pager 2>&1 || ps aux | grep -E '[a]i_agent_service|[u]vicorn' || true
''';
          friendlyMsg = 'Đã gửi lệnh khởi động lại dịch vụ $service thành công';
          break;

        case 'stop':
          cmd = '''
(sudo systemctl stop $service.service 2>&1 || (export XDG_RUNTIME_DIR=/run/user/\$(id -u); export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus; systemctl --user stop $service.service 2>&1) || true)
fuser -k -9 $apiPort/tcp 2>/dev/null || pkill -9 -f ai_agent_service 2>/dev/null || true
echo "Dịch vụ $service đã được dừng."
''';
          friendlyMsg = 'Đã dừng dịch vụ $service thành công';
          break;

        case 'status':
        default:
          cmd = '''
echo "======================================================="
echo "● 1. SYSTEMD SERVICE STATUS ($service.service)"
echo "======================================================="
systemctl status $service.service --no-pager 2>&1 || (export XDG_RUNTIME_DIR=/run/user/\$(id -u); export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus; systemctl --user status $service.service --no-pager 2>&1) || echo "Chưa tìm thấy systemd service file."

echo ""
echo "======================================================="
echo "● 2. HTTP HEALTH CHECK (Port: $apiPort)"
echo "======================================================="
curl -s -m 3 -i http://127.0.0.1:$apiPort/health 2>&1 || echo "Không nhận được phản hồi HTTP từ cổng $apiPort"

echo ""
echo "======================================================="
echo "● 3. RUNNING PROCESSES (ai_agent_service / uvicorn)"
echo "======================================================="
ps aux | grep -E '[a]i_agent_service|[u]vicorn' || echo "Không có tiến trình ai-agent nào đang chạy."

echo ""
echo "======================================================="
echo "● 4. RECENT JOURNAL / LOGS (Top 15 lines)"
echo "======================================================="
journalctl -u $service.service -n 15 --no-pager 2>/dev/null || tail -n 15 $remoteDir/agent.log 2>/dev/null || echo "Chưa có log ghi nhận."
''';
          friendlyMsg = 'Chi tiết trạng thái dịch vụ $service';
          break;
      }

      final res = await client.run(cmd).timeout(const Duration(seconds: 15));
      client.close();
      final outputStr = utf8.decode(res).trim();
      return {
        'status': 'success',
        'message': friendlyMsg,
        'output': outputStr.isNotEmpty ? outputStr : friendlyMsg,
      };
    } catch (e) {
      return {
        'status': 'error',
        'message': 'Lỗi: $e',
        'output': 'Lỗi thực thi lệnh SSH: $e',
      };
    }
  }

  Future<List<String>> listRemoteDirs(String prefix) async {
    final cleanPrefix = prefix.trim().isEmpty ? '/' : prefix.trim();
    final normalized = cleanPrefix.startsWith('/') ? cleanPrefix : '/$cleanPrefix';
    const common = [
      '/var/www',
      '/var/www/chatbot.ai-acv.io.vn',
      '/var/www/blog.ai-acv.io.vn',
      '/etc/nginx',
      '/opt/ai_agent',
      '/home',
      '/var/log',
      '/etc',
      '/opt',
      '/root',
    ];

    try {
      final client = await getClient();
      final cmd = 'compgen -d "$normalized" 2>/dev/null | head -30 || find "$normalized" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -30';
      final res = await client.run(cmd).timeout(const Duration(seconds: 4));
      client.close();
      final lines = utf8.decode(res).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

      final resultSet = <String>{...lines};
      for (final c in common) {
        if (c.startsWith(normalized) || normalized == '/') {
          resultSet.add(c);
        }
      }
      final resultList = resultSet.toList()..sort();
      return resultList.isNotEmpty ? resultList : common;
    } catch (_) {
      final filtered = common.where((c) => c.startsWith(normalized)).toList();
      return filtered.isNotEmpty ? filtered : common;
    }
  }

  Future<Map<String, dynamic>> uploadFile({
    required String fileName,
    Uint8List? bytes,
    String? localFilePath,
    String? targetDir,
    void Function(int sentBytes, int totalBytes, double progress)? onProgress,
  }) async {
    SSHClient? client;
    try {
      final cfg = await _configService.loadConfig();
      final sshUser = cfg['ssh_user']?.toString() ?? 'root';
      var baseDir = targetDir ?? cfg['remote_work_dir']?.toString() ?? '/opt/ai_agent';
      if (baseDir.isEmpty) baseDir = '/opt/ai_agent';
      final uploadDir = '$baseDir/uploads';

      client = await getClient();
      await client.run('sudo mkdir -p "$uploadDir" && sudo chown -R $sshUser "$uploadDir" 2>/dev/null || mkdir -p "$uploadDir"');

      final cleanFileName = fileName.replaceAll(RegExp(r'[^\w\.\-\_]'), '_');
      final remoteFilePath = '$uploadDir/$cleanFileName';

      // 1. Determine file size and source stream
      int totalBytes = 0;
      Stream<List<int>> dataStream;

      if (localFilePath != null && File(localFilePath).existsSync()) {
        final f = File(localFilePath);
        totalBytes = await f.length();
        dataStream = f.openRead();
      } else if (bytes != null) {
        totalBytes = bytes.length;
        dataStream = Stream.value(bytes);
      } else {
        return {'status': 'error', 'message': 'Không có dữ liệu hoặc đường dẫn tệp nguồn'};
      }

      int sentBytes = 0;
      bool sftpSuccess = false;

      // 2. Thử truyền qua SFTP (chuẩn tối ưu nhất cho file lớn 5-10GB, tránh buffer tràn)
      try {
        final sftp = await client.sftp();
        final remoteFile = await sftp.open(
          remoteFilePath,
          mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
        );

        await for (final chunk in dataStream) {
          await remoteFile.write(Stream.value(Uint8List.fromList(chunk)));
          sentBytes += chunk.length;
          if (onProgress != null) {
            final prog = totalBytes > 0 ? (sentBytes / totalBytes).clamp(0.0, 1.0) : 1.0;
            onProgress(sentBytes, totalBytes, prog);
          }
        }
        await remoteFile.close();
        sftp.close();
        sftpSuccess = true;
      } catch (sftpErr) {
        // Fallback sang SSH Channel Stream nếu server disable SFTP subsystem
        sftpSuccess = false;
      }

      // 3. Fallback sang SSH Pipe Stream nếu SFTP không khả dụng
      if (!sftpSuccess) {
        // Re-open data stream if localFilePath available
        if (localFilePath != null && File(localFilePath).existsSync()) {
          dataStream = File(localFilePath).openRead();
        } else if (bytes != null) {
          dataStream = Stream.value(bytes);
        }

        sentBytes = 0;
        final session = await client.execute('cat > "$remoteFilePath"');
        const chunkSize = 256 * 1024; // 256 KB chunk size for high throughput

        await for (final rawChunk in dataStream) {
          for (int offset = 0; offset < rawChunk.length; offset += chunkSize) {
            final end = (offset + chunkSize < rawChunk.length) ? offset + chunkSize : rawChunk.length;
            final slice = rawChunk.sublist(offset, end);
            session.stdin.add(Uint8List.fromList(slice));
            sentBytes += slice.length;
            if (onProgress != null) {
              final prog = totalBytes > 0 ? (sentBytes / totalBytes).clamp(0.0, 1.0) : 1.0;
              onProgress(sentBytes, totalBytes, prog);
            }
          }
        }
        await session.stdin.close();
        await session.done;
      }

      client.close();

      return {
        'status': 'success',
        'remote_path': remoteFilePath,
        'size': totalBytes,
        'name': fileName,
      };
    } catch (e) {
      client?.close();
      return {
        'status': 'error',
        'message': 'Lỗi upload qua SSH: $e',
      };
    }
  }

  Future<Uint8List?> downloadFile({
    required String remotePath,
    void Function(int receivedBytes, int totalBytes, double progress)? onProgress,
  }) async {
    try {
      final client = await getClient();
      final sizeRes = await client.run('stat -c %s "$remotePath" 2>/dev/null || wc -c < "$remotePath" 2>/dev/null || echo "0"');
      final totalBytes = int.tryParse(utf8.decode(sizeRes).trim()) ?? 0;

      final session = await client.execute('cat "$remotePath"');
      final bytesBuilder = BytesBuilder(copy: false);
      int receivedBytes = 0;

      await for (final chunk in session.stdout) {
        bytesBuilder.add(chunk);
        receivedBytes += chunk.length;
        if (onProgress != null) {
          final prog = totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
          onProgress(receivedBytes, totalBytes, prog);
        }
      }

      await session.done;
      client.close();
      return bytesBuilder.toBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> streamDeploy({
    required void Function(String step) onStep,
    required void Function() onDone,
    required void Function(dynamic error) onError,
  }) async {
    try {
      final cfg = await _configService.loadConfig();
      final serverIp = cfg['server_ip']?.toString() ?? '127.0.0.1';
      final sshPort = int.tryParse(cfg['ssh_port']?.toString() ?? '22') ?? 22;
      final sshUser = cfg['ssh_user']?.toString() ?? 'root';
      var remoteDir = cfg['remote_work_dir']?.toString() ?? '/opt/ai_agent';
      if (remoteDir.isEmpty) remoteDir = '/opt/ai_agent';
      final apiPort = int.tryParse(cfg['api_port']?.toString() ?? '8000') ?? 8000;
      final proxyKey = cfg['proxy_api_key']?.toString() ?? '';
      final proxyBase = cfg['proxy_base_url']?.toString() ?? 'https://api-us-ca.umodelverse.ai/v1';
      final aiModel = cfg['ai_model']?.toString() ?? 'glm-5.3';
      final secretToken = cfg['secret_token']?.toString() ?? 'super_secret_token_123';

      onStep('⚡ Bắt đầu kết nối SSH tới máy chủ $serverIp:$sshPort...');
      final client = await getClient();
      onStep('✅ Kết nối SSH thành công tới $serverIp (User: $sshUser | SSH Port: $sshPort | API Port: $apiPort)!');

      onStep('🔍 Đang kiểm tra môi trường và kiến trúc CPU máy chủ...');
      final archRes = await client.run('uname -m 2>/dev/null || echo "x86_64"');
      final remoteArch = utf8.decode(archRes).trim();
      final isArm = remoteArch.contains('arm') || remoteArch.contains('aarch64');
      final archLabel = isArm ? 'ARM64 / AArch64' : 'x86_64 / AMD64';
      onStep('💻 Kiến trúc CPU máy chủ: $remoteArch ($archLabel)');

      final possiblePaths = [
        if (isArm) ...[
          '${Directory.current.path}/dist/ai_agent_service_linux_arm64',
          '${Directory.current.path}/../dist/ai_agent_service_linux_arm64',
          '/home/yenai/Documents/Projects/Typing/apps/plugins/agent-client-server/dist/ai_agent_service_linux_arm64',
          '${Directory.current.path}/dist/ai_agent_service',
          '${Directory.current.path}/../dist/ai_agent_service',
          '/home/yenai/Documents/Projects/Typing/apps/plugins/agent-client-server/dist/ai_agent_service',
        ] else ...[
          '${Directory.current.path}/dist/ai_agent_service_linux_amd64',
          '${Directory.current.path}/../dist/ai_agent_service_linux_amd64',
          '/home/yenai/Documents/Projects/Typing/apps/plugins/agent-client-server/dist/ai_agent_service_linux_amd64',
          '${Directory.current.path}/dist/ai_agent_service',
          '${Directory.current.path}/../dist/ai_agent_service',
          '/home/yenai/Documents/Projects/Typing/apps/plugins/agent-client-server/dist/ai_agent_service',
        ]
      ];

      List<int>? binBytes;
      String? foundPath;
      for (final p in possiblePaths) {
        final f = File(p);
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          if (bytes.isNotEmpty) {
            binBytes = bytes;
            foundPath = p;
            break;
          }
        }
      }

      onStep('📁 Đang tạo thư mục làm việc $remoteDir trên VPS...');
      await client.run('sudo mkdir -p $remoteDir && sudo chown -R $sshUser:$sshUser $remoteDir 2>/dev/null || mkdir -p $remoteDir');

      onStep('⏸️ Tạm dừng service cũ và giải phóng port $apiPort...');
      await client.run('sudo systemctl stop ai-agent.service 2>/dev/null || systemctl --user stop ai-agent.service 2>/dev/null || true; fuser -k -9 $apiPort/tcp 2>/dev/null || true; pkill -9 -f ai_agent_service 2>/dev/null || true');

      if (binBytes != null && binBytes.isNotEmpty) {
        final mbSize = (binBytes.length / (1024 * 1024)).toStringAsFixed(1);
        onStep('📦 Tìm thấy Standalone Binary ($mbSize MB) tại: $foundPath');
        onStep('🚀 Đang truyền file nhị phân ai_agent_service lên VPS qua kênh bảo mật SSH...');

        final tmpPath = '/tmp/ai_agent_service_${DateTime.now().millisecondsSinceEpoch}.tmp';
        final session = await client.execute('cat > $tmpPath');
        session.stdin.add(Uint8List.fromList(binBytes));
        await session.stdin.close();
        await session.done;

        onStep('🛡️ Di chuyển file nhị phân vào $remoteDir và cấp quyền thực thi (chmod +x)...');
        await client.run(
          'sudo mv -f $tmpPath $remoteDir/ai_agent_service && '
          'sudo chmod 755 $remoteDir/ai_agent_service && '
          'sudo chown -R $sshUser:$sshUser $remoteDir 2>/dev/null && '
          'sudo rm -f $remoteDir/ai_agent_service.py 2>/dev/null || true'
        );
      } else {
        onStep('⚠️ Không tìm thấy file nhị phân Go, tiến hành cài đặt Python AI Agent fallback...');
        await client.run('pip3 install fastapi uvicorn openai requests 2>&1 || python3 -m pip install fastapi uvicorn openai requests 2>&1 || true');
      }

      onStep('⚙️ Đang cấu hình và kích hoạt Systemd Daemon (ai-agent.service)...');
      final serviceContent = '''[Unit]
Description=MXH tự động Service (Standalone Binary)
After=network.target

[Service]
Type=simple
User=$sshUser
WorkingDirectory=$remoteDir
Environment="PROXY_API_KEY=$proxyKey"
Environment="OPENROUTER_API_KEY=$proxyKey"
Environment="PROXY_BASE_URL=$proxyBase"
Environment="OPENROUTER_BASE_URL=$proxyBase"
Environment="AI_MODEL=$aiModel"
Environment="SECRET_TOKEN=$secretToken"
Environment="AGENT_SECRET_TOKEN=$secretToken"
Environment="AGENT_PORT=$apiPort"
Environment="PORT=$apiPort"
ExecStart=$remoteDir/ai_agent_service
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
''';

      final serviceTmpPath = '/tmp/ai-agent-${DateTime.now().millisecondsSinceEpoch}.service';
      final svcSession = await client.execute('cat > $serviceTmpPath');
      svcSession.stdin.add(utf8.encode(serviceContent));
      await svcSession.stdin.close();
      await svcSession.done;

      await client.run(
        'sudo mv -f $serviceTmpPath /etc/systemd/system/ai-agent.service && '
        'sudo chmod 644 /etc/systemd/system/ai-agent.service && '
        'sudo systemctl daemon-reload && '
        'sudo systemctl enable --now ai-agent.service && '
        'sudo systemctl restart ai-agent.service'
      );

      onStep('⏳ Đang khởi động tiến trình và kiểm tra HTTP Health Check (Port $apiPort)...');
      await Future.delayed(const Duration(seconds: 2));

      // Fallback nohup if systemd is not active
      final chk = await client.run('systemctl is-active ai-agent.service 2>/dev/null || pgrep -f ai_agent_service 2>/dev/null || fuser $apiPort/tcp 2>/dev/null || echo "inactive"');
      final chkStr = utf8.decode(chk).trim();

      if (chkStr == 'inactive' || chkStr.isEmpty) {
        onStep('🔄 Kích hoạt tiến trình chế độ chạy nền Standalone (nohup)...');
        await client.run(
          'nohup env AGENT_PORT=$apiPort PORT=$apiPort PROXY_API_KEY="$proxyKey" OPENROUTER_API_KEY="$proxyKey" PROXY_BASE_URL="$proxyBase" OPENROUTER_BASE_URL="$proxyBase" AI_MODEL="$aiModel" SECRET_TOKEN="$secretToken" AGENT_SECRET_TOKEN="$secretToken" $remoteDir/ai_agent_service > $remoteDir/agent.log 2>&1 &'
        );
        await Future.delayed(const Duration(seconds: 1));
      }

      final healthRes = await client.run('curl -s -m 3 http://127.0.0.1:$apiPort/health 2>&1 || echo "curl_failed"');
      final healthStr = utf8.decode(healthRes).trim();

      client.close();

      if (healthStr.contains('status') || healthStr.contains('ok') || healthStr.contains('online') || chkStr == 'active') {
        onStep('🎉 [SUCCESS] AI Agent Standalone Binary đã được triển khai và khởi động THÀNH CÔNG trên VPS!');
      } else {
        onStep('✅ Đã hoàn tất cài đặt cấu hình Systemd và gửi lệnh khởi động tới máy chủ.');
      }

      onDone();
    } catch (e) {
      onError(e);
    }
  }
}
