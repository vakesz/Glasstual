# Glasstual developer entry points. Run `make help` for a list.

PROJECT      := Glasstual.xcodeproj
SCHEME       := Glasstual
CONFIG       ?= Debug
DESTINATION  := platform=macOS,arch=arm64
DERIVED_DATA ?= DerivedData
XCODEBUILD   := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA)

.PHONY: help setup generate build release archive run test lint format format-check clean

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[1m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: ## Install development tools from the Brewfile
	brew bundle

generate: ## Regenerate Glasstual.xcodeproj from project.yml
	xcodegen generate --spec project.yml

build: generate ## Build the app (CONFIG=Debug|Release)
	./Scripts/UpdateVersion.sh
	$(XCODEBUILD) -configuration $(CONFIG) build

release: ## Build a Release configuration
	$(MAKE) build CONFIG=Release

archive: generate ## Create a Release archive in build/
	./Scripts/UpdateVersion.sh
	$(XCODEBUILD) -configuration Release -archivePath build/Glasstual.xcarchive archive

run: build ## Build and launch the Debug app
	open "$(DERIVED_DATA)/Build/Products/$(CONFIG)/Glasstual.app"

lint: ## Run shellcheck, actionlint, plist/xib validation and format checks
	./Scripts/lint.sh

format: ## Format Objective-C, Swift and shell sources in place
	./Scripts/format.sh

format-check: ## Verify formatting without changing files
	./Scripts/format.sh --check

clean: ## Remove build products and generated files
	rm -rf $(DERIVED_DATA) build "Build Results" .tmp Configurations/Version.generated.xcconfig
