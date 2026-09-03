# AppKit integration harness

Harness này dùng `NSTextView` thật để kiểm tra event tap, Rust FFI và
injector mà không phụ thuộc UI automation. `FastHarness` dùng strategy mặc
định; `SlowHarness` có bundle id Debug-only được map sang `.slow`.

Build hai app harness:

```bash
mkdir -p build/integration/FastHarness.app/Contents/MacOS
mkdir -p build/integration/SlowHarness.app/Contents/MacOS
xcrun swiftc macos/IntegrationTests/TextViewHarness.swift \
  -o build/integration/TextViewHarness
cp build/integration/TextViewHarness build/integration/FastHarness.app/Contents/MacOS/
cp build/integration/TextViewHarness build/integration/SlowHarness.app/Contents/MacOS/
cp macos/IntegrationTests/FastHarness-Info.plist \
  build/integration/FastHarness.app/Contents/Info.plist
cp macos/IntegrationTests/SlowHarness-Info.plist \
  build/integration/SlowHarness.app/Contents/Info.plist
codesign --force --deep --sign - build/integration/FastHarness.app
codesign --force --deep --sign - build/integration/SlowHarness.app
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

Bài stress chuyển focus: gửi burst dài vào `SlowHarness`, mở ngay
`FastHarness` khi hàng đợi còn bận. Slow harness phải nhận đủ kết quả;
fast harness phải rỗng.
