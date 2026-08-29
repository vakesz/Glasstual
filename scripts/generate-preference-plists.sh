#!/bin/bash
# Writes the five preference plists from the typed `PreferenceKey` declarations,
# which are the source of truth. Nothing in the plists is authored by hand.
#
# The tool it builds is the declarations themselves -- the same
# `Preferences.GeneratedResources` the application and `PreferenceCatalogTests`
# read -- compiled together with `scripts/PreferencePlistGenerator.swift`. So
# the files it writes cannot describe a key the code does not declare, and the
# drift test compares the checked-in copies against that same derivation.
#
# The declarations take their property-list value type from CocoaExtensions, so
# the tool compiles against a stand-in module of that name built from that one
# file rather than against the built framework. That keeps this a few seconds of
# `swiftc` instead of a nested build, which matters because it runs as a build
# phase of the application.
#
# Usage
#   scripts/generate-preference-plists.sh          rewrite the plists in place
#   scripts/generate-preference-plists.sh --check  fail if a checked-in copy has drifted

set -uo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

check_only=0

case "${1-}" in
	"") ;;
	--check) check_only=1 ;;
	--help | -h)
		sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		echo "generate-preference-plists: unknown argument '$1' (expected --check)" >&2
		exit 2
		;;
esac

cd "$repo_root" || exit 2

output_dir="Sources/App/Resources/Property Lists/Preferences"

# The declarations, plus the little that they need to compile: the store they
# extend and the application group it names its suite after.
# The one file the stand-in CocoaExtensions module is built from.
cocoa_extensions_sources=(
	"Sources/Frameworks/Cocoa Extensions/Classes/PropertyListValue.swift"
)

sources=(
	"Sources/Shared/Application/ApplicationGroup.swift"
	"Sources/Shared/Preferences/TPCPreferencesUserDefaults.swift"
	"Sources/Shared/Preferences/PreferenceKey.swift"
	# The inline-media keys are declared here rather than under Keys/ because
	# the inline-content service compiles this file too.
	"Sources/Shared/Preferences/TPCPreferences.swift"
	# The enumerations a typed declaration names as its default, and the
	# notification events whose per-event keys are declared one by one.
	"Sources/App/Preferences/PreferenceTypes.swift"
	"Sources/App/Features/Notifications/NotificationEvent.swift"
	"scripts/PreferenceGeneratorStandIns.swift"
	"scripts/PreferencePlistGenerator.swift"
)

for file in "Sources/App/Preferences/Keys/"*.swift; do
	case "$file" in
		# Observation and SwiftUI wrappers around the declarations rather than
		# declarations, and the only file here that needs either framework.
		*/ObservablePreferences.swift) continue ;;
	esac

	sources+=("$file")
done

for source in "${cocoa_extensions_sources[@]}" "${sources[@]}"; do
	if [ ! -f "$source" ]; then
		echo "generate-preference-plists: missing input $source" >&2
		exit 2
	fi

	# Run as a build phase this is sandboxed to the files project.yml declares
	# as inputs, one by one -- naming the directory does not cover what is in
	# it. So a new declaration file is unreadable until it is declared there.
	if [ ! -r "$source" ]; then
		echo "generate-preference-plists: cannot read $source" >&2
		echo "generate-preference-plists: add it to the 'Generate preference plists' inputFiles in project.yml" >&2
		exit 2
	fi
done

# Under `ENABLE_USER_SCRIPT_SANDBOXING` a build phase may only write inside the
# target's temporary directory, so the tool is built where the build says.
build_dir="${TEMP_DIR:-$repo_root/.tmp}/preference-plists"
mkdir -p "$build_dir" || exit 2

# Recompiling on every build of the application would cost several seconds for
# nothing, so the tool is rebuilt only when one of its inputs changes.
stamp="$(shasum -a 256 "${cocoa_extensions_sources[@]}" "${sources[@]}" | shasum -a 256)"
tool="$build_dir/generate-preference-plists"

if [ ! -x "$tool" ] || [ "$(cat "$build_dir/inputs.sha256" 2>/dev/null)" != "$stamp" ]; then
	rm -rf "$build_dir/CocoaExtensions.swiftmodule" "$build_dir/CocoaExtensions.o"

	# The interface for the declarations to compile against, and the code for
	# them to link against: the stand-in carries a real type now, not a name.
	if ! xcrun swiftc -swift-version 6 -O -wmo -parse-as-library -module-name CocoaExtensions \
		-emit-module -emit-module-path "$build_dir/CocoaExtensions.swiftmodule" \
		"${cocoa_extensions_sources[@]}" ||
		! xcrun swiftc -swift-version 6 -O -wmo -parse-as-library -module-name CocoaExtensions \
			-c -o "$build_dir/CocoaExtensions.o" "${cocoa_extensions_sources[@]}"; then
		echo "generate-preference-plists: could not build the CocoaExtensions stand-in" >&2
		exit 1
	fi

	if ! xcrun swiftc -swift-version 6 -O -module-name PreferencePlistGenerator \
		-I "$build_dir" -o "$tool" "${sources[@]}" "$build_dir/CocoaExtensions.o"; then
		echo "generate-preference-plists: the declarations did not compile" >&2
		exit 1
	fi

	printf '%s' "$stamp" > "$build_dir/inputs.sha256"
fi

if [ "$check_only" -eq 1 ]; then
	staging="$build_dir/staging"
	rm -rf "$staging"
	mkdir -p "$staging" || exit 2

	if ! "$tool" "$staging" > /dev/null; then
		exit 1
	fi

	status=0

	for generated in "$staging"/*.plist; do
		name="$(basename "$generated")"

		if ! cmp -s "$generated" "$output_dir/$name"; then
			echo "generate-preference-plists: $name has drifted from the declarations" >&2
			status=1
		fi
	done

	if [ "$status" -ne 0 ]; then
		echo "generate-preference-plists: run 'make generate-preference-plists' and commit the result" >&2
	fi

	exit "$status"
fi

if ! "$tool" "$output_dir"; then
	exit 1
fi

echo "generate-preference-plists: $output_dir is up to date"
