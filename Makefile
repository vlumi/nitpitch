# Nitpitch — command-line build/run/test, so you never have to open Xcode.
#
# The Scripts/*.sh do the actual work (one job each); this Makefile wires up the
# dependencies (e.g. the Xcode project is regenerated only when project.yml or
# an Info.plist changes) and gives short targets. Run `make` (or `make help`)
# to list them.

.DEFAULT_GOAL := help

.PHONY: help
help:  ## List the available commands
	@echo "Nitpitch — available make targets:"
	@awk 'BEGIN {FS = ":.*## "} \
		/^##@ / {printf "\n\033[1m%s\033[0m\n", substr($$0, 5); next} \
		/^##~ / {printf "  \033[2m%s\033[0m\n", substr($$0, 5); next} \
		/^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

##@ Dev — build, run, test

# Inputs xcodegen reads — regenerate the project when any of these change.
PROJECT_INPUTS := project.yml \
	$(wildcard Sources/*/Info.plist) \
	$(wildcard Sources/*/*.xcstrings)

# File target: the generated project depends on its inputs, so `make` skips the
# regen when nothing changed (and reruns it when project.yml etc. are edited).
Nitpitch.xcodeproj: $(PROJECT_INPUTS)
	@Scripts/generate.sh

.PHONY: generate
generate: Nitpitch.xcodeproj  ## Regenerate Nitpitch.xcodeproj from project.yml (if stale)

.PHONY: run-mac
run-mac: Nitpitch.xcodeproj  ## Build + launch the macOS app
	@Scripts/run.sh

.PHONY: run-iphone
run-iphone: Nitpitch.xcodeproj  ## Build + launch on an iPhone simulator (DEVICE="SE" / "17 Pro" to pick)
	@Scripts/run-ios.sh iphone "$(DEVICE)"

.PHONY: demo-iphone
demo-iphone: Nitpitch.xcodeproj  ## Build + launch on a simulator with a synthetic reading (no mic needed)
	@LAUNCH_ARGS=-demo Scripts/run-ios.sh iphone "$(DEVICE)"

.PHONY: demo-mac
demo-mac: Nitpitch.xcodeproj  ## Build + launch the Mac app with a synthetic reading
	@LAUNCH_ARGS=-demo Scripts/run.sh

.PHONY: debug-iphone
debug-iphone: Nitpitch.xcodeproj  ## Build + launch on a simulator with the detector diagnostics screen
	@LAUNCH_ARGS=-debug Scripts/run-ios.sh iphone "$(DEVICE)"

.PHONY: debug-mac
debug-mac: Nitpitch.xcodeproj  ## Build + launch the Mac app with the detector diagnostics screen
	@LAUNCH_ARGS=-debug Scripts/run.sh

.PHONY: run-ipad
run-ipad: Nitpitch.xcodeproj  ## Build + launch on an iPad simulator (DEVICE="Air" / "13-inch" to pick)
	@Scripts/run-ios.sh ipad "$(DEVICE)"

.PHONY: build-mac
build-mac: Nitpitch.xcodeproj  ## Build the macOS app
	@Scripts/build.sh macos

.PHONY: build-ios
build-ios: Nitpitch.xcodeproj  ## Build the iOS app (simulator)
	@Scripts/build.sh ios

# Logic tests run straight from the Swift package — no Xcode project involved.
.PHONY: test
test:  ## Run the package logic tests (no Xcode project needed)
	@Scripts/test.sh

# UI tests are local-only (CI never runs `xcodebuild test`); they drive the
# built iOS app in a simulator.
.PHONY: uitest
uitest: Nitpitch.xcodeproj  ## Run the local-only iOS UI tests (simulator)
	@Scripts/uitest.sh

.PHONY: clean
clean:  ## Remove the generated project + local build output
	@rm -rf Nitpitch.xcodeproj .build-xcode
	@echo "removed Nitpitch.xcodeproj and .build-xcode"

##@ Release lane
##~ Cut a build: make release (PLATFORM=all|ios|macos) — runs preflight → publish → tag → distribute

