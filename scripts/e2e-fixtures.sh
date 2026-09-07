#!/bin/bash
# Check the scripted peers with synthetic clients; never launch the app or use AX.
set -euo pipefail
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
helper="${E2E_HELPER:-$repo_root/DerivedData/Build/Products/Debug/GlasstualE2EHarness}"
[[ -x "$helper" ]] || { printf '%s\n' 'Build the GlasstualE2E scheme first.' >&2; exit 2; }
mkdir -p "$repo_root/build/e2e-fixtures"
run="$(mktemp -d "$repo_root/build/e2e-fixtures/run-XXXXXX")"
export E2E_FIXTURE="$repo_root/Tests/Corpora/E2E/Startup.plist"
export E2E_RUN_DIRECTORY="$run"
unset E2E_DISPOSABLE_USER_CONSENT

# ScenarioKind.hasFixtureTest is the only list of fixture modes; ask the helper
# for it rather than repeating it here. Each mode bounds itself with monotonic
# deadlines, so no external `timeout` command is required.
scenarios=()
while IFS= read -r scenario; do
  [[ -n "$scenario" ]] && scenarios+=("$scenario")
done < <("$helper" list-fixtures)
# The count is what Documentation/E2E.md and Remediation.md promise; a mode
# added or dropped on one side has to show up here rather than pass quietly.
expected_fixture_count=13
if (( ${#scenarios[@]} != expected_fixture_count )); then
  printf 'Helper reported %d fixture modes, expected %d.\n' "${#scenarios[@]}" "$expected_fixture_count" >&2
  exit 1
fi

for scenario in "${scenarios[@]}"; do
  export E2E_SCENARIO="$scenario"
  export E2E_SCENARIO_DIRECTORY="$run/$scenario"
  mkdir "$E2E_SCENARIO_DIRECTORY"
  if ! "$helper" fixture-test > "$E2E_SCENARIO_DIRECTORY/output.log" 2>&1; then
    printf 'Fixture failed: %s. Artifacts: %s\n' "$scenario" "$run" >&2
    exit 1
  fi
  [[ -f "$E2E_SCENARIO_DIRECTORY/fixture-selftests-passed" ]] || exit 1
  printf 'Fixture passed: %s\n' "$scenario"
done
printf 'All %d loopback fixtures passed. GUI workflows were not run. Artifacts: %s\n' \
  "${#scenarios[@]}" "$run"
