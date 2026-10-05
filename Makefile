# havooch: build, test, bundle, sign and install the app with SwiftPM
# alone (no Xcode project).
#
#   make            build the app and the command (release)
#   make test       run the tests (swift test); never drives the Mac
#   make bundle     build/<app name>.app with the havooch command in
#                   Contents/Helpers, the app icon and the cat mark in
#                   Contents/Resources, the built-in themes in
#                   Contents/Resources/Themes, the agents' logos and their
#                   notice in Contents/Resources/AgentLogos and the demo
#                   video in Contents/Resources/Demo, ad-hoc signed
#   make install    bundle, then replace /Applications/<app name>.app and open
#                   it; on the support folder HAVOOCH_SUPPORT_DIR names when
#                   it's set, so a check never opens the person's own data
#   make acceptance run the acceptance scenario through the installed app's
#                   command, on demo data (scripts/acceptance.sh); after make install
#   make agent-logos redraw Packaging/AgentLogos/*.pdf from the SVGs in
#                   assets/images/agent-logos/ (needs rsvg-convert)
#   make logo       redraw Packaging/Logo/*.pdf, the cat mark the app shows,
#                   from assets/images/logo/v2-havuc/ (needs rsvg-convert)
#   make identity   print the app name, the command, the bundle id and the
#                   version as name=value lines (the release workflow reads them)
#   make clean

# The executables' names.
APP := HavoochApp
CLI := havooch

# The name, the bundle id and the version each live in one Swift constant,
# so the command, the app and `swift test` see the same identity as this file.
APP_NAME  := $(shell sed -n 's/.*static let appName = "\(.*\)".*/\1/p' Sources/ReviewLease/ControlLease.swift)
BUNDLE_ID := $(shell sed -n 's/.*static let bundleID = "\(.*\)".*/\1/p' Sources/ReviewWire/AppIdentity.swift)
VERSION   := $(shell sed -n 's/.*static let app = "\(.*\)".*/\1/p' Sources/ReviewWire/Version.swift)

BUILD_DIR   := build
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS    := $(APP_BUNDLE)/Contents
INSTALLED   := /Applications/$(APP_NAME).app
# The app icon: logo v2 "Havuç" on the white tile, beside Shipyard's.
APP_ICON    := assets/images/logo/v2-havuc/AppIcon-light.icns

