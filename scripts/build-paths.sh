#!/bin/bash
# Source this file to locate products using Xcode's configured build location.
# DERIVED_DATA and CONFIG may override the location and configuration.

build_paths_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
build_paths_arguments=(
	-project "$build_paths_root/Glasstual.xcodeproj"
	-scheme Glasstual
	-configuration "${CONFIG:-Debug}"
	-destination 'platform=macOS,arch=arm64'
	-showBuildSettings -json
)
if [[ -n "${DERIVED_DATA:-}" ]]; then
	build_paths_arguments+=(-derivedDataPath "$DERIVED_DATA")
fi
build_paths_settings="$(xcodebuild "${build_paths_arguments[@]}")" || return
BUILD_PRODUCTS="$(plutil -extract 0.buildSettings.CONFIGURATION_BUILD_DIR raw -o - - <<< "$build_paths_settings")" || return
build_paths_identifier="$(printf '%s' "$build_paths_root" | shasum -a 256 | cut -c 1-12)"
BUILD_LOGS="$HOME/Library/Logs/Glasstual/$(basename -- "$build_paths_root")-$build_paths_identifier"
export BUILD_PRODUCTS BUILD_LOGS
unset build_paths_root build_paths_arguments build_paths_settings build_paths_identifier
