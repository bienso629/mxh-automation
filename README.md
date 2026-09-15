# 📱 MXH tự động - Flutter Mobile App

Ứng dụng di động (Android & iOS) quản trị máy chủ Linux VPS và điều khiển trợ lý AI Agent cho hệ thống Tadu Cloud.

---

## 🌟 Tính Năng Chính

1. **🤖 Trợ Lý AI Agent (AI Chat & Stream Response)**:
   - Tương tác với mô hình LLM (GLM-5.3, OpenRouter, GPT-4, v.v.).
   - Phản hồi dạng Stream SSE theo thời gian thực kèm định dạng Markdown và cú pháp Code.
   - Thẻ hiển thị lệnh terminal AI thực thi kèm kết quả trực quan.
   - Các phím tắt yêu cầu nhanh (Quick Prompt Action Chips).
   - Quản lý danh sách phiên hội thoại (Chat Sessions History).

2. **📊 Giám Sát Tài Nguyên Hệ Thống (Realtime Dashboard)**:
   - Đo tải CPU %, Load Average, RAM %, Ổ cứng (Disk), Băng thông mạng (Rx/Tx KB/s).
   - Biểu đồ đường thời gian thực (Realtime Line Chart) bằng `fl_chart`.
   - Danh sách trạng thái và nút khởi động lại các dịch vụ (Nginx, Docker, MySQL, AI Agent).

3. **💻 SSH Terminal Cảm Ứng (Mobile Touch Terminal)**:
   - Kết nối trực tiếp qua WebSocket `/ws/terminal`.
   - **Thanh phím cứng ảo phụ trợ**: `ESC`, `TAB`, `CTRL+C`, `CTRL+D`, `CTRL+Z`, `↑`, `↓`, `←`, `→`, `ls -la`, `htop`, `clear`.

4. **📁 Trình Duyệt File Từ Xa (SFTP Explorer)**:
   - Duyệt cây thư mục từ xa trên VPS.

5. **🖥️ Quản Lý Đa Máy Chủ (Multi-Server Manager)**:
   - Thêm, sửa, xóa, chuyển đổi nhanh giữa các VPS.

6. **⚙️ Kết Nối Gateway Linh Hoạt**:
   - Cấu hình địa chỉ IP / Domain của Control Center Gateway (`http://vps-ip:8888` hoặc `https://domain.com`).
   - Hỗ trợ Secret Token xác thực an toàn.

---

## 🚀 Hướng Dẫn Chạy & Build App

### 1. Cài đặt Flutter & Dependencies
```bash
cd mobile
flutter pub get
```

### 2. Chạy ứng dụng trên Thiết bị / Giả lập
```bash
# Chạy trên thiết bị kết nối (Android / iOS / Linux Desktop)
flutter run
```

### 3. Đóng gói file cài đặt Android APK
```bash
# Xuất file APK (Release mode)
flutter build apk --release
```
File APK xuất ra sẽ nằm tại: `build/app/outputs/flutter-apk/app-release.apk`.

### 4. Đóng gói cho iOS
```bash
flutter build ipa --release
```
