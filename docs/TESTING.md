# Kiểm thử

## Tự động

Chạy `make test` sau mọi thay đổi. Lệnh này chạy corpus/unit/stress
test của Rust, Clippy với warning là lỗi, và XCTest cho phần Swift có
thể tách khỏi UI. CI cũng chạy Swift test trước khi build app universal.

Harness AppKit trong `macos/IntegrationTests/` tạo `NSTextView` thật để kiểm
tra trọn pipeline event tap → Rust FFI → injector. Build Debug, bật
`SelfTestEnabled`, rồi gửi notification `com.kynguyen.goviet.typetest`;
`userInfo["delay_us"]` có thể đặt về 0 để mô phỏng burst. Hook này bị
biên dịch loại khỏi bản Release.

## Ma trận test tay

Chạy sau mỗi thay đổi đáng kể ở event tap/injector.
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
  đã đổi, kiểm tra `codesign -dv /Applications/GoViet.app`. Trong output
  `codesign -dvvv`, cờ chữ ký phải có `runtime` (hardened runtime).
- **Smart switch**: tắt VN trong Chrome (⌃⇧), chuyển sang TextEdit (VN bật),
  quay lại Chrome → phải tự về EN.
- **Phím tắt fn 🌐**: chọn "fn 🌐 (Globe)" trong Settings → nhấn-nhả fn phải
  toggle VN/EN và KHÔNG mở bảng emoji/đổi nguồn nhập; giữ fn + mũi tên
  (Page Up/Down) và fn + F-key phải hoạt động bình thường, không toggle.
- **Khởi động cùng máy**: bật trong Settings → reboot → icon menu bar có mặt.
- **Nâng cấp config**: dùng một `config.json` cũ thiếu các field mới và thiếu
  `id` trong macro → mở app → các giá trị cũ/macro vẫn còn, field thiếu nhận
  default và file được ghi lại với `config_version`. File `config_version` 1
  với `macros: []` phải được gieo sẵn viết tắt tiếng Việt (`đc`→được,
  `đn`→Đà Nẵng) mà không ghi đè trigger người dùng đã có. Làm hỏng cú pháp JSON →
  app tạo `config.invalid-<uuid>.json` trước khi tạo config mặc định. Đặt
  `config_version` lớn hơn bản app hỗ trợ → file phải được giữ nguyên ngay cả
  sau khi đổi một tùy chọn trong UI.
- **Unicode ngoài BMP**: gõ `vieejt`, chèn U+1F600 bằng Character Viewer hoặc
  self-test Debug, rồi gõ tiếp `nam` → emoji và chữ trước nó không bị backspace
  nhầm. Tạo macro chứa emoji/chuỗi có combining mark và thử cả `.fast`,
  `.slow` → grapheme phải nguyên vẹn.
- **Slow injection không chặn tap**: trong Terminal/iTerm2 tạo macro ít nhất
  200 ký tự, expand rồi lập tức gõ `abc` và click vị trí khác → expansion phải
  đứng trước `abc`/click, không mất phím và log không có
  `tap disabled ... timeout`.
- **Đổi app khi hàng đợi còn bận**: trong app `.slow`, gõ burst hoặc
  expand macro dài, rồi chuyển ngay sang app khác → phần thay thế và phím
  đã hoãn phải chỉ đi vào process ban đầu; app mới không được nhận
  backspace/text cũ. Lặp lại nhiều lần với Spotlight/terminal.
- **Self-test chỉ có ở Debug**: bật `SelfTestEnabled`, gửi distributed
  notification vào bản Release từ `make app` → app không được gõ gì. Lặp lại
  với Debug build để xác nhận hook phát triển vẫn hoạt động.
  Chuỗi Debug có thể dùng `⌫`, `⎋`, `⏎`, `←`, `→`, `↑`, `↓` để
  kiểm tra các phím điều khiển mà không log nội dung người dùng.
- **Autocaps + khôi phục tiếng Anh**: bật cả hai tùy chọn, gõ
  `a. hello ` và `a. text ` → phải ra `a. Hello ` và `a. Text `; ESC vẫn trả
  đúng phím gốc khi người dùng chủ động yêu cầu.
- **Macro rất dài**: nhập macro có expansion dài hơn 65.535 UTF-16 units,
  expand và kiểm tra không bị cắt ở mốc 65.535; thử kèm emoji ở hai phía mốc.
- **Clean/universal build**: từ fresh clone chạy `make app` khi chưa có
  `macos/Generated/` → build phải tự tạo header. Chạy
  `lipo build/Release/GoViet.app/Contents/MacOS/GoViet -verify_arch arm64 x86_64`.
- **Hiển thị lỗi Settings**: nhập JSON macro sai, xuất vào thư mục không ghi
  được và làm đăng ký Launch at Login thất bại → Settings phải hiện alert,
  không được im lặng. Giá trị `slowDelayMS` ngoài 1...30 trong config phải được
  clamp; tab Giới thiệu phải đọc đúng version từ Info.plist.
