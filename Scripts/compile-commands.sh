#!/bin/bash

# Produces compile_commands.json at the repository root for clangd and other
# editors. The database is extracted from a full Debug build log, so the
# first run takes as long as a build; later runs reuse the incremental
# DerivedData. The output is ignored by git.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

derived_data="${DERIVED_DATA:-${repo_root}/DerivedData}"
log_file="${derived_data}/compile-commands.log"
output="${repo_root}/compile_commands.json"

mkdir -p "${derived_data}"

xcodebuild \
	-project "${repo_root}/Glasstual.xcodeproj" \
	-scheme Glasstual \
	-destination 'platform=macOS,arch=arm64' \
	-derivedDataPath "${derived_data}" \
	-configuration Debug \
	COMPILER_INDEX_STORE_ENABLE=NO \
	build > "${log_file}" 2>&1 || {
	echo "Build failed; see ${log_file}" >&2
	exit 1
}

python3 - "${log_file}" "${output}" "${repo_root}" << 'PY'
import json, re, shlex, sys

log_path, output_path, root = sys.argv[1:4]

entries = []
seen = set()

with open(log_path, encoding="utf-8", errors="replace") as handle:
	for line in handle:
		line = line.strip()
		if " -c " not in line:
			continue
		if not (line.startswith("/") and "clang" in line.split(" ", 1)[0]):
			continue
		try:
			argv = shlex.split(line)
		except ValueError:
			continue
		try:
			source = argv[argv.index("-c") + 1]
		except (ValueError, IndexError):
			continue
		if not source.endswith((".m", ".mm", ".c", ".cpp", ".cc")):
			continue
		if source in seen:
			continue
		seen.add(source)
		entries.append({"directory": root, "file": source, "arguments": argv})

with open(output_path, "w", encoding="utf-8") as handle:
	json.dump(entries, handle, indent=1)

print(f"Wrote {len(entries)} entries to {output_path}")
PY