# With the Command Line Tools alone (no Xcode), swift test can't find the
# Testing framework the tests use: point the compiler and the test runner at
# the copy the Command Line Tools ship. With Xcode nothing is needed.
DEVELOPER_DIR := $(shell xcode-select -p 2>/dev/null)
ifneq (,$(findstring CommandLineTools,$(DEVELOPER_DIR)))
TESTING_FRAMEWORKS := $(DEVELOPER_DIR)/Library/Developer/Frameworks
TESTING_LIBRARIES  := $(DEVELOPER_DIR)/Library/Developer/usr/lib
TEST_FLAGS := -Xswiftc -F -Xswiftc $(TESTING_FRAMEWORKS) \
	-Xlinker -F -Xlinker $(TESTING_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(TESTING_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(TESTING_LIBRARIES)
# The Command Line Tools ship no prebuilt SDK modules either, so a new
# checkout's first build compiles Swift, Foundation, SwiftUI and the rest
# from their interfaces. One module cache shared by every checkout and
# worktree pays that once.
# The folder keeps the app's earlier name (docs/adr/0002): checkouts and
# worktrees of both names share it, and the agents' install lock beside it.
MODULE_CACHE := $(HOME)/Library/Caches/video-review/ModuleCache
SWIFT_FLAGS  := -Xswiftc -module-cache-path -Xswiftc $(MODULE_CACHE)
endif

.PHONY: all build test bundle install acceptance agent-logos logo identity clean

all: build

build:
	swift build -c release --product $(APP) $(SWIFT_FLAGS)
	swift build -c release --product $(CLI) $(SWIFT_FLAGS)

test:
	swift test $(SWIFT_FLAGS) $(TEST_FLAGS)

bundle: build
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Helpers" "$(CONTENTS)/Resources"
	cp "$$(swift build -c release --show-bin-path)/$(APP)" "$(CONTENTS)/MacOS/$(APP)"
	cp "$$(swift build -c release --show-bin-path)/$(CLI)" "$(CONTENTS)/Helpers/$(CLI)"
	sed -e 's/__APP_NAME__/$(APP_NAME)/g' -e 's/__BUNDLE_ID__/$(BUNDLE_ID)/g' -e 's/__VERSION__/$(VERSION)/g' \
		Packaging/Info.plist > "$(CONTENTS)/Info.plist"
	@printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	@# The app icon (CFBundleIconFile in Info.plist), and the cat mark the
	@# empty screen, Settings and the header show (Contents/Resources/Logo).
	cp "$(APP_ICON)" "$(CONTENTS)/Resources/AppIcon.icns"
	@mkdir -p "$(CONTENTS)/Resources/Logo"
	cp Packaging/Logo/*.pdf "$(CONTENTS)/Resources/Logo/"
	@# The built-in themes, as plain files beside the code (Contents/Resources/Themes).
	@mkdir -p "$(CONTENTS)/Resources/Themes"
	cp Packaging/Themes/*.json Packaging/Themes/NOTICE.md "$(CONTENTS)/Resources/Themes/"
	@# The agents' logos and their notice, which travels with every copy of
	@# them (Contents/Resources/AgentLogos).
	@mkdir -p "$(CONTENTS)/Resources/AgentLogos"
	cp Packaging/AgentLogos/*.pdf Packaging/AgentLogos/NOTICE.md "$(CONTENTS)/Resources/AgentLogos/"
	@# The demo the empty screen's "Try the demo" opens (Contents/Resources/Demo).
	@mkdir -p "$(CONTENTS)/Resources/Demo"
	cp fixtures/sample/* "$(CONTENTS)/Resources/Demo/"
	@# Ad-hoc: no Developer ID. The command is signed first: the bundle's
	@# signature seals nested code.
	codesign --force --sign - --timestamp=none "$(CONTENTS)/Helpers/$(CLI)"
	codesign --force --sign - --timestamp=none "$(APP_BUNDLE)"
	codesign --verify --strict "$(APP_BUNDLE)"
	@echo "bundled $(APP_BUNDLE) ($(VERSION))"

install: bundle
	@# Only this bundle's app, by the full path of its executable, so a
	@# prototype's app (`Havooch (proto-N).app`) keeps running. One
	@# that hasn't quit after about 10 s is killed.
	@running=$$(printf '%s' "$(INSTALLED)/Contents/MacOS/$(APP)" | sed 's/[][().*^$$+?{}|\\]/\\&/g'); \
	pkill -u "$$USER" -f "^$$running" 2>/dev/null || true; \
	tries=0; while pgrep -u "$$USER" -f "^$$running" >/dev/null; do \
		if [ $$tries -ge 50 ]; then \
			echo "$(APP_NAME) didn't quit within 10 s; killing it"; \
			pkill -9 -u "$$USER" -f "^$$running" 2>/dev/null || true; \
			sleep 0.5; break; \
		fi; \
		tries=$$((tries + 1)); sleep 0.2; \
	done
	rm -rf "$(INSTALLED)"
	ditto "$(APP_BUNDLE)" "$(INSTALLED)"
	@echo "installed $(INSTALLED)"
	@# In the background: the terminal keeps the focus. With
	@# HAVOOCH_SUPPORT_DIR set, on that folder: a check that installs never
	@# opens the person's data, nor moves the earlier name's folder.
	open -g $(if $(HAVOOCH_SUPPORT_DIR),--env "HAVOOCH_SUPPORT_DIR=$(HAVOOCH_SUPPORT_DIR)") "$(INSTALLED)"

# Drives the installed app, in demo mode only. It is not part of `make test`.
acceptance:
	@scripts/acceptance.sh

# Each known agent's logo, kept as its maker's SVG in
# assets/images/agent-logos/ (sources in Packaging/AgentLogos/NOTICE.md),
# converted to the vector PDF the app bundles: macOS can't be relied on to
# load SVG. The PDFs are committed, so bundling doesn't need librsvg; run
# this after changing an SVG (brew install librsvg).
AGENT_LOGO_SVGS := $(wildcard assets/images/agent-logos/*.svg)
AGENT_LOGOS     := Packaging/AgentLogos

agent-logos:
	@mkdir -p $(AGENT_LOGOS)
	@for svg in $(AGENT_LOGO_SVGS); do \
		pdf=$(AGENT_LOGOS)/$$(basename $$svg .svg).pdf; \
		rsvg-convert --format pdf --output $$pdf $$svg || exit 1; \
		echo "drew $$pdf"; \
	done

# The cat mark, as the vector PDFs the app bundles: the full mark, and the
# small cut for 32 points and under. Committed like the agents' logos; run
# this after changing the logo (brew install librsvg).
LOGO_SVGS := assets/images/logo/v2-havuc/havooch-mark.svg assets/images/logo/v2-havuc/havooch-mark-small.svg

logo:
	@mkdir -p Packaging/Logo
	@for svg in $(LOGO_SVGS); do \
		pdf=Packaging/Logo/$$(basename $$svg .svg).pdf; \
		rsvg-convert --format pdf --output $$pdf $$svg || exit 1; \
		echo "drew $$pdf"; \
	done

# One name=value line each, the form $$GITHUB_OUTPUT takes, so the release
# workflow names the zip and the release from the same constants as this file.
identity:
	@echo "app_name=$(APP_NAME)"
	@echo "command=$(CLI)"
	@echo "bundle_id=$(BUNDLE_ID)"
	@echo "version=$(VERSION)"

clean:
	rm -rf $(BUILD_DIR) .build