# The cut is split by concern, one script each, chained here in order:
#   preflight → publish → tag → distribute
# The pure ends (preflight, tag, distribute) re-derive their inputs from git +
# project.yml, so each runs standalone. The dirty middle (publish: version-bump
# prompts + auto-merging PR + CI-wait) is the one stateful script; state crosses
# to the later steps via the merged commit on main, not through Make.
#
# PLATFORM selects scope (default all); UPLOAD=0 stops after export (no ASC
# upload). The steps are a linear dependency chain so they stay ordered even
# under `make -j`. Run from a clean, up-to-date main.
PLATFORM ?= all
UPLOAD ?= 1
DIST_FLAGS := $(if $(filter 0,$(UPLOAD)),--no-upload,)

.PHONY: release
release: release-distribute  ## Cut a release (PLATFORM=all|ios|macos, UPLOAD=0 to skip ASC)
	@echo "✓ release complete (PLATFORM=$(PLATFORM))."

.PHONY: release-build
release-build:  ## Like `release` but stop after export (no upload)
	@$(MAKE) release UPLOAD=0

.PHONY: release-preflight
release-preflight:  ## Release step 1: verify a clean, up-to-date base (main or release/X.Y.x)
	@Scripts/release-preflight.sh

.PHONY: release-publish
release-publish: release-preflight  ## Release step 2: bump, open auto-merging PR, wait for CI
	@Scripts/release-publish.sh $(PLATFORM)

.PHONY: release-tag
release-tag: release-publish  ## Release step 3: tag the merge commit + publish GitHub releases
	@Scripts/release-tag.sh $(PLATFORM)

.PHONY: release-distribute
release-distribute: release-tag  ## Release step 4: archive/export (+ upload unless UPLOAD=0)
	@Scripts/release-distribute.sh $(PLATFORM) $(DIST_FLAGS)

# Distribute is the likeliest step to fail (archive/export/ASC upload) and is
# safe to repeat. This standalone retry has NO prereqs — it re-distributes an
# already-tagged release without touching git/PR/tags, after verifying the tag
# for the current version+build exists.
.PHONY: release-distribute-retry
release-distribute-retry:  ## Re-distribute an already-tagged release (no PR/tag steps)
	@Scripts/release-distribute.sh $(PLATFORM) $(DIST_FLAGS) --require-tag

# Upload the package already in dist/ (from a prior `release-build`) without
# rebuilding — for when export succeeded but only the ASC upload failed.
.PHONY: release-upload
release-upload:  ## Upload the already-built dist/ package (no rebuild)
	@Scripts/release-distribute.sh $(PLATFORM) --upload-only

##@ App Store listing
##~ Screenshot refresh: make shots → make asc-screenshots → make asc-screenshots-apply

# The listing (text + screenshots) is managed from the repo — Scripts/asc/ —
# never the ASC UI. Everything is dry-run unless the target says -apply.
# `filter-out all`: the release lane defaults PLATFORM=all, which is not a
# screenshot platform; stripped here so shoot.sh's own default (iphone) wins.
.PHONY: shots
shots: Nitpitch.xcodeproj  ## Guided screenshot capture: PLATFORM=iphone|ipad|mac [OUT=shots]
	@PLATFORM="$(filter-out all,$(PLATFORM))" OUT="$(OUT)" Scripts/shoot.sh

.PHONY: shots-organize
shots-organize:  ## Rename freehand captures: PLATFORM=iphone|ipad|mac DIR=<folder>
	@Scripts/asc/run.sh organize "$(filter-out all,$(PLATFORM))" $(if $(DIR),"$(DIR)",--list)

.PHONY: asc-listing
asc-listing:  ## Dry-run the listing text sync (Scripts/asc/listing.json → ASC)
	@Scripts/asc/run.sh listing

.PHONY: asc-listing-apply
asc-listing-apply:  ## Push the listing text to App Store Connect
	@Scripts/asc/run.sh listing --apply

.PHONY: asc-screenshots
asc-screenshots:  ## Dry-run the screenshot upload (shots/ → ASC)
	@Scripts/asc/run.sh screens

.PHONY: asc-screenshots-apply
asc-screenshots-apply:  ## Replace + upload the screenshots, in store order
	@Scripts/asc/run.sh screens --apply
