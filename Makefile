APP_NAME := QuickCopy
BUILD_DIR := .build
RELEASE_BIN := $(BUILD_DIR)/release/$(APP_NAME)
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
MACOS_DIR := $(APP_DIR)/Contents/MacOS
RESOURCES_DIR := $(APP_DIR)/Contents/Resources
ICONSET_DIR := $(BUILD_DIR)/$(APP_NAME).iconset
ICON_FILE := $(BUILD_DIR)/$(APP_NAME).icns
INSTALL_DIR := /Applications
INSTALLED_APP := $(INSTALL_DIR)/$(APP_NAME).app

.PHONY: build icon bundle install run clean

build:
	mkdir -p "$(BUILD_DIR)/release"
	swiftc -O -parse-as-library Sources/QuickCopy/main.swift \
		-framework AppKit \
		-framework ApplicationServices \
		-o "$(RELEASE_BIN)"

icon:
	swift Tools/GenerateIcon.swift "$(ICONSET_DIR)"
	iconutil -c icns "$(ICONSET_DIR)" -o "$(ICON_FILE)"

bundle: build icon
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	cp "$(RELEASE_BIN)" "$(MACOS_DIR)/$(APP_NAME)"
	cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
	cp "$(ICON_FILE)" "$(RESOURCES_DIR)/$(APP_NAME).icns"
	codesign --force --deep --sign - "$(APP_DIR)"

install: bundle
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALLED_APP)"
	ditto "$(APP_DIR)" "$(INSTALLED_APP)"

run: install
	open "$(INSTALLED_APP)"

clean:
	rm -rf "$(BUILD_DIR)"
