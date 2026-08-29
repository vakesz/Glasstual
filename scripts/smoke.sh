#!/bin/bash
# Seeded smoke launch: run the Debug app for 40 s against a copy of the real
# preferences with every client's autoConnect turned off, probe the main thread
# from outside the process every 10 s, quit it, and read the unified log back.
#
# The probe is the point. `System Events` asks the app for its window names over
# the accessibility API, which is answered on the main thread: if the main actor
# is blocked -- a lock held across a hop, a synchronous dispatch back to itself,
# a runaway render loop -- the probe times out even though the process is still
# alive and Activity Monitor looks normal. That is how the 2026-08-28 launch
# hang was found.
#
# Usage
#   scripts/smoke.sh                                     seed and run
#   APP=/path/to/Glasstual.app scripts/smoke.sh          run a different build
#   SMOKE_SEED=0 scripts/smoke.sh                        reuse the existing seed
#
# Exit status
#   0  clean run
#   1  a probe timed out, the app crashed, quit hung, or the log carried an
#      error or fault that the allowlist does not cover
#   2  the environment is not set up (no app, no source preferences)
#
# Requires: an accessibility grant for the terminal running it (System Settings
# > Privacy & Security > Accessibility), and read access to the app's group
# container (Full Disk Access) for the seed step.

set -uo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

APP="${APP:-$repo_root/DerivedData/Build/Products/Debug/Glasstual.app}"
SUITE="${SUITE:-com.vakesz.glasstual.repro}"
BUNDLE_ID="${BUNDLE_ID:-com.vakesz.glasstual}"
GROUP_ID="${GROUP_ID:-group.H8W5DK3FN2.com.vakesz.glasstual}"
SMOKE_SEED="${SMOKE_SEED:-1}"
PROBES="${PROBES:-4}"
PROBE_INTERVAL="${PROBE_INTERVAL:-10}"

allowlist_file="$script_dir/smoke-allowlist.txt"
container_prefs="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Preferences"
seed_plist="$container_prefs/$SUITE.plist"
source_plist="$HOME/Library/Group Containers/$GROUP_ID/Library/Preferences/$GROUP_ID.plist"
plistbuddy=/usr/libexec/PlistBuddy
client_list_key="World Controller Client Configurations"

fail() {
	echo "smoke: $*" >&2
	exit 1
}

setup_failure() {
	echo "smoke: $*" >&2
	exit 2
}

[ -d "$APP" ] || setup_failure "no app at $APP (run 'make build' first, or set APP=)"

# --- seed -----------------------------------------------------------------
#
# The scratch suite is a copy of the real preferences -- real servers, channels,
# themes and window state, which is what makes the run representative -- with
# autoConnect cleared so the launch never touches the network.

seed_preferences() {
	[ -f "$source_plist" ] || setup_failure "no preferences to copy at $source_plist"
	[ -r "$source_plist" ] || setup_failure "cannot read $source_plist -- grant this terminal Full Disk Access, or run with SMOKE_SEED=0 to reuse an existing seed"

	mkdir -p "$container_prefs" || setup_failure "cannot write to $container_prefs"
	cp "$source_plist" "$seed_plist" || setup_failure "cannot seed $seed_plist"

	local index=0 disabled=0
	while "$plistbuddy" -c "Print :$client_list_key:$index" "$seed_plist" > /dev/null 2>&1; do
		"$plistbuddy" -c "Set :$client_list_key:$index:autoConnect false" "$seed_plist" > /dev/null 2>&1 ||
			"$plistbuddy" -c "Add :$client_list_key:$index:autoConnect bool false" "$seed_plist" > /dev/null 2>&1 ||
			setup_failure "cannot clear autoConnect on client $index"
		disabled=$((disabled + 1))
		index=$((index + 1))
	done

	plutil -lint "$seed_plist" > /dev/null || setup_failure "the seeded plist is malformed"
	echo "smoke: seeded $SUITE from the group container, autoConnect cleared on $disabled clients"
}

if [ "$SMOKE_SEED" = "1" ]; then
	seed_preferences
else
	[ -f "$seed_plist" ] || setup_failure "SMOKE_SEED=0 but $seed_plist does not exist"
	echo "smoke: reusing the existing seed at $seed_plist"
