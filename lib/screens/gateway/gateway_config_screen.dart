import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/gateway_provider.dart';

class GatewayConfigScreen extends StatefulWidget {
  const GatewayConfigScreen({super.key});

  @override
  State<GatewayConfigScreen> createState() => _GatewayConfigScreenState();
}

class _GatewayConfigScreenState extends State<GatewayConfigScreen> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _tokenCtrl;

  @override
  void initState() {
    super.initState();
    final gateway = context.read<GatewayProvider>();
    _urlCtrl = TextEditingController(text: gateway.gatewayUrl);
    _tokenCtrl = TextEditingController(text: gateway.secretToken);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gateway = context.watch<GatewayProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cấu Hình Gateway API', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: gateway.isConnected ? AppColors.accent : AppColors.danger,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    gateway.isConnected ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                    color: gateway.isConnected ? AppColors.accent : AppColors.danger,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gateway.isConnected ? 'ĐÃ KẾT NỐI GATEWAY' : 'CHƯA KẾT NỐI',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: gateway.isConnected ? AppColors.accent : AppColors.danger,
                          ),
                        ),
                        if (gateway.isConnected)
                          Text(
                            'Độ trễ: ${gateway.pingMs} ms',
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                          )
                        else if (gateway.errorMessage.isNotEmpty)
                          Text(
                            gateway.errorMessage,
                            style: const TextStyle(fontSize: 12, color: AppColors.danger),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Địa chỉ Backend Gateway',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Địa chỉ IP hoặc Tên miền chạy tadu-go backend (ví dụ: http://192.168.1.10:8888 hoặc https://vps.tadu.vn)',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.link_rounded, size: 20),
                hintText: 'http://127.0.0.1:8888',
              ),
            ),
            const SizedBox(height: 18),

            const Text(
              'Secret Token Xác Thực (Tùy chọn)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Mã khóa bí mật dùng để xác thực an toàn giữa Mobile App và Gateway.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tokenCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.lock_outline_rounded, size: 20),
                hintText: 'Nhập Secret Token...',
              ),
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: gateway.status == GatewayStatus.connecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_rounded),
                label: const Text('Lưu & Kiểm Tra Kết Nối'),
                onPressed: gateway.status == GatewayStatus.connecting
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final ok = await gateway.setGatewayConfig(_urlCtrl.text, _tokenCtrl.text);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(ok ? 'Kết nối Gateway thành công!' : 'Kết nối thất bại, vui lòng kiểm tra lại URL!'),
                            backgroundColor: ok ? AppColors.accent : AppColors.danger,
                          ),
                        );
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
