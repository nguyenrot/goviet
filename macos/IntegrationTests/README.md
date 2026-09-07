# AppKit integration harness

Harness này dùng `NSTextView` thật để kiểm tra event tap, Rust FFI và
injector mà không phụ thuộc UI automation. `FastHarness` dùng strategy mặc
định; `SlowHarness` có bundle id Debug-only được map sang `.slow`;
`SelectionHarness` dùng `.selectAndRetype` như Chrome.

Build ba app harness:

```bash
mkdir -p build/integration/FastHarness.app/Contents/MacOS
mkdir -p build/integration/SlowHarness.app/Contents/MacOS
mkdir -p build/integration/SelectionHarness.app/Contents/MacOS
xcrun swiftc macos/IntegrationTests/TextViewHarness.swift \
  -o build/integration/TextViewHarness
cp build/integration/TextViewHarness build/integration/FastHarness.app/Contents/MacOS/
cp build/integration/TextViewHarness build/integration/SlowHarness.app/Contents/MacOS/
cp build/integration/TextViewHarness build/integration/SelectionHarness.app/Contents/MacOS/
cp macos/IntegrationTests/FastHarness-Info.plist \
  build/integration/FastHarness.app/Contents/Info.plist
cp macos/IntegrationTests/SlowHarness-Info.plist \
  build/integration/SlowHarness.app/Contents/Info.plist
cp macos/IntegrationTests/SelectionHarness-Info.plist \
  build/integration/SelectionHarness.app/Contents/Info.plist
codesign --force --deep --options runtime --sign "Apple Development" build/integration/FastHarness.app
codesign --force --deep --options runtime --sign "Apple Development" build/integration/SlowHarness.app
codesign --force --deep --options runtime --sign "Apple Development" build/integration/SelectionHarness.app
```

Cài và chạy bản GõViệt Debug đã ký bằng identity ổn định, sau đó
bật hook:

```bash
defaults write com.kynguyen.goviet SelfTestEnabled -bool true
```

Mở một harness, gửi notification `com.kynguyen.goviet.typetest` với
chuỗi Telex trong `object`, rồi so sánh stdout khi harness tự thoát.
`userInfo["delay_us"] = 0` tạo burst; mặc định là 25.000 µs. Dùng
`GOVIET_HARNESS_SECONDS` để tăng timeout. Luôn tắt lại hook sau test:

```bash
defaults write com.kynguyen.goviet SelfTestEnabled -bool false
```

Regression mất chữ đầu: gửi `1 xius 1 xisu 2 chuts ` lặp lại 10 lần vào
từng harness, lần lượt với `delay_us` 0, 1.000 và 25.000. Kết quả phải bằng
`1 xíu 1 xíu 2 chút ` lặp lại 10 lần. Dùng timeout ít nhất 12 giây và đợi
harness thoát trước khi bắt đầu lượt tiếp theo để không chồng hai lần gõ.
Hook dùng mã phím ANSI đúng cho chữ/số, không giả mọi phím thành phím A.

Bài stress chuyển focus: gửi burst dài vào `SlowHarness`, mở ngay
`FastHarness` khi hàng đợi còn bận. Slow harness phải nhận đủ kết quả;
fast harness phải rỗng.
