#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

cd "${repo_root}"

mode="write"

if [ "${1:-}" = "--check" ]; then
	mode="check"
elif [ "$#" -ne 0 ]; then
	echo "Usage: $0 [--check]" >&2
	exit 64
fi

require_command() {
	if ! command -v "$1" > /dev/null 2>&1; then
		echo "Missing required formatter: $1" >&2
		echo "Install development tools with: brew bundle" >&2
		exit 69
	fi
}

require_command xcrun
require_command shfmt

clang_format="$(xcrun --find clang-format)"
swift_format="$(xcrun --find swift-format)"

objective_c_files=()
swift_files=()
shell_files=()

while IFS= read -r -d '' file; do
	# Format the canonical target, not tracked compatibility symlinks pointing to it.
	if [ -L "${file}" ]; then
		continue
	fi

	case "${file}" in
		Frameworks/* | */External\ Libraries/*)
			continue
			;;
		*.c | *.cc | *.cpp | *.h | *.m | *.mm)
			objective_c_files+=("${file}")
			;;
		*.swift)
			swift_files+=("${file}")
			;;
		*.sh)
			shell_files+=("${file}")
			;;
	esac
done < <(git ls-files --cached --others --exclude-standard -z -- '*.c' '*.cc' '*.cpp' '*.h' '*.m' '*.mm' '*.swift' '*.sh')

if [ "${mode}" = "check" ]; then
	"${clang_format}" --dry-run --Werror --style=file "${objective_c_files[@]}"
	"${swift_format}" lint --strict --configuration .swift-format "${swift_files[@]}"
	shfmt -d -i 0 -ci -sr "${shell_files[@]}"
else
	"${clang_format}" -i --style=file "${objective_c_files[@]}"
	"${swift_format}" format --in-place --configuration .swift-format "${swift_files[@]}"
	shfmt -w -i 0 -ci -sr "${shell_files[@]}"
fi
