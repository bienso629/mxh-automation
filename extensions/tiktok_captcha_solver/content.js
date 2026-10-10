/**
 * TikTok Rotate / Whack-a-Mole Slider Captcha Auto-Solver
 * Thuật toán tính góc xoay viền tròn và giả lập chuyển động chuột Bézier tự nhiên.
 */

(function () {
  'use strict';

  console.log('[TikTok Captcha Solver] Tiện ích tự động giải Captcha đã sẵn sàng.');

  let isSolving = false;

  // Lắng nghe DOM định kỳ để phát hiện popup Captcha xuất hiện
  setInterval(() => {
    if (isSolving) return;

    // Các selector phổ biến của khung Captcha TikTok
    const captchaContainer = document.querySelector(
      '#captcha_container, .captcha_verify_container, [class*="captcha"], [class*="verify-bar-close"]'
    ) || document.querySelector('img[src*="captcha"], canvas[class*="captcha"]')?.closest('div[style*="z-index"]');

    const sliderBtn = document.querySelector(
      '.secsdk-captcha-drag-icon, [class*="secsdk_captcha_drag"], [class*="drag-button"], .captcha_verify_slide--drag-icon'
    );

    if (sliderBtn && !isSolving) {
      console.log('[TikTok Captcha Solver] Phát hiện hộp thoại Captcha TikTok!');
      trySolveCaptcha();
    }
  }, 1200);

  async function trySolveCaptcha() {
    isSolving = true;
    try {
      await sleep(1000);

      // Tìm ảnh tròn bên trong và ảnh nền bên ngoài
      const images = Array.from(document.querySelectorAll('img')).filter(img => {
        return (
          img.src &&
          (img.src.includes('captcha') || img.src.includes('verify') || img.src.includes('byteimg')) &&
          img.naturalWidth > 50
        );
      });

      const sliderBtn = document.querySelector(
        '.secsdk-captcha-drag-icon, [class*="secsdk_captcha_drag"], [class*="drag-button"], .captcha_verify_slide--drag-icon'
      );

      const sliderTrack = sliderBtn?.parentElement || document.querySelector('[class*="drag-track"], [class*="verify-bar-track"]');

      if (!sliderBtn || !sliderTrack) {
        console.warn('[TikTok Captcha Solver] Không tìm thấy thanh trượt slider.');
        isSolving = false;
        return;
      }

      console.log('[TikTok Captcha Solver] Bắt đầu phân tích góc xoay...');
      let targetDistance = 0;

      if (images.length >= 2) {
        // Có 2 ảnh: inner (ảnh tròn xoay) và outer (khung viền nền)
        targetDistance = await calculateRotateAngleFromImages(images[0], images[1], sliderTrack);
      } else {
        // Fallback: Tìm góc cân bằng tương phản hoặc dùng vị trí tối ưu mặc định
        const trackWidth = sliderTrack.getBoundingClientRect().width || 250;
        const btnWidth = sliderBtn.getBoundingClientRect().width || 40;
        const maxSlide = trackWidth - btnWidth;
        // Ước lượng vị trí điểm cân bằng hình học
        targetDistance = maxSlide * 0.48;
      }

      console.log(`[TikTok Captcha Solver] Quãng đường kéo trượt xác định: ${targetDistance}px`);
      await simulateHumanDrag(sliderBtn, targetDistance);

      await sleep(2000);
    } catch (e) {
      console.error('[TikTok Captcha Solver] Lỗi giải Captcha:', e);
    } finally {
      isSolving = false;
    }
  }

  /**
   * Tính toán góc xoay dựa trên so khớp gradient viền ranh giới giữa 2 ảnh bằng Canvas
   */
  async function calculateRotateAngleFromImages(innerImg, outerImg, track) {
    try {
      const trackWidth = track.getBoundingClientRect().width || 260;
      const maxSlide = trackWidth - 44;

      const canvasInner = document.createElement('canvas');
      const canvasOuter = document.createElement('canvas');
      const size = 200;
      canvasInner.width = size;
      canvasInner.height = size;
      canvasOuter.width = size;
      canvasOuter.height = size;

      const ctxInner = canvasInner.getContext('2d');
      const ctxOuter = canvasOuter.getContext('2d');

      ctxInner.drawImage(innerImg, 0, 0, size, size);
      ctxOuter.drawImage(outerImg, 0, 0, size, size);

      // Bán kính ranh giới khớp viền (vòng tròn cắt)
      const radius = size * 0.38;
      const centerX = size / 2;
      const centerY = size / 2;

      let bestAngle = 0;
      let minDiff = Infinity;

      // Xoay thử các góc từ 0 đến 360 độ (bước nhảy 3 độ để tăng tốc độ tính toán)
      for (let angle = 0; angle < 360; angle += 3) {
        const rad = (angle * Math.PI) / 180;
        let diff = 0;
        let samples = 0;

        for (let sampleAngle = 0; sampleAngle < Math.PI * 2; sampleAngle += 0.1) {
          // Tọa độ trên vòng tròn trong (bị xoay)
          const inX = Math.round(centerX + (radius - 2) * Math.cos(sampleAngle + rad));
          const inY = Math.round(centerY + (radius - 2) * Math.sin(sampleAngle + rad));

          // Tọa độ trên vòng tròn ngoài (cố định)
          const outX = Math.round(centerX + (radius + 2) * Math.cos(sampleAngle));
          const outY = Math.round(centerY + (radius + 2) * Math.sin(sampleAngle));

          if (inX >= 0 && inX < size && inY >= 0 && inY < size && outX >= 0 && outX < size && outY >= 0 && outY < size) {
            const pInner = ctxInner.getImageData(inX, inY, 1, 1).data;
            const pOuter = ctxOuter.getImageData(outX, outY, 1, 1).data;

            // Tính sai khác màu sắc RGB tại ranh giới
            const d = Math.abs(pInner[0] - pOuter[0]) + Math.abs(pInner[1] - pOuter[1]) + Math.abs(pInner[2] - pOuter[2]);
            diff += d;
            samples++;
          }
        }

        const avgDiff = samples > 0 ? diff / samples : Infinity;
        if (avgDiff < minDiff) {
          minDiff = avgDiff;
          bestAngle = angle;
        }
      }

      console.log(`[TikTok Captcha Solver] Góc xoay khớp nhất: ${bestAngle} độ (sai số: ${minDiff.toFixed(1)})`);
      return (bestAngle / 360) * maxSlide;
    } catch (err) {
      console.warn('[TikTok Captcha Solver] Không thể đọc pixel canvas (CORS), dùng tỷ lệ mặc định:', err);
      const trackWidth = track.getBoundingClientRect().width || 260;
      return (trackWidth - 44) * 0.5;
    }
  }

  /**
   * Giả lập chuyển động kéo chuột tự nhiên của người thật theo đường cong Bézier kèm rung động
   */
  async function simulateHumanDrag(element, targetX) {
    const rect = element.getBoundingClientRect();
    const startX = rect.left + rect.width / 2;
    const startY = rect.top + rect.height / 2;

    // Phát sự kiện mousedown
    element.dispatchEvent(
      new MouseEvent('mousedown', {
        bubbles: true,
        cancelable: true,
        view: window,
        clientX: startX,
        clientY: startY,
        button: 0,
      })
    );

    await sleep(randomInt(80, 150));

    // Sinh các bước di chuyển chuột kèm gia tốc và độ rung tay tự nhiên
    const steps = randomInt(25, 40);
    let currentX = startX;
    let currentY = startY;

    for (let i = 1; i <= steps; i++) {
      const progress = i / steps;
      // Hàm gia tốc mượt mà Ease-Out-Cubic
      const ease = 1 - Math.pow(1 - progress, 3);
      const nextX = startX + targetX * ease;
      // Thêm chút rung động trục Y ngẫu nhiên (±1px đến 2px)
      const jitterY = (Math.random() - 0.5) * 3;

      currentX = nextX;
      currentY = startY + jitterY;

      window.dispatchEvent(
        new MouseEvent('mousemove', {
          bubbles: true,
          cancelable: true,
          view: window,
          clientX: currentX,
          clientY: currentY,
          button: 0,
        })
      );

      // Thời gian nghỉ giữa mỗi bước di chuột (mô phỏng tốc độ tay)
      await sleep(randomInt(8, 20));
    }

    // Tạm dừng ở điểm đích một nhịp ngắn trước khi thả chuột (như người thật kiểm tra đã khớp chưa)
    await sleep(randomInt(120, 250));

    // Phát sự kiện mouseup kết thúc kéo
    window.dispatchEvent(
      new MouseEvent('mouseup', {
        bubbles: true,
        cancelable: true,
        view: window,
        clientX: currentX,
        clientY: currentY,
        button: 0,
      })
    );

    console.log('[TikTok Captcha Solver] Đã hoàn tất kéo thanh trượt.');
  }

  function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  function randomInt(min, max) {
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }
})();
