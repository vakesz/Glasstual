#!/bin/bash
# Install and remove the Developer ID signing material on a hosted CI runner.
#
# The Signed Release workflow signs its archive with it. Nothing stays on the
# runner: `install` creates a throwaway keychain and copies two provisioning
# profiles, and `remove` deletes both again.
#
# Usage
#   scripts/ci-signing.sh install   needs CERT_P12 (base64) and CERT_PASSWORD
#   scripts/ci-signing.sh remove    safe to run when install failed part-way
#
# Both run inside GitHub Actions and read RUNNER_TEMP. `install` records
# KEYCHAIN_PATH in GITHUB_ENV for `remove`.

set -euo pipefail

: "${RUNNER_TEMP:?run this inside GitHub Actions}"

profile_archive=".github/signing/DeveloperIDProfiles.tar.gz"
profile_source_dir="$RUNNER_TEMP/glasstual-profiles"
# Xcode 16 and later read profiles from UserData; older tooling reads MobileDevice.
profile_dirs=(
	"$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
	"$HOME/Library/MobileDevice/Provisioning Profiles"
)
# File name in the archive, then the UUID the profile must carry.
profiles=(
	"Glasstual_Developer_ID.provisionprofile" "1e065476-c63a-4093-b027-e12cdbc03a56"
	"Glasstual_IRC_Connection_Host_Developer_ID.provisionprofile" "efad779e-5dc8-46fb-8466-d4c5a78b5591"
)

fail() {
	echo "::error::$*" >&2
	exit 1
}

import_certificate() {
	: "${GITHUB_ENV:?run this inside GitHub Actions}"
	if [ -z "${CERT_P12:-}" ] || [ -z "${CERT_PASSWORD:-}" ]; then
		fail "Developer ID certificate secrets are not set."
	fi

	local keychain_path="$RUNNER_TEMP/glasstual-signing.keychain-db"
	local keychain_password certificate="$RUNNER_TEMP/certificate.p12"
	keychain_password="$(uuidgen)"
	echo "KEYCHAIN_PATH=$keychain_path" >> "$GITHUB_ENV"

	security create-keychain -p "$keychain_password" "$keychain_path"
	security set-keychain-settings -lut 21600 "$keychain_path"
	security unlock-keychain -p "$keychain_password" "$keychain_path"

	printf '%s' "$CERT_P12" | base64 --decode > "$certificate"
	security import "$certificate" \
		-k "$keychain_path" \
		-P "$CERT_PASSWORD" \
		-T /usr/bin/codesign -T /usr/bin/security
	rm -f "$certificate"

	security set-key-partition-list -S apple-tool:,apple:,codesign: \
		-s -k "$keychain_password" "$keychain_path" > /dev/null
	security list-keychain -d user -s "$keychain_path" login.keychain-db
	security find-identity -v -p codesigning "$keychain_path" |
		grep -q 'Developer ID Application' ||
		fail "The imported certificate is not a Developer ID Application identity."
}

install_profiles() {
	local index filename uuid source actual_uuid dir
	mkdir -p "$profile_source_dir" "${profile_dirs[@]}"
	tar -xzf "$profile_archive" -C "$profile_source_dir"

	for ((index = 0; index < ${#profiles[@]}; index += 2)); do
		filename="${profiles[index]}"
		uuid="${profiles[index + 1]}"
		source="$profile_source_dir/$filename"
		actual_uuid="$(security cms -D -i "$source" | plutil -extract UUID raw -o - -)"
		[ "$actual_uuid" = "$uuid" ] || fail "Unexpected UUID in $filename."
		for dir in "${profile_dirs[@]}"; do
			cp "$source" "$dir/$uuid.mobileprovision"
		done
	done
}

remove() {
	local index dir
	if [ -n "${KEYCHAIN_PATH:-}" ]; then
		security delete-keychain "$KEYCHAIN_PATH" 2> /dev/null || true
	fi
	rm -rf "$RUNNER_TEMP/certificate.p12" "$profile_source_dir"
	for ((index = 1; index < ${#profiles[@]}; index += 2)); do
		for dir in "${profile_dirs[@]}"; do
			rm -f "$dir/${profiles[index]}.mobileprovision"
		done
	done
}

case "${1:-}" in
	install)
		import_certificate
		install_profiles
		;;
	remove) remove ;;
	*) fail "Usage: $0 {install|remove}" ;;
esac
