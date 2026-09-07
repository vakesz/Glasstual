#!/bin/bash
# The independent supervisor owns every build, preflight and test child.
set -euo pipefail
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
E2E_REPO_ROOT="$(cd -- "$script_dir/.." && pwd)"
export E2E_REPO_ROOT
export E2E_DERIVED_DATA="${DERIVED_DATA:-$E2E_REPO_ROOT/DerivedData}"
export E2E_APP="${E2E_APP:-$E2E_DERIVED_DATA/Build/Products/Debug/Glasstual.app}"
export E2E_HELPER="${E2E_HELPER:-$E2E_DERIVED_DATA/Build/Products/Debug/GlasstualE2EHarness}"
export E2E_FIXTURE="$E2E_REPO_ROOT/Tests/Corpora/E2E/Startup.plist"
export E2E_DISPOSABLE_USER_CONSENT="${E2E_DISPOSABLE_USER_CONSENT:-NO}"

if [[ "$E2E_DISPOSABLE_USER_CONSENT" != YES ]]; then
	printf '%s\n' 'e2e: setup failure: a disposable GUI login and explicit consent are required' >&2
	exit 2
fi
if [[ ! -x "$E2E_HELPER" ]]; then
	printf '%s\n' 'e2e: setup failure: build GlasstualE2E for testing first to provision the stable supervisor/helper' >&2
	exit 2
fi
E2E_OUTPUT="${E2E_OUTPUT:-$E2E_REPO_ROOT/build/e2e}"
export E2E_OUTPUT
mkdir -p "$E2E_OUTPUT"
E2E_RUN_DIRECTORY="$(mktemp -d "$E2E_OUTPUT/run-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")"
export E2E_RUN_DIRECTORY
mkdir "$E2E_RUN_DIRECTORY/owned"
mkdir "$E2E_RUN_DIRECTORY/scenarios"
cp "$E2E_HELPER" "$E2E_RUN_DIRECTORY/supervisor"
# The test bundle receives the stable E2E_OUTPUT through the scheme and reads the
# per-run directory from here. Passing the per-run path as a build setting would
# change the build description and force a full rebuild on every invocation.
printf '%s' "$E2E_RUN_DIRECTORY" > "$E2E_OUTPUT/current-run"
printf 'e2e: artifacts: %s\n' "$E2E_RUN_DIRECTORY"
# exec leaves no shell blocked in wait. The supervisor polls deadlines independently
# of the AX driver, runner and app, including while codesign or preflight is stuck.
# A signed snapshot avoids rebuilding the watchdog binary while it is executing.
# AX operations still use E2E_HELPER at its stable, consented path.
exec "$E2E_RUN_DIRECTORY/supervisor" supervise
