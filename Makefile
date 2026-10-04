# video-review: build, test, bundle, sign and install the app with SwiftPM
# alone (no Xcode project).
#
#   make            build the app and the CLI (release)
#   make test       run the tests (swift test); never drives the Mac
#   make bundle     build/<APP_NAME>.app with the CLI in Contents/Helpers, ad-hoc signed
#   make install    bundle, quit this build's running app, replace /Applications/<APP_NAME>.app
#   make acceptance run the spec's v1 scenario against the installed app, in demo mode
#   make run        run the app's executable from .build, without a bundle
#   make clean

APP := VideoReview
CLI := video-review-cli

# The build's identity lives in one place, Identity.swift; the bundle is named
# and stamped from it. An empty variant is the real product.
IDENTITY  := Sources/VRWire/Identity.swift
VARIANT   := $(shell sed -n 's/.*static let variant = "\(.*\)".*/\1/p' $(IDENTITY))
VERSION   := $(shell sed -n 's/.*static let version = "\(.*\)".*/\1/p' $(IDENTITY))
ifeq ($(VARIANT),)
APP_NAME  := Video Review
BUNDLE_ID := com.yahyabedirhan.video-review
else
APP_NAME  := Video Review ($(VARIANT))
BUNDLE_ID := com.yahyabedirhan.video-review.$(VARIANT)
endif

# APP_NAME holds spaces and parentheses: every recipe quotes the paths made
# from it, and no target is named after one.
BUILD_DIR   := build
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS    := $(APP_BUNDLE)/Contents
INSTALL_DIR := /Applications
INSTALLED   := $(INSTALL_DIR)/$(APP_NAME).app
# This build's running app, as pkill and pgrep match it: by the full path of
# its executable, never by the name `VideoReview`, which every prototype
# shares. They read a regular expression, so the name's punctuation is escaped.
RUNNING     := $(shell printf '%s' '$(INSTALLED)/Contents/MacOS/' | sed 's/[().]/\\&/g')

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
# checkout's first build compiles Swift, Foundation, SwiftUI and the rest from
# their interfaces. One module cache shared by every checkout and worktree
# pays that once; its entries are keyed by the compiler, the SDK and the flags.
MODULE_CACHE := $(HOME)/Library/Caches/video-review/ModuleCache
SWIFT_FLAGS  := -Xswiftc -module-cache-path -Xswiftc $(MODULE_CACHE)
endif

.PHONY: all build test bundle install acceptance run clean

all: build

build:
	swift build -c release --product $(APP) $(SWIFT_FLAGS)
	swift build -c release --product $(CLI) $(SWIFT_FLAGS)

test:
	swift test $(SWIFT_FLAGS) $(TEST_FLAGS)

run:
	swift run $(APP) $(SWIFT_FLAGS)

bundle: build
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Helpers"
	cp "$$(swift build -c release --show-bin-path)/$(APP)" "$(CONTENTS)/MacOS/$(APP)"
	cp "$$(swift build -c release --show-bin-path)/$(CLI)" "$(CONTENTS)/Helpers/video-review"
	sed -e 's/__APP_NAME__/$(APP_NAME)/g' -e 's/__BUNDLE_ID__/$(BUNDLE_ID)/g' -e 's/__VERSION__/$(VERSION)/g' \
		Packaging/Info.plist > "$(CONTENTS)/Info.plist"
	@printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	@# Ad-hoc: no Developer ID in v1. The CLI is signed first: the bundle's
	@# signature seals nested code.
	codesign --force --sign - --timestamp=none "$(CONTENTS)/Helpers/video-review"
	codesign --force --sign - --timestamp=none "$(APP_BUNDLE)"
	codesign --verify --strict "$(APP_BUNDLE)"
	@echo "bundled $(APP_BUNDLE) ($(VERSION))"

install: bundle
	@# Only this user's copy of this build; one that hasn't quit after about
	@# 10 s is killed. The app isn't started: `video-review app open` does that.
	@pkill -u "$$USER" -f "$(RUNNING)" 2>/dev/null || true
	@tries=0; while pgrep -u "$$USER" -f "$(RUNNING)" >/dev/null; do \
		if [ $$tries -ge 50 ]; then \
			echo "$(APP_NAME) didn't quit within 10 s; killing it"; \
			pkill -9 -u "$$USER" -f "$(RUNNING)" 2>/dev/null || true; \
			sleep 0.5; break; \
		fi; \
		tries=$$((tries + 1)); sleep 0.2; \
	done
	rm -rf "$(INSTALLED)"
	ditto "$(APP_BUNDLE)" "$(INSTALLED)"
	@echo "installed $(INSTALLED)"

# Drives the installed app, so take turns with whoever else uses it. The
# script gets the command line's path and knows nothing else of this build.
acceptance:
	scripts/acceptance.sh "$(INSTALLED)/Contents/Helpers/video-review"

clean:
	rm -rf $(BUILD_DIR) .build
