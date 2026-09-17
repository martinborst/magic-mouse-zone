APP_NAME = MagicMouseZone
APP_BUNDLE = build/$(APP_NAME).app
MACOS_DIR = $(APP_BUNDLE)/Contents/MacOS
SRC = $(wildcard Sources/*.swift)
SDK := $(shell xcrun --sdk macosx --show-sdk-path)
SWIFT ?= swiftc
MIN_OS = 14.0
ARCH := $(shell uname -m)
TARGET = $(ARCH)-apple-macosx$(MIN_OS)
CERT_NAME ?= Magic Mouse Zone Dev
BUNDLE_ID = com.magicmousezone.app
LSREGISTER = /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: all clean run probe install icons ensure-cert sign-app

all: $(APP_BUNDLE)

$(APP_BUNDLE): $(SRC) Sources/Bridging.h Sources/MultitouchSupport.h Resources/Info.plist Resources/MagicMouseZone.entitlements Resources/AppIcon.icns
	mkdir -p "$(MACOS_DIR)" "$(APP_BUNDLE)/Contents/Resources"
	cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	echo "APPL????" > "$(APP_BUNDLE)/Contents/PkgInfo"
	$(SWIFT) \
		-parse-as-library \
		-O \
		-target $(TARGET) \
		-sdk "$(SDK)" \
		-import-objc-header Sources/Bridging.h \
		-framework SwiftUI \
		-framework AppKit \
		-framework ApplicationServices \
		-framework IOKit \
		-framework IOBluetooth \
		-framework ServiceManagement \
		-framework Combine \
		-F /System/Library/PrivateFrameworks \
		-framework MultitouchSupport \
		-o "$(MACOS_DIR)/$(APP_NAME)" \
		$(SRC)
	@$(MAKE) sign-app
	@echo "Built $(APP_BUNDLE)"

ensure-cert:
	@chmod +x Scripts/ensure-dev-cert.sh
	@Scripts/ensure-dev-cert.sh || echo "warning: could not create signing cert; Accessibility may reset on rebuild" >&2

sign-app: ensure-cert
	@if security find-identity -p codesigning 2>/dev/null | grep -qF "$(CERT_NAME)"; then \
		echo "Signing with $(CERT_NAME)"; \
		codesign --force --sign "$(CERT_NAME)" --identifier "$(BUNDLE_ID)" --entitlements Resources/MagicMouseZone.entitlements "$(APP_BUNDLE)"; \
	else \
		echo "warning: no stable signing identity; Accessibility will reset on every rebuild" >&2; \
		codesign --force --sign - --identifier "$(BUNDLE_ID)" --entitlements Resources/MagicMouseZone.entitlements "$(APP_BUNDLE)"; \
	fi
	@"$(LSREGISTER)" -f "$(APP_BUNDLE)" >/dev/null 2>&1 || true

run: all
	open "$(APP_BUNDLE)"

probe: all
	"$(MACOS_DIR)/$(APP_NAME)" --probe

install: all
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/Magic Mouse Zone.app"
	cp -R "$(APP_BUNDLE)" "$(HOME)/Applications/Magic Mouse Zone.app"
	open "$(HOME)/Applications/Magic Mouse Zone.app"

icons: Resources/AppIcon.icns

Resources/AppIcon.icns: Scripts/generate-icon.swift
	swift Scripts/generate-icon.swift Resources/AppIcon-1024.png
	mkdir -p Resources/AppIcon.iconset
	sips -z 16 16     Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_16x16.png >/dev/null
	sips -z 32 32     Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_16x16@2x.png >/dev/null
	sips -z 32 32     Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_32x32.png >/dev/null
	sips -z 64 64     Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_32x32@2x.png >/dev/null
	sips -z 128 128   Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_128x128.png >/dev/null
	sips -z 256 256   Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_128x128@2x.png >/dev/null
	sips -z 256 256   Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_256x256.png >/dev/null
	sips -z 512 512   Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_256x256@2x.png >/dev/null
	sips -z 512 512   Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_512x512.png >/dev/null
	sips -z 1024 1024 Resources/AppIcon-1024.png --out Resources/AppIcon.iconset/icon_512x512@2x.png >/dev/null
	iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns

clean:
	rm -rf build Resources/AppIcon.iconset
