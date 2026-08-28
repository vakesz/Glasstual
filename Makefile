# Glasstual developer entry points. Run `make help` for a list.

SHELL        := /bin/bash
PROJECT      := Glasstual.xcodeproj
SCHEME       := Glasstual
CONFIG       ?= Debug
DESTINATION  := platform=macOS,arch=arm64
DERIVED_DATA ?= DerivedData
RESULT_BUNDLE ?= build/Glasstual.xcresult
GENERATED_XCODE_DIR := Generated/Xcode
XCODEBUILD   := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA)

.PHONY: help generate validate-generated-metadata build release archive run test coverage lint format format-check ensure-xcodegen ensure-formatters ensure-linters clean

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[1m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

ensure-xcodegen:
	@command -v xcodegen >/dev/null 2>&1 || brew install xcodegen

generate: ensure-xcodegen ## Regenerate Glasstual.xcodeproj from project.yml
	rm -rf "$(GENERATED_XCODE_DIR)"
	xcodegen generate --spec project.yml
	$(MAKE) validate-generated-metadata

validate-generated-metadata: ## Validate XcodeGen-owned Info.plists and entitlements
	@files=(); \
	while IFS= read -r -d '' file; do \
		files+=("$$file"); \
	done < <(find "$(GENERATED_XCODE_DIR)" -type f \( -name '*.plist' -o -name '*.entitlements' \) -print0); \
	if [ "$${#files[@]}" -eq 0 ]; then \
		echo "No generated Xcode metadata found in $(GENERATED_XCODE_DIR)" >&2; \
		exit 1; \
	fi; \
	for file in "$${files[@]}"; do \
		plutil -lint "$$file" >/dev/null; \
	done

build: generate ## Build the app (CONFIG=Debug|Release)
	$(XCODEBUILD) -configuration $(CONFIG) build

release: ## Build a Release configuration
	$(MAKE) build CONFIG=Release

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

coverage: ## Print the line coverage of the last `make test` run
	xcrun xccov view --report --only-targets "$(RESULT_BUNDLE)"

ensure-formatters:
	@command -v swiftformat >/dev/null 2>&1 || brew install swiftformat

ensure-linters: ensure-formatters
	@command -v swiftlint >/dev/null 2>&1 || brew install swiftlint
	@command -v actionlint >/dev/null 2>&1 || brew install actionlint

lint: ensure-linters format-check ## Run whole-tree linters and format checks
	swiftlint lint --strict --no-cache --config .swiftlint.yml Sources Tests
	actionlint
	@git ls-files --cached --others --exclude-standard -z -- '*.entitlements' '*.plist' '*.strings' '*.xcprivacy' | while IFS= read -r -d '' file; do if [ -f "$$file" ] && [ ! -L "$$file" ]; then plutil -lint "$$file" >/dev/null; fi; done
	@git ls-files --cached --others --exclude-standard -z -- '*.xib' '*.xcscheme' '*.xcworkspacedata' | while IFS= read -r -d '' file; do if [ -f "$$file" ] && [ ! -L "$$file" ]; then xmllint --noout "$$file"; fi; done
	git diff --check

format: ensure-formatters ## Format Swift sources in place
	swiftformat --cache ignore Sources Tests

format-check: ensure-formatters ## Verify formatting without changing files
	swiftformat --lint --cache ignore Sources Tests

clean: ## Remove build products and ignored generated metadata
	rm -rf "$(DERIVED_DATA)" build "Build Results" .tmp "$(GENERATED_XCODE_DIR)"
