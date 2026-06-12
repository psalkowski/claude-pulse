APP := ClaudePulse
BUILD_DIR := build
APP_PATH := $(BUILD_DIR)/Build/Products/Release/$(APP).app
INSTALL_DIR := /Applications

.PHONY: install build gen run clean screenshots dmg

# Full install (deps check + build + copy to /Applications + launch).
install:
	./install.sh

gen:
	xcodegen

build: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Release \
		-derivedDataPath $(BUILD_DIR) build

# Build and run without copying to /Applications (dev loop).
run: build
	@pkill -x $(APP) 2>/dev/null || true
	open "$(APP_PATH)"

# Regenerate the README images from the app's own views (anonymized sample data).
screenshots: build
	"$(APP_PATH)/Contents/MacOS/$(APP)" --render-docs "$(PWD)/docs/images"

# Local drag-&-drop DMG (ad-hoc signed — for layout testing; releases come from CI).
dmg: build
	rm -rf dist/dmg-stage dist/ClaudePulse-dev.dmg
	mkdir -p dist/dmg-stage
	ditto "$(APP_PATH)" "dist/dmg-stage/$(APP).app"
	create-dmg --volname "Claude Pulse" --window-pos 200 120 --window-size 580 360 \
		--icon-size 128 --icon "$(APP).app" 150 170 --app-drop-link 430 170 \
		--hide-extension "$(APP).app" dist/ClaudePulse-dev.dmg dist/dmg-stage

clean:
	rm -rf $(BUILD_DIR) dist $(APP).xcodeproj
