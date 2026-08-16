#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

cd "${repo_root}"

if [ "$#" -ne 0 ]; then
	echo "Usage: $0" >&2
	exit 64
fi

require_command() {
	if ! command -v "$1" > /dev/null 2>&1; then
		echo "Missing required linter: $1" >&2
		echo "Install development tools with: brew bundle" >&2
		exit 69
	fi
}

require_command actionlint
require_command shellcheck

./Scripts/format.sh --check

shell_files=()

while IFS= read -r -d '' file; do
	shell_files+=("${file}")
done < <(git ls-files --cached --others --exclude-standard -z -- '*.sh')

shellcheck "${shell_files[@]}"

actionlint

while IFS= read -r -d '' file; do
	if [ "${file##*/}" = "distribution.plist" ]; then
		continue
	fi

	plutil -lint "${file}" > /dev/null
done < <(git ls-files --cached --others --exclude-standard -z -- '*.entitlements' '*.plist' '*.strings')

while IFS= read -r -d '' file; do
	xmllint --noout "${file}"
done < <(git ls-files --cached --others --exclude-standard -z -- '*.xib' '*.xcscheme' '*.xcworkspacedata')

while IFS= read -r -d '' file; do
	xmllint --noout "${file}"
done < <(git ls-files --cached --others --exclude-standard -z -- 'distribution.plist')

git diff --check
