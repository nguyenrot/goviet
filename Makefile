# GõViệt build entry points.
# Signing identity is intentionally pinned: a STABLE code identity is what
# keeps the Accessibility permission from resetting on every rebuild.

IDENTITY ?= Apple Development
APP      := build/Release/GoViet.app
DEST     := /Applications/GoViet.app
VERSION  := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' macos/Resources/Info.plist)
DMG      := build/GoViet-$(VERSION).dmg
RUST_ARM64_TARGET := aarch64-apple-darwin
RUST_X86_64_TARGET := x86_64-apple-darwin
RUST_ARM64_LIB := rust/target/$(RUST_ARM64_TARGET)/release/libgoviet_ffi.a
RUST_X86_64_LIB := rust/target/$(RUST_X86_64_TARGET)/release/libgoviet_ffi.a
UNIVERSAL_LIB := build/universal/libgoviet_ffi.a

.PHONY: core app test sign install dmg watch clean icon

# Tái tạo macos/Resources/AppIcon.icns từ scripts/make-icon.swift (đã commit
# sẵn .icns — chỉ cần chạy lại khi đổi thiết kế icon).
icon:
	swift scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o macos/Resources/AppIcon.icns

core:
	rustup target add $(RUST_ARM64_TARGET) $(RUST_X86_64_TARGET)
	cd rust && cargo build --release --target $(RUST_ARM64_TARGET)
	cd rust && cargo build --release --target $(RUST_X86_64_TARGET)
	mkdir -p build/universal macos/Generated
	lipo -create $(RUST_ARM64_LIB) $(RUST_X86_64_LIB) -output $(UNIVERSAL_LIB)
	lipo $(UNIVERSAL_LIB) -verify_arch arm64 x86_64
	cbindgen --config rust/ffi/cbindgen.toml --crate goviet-ffi --output macos/Generated/goviet.h rust/ffi

app: core
	cd macos && xcodegen generate
	cd macos && xcodebuild -project GoViet.xcodeproj -scheme GoViet \
		-configuration Release -derivedDataPath ../build/DerivedData \
		CONFIGURATION_BUILD_DIR=$(CURDIR)/build/Release \
		ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
		CODE_SIGNING_ALLOWED=NO build

test:
	cd rust && cargo test
	cd rust && cargo clippy --all-targets -- -D warnings

sign: app
	codesign --force --deep --options runtime --sign "$(IDENTITY)" $(APP)
	codesign --verify --deep --strict --verbose=2 $(APP)
	codesign -dvvv $(APP) 2>&1 | grep -q "flags=.*runtime"
	codesign -dvv $(APP) 2>&1 | grep -E "Authority|TeamIdentifier"

install: sign
	@pgrep -x GoViet >/dev/null && killall GoViet || true
	rm -rf $(DEST)
	ditto $(APP) $(DEST)
	open $(DEST)
	@echo "✓ GõViệt installed to $(DEST)"

dmg: sign
	rm -rf build/dmg $(DMG)
	mkdir -p build/dmg
	ditto $(APP) "build/dmg/GoViet.app"
	ln -s /Applications "build/dmg/Applications"
	cp packaging/HUONG-DAN-CAI-DAT.txt "build/dmg/HƯỚNG DẪN CÀI ĐẶT.txt"
	hdiutil create -volname "GõViệt $(VERSION)" -srcfolder build/dmg -ov -format UDZO $(DMG)
	@echo "✓ DMG: $(DMG)"

watch:
	/usr/bin/log stream --predicate 'subsystem == "com.kynguyen.goviet"' --style compact

clean:
	rm -rf build macos/GoViet.xcodeproj
	cd rust && cargo clean
