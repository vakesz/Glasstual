#!/bin/bash

set -e

echo "Building using architecture: ${ARCHS}"

GLASSTUAL_PRODUCT_LOCATION="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}"
GLASSTUAL_PRODUCT_BINARY="${TARGET_BUILD_DIR}/${EXECUTABLE_PATH}"

services=(
    'Historic Log File Manager'
    'Inline Content Loader'
    'IRC Remote Connection Manager'
)

for service in "${services[@]}"; do
    cd "${GLASSTUAL_WORKSPACE_DIR}/XPC Services/${service}/"

    xcodebuild -target "$service" \
        -configuration "${GLASSTUAL_XPC_SERVICE_BUILD_SCHEME}" \
        ARCHS="${ARCHS}" \
        CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY}" \
        DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
        PROVISIONING_PROFILE_SPECIFIER="" \
        GLASSTUAL_WORKSPACE_DIR="${GLASSTUAL_WORKSPACE_DIR}" \
        GLASSTUAL_PRODUCT_LOCATION="${GLASSTUAL_PRODUCT_LOCATION}" \
        GLASSTUAL_PRODUCT_BINARY="${GLASSTUAL_PRODUCT_BINARY}"
done
