# Ma trận test tay

Chạy sau mỗi thay đổi đáng kể ở shell Swift (engine đã có test tự động).
Với mỗi app: (1) gõ nhanh một đoạn tiếng Việt dài, (2) click vào giữa từ rồi
gõ tiếp, (3) backspace vào giữa từ đã bỏ dấu, (4) gõ macro + space,
(5) toggle ⌃⇧ giữa chừng từ, (6) gõ từ tiếng Anh ("text", "world").

Câu mẫu: `Toàn thể nhân dân Việt Nam quyết tâm giữ vững độc lập, tự do.`

| App | Ghi chú | Pass? |
|---|---|---|
| TextEdit | baseline `.fast` | |
| Notes | | |
| Safari (trang web + thanh địa chỉ) | | |
| Chrome — **thanh địa chỉ** | `.selectAndRetype`, autocomplete là kẻ thù | |
| Chrome — Google Docs | mất chữ là lỗi kinh điển của bộ gõ mặc định | |
| VS Code (editor + terminal tích hợp) | `.slow` | |
| iTerm2 / Terminal.app | `.slow`; thử cả khi gõ trong vim | |
| Claude Code CLI (trong iTerm2) | case OpenKey #319 | |
| Spotlight (⌘Space) | ký tự đầu hay bị nuốt | |
| Excel / Numbers | ô tính hay tự bật edit mode | |
| Messages | | |
| Ô mật khẩu (đăng nhập web + System Settings) | phải pass-through + icon 🔒 | |
| Game bất kỳ (nếu có) | thêm vào exclusion list → phím không bị can thiệp | |

## Kịch bản đặc biệt

- **Tap tự hồi phục**: chạy `make watch`, mở app nặng cho hệ máy lag hoặc
  `killall -STOP GoViet && sleep 3 && killall -CONT GoViet`, gõ tiếp — trong
  vòng 2s watchdog phải re-enable (xem log "watchdog: tap found disabled").
- **Quyền không reset**: `make install` lại (rebuild + re-sign) → mở app →
  gõ được NGAY không cần cấp lại quyền. Nếu phải cấp lại = signing identity
  đã đổi, kiểm tra `codesign -dv /Applications/GoViet.app`.
- **Smart switch**: tắt VN trong Chrome (⌃⇧), chuyển sang TextEdit (VN bật),
  quay lại Chrome → phải tự về EN.
- **Khởi động cùng máy**: bật trong Settings → reboot → icon menu bar có mặt.