fi

# --- launch ---------------------------------------------------------------

crash_reports_before="$(mktemp)"
crash_reports_after="$(mktemp)"
log_output="$(mktemp)"
trap 'rm -f "$crash_reports_before" "$crash_reports_after" "$log_output"' EXIT

find "$HOME/Library/Logs/DiagnosticReports" -name 'Glasstual*' 2> /dev/null | sort > "$crash_reports_before"

started_at="$(date '+%Y-%m-%d %H:%M:%S')"
open -n "$APP" --env "GLASSTUAL_UI_REVIEW_SUITE=$SUITE" || fail "the app would not launch"

/bin/sleep 5
pid="$(pgrep -n -x Glasstual)" || fail "the app exited during launch"
echo "smoke: pid=$pid"

status=0

# --- probe ----------------------------------------------------------------

for probe in $(seq 1 "$PROBES"); do
	/bin/sleep "$PROBE_INTERVAL"

	if ! kill -0 "$pid" 2> /dev/null; then
		echo "smoke: probe $probe: the process is gone" >&2
		status=1
		break
	fi

	before="$(date +%s)"
	windows="$(timeout 8 osascript -e 'tell application "System Events" to tell process "Glasstual" to get name of windows' 2>&1)"
	probe_status=$?
	elapsed=$(($(date +%s) - before))
	cpu="$(ps -o %cpu= -p "$pid" 2> /dev/null | tr -d ' ')"

	echo "smoke: probe $probe: rc=$probe_status ${elapsed}s cpu=${cpu:-gone} windows=${windows}"

	if [ "$probe_status" -ne 0 ]; then
		echo "smoke: the main thread did not answer within 8s -- the app is hung" >&2
		status=1
	fi
done

# --- quit -----------------------------------------------------------------

if kill -0 "$pid" 2> /dev/null; then
	quit_started="$(date +%s)"
	timeout 15 osascript -e 'tell application "Glasstual" to quit' > /dev/null 2>&1
	for _ in $(seq 1 10); do
		kill -0 "$pid" 2> /dev/null || break
		/bin/sleep 1
	done
	if kill -0 "$pid" 2> /dev/null; then
		echo "smoke: quit hung after $(($(date +%s) - quit_started))s" >&2
		kill -9 "$pid"
		status=1
	else
		echo "smoke: quit in $(($(date +%s) - quit_started))s"
	fi
fi

# --- crash reports --------------------------------------------------------

find "$HOME/Library/Logs/DiagnosticReports" -name 'Glasstual*' 2> /dev/null | sort > "$crash_reports_after"
new_crashes="$(comm -13 "$crash_reports_before" "$crash_reports_after")"
if [ -n "$new_crashes" ]; then
	echo "smoke: the run produced a crash report:" >&2
	printf '%s\n' "$new_crashes" >&2
	status=1
fi

# --- unified log ----------------------------------------------------------
#
# Only the app's own subsystems: framework noise from AppKit and WebKit is not
# this gate's business, and filtering by process would pull all of it in.

/usr/bin/log show \
	--start "$started_at" \
	--predicate '(messageType == error OR messageType == fault) AND subsystem BEGINSWITH "com.vakesz"' \
	--style compact 2> /dev/null | grep -v '^Timestamp' > "$log_output"

allowed_pattern=''
if [ -f "$allowlist_file" ]; then
	allowed_pattern="$(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$allowlist_file" | paste -sd '|' -)"
fi

if [ -n "$allowed_pattern" ]; then
	unexpected="$(grep -v -E "$allowed_pattern" "$log_output")"
else
	unexpected="$(cat "$log_output")"
fi

allowed_count=$(($(grep -c . "$log_output") - $(printf '%s' "$unexpected" | grep -c .)))
echo "smoke: $(grep -c . "$log_output") error/fault lines from com.vakesz subsystems, $allowed_count allowlisted"

if [ -n "$unexpected" ]; then
	echo "smoke: unexpected error/fault lines:" >&2
	printf '%s\n' "$unexpected" >&2
	status=1
fi

if [ "$status" -eq 0 ]; then
	echo "smoke: clean"
fi

exit "$status"
