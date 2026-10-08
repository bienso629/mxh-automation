# TÀI LIỆU YÊU CẦU VÀ THIẾT KẾ HỆ THỐNG DỰ ÁN AGENT-MXH-AUTO

Dự án: **Agent MXH Tự Động (AI Social Media Auto Manager)**  
Môi trường thực thi: Đa nền tảng (Linux Desktop Ubuntu/Debian, Windows, macOS, Android/iOS)  
Thư mục gốc: `/home/yenai/Documents/Projects/Typing/apps/plugins/agent-mxh-auto`

---

## 1. Mục tiêu và Phạm vi Dự án

Hệ thống cung cấp giải pháp toàn diện cho việc tự động hóa quản lý mạng xã hội, quản trị máy chủ từ xa và điều hành mạng lưới nhân vật (Personas) gắn liền với danh tính số, proxy và môi trường thiết bị độc lập:
- Quản trị hạ tầng máy chủ VPS Linux (SSH Terminal, SFTP Explorer, giám sát tài nguyên thời gian thực).
- Quản lý danh tính nhân vật số (Personas) gắn với từng IP mạng riêng biệt (SOCKS5 / SSH Tunnel).
- Khởi tạo và điều khiển môi trường cô lập: Trình duyệt Chrome độc lập (anti-detect profile) và Thiết bị di động Android (Android Emulator hoặc thiết bị thật kết nối ADB WiFi).
- Đảm bảo toàn bộ lưu lượng truy cập Internet của cả Trình duyệt và Thiết bị của mỗi nhân vật đều bắt buộc đi qua đúng địa chỉ IP Proxy của nhân vật đó.
- Tích hợp trí tuệ nhân tạo (AI Assistant) để tạo kịch bản tương tác, soạn thảo nội dung, đăng bài và tự động hóa thao tác MXH (Facebook, TikTok, v.v.).

---

## 2. Kiến trúc và Các Module Thành phần

### 2.1. Module Mạng và Định tuyến Proxy (Trình duyệt & Thiết bị)
- **File phụ trách chính:** `lib/core/services/socks5_proxy_service.dart`
- **Nguyên tắc cốt lõi:**
  - Mỗi nhân vật (mỗi IP) sở hữu một đường hầm SSH / SOCKS5 Tunnel riêng biệt, hoạt động độc lập và không dùng chung cổng.
  - Cả Trình duyệt và Thiết bị của cùng một nhân vật đều dùng chung địa chỉ IP đối ngoại của nhân vật đó nhưng áp dụng 2 cơ chế kết nối kỹ thuật phù hợp với từng nền tảng:

| Đối tượng | Giao thức kết nối | Cơ chế thực thi |
| :--- | :--- | :--- |
| **Trình duyệt (Browser)** | SOCKS5 nguyên bản trực tiếp | Khởi chạy qua tham số `--proxy-server=socks5://127.0.0.1:<socksPort>`, ăn thẳng vào đường hầm SOCKS5 không qua trung gian. Dữ liệu profile được cô lập tại `~/.agent_mxh_auto/browser_profiles/ip_<IP>/`. |
| **Thiết bị (Android Device)** | HTTP CONNECT qua Bridge | Do Android OS không hỗ trợ SOCKS5 toàn hệ thống, app khởi tạo một cổng trung chuyển nội bộ `startSocks2HttpBridge` thuần Dart (State Machine stream). Cầu nối nhận HTTP CONNECT từ Android (`10.0.2.2:<httpPort>` với Emulator hoặc `<HOST_LAN_IP>:<httpPort>` với WiFi) và chuyển tiếp trọn vẹn vào hầm SOCKS5 của IP đó. |

- **Bảo toàn kết nối:**
  - Xử lý triệt để lỗi Single-subscription Stream trong Dart Socket để kết nối không bị ngắt ngầm (`Proxy CONNECT aborted`).
  - Phân tách và forward trọn vẹn các byte dữ liệu ban đầu trong gói bắt tay TLS sau header CONNECT.
  - Tự động dọn dẹp cấu hình proxy kẹt trong ADB (`settings delete global http_proxy`) khi đóng thiết bị.
  - Bộ giám sát Watchdog quét định kỳ để thu hồi tài nguyên, đóng port và dọn dẹp tiến trình zombie khi người dùng tắt trình duyệt hoặc máy ảo.

