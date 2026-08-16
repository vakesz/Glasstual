#!/bin/bash

set -e

echo "Building using architecture: ${ARCHS}"

GLASSTUAL_PRODUCT_LOCATION="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}"
GLASSTUAL_PRODUCT_BINARY="${TARGET_BUILD_DIR}/${EXECUTABLE_PATH}"

plugins=(
    'Caffeine'
    'Chat Filter'
    'Smiley Converter'
    'System Profiler'
    'User Insights'
    'ZNC Additions'
)

for plugin in "${plugins[@]}"; do
    cd "${GLASSTUAL_WORKSPACE_DIR}/Sources/Plugins/${plugin}"
    xcodebuild -target "$plugin Extension" \
        -configuration "${GLASSTUAL_EXTENSION_BUILD_SCHEME}" \
        ARCHS="${ARCHS}" \
        CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY}" \
        CODE_SIGN_STYLE="${CODE_SIGN_STYLE}" \
        DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
        PROVISIONING_PROFILE_SPECIFIER="" \
        GLASSTUAL_WORKSPACE_DIR="${GLASSTUAL_WORKSPACE_DIR}" \
        GLASSTUAL_PRODUCT_LOCATION="${GLASSTUAL_PRODUCT_LOCATION}" \
        GLASSTUAL_PRODUCT_BINARY="${GLASSTUAL_PRODUCT_BINARY}"

done

exit 0
