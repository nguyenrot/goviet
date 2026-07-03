# GõViệt build entry points.
# Signing identity is intentionally pinned: a STABLE code identity is what
# keeps the Accessibility permission from resetting on every rebuild.

IDENTITY ?= Apple Development
APP      := build/Release/GoViet.app
DEST     := /Applications/GoViet.app
VERSION  := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' macos/Resources/Info.plist)
DMG      := build/GoViet-$(VERSION).dmg

.PHONY: core app test sign install dmg watch clean

core:
	cd rust && cargo build --release
	cbindgen --config rust/ffi/cbindgen.toml --crate goviet-ffi --output macos/Generated/goviet.h rust/ffi

app: core
	cd macos && xcodegen generate
	cd macos && xcodebuild -project GoViet.xcodeproj -scheme GoViet \
		-configuration Release -derivedDataPath ../build/DerivedData \
		CONFIGURATION_BUILD_DIR=$(CURDIR)/build/Release \
		CODE_SIGNING_ALLOWED=NO build

test:
	cd rust && cargo test
	cd rust && cargo clippy --all-targets -- -D warnings

sign: app
	codesign --force --deep --sign "$(IDENTITY)" $(APP)
	codesign -dv $(APP) 2>&1 | grep -E "Authority|TeamIdentifier" || true

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
