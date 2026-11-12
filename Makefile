# Build e release.
# Per una release firmata con Developer ID:
#   make release SIGN_ID="Developer ID Application: Nome (TEAMID)"
# La notarizzazione resta un passaggio separato.
# Build predefinita: arm64 (Apple Silicon). Per un universale (Intel su macOS 14–26):
#   make release ARCHS="arm64 x86_64"

APP_NAME := TimeMachineScheduler
BUILD := build
APP := $(BUILD)/$(APP_NAME).app
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
DMG := $(BUILD)/$(APP_NAME)-$(VERSION).dmg
ZIP := $(BUILD)/$(APP_NAME)-$(VERSION).zip
CHECKSUMS := $(BUILD)/SHA256SUMS.txt
DMG_STAGE := $(BUILD)/dmg
ICON_PNG := Resources/AppIcon-1024.png
ICON_ICNS := $(BUILD)/AppIcon.icns
ICONSET := $(BUILD)/AppIcon.iconset
SDK := $(shell xcrun --show-sdk-path)
MACOS_MIN := 14.0
ARCHS ?= arm64
HOST_ARCH := $(shell uname -m)
SWIFTFLAGS := -O -parse-as-library -sdk $(SDK)
SIGN_ID ?= -

# Daemon: un binario che tiene l'assertion sul keybag e lancia il backup. Compilato per
# l'architettura host, non universale: viene installato sulla macchina che lo esegue.
DAEMON_SRC := App/Schedule.swift Daemon/main.swift
DAEMON := $(BUILD)/$(APP_NAME)-daemon

.PHONY: app test run clean icon refresh-icon dmg zip release checksums install

app: $(APP)

icon: $(ICON_PNG)

$(DAEMON): $(DAEMON_SRC)
	mkdir -p $(BUILD)
	swiftc -O -sdk $(SDK) -target $(HOST_ARCH)-apple-macos$(MACOS_MIN) $(DAEMON_SRC) -o $@

refresh-icon: app
	touch $(APP)
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f $(APP)
	killall Dock

$(ICON_PNG): Tools/make-icon.swift
	mkdir -p Resources
	swift Tools/make-icon.swift $(ICON_PNG)

$(ICON_ICNS): $(ICON_PNG)
	rm -rf $(ICONSET)
	mkdir -p $(ICONSET)
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s $(ICON_PNG) --out $(ICONSET)/icon_$${s}x$${s}.png >/dev/null; \
		sips -z $$((s * 2)) $$((s * 2)) $(ICON_PNG) --out $(ICONSET)/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns $(ICONSET) -o $(ICON_ICNS)

$(APP): App/*.swift Info.plist Daemon/tmscheduler-run.sh $(DAEMON) $(ICON_ICNS) $(wildcard Resources/*.lproj/*.strings)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	set -e; for arch in $(ARCHS); do \
		mkdir -p $(BUILD)/$$arch; \
		swiftc $(SWIFTFLAGS) -target $$arch-apple-macos$(MACOS_MIN) App/*.swift -o $(BUILD)/$$arch/$(APP_NAME); \
	done
	lipo -create $(foreach arch,$(ARCHS),$(BUILD)/$(arch)/$(APP_NAME)) -output $(APP)/Contents/MacOS/$(APP_NAME)
	cp Info.plist $(APP)/Contents/Info.plist
	cp Daemon/tmscheduler-run.sh $(APP)/Contents/Resources/tmscheduler-run.sh
	cp $(DAEMON) $(APP)/Contents/Resources/tmscheduler-daemon
	cp $(ICON_ICNS) $(APP)/Contents/Resources/AppIcon.icns
	for lproj in Resources/*.lproj; do cp -R "$$lproj" $(APP)/Contents/Resources/; done
	codesign --force --deep --sign "$(SIGN_ID)" $(APP)

test:
	mkdir -p $(BUILD)
	swiftc -parse-as-library -target $(HOST_ARCH)-apple-macos$(MACOS_MIN) -sdk $(SDK) \
		App/Schedule.swift Tests/ScheduleTests.swift -o $(BUILD)/schedule-tests
	./$(BUILD)/schedule-tests

run: app
	open $(APP)

dmg: app Resources/DMG-Leggimi.txt
	rm -rf $(DMG_STAGE)
	mkdir -p $(DMG_STAGE)
	cp -R $(APP) $(DMG_STAGE)/
	ln -s /Applications $(DMG_STAGE)/Applications
	cp Resources/DMG-Leggimi.txt $(DMG_STAGE)/Leggimi.txt
	hdiutil create -volname "$(APP_NAME) $(VERSION)" -srcfolder $(DMG_STAGE) -ov -format UDZO $(DMG)
	rm -rf $(DMG_STAGE)
	@echo "DMG pronto: $(DMG)"

zip: app
	ditto -c -k --keepParent $(APP) $(ZIP)
	@echo "ZIP pronto: $(ZIP)"

checksums: dmg zip
	cd $(BUILD) && shasum -a 256 $(notdir $(DMG)) $(notdir $(ZIP)) > $(notdir $(CHECKSUMS))
	@echo "Checksum pronti: $(CHECKSUMS)"

release: checksums

PREFIX ?= /Applications

install: app
	rm -rf "$(PREFIX)/$(APP_NAME).app"
	ditto $(APP) "$(PREFIX)/$(APP_NAME).app"
	-xattr -dr com.apple.quarantine "$(PREFIX)/$(APP_NAME).app"
	@echo "Installata in $(PREFIX)/$(APP_NAME).app"

clean:
	rm -rf $(BUILD)
