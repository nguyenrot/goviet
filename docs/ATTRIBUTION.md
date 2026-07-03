# Attribution

GõViệt được viết mới hoàn toàn (engine Rust + shell Swift), nhưng học hỏi
hành vi và kinh nghiệm từ các dự án sau:

- **UniKey** (Phạm Kim Long) — chuẩn hành vi Telex/VNI de-facto: quy tắc đặt
  dấu, double-tap revert (aa→â→aa), delayed stroke (d…d→đ). Không dùng code.
- **vi-rs** (zerox-dg, MIT) — tham khảo mô hình xử lý phím theo từ.
- **bamboo-core** (BambooEngine, MIT) — tham khảo ý tưởng kiểm tra chính tả
  âm tiết và khôi phục phím với từ không hợp lệ.
- **goxkey** (huytd, BSD-3) — tham khảo mô hình CGEventTap trong Rust/macOS.
- **Gõ Nhanh** (khaphanspace) — tham khảo hành vi (khôi phục tiếng Anh, nhớ
  chế độ theo app, delay cho terminal). Chỉ tham khảo hành vi, không dùng code
  (metadata license của repo không nhất quán).
- **OpenKey** (tuyenvm, GPL-3) — chỉ đọc issue tracker để lập danh mục lỗi
  per-app (đặc biệt issue #37 về cơ chế fix Chromium). Không đọc/dùng code GPL.

Bài học kỹ thuật quan trọng từ cộng đồng:

- TCC/Accessibility gắn với code identity → ký bằng certificate ổn định,
  không bao giờ ký ad-hoc (bài học OpenKey trên macOS Tahoe, issue #310).
- "A non-nil tap is not a healthy tap" → watchdog kiểm tra `tapIsEnabled`
  định kỳ ngoài việc xử lý `tapDisabledByTimeout/UserInput`.
- Secure input (ô mật khẩu) chặn mọi event tap → phát hiện và hiển thị rõ.
