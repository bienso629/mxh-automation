import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class DocsScreen extends StatelessWidget {
  const DocsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: const BoxDecoration(
              color: AppColors.bgDark,
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: const Row(
              children: [
                Icon(Icons.menu_book_rounded, color: AppColors.primary, size: 22),
                SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tài Liệu Hướng Dẫn',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Cẩm nang quản lý Profiles, Proxy và tự động hóa mạng xã hội',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _buildSectionCard(
                  icon: Icons.badge_outlined,
                  iconColor: AppColors.primary,
                  title: '1. Quản lý Profiles & IP Contact Cards',
                  content:
                      '• Mỗi card đại diện cho một danh tính nhân vật AI với IP proxy, tài khoản và fingerprint trình duyệt antidetect riêng biệt.\n'
                      '• Bấm "Mở browser" để khởi chạy phiên duyệt web độc lập hoặc "Mở device" để kết nối thiết bị ngoại vi / máy ảo.',
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  icon: Icons.chat_bubble_outline_rounded,
                  iconColor: AppColors.accent,
                  title: '2. Tương tác với Trợ lý AI',
                  content:
                      '• Trợ lý AI hỗ trợ điều khiển, giám sát và thực thi lệnh Linux an toàn trên hệ thống Sân khấu.\n'
                      '• Hỗ trợ quản lý session hội thoại, ghim những cuộc trò chuyện quan trọng và tra cứu lịch sử.',
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  icon: Icons.devices_rounded,
                  iconColor: AppColors.accentCyan,
                  title: '3. Kết nối thiết bị ngoại vi & Máy ảo',
                  content:
                      '• Bật công tắc "Kết nối thiết bị ngoại vi" trong chi tiết hồ sơ để chuyển đổi linh hoạt giữa máy ảo Local AVD và thiết bị thật cắm ngoài.\n'
                      '• Tự động map proxy SOCKS5 qua bridge cục bộ đảm bảo an toàn tuyệt đối.',
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  icon: Icons.settings_outlined,
                  iconColor: AppColors.warning,
                  title: '4. Cấu hình hệ thống',
                  content:
                      '• Mục "Cấu hình" cho phép tùy chỉnh AI Model, Base URL, API Key và thông số Sân khấu.\n'
                      '• Kiểm tra trạng thái kết nối SSH và quản lý dịch vụ nền theo thời gian thực.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String content,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.textBody),
          ),
        ],
      ),
    );
  }
}
