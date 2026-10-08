# QUY TẮC TIÊU CHUẨN KHI AGENT ĐỌC BÁO VÀ XEM VIDEO TRÊN WEBSITE (AGENT MXH AUTO RULES)

Tài liệu này định nghĩa hệ thống quy chuẩn bắt buộc mà AI Agent (bao gồm Native AI Chat, CLI Agent `agy`, Claude Code, Gemini...) phải tuân thủ khi nhận nhiệm vụ đọc bài viết, tin tức hoặc xem video trên bất kỳ trang web nào.

---

## 1. NGUYÊN TẮC CỐT LÕI (CORE PRINCIPLES)

1. **Mô phỏng hành vi con người thật (Human-like Interaction)**:
   * Tuyệt đối không tương tác cơ học tức thời (0.1s/hành động) gây kích hoạt hệ thống bảo vệ (Cloudflare, reCAPTCHA, Bot Detector).
   * Mọi thao tác cuộn, dừng đọc, bấm phát video, chuyển tab phải có độ trễ ngẫu nhiên (`random delay` từ 1.5s đến 5.0s).

2. **Bảo toàn danh tính nhân vật (Persona Consistency)**:
   * Khi tóm tắt, phát biểu cảm nghĩ, đánh giá hoặc để lại bình luận trên bài viết/video: Bắt buộc phải đứng dưới góc nhìn, giọng văn, độ tuổi, chuyên môn và tiểu sử (`bio`) của đúng nhân vật (`PersonaProfile`) được giao nhiệm vụ.

3. **Cách ly phiên duyệt web (Profile Isolation)**:
   * Mọi lượt truy cập website phải chạy đúng trên Browser Profile độc lập gắn với IP SOCKS5 của nhân vật đó (`browser_profiles/ip_<IP>`).
   * Không dùng chung cookie, cache hoặc session giữa các nhân vật khác nhau.

---

## 2. QUY TRÌNH ĐỌC BÀI BÁO TRÊN WEBSITE (ARTICLE READING RULES)

Khi nhận lệnh đọc một bài báo/bài viết theo URL:

1. **Giai đoạn tiếp cận & Điều hướng (Navigation)**:
   * Khởi chạy trình duyệt bằng lệnh hoặc tool chuyên dụng (`mxh-tool open-browser --ip <IP> --url <URL>` hoặc `open_profile_browser`).
   * Chờ trang tải hoàn tất (`networkidle` hoặc `domcontentloaded`).
   * Nếu có pop-up che màn hình (đồng ý Cookie, thông báo đăng ký, quảng cáo chặn đọc): Tìm nút đóng (X / Close / Dismiss / Accept Cookies) để tắt trước khi đọc.

2. **Giai đoạn đọc nội dung (Reading & Dwell Time)**:
   * **Bóc tách cấu trúc bài viết**:
     * Tiêu đề chính (`h1`).
     * Tác giả, ngày đăng, nguồn báo (`metadata`).
     * Nội dung bài viết (thẻ `<article>`, `.content`, `.post-body` hoặc các thẻ đoạn văn `<p>`).
   * **Mô phỏng thao tác đọc**:
     * Cuộn trang từ từ xuống dưới (khoảng 300px - 600px mỗi lần).
     * Dừng lại ở mỗi đoạn từ 3 đến 8 giây tùy theo độ dài đoạn văn để tính thời gian đọc thực (Read Time).
     * Cuộn đến ít nhất 70% - 100% chiều dài bài viết để hoàn tất một phiên đọc hợp lệ.

3. **Giai đoạn tổng hợp & Phản hồi (Synthesis & Interaction)**:
   * Trích xuất các luận điểm chính của bài viết.
   * Nếu người dùng yêu cầu tóm tắt: Đưa ra 3-5 ý cốt lõi ngắn gọn, dễ hiểu.
   * Nếu yêu cầu bình luận / tương tác:
     * Viết bình luận có văn phong tự nhiên, đúng giọng điệu của nhân vật.
     * Liên hệ trực tiếp đến nội dung có thật trong bài viết (tránh bình luận chung chung, vô nghĩa như "bài viết hay quá", "like").

---

## 3. QUY TRÌNH XEM VIDEO TRÊN WEBSITE (VIDEO WATCHING RULES)

Khi bài viết có chứa video hoặc trang đích là trang video (YouTube, TikTok, Facebook Video, trang báo nhúng player):

1. **Nhận diện trình phát (Player Detection)**:
   * Định vị phần tử thẻ `<video>` hoặc iframe nhúng (`iframe[src*="youtube"]`, `iframe[src*="facebook"]`, v.v.).
   * Cuộn màn hình đưa trình phát video vào khung nhìn trung tâm (`scrollIntoView`).

2. **Kích hoạt & Điều khiển phát (Playback Control)**:
   * Nếu video chưa tự phát: Bấm nút Play trên player hoặc kích hoạt qua giao diện.
   * Đảm bảo không bấm nhầm vào quảng cáo đè lên video. Nếu xuất hiện quảng cáo Skip Ad, đợi xuất hiện nút "Bỏ qua quảng cáo" (sau 5s) rồi bấm bỏ qua.

3. **Thời gian xem tối thiểu (Watch Duration)**:
   * **Video ngắn (< 1 phút)**: Phải xem tối thiểu 80% thời lượng video.
   * **Video dài (> 3 phút)**: Phải xem tối thiểu từ 45 giây đến 2 phút (hoặc theo số giây người dùng chỉ định) để hệ thống ghi nhận một lượt xem thực tế (`valid view`).
   * Không được tắt trình duyệt ngay sau khi vừa bấm Play.

4. **Hiểu & Khai thác nội dung Video (Content Understanding)**:
   * Đọc tiêu đề, mô tả, bình luận ghim hoặc bóc tách phụ đề (`closed captions` / `.vtt`) nếu có.
   * Tổng hợp nội dung video kết hợp với ngữ cảnh bài báo xung quanh để hiểu trọn vẹn chủ đề.

---

## 4. BÁO CÁO KẾT QUẢ CHO NGƯỜI DÙNG

Sau khi hoàn thành tác vụ đọc báo hoặc xem video:
1. Báo cáo rõ ràng:
   * Tên nhân vật và IP đã thực hiện.
   * Tiêu đề bài viết / video đã xem.
   * Thời lượng đã dành để đọc/xem.
2. Trình bày bản tóm tắt hoặc nội dung cảm nghĩ/bình luận đã tạo (nếu có yêu cầu).
3. Đóng trình duyệt (`close-browser` / `close_profile_browser`) nếu kịch bản kết thúc, hoặc giữ nguyên nếu người dùng yêu cầu giữ lại để xem tiếp.
