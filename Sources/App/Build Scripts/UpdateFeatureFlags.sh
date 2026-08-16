#!/bin/bash

set -e

cd "${GLASSTUAL_WORKSPACE_TEMP_DIR}/Build Headers/"

echo "
/* ANY CHANGES TO THIS FILE WILL NOT BE SAVED AND WILL NOT BE COMMITTED */
" > _FeatureFlags.h

featureNames=("GLASSTUAL_BUILT_INSIDE_SANDBOX"
	"GLASSTUAL_BUILT_WITH_SPARKLE_ENABLED"
	"GLASSTUAL_BUILT_WITH_ADVANCED_ENCRYPTION"
	"GLASSTUAL_BUILT_AS_UNIVERSAL_BINARY")

for feature in "${featureNames[@]}"; do
	featureValue="${!feature}"

	if [ -n "${featureValue}" ]; then
		echo "#define ${feature} ${featureValue}" >> _FeatureFlags.h
	else
		echo "#define ${feature} 0" >> _FeatureFlags.h
	fi
done

if cmp -s "FeatureFlags.h" "_FeatureFlags.h"; then
	echo "The feature flags file hasn't changed. Not deploying."

	rm "_FeatureFlags.h"
else
	# Force flag is used on rm to avoid error for missing file
	rm -f "FeatureFlags.h"

	mv "_FeatureFlags.h" "FeatureFlags.h"
fi

# ------ #

# Exit with success
exit 0
