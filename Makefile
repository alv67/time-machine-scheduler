APP_NAME := TimeMachineScheduler
BUILD := build
APP := $(BUILD)/$(APP_NAME).app
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
DMG := $(BUILD)/$(APP_NAME)-$(VERSION).dmg
DMG_STAGE := $(BUILD)/dmg
ICON_PNG := Resources/AppIcon-1024.png
ICON_ICNS := $(BUILD)/AppIcon.icns
ICONSET := $(BUILD)/AppIcon.iconset
SDK := $(shell xcrun --show-sdk-path)
ARCH := $(shell uname -m)
SWIFTFLAGS := -O -parse-as-library -target $(ARCH)-apple-macos14.0 -sdk $(SDK)

.PHONY: app test run clean icon refresh-icon dmg install

app: $(APP)

icon: $(ICON_PNG)

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

$(APP): App/*.swift Info.plist Daemon/tmscheduler-run.sh $(ICON_ICNS) $(wildcard Resources/*.lproj/*.strings)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	swiftc $(SWIFTFLAGS) App/*.swift -o $(APP)/Contents/MacOS/$(APP_NAME)
	cp Info.plist $(APP)/Contents/Info.plist
	cp Daemon/tmscheduler-run.sh $(APP)/Contents/Resources/tmscheduler-run.sh
	cp $(ICON_ICNS) $(APP)/Contents/Resources/AppIcon.icns
	for lproj in Resources/*.lproj; do cp -R "$$lproj" $(APP)/Contents/Resources/; done
	codesign --force --deep --sign - $(APP)

test:
	mkdir -p $(BUILD)
	swiftc -parse-as-library -target $(ARCH)-apple-macos14.0 -sdk $(SDK) \
		App/Schedule.swift Tests/ScheduleTests.swift -o $(BUILD)/schedule-tests
	./$(BUILD)/schedule-tests

run: app
	open $(APP)

dmg: app
	rm -rf $(DMG_STAGE)
	mkdir -p $(DMG_STAGE)
	cp -R $(APP) $(DMG_STAGE)/
	ln -s /Applications $(DMG_STAGE)/Applications
	hdiutil create -volname "Time Machine Scheduler" -srcfolder $(DMG_STAGE) -ov -format UDZO $(DMG)
	rm -rf $(DMG_STAGE)
	@echo "DMG pronto: $(DMG)"

PREFIX ?= /Applications

install: app
	rm -rf "$(PREFIX)/$(APP_NAME).app"
	ditto $(APP) "$(PREFIX)/$(APP_NAME).app"
	-xattr -dr com.apple.quarantine "$(PREFIX)/$(APP_NAME).app"
	@echo "Installata in $(PREFIX)/$(APP_NAME).app"

clean:
	rm -rf $(BUILD)
