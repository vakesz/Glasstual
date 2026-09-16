# Glasstual developer entry points. Run `make help` for a list.

SHELL        := /bin/bash
PROJECT      := Glasstual.xcodeproj
SCHEME       := Glasstual
CONFIG       ?= Debug
DESTINATION  := platform=macOS,arch=arm64
DERIVED_DATA ?= DerivedData
RESULT_BUNDLE ?= build/Glasstual.xcresult
TSAN_RESULT_BUNDLE ?= build/Glasstual-tsan.xcresult
E2E_APP ?= $(DERIVED_DATA)/Build/Products/Debug/Glasstual.app
E2E_OUTPUT ?= build/e2e
GENERATED_XCODE_DIR := Generated/Xcode
E2E_HELPER   := $(abspath $(DERIVED_DATA))/Build/Products/Debug/GlasstualE2EHarness
# Extra build settings for every xcodebuild call, such as the signing overrides
# the Quality workflow passes. The shell parses the value, so quote any setting
# that contains a space.
XCODEBUILD_FLAGS ?=
XCODEBUILD   := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) $(XCODEBUILD_FLAGS)

# scripts/ensure-tool.sh puts a wrapper for each pinned tool here, and every
# recipe runs the tool through that wrapper by its full path. Exporting PATH
# from the Makefile is not enough: Apple's GNU Make 3.81, the /usr/bin/make on
# the CI runner, execs a plain recipe line with its own PATH, not the exported
# one. `make clean` removes the wrappers with the rest of build/.
TOOLS_BIN    := $(CURDIR)/build/tools/bin

.PHONY: help generate validate-generated-metadata build archive run test tsan smoke e2e e2e-build e2e-fixtures coverage lint format format-check ensure-xcodegen ensure-formatters ensure-linters clean

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_-]+:.*##/ {printf "  \033[1m%-27s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

ensure-xcodegen:
	@scripts/ensure-tool.sh xcodegen

generate: ensure-xcodegen ## Regenerate Glasstual.xcodeproj from project.yml
	rm -rf "$(GENERATED_XCODE_DIR)"
	$(TOOLS_BIN)/xcodegen generate --spec project.yml
	$(MAKE) validate-generated-metadata

# The list travels NUL-separated so a newline in a path cannot split one name
# into two; `-s` on the list file is the emptiness check, and `plutil -lint -s`
# stays quiet until a file is malformed, which makes xargs exit non-zero.
validate-generated-metadata: ## Validate XcodeGen-owned Info.plists and entitlements
	@set -euo pipefail; \
	list="$$(mktemp)"; trap 'rm -f "$$list"' EXIT; \
	find "$(GENERATED_XCODE_DIR)" -type f \( -name '*.plist' -o -name '*.entitlements' \) -print0 >"$$list"; \
	[ -s "$$list" ] || { echo "No generated Xcode metadata found in $(GENERATED_XCODE_DIR)" >&2; exit 1; }; \
	xargs -0 plutil -lint -s <"$$list"

build: generate ## Build the app (CONFIG=Debug|Release)
	$(XCODEBUILD) -configuration $(CONFIG) build

archive: generate ## Create a Release archive in build/
	$(XCODEBUILD) -configuration Release -archivePath build/Glasstual.xcarchive archive

run: build ## Build and launch the Debug app
	open "$(DERIVED_DATA)/Build/Products/$(CONFIG)/Glasstual.app"

# The scheme's test action sets gatherCoverageData, so the run always measures
# coverage; -resultBundlePath is what keeps the measurement afterwards. Read it
# with `make coverage`, or open the bundle in Xcode.
test: generate ## Run the unit tests (GlasstualTests) inside the Debug app
	rm -rf "$(RESULT_BUNDLE)"
	$(XCODEBUILD) -configuration Debug -resultBundlePath "$(RESULT_BUNDLE)" test

# ThreadSanitizer instruments every memory access, so the suite runs roughly
# ten times slower and needs its own result bundle. It stays out of CI: the
# runtime cost is too high for every push, and a TSan report is a diagnosis to
# read rather than a pass/fail signal. Run it before merging isolation work.
tsan: generate ## Run the test suite under ThreadSanitizer (local only, not in CI)
	rm -rf "$(TSAN_RESULT_BUNDLE)"
	$(XCODEBUILD) -configuration Debug -enableThreadSanitizer YES \
		-resultBundlePath "$(TSAN_RESULT_BUNDLE)" test

smoke: ## Seeded launch of about a minute with an accessibility probe (see scripts/smoke.sh)
	./scripts/smoke.sh

e2e: e2e-build ## Real-app Swift Testing gate (disposable GUI login + AX grant)
	E2E_APP="$(abspath $(E2E_APP))" E2E_OUTPUT="$(abspath $(E2E_OUTPUT))" E2E_HELPER="$(E2E_HELPER)" \
		DERIVED_DATA="$(abspath $(DERIVED_DATA))" bash scripts/e2e.sh

# Both E2E entry points need the harness binary before anything runs: the
# fixtures execute it directly, and scripts/e2e.sh copies it as the supervisor.
e2e-build: generate ## Build the GlasstualE2E scheme (app, harness and E2E tests) for testing
	xcodebuild -quiet -project "$(PROJECT)" -scheme GlasstualE2E -destination '$(DESTINATION)' \
		-derivedDataPath "$(DERIVED_DATA)" -configuration Debug $(XCODEBUILD_FLAGS) build-for-testing

e2e-fixtures: e2e-build ## Build and check loopback peers without launching the app or using Accessibility
	E2E_HELPER="$(E2E_HELPER)" bash scripts/e2e-fixtures.sh

coverage: ## Print the line coverage of the last `make test` run
	xcrun xccov view --report --only-targets "$(RESULT_BUNDLE)"

ensure-formatters:
	@scripts/ensure-tool.sh swiftformat

ensure-linters: ensure-formatters
	@scripts/ensure-tool.sh swiftlint
	@scripts/ensure-tool.sh actionlint
	@scripts/ensure-tool.sh shellcheck

lint: ensure-linters format-check ## Run whole-tree linters and format checks
	$(TOOLS_BIN)/swiftlint lint --strict --no-cache --config .swiftlint.yml Sources Tests
	$(TOOLS_BIN)/actionlint
	$(TOOLS_BIN)/shellcheck scripts/*.sh
	@set -euo pipefail; git ls-files --cached --others --exclude-standard -z -- '*.entitlements' '*.plist' '*.strings' '*.xcprivacy' | while IFS= read -r -d '' file; do if [ -f "$$file" ] && [ ! -L "$$file" ]; then plutil -lint "$$file" >/dev/null || exit 1; fi; done
	@set -euo pipefail; git ls-files --cached --others --exclude-standard -z -- '*.xib' '*.xcscheme' '*.xcworkspacedata' | while IFS= read -r -d '' file; do if [ -f "$$file" ] && [ ! -L "$$file" ]; then xmllint --noout "$$file" || exit 1; fi; done
	git diff --check

format: ensure-formatters ## Format Swift sources in place
	$(TOOLS_BIN)/swiftformat --cache ignore Sources Tests

format-check: ensure-formatters ## Verify formatting without changing files
	$(TOOLS_BIN)/swiftformat --lint --cache ignore Sources Tests

clean: ## Remove build products and ignored generated metadata
	rm -rf "$(DERIVED_DATA)" build "Build Results" .tmp "$(GENERATED_XCODE_DIR)"
