# video-review: build, test, bundle, sign and install the app with SwiftPM
# alone (no Xcode project).
#
#   make            build the app and the command (release)
#   make test       run the tests (swift test); never drives the Mac
#   make bundle     build/<app name>.app with the video-review command in
#                   Contents/Helpers, the built-in themes in
#                   Contents/Resources/Themes and the demo video in
#                   Contents/Resources/Demo, ad-hoc signed
#   make install    bundle, then replace /Applications/<app name>.app and open it
#   make acceptance run the acceptance scenario through the installed app's
#                   command, on demo data (scripts/acceptance.sh); after make install
#   make clean

# The executables' names.
APP := VideoReview
CLI := video-review

# The name, the bundle id and the version each live in one Swift constant,
# so the command, the app and `swift test` see the same identity as this file.
APP_NAME  := $(shell sed -n 's/.*static let appName = "\(.*\)".*/\1/p' Sources/ReviewLease/ControlLease.swift)
BUNDLE_ID := $(shell sed -n 's/.*static let bundleID = "\(.*\)".*/\1/p' Sources/ReviewWire/AppIdentity.swift)
VERSION   := $(shell sed -n 's/.*static let app = "\(.*\)".*/\1/p' Sources/ReviewWire/Version.swift)

BUILD_DIR   := build
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS    := $(APP_BUNDLE)/Contents
INSTALLED   := /Applications/$(APP_NAME).app

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
MODULE_CACHE := $(HOME)/Library/Caches/video-review/ModuleCache
SWIFT_FLAGS  := -Xswiftc -module-cache-path -Xswiftc $(MODULE_CACHE)
endif

.PHONY: all build test bundle install acceptance clean

all: build

build:
	swift build -c release --product $(APP) $(SWIFT_FLAGS)
	swift build -c release --product $(CLI) $(SWIFT_FLAGS)

test:
	swift test $(SWIFT_FLAGS) $(TEST_FLAGS)

bundle: build
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Helpers"
	cp "$$(swift build -c release --show-bin-path)/$(APP)" "$(CONTENTS)/MacOS/$(APP)"
	cp "$$(swift build -c release --show-bin-path)/$(CLI)" "$(CONTENTS)/Helpers/$(CLI)"
	sed -e 's/__APP_NAME__/$(APP_NAME)/g' -e 's/__BUNDLE_ID__/$(BUNDLE_ID)/g' -e 's/__VERSION__/$(VERSION)/g' \
		Packaging/Info.plist > "$(CONTENTS)/Info.plist"
	@printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	@# The built-in themes, as plain files beside the code (Contents/Resources/Themes).
	@mkdir -p "$(CONTENTS)/Resources/Themes"
	cp Packaging/Themes/*.json Packaging/Themes/NOTICE.md "$(CONTENTS)/Resources/Themes/"
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
	@# prototype's app (`Video Review (proto-N).app`) keeps running. One
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
	@# In the background: the terminal keeps the focus.
	open -g "$(INSTALLED)"

# Drives the installed app, in demo mode only. It is not part of `make test`.
acceptance:
	@scripts/acceptance.sh

clean:
	rm -rf $(BUILD_DIR) .build
