APP := ClaudePulse
BUILD_DIR := build
APP_PATH := $(BUILD_DIR)/Build/Products/Release/$(APP).app
INSTALL_DIR := /Applications

.PHONY: install build gen run clean

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

clean:
	rm -rf $(BUILD_DIR) $(APP).xcodeproj
