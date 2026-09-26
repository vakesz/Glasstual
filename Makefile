# Glasstual developer entry points. Run `make help` for a list.

SHELL        := /bin/bash
PROJECT      := Glasstual.xcodeproj
SCHEME       := Glasstual
CONFIG       ?= Debug
DESTINATION  := platform=macOS,arch=arm64
# Leave these unset to use Xcode's configured Derived Data, test results and archives.
DERIVED_DATA ?=
RESULT_BUNDLE ?=
TSAN_RESULT_BUNDLE ?=
ARCHIVE_PATH ?=
GENERATED_XCODE_DIR := Generated/Xcode
export DERIVED_DATA CONFIG E2E_APP E2E_OUTPUT E2E_HELPER
# Extra build settings for every xcodebuild call, such as the signing overrides
# the Signed Release workflow passes. The shell parses the value, so quote any setting
# that contains a space.
XCODEBUILD_FLAGS ?=
XCODEBUILD   := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' $(if $(DERIVED_DATA),-derivedDataPath "$(DERIVED_DATA)") $(XCODEBUILD_FLAGS)

# Absolute wrappers work with Apple's Make 3.81, which ignores an exported PATH.
GLASSTUAL_TOOLS_DIR ?= $(HOME)/Library/Caches/Glasstual/Tools
export GLASSTUAL_TOOLS_DIR
TOOLS_BIN := $(GLASSTUAL_TOOLS_DIR)/bin

.PHONY: help generate validate-generated-metadata build archive run test tsan smoke e2e e2e-build e2e-fixtures lint format format-check ensure-xcodegen ensure-formatters ensure-linters clean

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_-]+:.*##/ {printf "  \033[1m%-27s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

ensure-xcodegen:
	@scripts/ensure-tool.sh xcodegen

generate: ensure-xcodegen ## Regenerate Glasstual.xcodeproj from project.yml
	rm -rf "$(GENERATED_XCODE_DIR)"
	"$(TOOLS_BIN)/xcodegen" generate --spec project.yml
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

archive: generate ## Create a Release archive in Xcode's Archives folder
	$(XCODEBUILD) -configuration Release $(if $(ARCHIVE_PATH),-archivePath "$(ARCHIVE_PATH)") archive

run: build ## Build and launch the Debug app
	@set -e; source scripts/build-paths.sh; open "$$BUILD_PRODUCTS/Glasstual.app"

# Coverage and test results use Xcode's Logs/Test directory unless overridden.
test: generate ## Run the unit tests (GlasstualTests) inside the Debug app
	$(XCODEBUILD) -configuration Debug $(if $(RESULT_BUNDLE),-resultBundlePath "$(RESULT_BUNDLE)") test

# Run locally when changing isolation; instrumentation makes the suite slower.
tsan: generate ## Run the test suite under ThreadSanitizer
	$(XCODEBUILD) -configuration Debug -enableThreadSanitizer YES \
		$(if $(TSAN_RESULT_BUNDLE),-resultBundlePath "$(TSAN_RESULT_BUNDLE)") test

smoke: ## Seeded launch of about a minute with an accessibility probe (see scripts/smoke.sh)
	CONFIG=Debug bash scripts/smoke.sh

e2e: e2e-build ## Real-app Swift Testing gate (disposable GUI login + AX grant)
	CONFIG=Debug bash scripts/e2e.sh

# Both E2E entry points need the harness binary before anything runs: the
# fixtures execute it directly, and scripts/e2e.sh copies it as the supervisor.
e2e-build: generate ## Build the GlasstualE2E scheme (app, harness and E2E tests) for testing
	xcodebuild -quiet -project "$(PROJECT)" -scheme GlasstualE2E -destination '$(DESTINATION)' \
		$(if $(DERIVED_DATA),-derivedDataPath "$(DERIVED_DATA)") -configuration Debug $(XCODEBUILD_FLAGS) build-for-testing

e2e-fixtures: e2e-build ## Build and check loopback peers without launching the app or using Accessibility
	CONFIG=Debug bash scripts/e2e-fixtures.sh

ensure-formatters:
	@scripts/ensure-tool.sh swiftformat

ensure-linters: ensure-formatters
	@scripts/ensure-tool.sh swiftlint
	@scripts/ensure-tool.sh actionlint
	@scripts/ensure-tool.sh shellcheck

# actionlint resolves `shellcheck` from PATH and silently disables the check on
# inline `run:` blocks when it is absent, which is every CI run: the hosted macOS
# image does not preinstall it, and this Makefile deliberately does not export a
# PATH. Naming the pinned binary is what makes the gate mean the same thing here
# and there. `-pyflakes=` disables the Python check as a decision rather than by
# the same accident. `shellcheck scripts/*.sh` below covers only the checked-in
# scripts, never the YAML.
lint: ensure-linters format-check ## Run whole-tree linters and format checks
	"$(TOOLS_BIN)/swiftlint" lint --strict --no-cache --config .swiftlint.yml Sources Tests
	"$(TOOLS_BIN)/actionlint" -shellcheck "$(TOOLS_BIN)/shellcheck" -pyflakes=
	"$(TOOLS_BIN)/shellcheck" --external-sources --source-path=SCRIPTDIR scripts/*.sh
	@set -euo pipefail; git ls-files --cached --others --exclude-standard -z -- '*.entitlements' '*.plist' '*.strings' '*.xcprivacy' | while IFS= read -r -d '' file; do if [ -f "$$file" ] && [ ! -L "$$file" ]; then plutil -lint "$$file" >/dev/null || exit 1; fi; done
	git diff --check

format: ensure-formatters ## Format Swift sources in place
	"$(TOOLS_BIN)/swiftformat" --cache ignore Sources Tests

format-check: ensure-formatters ## Verify formatting without changing files
	"$(TOOLS_BIN)/swiftformat" --lint --cache ignore Sources Tests

clean: ## Clean this project's build products and generated files
	@if [ -d "$(PROJECT)" ]; then $(XCODEBUILD) -configuration $(CONFIG) clean; fi
	rm -rf "$(GENERATED_XCODE_DIR)"