### 2.2. Module Quản trị Thiết bị Di động và Nhân vật (Personas & Android AVD)
- **File phụ trách chính:** `lib/core/services/persona_service.dart`, `lib/core/services/adb_manager_service.dart`, `lib/core/services/socks5_proxy_service.dart`
- **Chức năng:**
  - Tạo, sao lưu (`backup`), khôi phục (`restore`) và đồng bộ trạng thái máy ảo Android AVD cho từng nhân vật.
  - Tự động gán thông tin định danh: Tên hiển thị nhân vật, số điện thoại (`autoSyncPhone`), mã vùng.
  - **Tối ưu hóa tài nguyên phần cứng (Resource Optimization):**
    - Cắt giảm CPU ảo xuống 2 cores (`hw.cpu.ncore=2`).
    - Giới hạn RAM máy ảo ở mức 1536MB (`hw.ramSize=1536`), heap size 192MB (`vm.heapSize=192`).
    - Tắt toàn bộ camera trước/sau (`hw.camera.back=none`, `hw.camera.front=none`, cờ `-camera-back none -camera-front none`).
    - Vô hiệu hóa toàn bộ cảm biến nền không cần thiết (gia tốc kế, con quay hồi chuyển, ánh sáng, từ trường, áp suất, tiệm cận).
    - Duy trì âm thanh (`hw.audioInput=yes`, `hw.audioOutput=yes`) phục vụ tương tác media.
    - Tự động vô hiệu hóa hiệu ứng chuyển cảnh qua ADB (`window_animation_scale=0`, `transition_animation_scale=0`, `animator_duration_scale=0`) để máy ảo đạt độ phản hồi tức thì và không ngốn tài nguyên đồ họa.

### 2.3. Module Điều khiển Tự động hóa CLI & Native AI
- **File phụ trách chính:** `lib/core/services/cli_automation_bridge_service.dart`, `lib/core/services/native_ai_service.dart`
- **Chức năng:**
  - Kết nối và ra lệnh cho các kịch bản tự động hóa thao tác UI (click, cuộn, gõ phím, chụp màn hình kiểm chứng) trên Android thông qua ADB.
  - Tương tác với các mô hình ngôn ngữ lớn (LLM) qua Stream SSE để sinh nội dung, lập kế hoạch hành động và tương tác tự nhiên.

### 2.4. Module Quản trị Máy chủ và Hệ thống (Server Management)
- **File phụ trách chính:** `lib/core/services/native_ssh_service.dart`, `lib/core/services/api_service.dart`, `lib/core/services/database_service.dart`
- **Chức năng:**
  - Trình duyệt tệp tin SFTP từ xa: Tải lên, tải xuống, phân quyền tập tin.
  - Terminal SSH trực tiếp kèm bàn phím cảm ứng phụ trợ trên mobile và giao diện desktop.
  - Dashboard giám sát tải CPU, RAM, Disk, Network và trạng thái các daemon dịch vụ (Docker, Nginx, MySQL, v.v.).
  - Quản lý lịch trình tự động (`schedule_provider.dart`) và lưu trữ dữ liệu cục bộ bằng SQLite / SQLite FFI mã hóa.

---

## 3. Yêu cầu Đóng gói và Phát hành trên Linux (Ubuntu / Debian)

### 3.1. Cấu trúc Desktop & Icon Hệ thống
- Tên ứng dụng: **MXH Tự Động**
- Định danh cửa sổ ứng dụng: `APPLICATION_ID = "agent.mxh.auto"`
- Desktop Entry: `/usr/share/applications/mxh-tu-dong.desktop` (bắt buộc có `StartupWMClass=agent.mxh.auto`).
- Chuẩn biểu tượng: Đầy đủ kích thước trong theme `hicolor` (`16x16`, `24x24`, `32x32`, `48x48`, `64x64`, `128x128`, `256x256`, `512x512`) tại `/usr/share/icons/hicolor/*/apps/mxh-tu-dong.png`.

### 3.2. Script Đóng gói và Cài đặt
- **Script Build:** `scripts/build_linux.sh`
  - Biên dịch Flutter Linux Release.
  - Tạo cấu trúc gói Debian `.deb` kèm các script tiền/hậu cài đặt (`prerm`, `postinst`, `postrm`).
  - Tự động sinh bản nén Portable `.tar.gz` và script cài đặt tự động `install.sh`.
- **Đầu ra đóng gói:** Thư mục `dist-flutter/`
  - `dist-flutter/mxh-tu-dong_1.0.0_amd64.deb`
  - `dist-flutter/install.sh` (Hỗ trợ tắt tiến trình cũ, xóa app cũ sạch sẽ và cài đặt bản mới).
  - `dist-flutter/MXH-Tu-Dong-Portable-Ubuntu-x64.tar.gz`

---

## 4. Hướng dẫn Thực thi và Phát triển Local

### Chạy trực tiếp môi trường phát triển (Hot reload)
```bash
python3 dev_run.py
```
hoặc
```bash
flutter run -d linux
```

### Đóng gói bản cài đặt Ubuntu (.deb)
```bash
bash ./scripts/build_linux.sh
```

### Cài đặt bản mới và dọn dẹp phiên bản cũ
```bash
bash ./dist-flutter/install.sh
```
