PROJECT := wina.xcodeproj
SCHEME := wina
CONFIGURATION ?= Debug
DERIVED_DATA := .build/DerivedData
BUNDLE_ID := com.kobbokkom.wina

SIMULATOR ?= iPhone 17 Pro
OS ?= latest

APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/$(SCHEME).app

ifneq ($(DEVICE_ID),)
DESTINATION := platform=iOS Simulator,id=$(DEVICE_ID)
SIMCTL_DEVICE := $(DEVICE_ID)
else
DESTINATION := platform=iOS Simulator,name=$(SIMULATOR),OS=$(OS)
SIMCTL_DEVICE := $(SIMULATOR)
endif

.PHONY: dev build boot install launch devices clean-derived

dev: boot build install launch

boot:
	@open -a Simulator
	@xcrun simctl boot "$(SIMCTL_DEVICE)" 2>/dev/null || true
	@xcrun simctl bootstatus "$(SIMCTL_DEVICE)" -b

build:
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		build

install:
	xcrun simctl install "$(SIMCTL_DEVICE)" "$(APP_PATH)"

launch:
	xcrun simctl launch "$(SIMCTL_DEVICE)" "$(BUNDLE_ID)"

devices:
	xcrun simctl list devices available

clean-derived:
	rm -rf "$(DERIVED_DATA)"
