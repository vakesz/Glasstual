#!/bin/bash

set -e

echo "Building using architecture: ${ARCHS}"

CONFIGURATION_BUILD_DIR="${GLASSTUAL_WORKSPACE_TEMP_DIR}/SharedBuildProducts-Frameworks"

xcb() {
    target=$1
    xcodebuild -target "$target" \
        -configuration "${GLASSTUAL_FRAMEWORK_BUILD_SCHEME}" \
        ARCHS="${ARCHS}" \
        CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY}" \
        CODE_SIGN_STYLE="${CODE_SIGN_STYLE}" \
        CONFIGURATION_BUILD_DIR="${CONFIGURATION_BUILD_DIR}" \
        DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
        PROVISIONING_PROFILE_SPECIFIER="" \
        DWARF_DSYM_FOLDER_PATH="${DWARF_DSYM_FOLDER_PATH}" \
        MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET}"
}

# Assumes the name and filename of the framework is the same just without spaces.
frameworks=(
    'Auto Hyperlinks'
    'Encryption Kit'
    'Cocoa Extensions'
)

for framework in "${frameworks[@]}"; do
    cd "${GLASSTUAL_WORKSPACE_DIR}/Frameworks/${framework}/"
    xcb "${framework// /}.framework"
done

exit 0
