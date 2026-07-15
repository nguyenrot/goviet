# GõViệt

[![CI](https://github.com/nguyenrot/goviet/actions/workflows/ci.yml/badge.svg)](https://github.com/nguyenrot/goviet/actions/workflows/ci.yml)

Bộ gõ tiếng Việt cho macOS theo phong cách **Unikey trên Windows**: app chạy nền
trên menu bar, gõ được ngay trong mọi ứng dụng, chuyển Anh–Việt bằng phím tắt
(mặc định **⌃⇧ Control+Shift**, có thể đổi sang ⌘⇧ hoặc phím **fn 🌐** trong
Cài đặt), không cần chuyển input source.

**Kiến trúc:** Rust engine (thuần logic, unit-test đầy đủ) + Swift shell
(CGEventTap + bơm phím có đánh dấu chống race).

## Tính năng

- Telex, VNI, Simple Telex; gõ nhanh phụ âm (cc→ch, gg→gi…)
- Hai kiểu đặt dấu: cũ (òa, úy) / mới (oà, uý)
- **Tự khôi phục từ tiếng Anh**: "text" không thành "tẽt", "add" không thành "ađ";
  từ sai chính tả tiếng Việt được trả về phím gốc khi kết thúc từ
- Phím **ESC** trả lại đúng phím đã gõ ("việt" → "vieejt")
- **Gõ tắt không giới hạn độ dài**, nhập/xuất JSON, thông minh theo hoa/thường
- **Nhớ chế độ Anh/Việt theo từng ứng dụng** + danh sách loại trừ (game…)
- Chiến lược bơm phím theo app: chậm cho terminal (iTerm2, Terminal, kitty…),
  select-and-retype cho Chromium (sửa lỗi loạn chữ ở thanh địa chỉ Chrome)
- Tự viết hoa đầu câu (tùy chọn), phát hiện secure input (ô mật khẩu) và
  hiện 🔒 trên menu bar
- Watchdog tự hồi phục event tap; ký code bằng certificate ổn định nên
  **quyền Accessibility không bị reset sau mỗi lần build lại**

## Build & cài đặt

**Bản dựng sẵn:** tải file DMG ở [Releases](https://github.com/nguyenrot/goviet/releases),
kéo app vào Applications (xem mục cài đặt bên dưới vì bản này chưa notarize).

Build từ source — yêu cầu: Xcode, Rust cài qua
[rustup](https://rustup.rs), `brew install xcodegen cbindgen`.

```bash
make install   # build core Rust + app, ký, cài vào /Applications, mở app
make test      # cargo test + clippy
make dmg       # DMG universal arm64 + x86_64 để cài máy khác
make watch     # xem log runtime
```

**Cài trên máy khác:** copy file DMG sang, kéo app vào Applications. Vì bản
này ký bằng cert Apple Development (chưa notarize), lần mở đầu bị Gatekeeper
chặn — làm theo `HƯỚNG DẪN CÀI ĐẶT.txt` trong DMG (System Settings → Privacy
& Security → "Open Anyway", hoặc `xattr -cr /Applications/GoViet.app`).
Muốn phát hành rộng không bị chặn thì cần Apple Developer Program
($99/năm) cùng Developer ID và notarization.

Lần đầu chạy, macOS sẽ hỏi quyền **Accessibility** (System Settings →
Privacy & Security → Accessibility → bật GoViet). Cấp xong là gõ được ngay,
không cần logout.

Nếu quyền bị kẹt sau khi đổi certificate: `tccutil reset Accessibility com.kynguyen.goviet`

## Hạn chế đã biết (tương thích UniKey)

Từ tiếng Anh trùng âm tiết Việt hợp lệ sẽ bị bỏ dấu: `this`→`thí`, `mix`→`mĩ`,
`was`→`ứa`… Xử lý: nhấn **ESC** để khôi phục, gõ đúp phím dấu (`tesst`→`test`),
hoặc chuyển EN bằng ⌃⇧ (app nhớ chế độ theo từng ứng dụng). Danh sách đầy đủ
trong `rust/engine/tests/corpus/known_limitations.tsv`.

## Cấu trúc

```text
rust/engine   # engine thuần Rust: telex/vni, đặt dấu, validate âm tiết,
              # auto-restore, macros — 14 test suites data-driven (TSV)
rust/ffi      # C ABI (cbindgen) → macos/Generated/goviet.h
macos/        # Swift shell: EventTapManager, TextInjector, AppProfiles,
              # SettingsStore (JSON), menu bar + SwiftUI Settings
```

MIT License. Tham khảo hành vi từ UniKey/vi-rs/bamboo-core — xem `docs/ATTRIBUTION.md`.
