# video-review: build, test, bundle, sign and install the app with SwiftPM
# alone (no Xcode project).
#
#   make            build the app and the CLI (release)
#   make test       run the tests (swift test); they never drive the Mac
#   make bundle     build/<name>.app with the video-review CLI in Contents/Helpers, ad-hoc signed
#   make install    bundle, then replace /Applications/<name>.app; it isn't opened (`video-review app open`)
#                   refused while another agent holds the running app's lease
#   make acceptance the v1 acceptance scenario through the installed CLI, in demo mode; it drives the app
#   make clean

APP := VideoReview
CLI := video-review
# The build's identity lives in one place, AppIdentity (docs/low-level-design.md,
# "Build identity"): the variant ("" for the real product) and the version.
IDENTITY    := Sources/VRWire/AppIdentity.swift
VARIANT     := $(shell sed -n 's/.*static let variant = "\(.*\)".*/\1/p' $(IDENTITY))
VERSION     := $(shell sed -n 's/.*static let version = "\(.*\)".*/\1/p' $(IDENTITY))
ifeq ($(VARIANT),)
APP_NAME    := Video Review
BUNDLE_ID   := com.yahyabedirhan.video-review
else
APP_NAME    := Video Review ($(VARIANT))
BUNDLE_ID   := com.yahyabedirhan.video-review.$(VARIANT)
endif

BUILD_DIR   := build
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS    := $(APP_BUNDLE)/Contents
INSTALL_DIR := /Applications
INSTALLED   := $(INSTALL_DIR)/$(APP_NAME).app

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
# pays that once.
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
	sed -e 's/__NAME__/$(APP_NAME)/g' -e 's/__BUNDLE_ID__/$(BUNDLE_ID)/g' -e 's/__VERSION__/$(VERSION)/g' \
		Packaging/Info.plist > "$(CONTENTS)/Info.plist"
	@printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	@# Ad-hoc: no Developer ID. The CLI is signed first: the bundle's
	@# signature seals nested code.
	codesign --force --sign - --timestamp=none "$(CONTENTS)/Helpers/$(CLI)"
	codesign --force --sign - --timestamp=none "$(APP_BUNDLE)"
	codesign --verify --strict "$(APP_BUNDLE)"
	@echo "bundled $(APP_BUNDLE) ($(VERSION))"

# This build's installed copy, found by its bundle's path as a fixed string.
# Every variant's process is named VideoReview, so a match by name would end
# another build's app.
RUNNING = ps -u "$$USER" -o pid=,command= | grep -F "$(INSTALLED)/Contents/MacOS/" | grep -v grep | awk '{print $$1}'

install: bundle
	@# Never quit another agent's run: while the app runs, take its lease
	@# first. The lease lives in the app, so the quit below ends it.
	@if [ -n "$$($(RUNNING))" ] && ! "$(INSTALLED)/Contents/Helpers/$(CLI)" control take >/dev/null; then \
		echo "make install: another agent drives $(APP_NAME); not replaced. Try again once it releases the lease."; \
		exit 1; \
	fi
	@# Only this build's copy; one that hasn't quit after about 10 s is killed.
	@pids=$$($(RUNNING)); [ -z "$$pids" ] || kill $$pids 2>/dev/null || true
	@tries=0; while [ -n "$$($(RUNNING))" ]; do \
		if [ $$tries -ge 50 ]; then \
			echo "$(APP_NAME) didn't quit within 10 s; killing it"; \
			kill -9 $$($(RUNNING)) 2>/dev/null || true; \
			sleep 0.5; break; \
		fi; \
		tries=$$((tries + 1)); sleep 0.2; \
	done
	rm -rf "$(INSTALLED)"
	ditto "$(APP_BUNDLE)" "$(INSTALLED)"
	@echo "installed $(INSTALLED)"

# Against what is installed: run `make install` first. VIDEO_REVIEW_CLI names
# another build's CLI.
acceptance:
	@scripts/acceptance.sh

clean:
	rm -rf $(BUILD_DIR) .build
