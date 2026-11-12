#!/bin/bash
# Regenerate the website screenshots in .github/website/assets from a seeded,
# disposable demo.
#
# The Debug app runs against a throwaway defaults suite and review directory
# (the GLASSTUAL_UI_REVIEW_* overrides `make e2e` also uses), connected
# to loopback IRC servers that script a fictional conversation. The real
# preferences, keychain and servers are never touched. Appearance is chosen
# with the app's own Preferred Appearance setting inside that disposable suite;
# the system appearance stays as it is.
#
# Usage
#   scripts/website-screenshots.sh              build, run, capture everything
#   APP=/path/to/Glasstual.app scripts/...      use an existing Debug build
#   SHOTS="main welcome" scripts/...            capture only some scenes
#   OUTPUT=/some/dir scripts/...                write somewhere else
#
# Scenes: main (main-window-*, networks-*, search-*, settings-*), welcome.
#
# Requires: Screen Recording and Accessibility for the app running this
# script (System Settings > Privacy & Security), swiftc, sips. pngquant is
# used when installed. Work files live in ~/Library/Caches/Glasstual.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
if [[ -z "${APP:-}" ]]; then
	# shellcheck source=scripts/build-paths.sh
	source "$script_dir/build-paths.sh"
	APP="$BUILD_PRODUCTS/Glasstual.app"
fi
OUTPUT="${OUTPUT:-$repo_root/.github/website/assets}"
SHOTS="${SHOTS:-main welcome}"
work="${WEBSITE_SCREENSHOTS_WORK:-$HOME/Library/Caches/Glasstual/website-screenshots}"
# Size of the main window in points.
window_width="${WINDOW_WIDTH:-1440}"
window_height="${WINDOW_HEIGHT:-760}"

bin="$work/bin"
state="$work/state"
raw="$work/raw"
run_id="website-$(uuidgen | tr '[:upper:]' '[:lower:]')"
suite="com.vakesz.glasstual.$run_id"
bundle_id="com.vakesz.glasstual"
group_id="group.H8W5DK3FN2.com.vakesz.glasstual"

app_pid=""
server_pid=""

fail() {
	echo "website-screenshots: $*" >&2
	exit 1
}

log() {
	echo "website-screenshots: $*"
}

# --- cleanup -----------------------------------------------------------------

stop_app() {
	if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2> /dev/null; then
		kill "$app_pid" 2> /dev/null || true
		for _ in $(seq 1 30); do
			kill -0 "$app_pid" 2> /dev/null || break
			sleep 0.2
		done
		kill -9 "$app_pid" 2> /dev/null || true
	fi
	app_pid=""
}

# Scratch suites are named com.vakesz.glasstual.website-<uuid>; cfprefsd writes
# the file shortly after the app quits, so this also sweeps earlier runs.
remove_scratch_preferences() {
	find "$HOME/Library/Containers/$bundle_id/Data/Library/Preferences" \
		"$HOME/Library/Group Containers/$group_id/Library/Preferences" \
		-maxdepth 1 -name 'com.vakesz.glasstual.website-*.plist' -delete 2> /dev/null || true
}

cleanup() {
	stop_app
	if [[ -n "$server_pid" ]]; then
		kill "$server_pid" 2> /dev/null || true
	fi
	# The run's own scratch state only; nothing else is matched.
	rm -rf \
		"$HOME/Library/Group Containers/$group_id/UI Reviews/$run_id" \
		"$HOME/Library/Containers/$bundle_id/Data/Library/Application Support/Glasstual/UI Reviews/$run_id"
	sleep 2
	remove_scratch_preferences
	rmdir "$HOME/Library/Group Containers/$group_id/UI Reviews" 2> /dev/null || true
	rmdir "$HOME/Library/Containers/$bundle_id/Data/Library/Application Support/Glasstual/UI Reviews" 2> /dev/null || true
}
trap cleanup EXIT

# --- preflight -----------------------------------------------------------------

[[ -d "$APP" ]] || fail "no app at $APP (run 'make build' first, or set APP=)"
command -v swiftc > /dev/null || fail "swiftc is required"
mkdir -p "$bin" "$state" "$raw" "$OUTPUT"
remove_scratch_preferences

compile_helper() {
	local name="$1"
	local source="$script_dir/$name.swift"
	if [[ ! -x "$bin/$name" || "$source" -nt "$bin/$name" ]]; then
		log "compiling $name"
		swiftc -O -swift-version 6 "$source" -o "$bin/$name"
	fi
}
compile_helper website-demo-server
compile_helper website-window-id

"$bin/website-window-id" --capture-allowed ||
	fail "Screen Recording is not granted. Grant it to the app running this script in System Settings > Privacy & Security > Screen & System Audio Recording, then run again."

if [[ -n "$(pgrep -f "$APP/Contents/MacOS/Glasstual" || true)" ]]; then
	fail "this build of Glasstual is already running; quit it first (it will not be touched)"
fi

# --- demo server ---------------------------------------------------------------

start_server() {
	rm -f "$state/direct-port" "$state/bouncer-port" "$state/control"
	"$bin/website-demo-server" "$state" > "$work/server.log" 2>&1 &
	server_pid=$!
	for _ in $(seq 1 100); do
		[[ -s "$state/direct-port" && -s "$state/bouncer-port" ]] && break
		kill -0 "$server_pid" 2> /dev/null || fail "the demo server exited: $(cat "$work/server.log")"
		sleep 0.1
	done
	[[ -s "$state/bouncer-port" ]] || fail "the demo server did not start"
	direct_port="$(< "$state/direct-port")"
	bouncer_port="$(< "$state/bouncer-port")"
}

# --- seed ----------------------------------------------------------------------

server_session() {
	# name, port, extra keys, conversation names...
	local name="$1" port="$2" extra="$3"
	shift 3
	local conversations="" channel
	for channel in "$@"; do
		conversations+="<dict><key>uniqueIdentifier</key><string>$(uuidgen)</string><key>name</key><string>$channel</string><key>type</key><integer>0</integer><key>ignoreGeneralEventMessages</key><true/></dict>"
	done
	cat << XML
<dict>
	<key>dictionaryVersion</key><integer>1</integer>
	<key>uniqueIdentifier</key><string>$(uuidgen)</string>
	<key>connectionName</key><string>$name</string>
	<key>nickname</key><string>casey</string>
	<key>username</key><string>casey</string>
	<key>realName</key><string>Casey Example</string>
	<key>proxyType</key><integer>0</integer>
	<key>autoConnect</key><true/>
	<key>autoReconnect</key><false/>
	<key>validateServerCertificateChain</key><true/>
	<key>setInvisibleModeOnConnect</key><false/>
	<key>performPongTimer</key><false/>
	<key>performDisconnectOnReachabilityChange</key><false/>
	<key>sidebarItemExpanded</key><true/>
	<key>normalLeavingComment</key><string>Goodbye</string>
	<key>serverList</key>
	<array><dict>
		<key>uniqueIdentifier</key><string>$(uuidgen)</string>
		<key>serverAddress</key><string>127.0.0.1</string>
		<key>serverPort</key><integer>$port</integer>
		<key>prefersSecuredConnection</key><false/>
	</dict></array>
	$extra
	<key>conversationList</key><array>$conversations</array>
</dict>
XML
}

# Prints the base64 property list GLASSTUAL_UI_REVIEW_PREFERENCES expects.
seed_settings() {
	local mode="$1" appearance_value=1 sessions=""
	[[ "$2" == dark ]] && appearance_value=2
	if [[ "$mode" == connected ]]; then
		sessions="$(server_session "Example Network" "$direct_port" "" '#swift' '#macdev' '#design')
$(server_session "Demo Bouncer" "$bouncer_port" '<key>bouncerDiscoversNetworks</key><true/><key>bouncerHidesParent</key><true/>')"
	fi
	local onboarding_done=true nickname=casey
	if [[ "$mode" == onboarding ]]; then
		onboarding_done=false
		nickname=""
	fi
	cat << XML | base64 | tr -d '\n'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Connection -&gt; Confirm Quit</key><false/>
	<key>Identity -&gt; Onboarding Completed</key><$onboarding_done/>
	<key>Identity -&gt; Nickname</key><string>$nickname</string>
	<key>Identity -&gt; Username</key><string>casey</string>
	<key>Identity -&gt; Real Name</key><string>Casey Example</string>
	<key>Appearance -&gt; Preferred Appearance</key><integer>$appearance_value</integer>
	<key>Notifications -&gt; Notify About Mentions</key><false/>
	<key>Notifications -&gt; Display Dock Badge</key><false/>
	<key>Sessions -&gt; Server Sessions</key>
	<array>
$sessions
	</array>
</dict>
</plist>
XML
}

# --- app control ------------------------------------------------------------------

# launch_app <mode> <light|dark>. The appearance is the app's own "Preferred
# Appearance" setting in the disposable suite: a launch argument such as
# -AppleInterfaceStyle Dark does not reach this app's windows, and the system
# appearance is never changed.
launch_app() {
	local mode="$1" appearance="$2"
	local settings
	settings="$(seed_settings "$mode" "$appearance")"
	env -i HOME="$HOME" USER="$USER" LOGNAME="${LOGNAME:-$USER}" PATH=/usr/bin:/bin TMPDIR="${TMPDIR:-/tmp}" \
		GLASSTUAL_UI_REVIEW_SUITE="$suite" \
		GLASSTUAL_UI_REVIEW_DIRECTORY="$run_id" \
		GLASSTUAL_UI_REVIEW_PREFERENCES="$settings" \
		"$APP/Contents/MacOS/Glasstual" -AppleLanguages '(en)' -AppleLocale en_US \
		> /dev/null 2>&1 &
	app_pid=$!
	sleep 1
	kill -0 "$app_pid" 2> /dev/null || fail "the app exited during launch"
}

# osa <script-lines...>: run AppleScript inside System Events for the app.
osa() {
	osascript -e 'tell application "System Events"' \
		-e "set appProcess to first process whose unix id is $app_pid" \
		-e "$1" \
		-e 'end tell'
}

# wait_window [title-prefix]: print the window id once it is on screen.
wait_window() {
	local identifier
	for _ in $(seq 1 100); do
		if identifier="$("$bin/website-window-id" "$app_pid" "${1:-}" 2> /dev/null)"; then
			echo "$identifier"
			return 0
		fi
		sleep 0.3
	done
	return 1
}

activate_app() {
	osa 'set frontmost of appProcess to true' > /dev/null 2>&1 || true
}

place_window() {
	osa "tell window 1 of appProcess to set position to {40, 50}" \
		> /dev/null
	osa "tell window 1 of appProcess to set size to {$window_width, $window_height}" > /dev/null
}

# capture <window-id> <name>: raw 2x capture without a shadow.
capture() {
	screencapture -l "$1" -o -x "$raw/$2.png"
	log "captured $2"
}


sidebar='outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1 of appProcess'

# select_row <description-prefix>: select a sidebar row by its accessibility
# label. Prints "true" when the row exists.
select_row() {
	osa "set found to false
repeat with index from 1 to (count of rows of $sidebar)
	set theRow to row index of $sidebar
	if (description of static text 1 of UI element 1 of theRow) starts with \"$1\" then
		select theRow
		set found to true
		exit repeat
	end if
end repeat
return found" 2> /dev/null || echo false
}

wait_row() {
	for _ in $(seq 1 60); do
		[[ "$(select_row "$1")" == true ]] && return 0
		sleep 0.5
	done
	fail "sidebar row '$1' never appeared"
}

menu_click() {
	# menu_click <menu> <item> [submenu-item-parent]
	if [[ -n "${3:-}" ]]; then
		osa "click menu item \"$2\" of menu 1 of menu item \"$3\" of menu 1 of menu bar item \"$1\" of menu bar 1 of appProcess" > /dev/null
	else
		osa "click menu item \"$2\" of menu 1 of menu bar item \"$1\" of menu bar 1 of appProcess" > /dev/null
	fi
}

connect_row() {
	wait_row "$1"
	menu_click Server Connect
}

# wait_connected <description-prefix>: until the row reports Connected.
wait_connected() {
	for _ in $(seq 1 60); do
		if [[ "$(osa "set found to false
repeat with index from 1 to (count of rows of $sidebar)
	set theRow to row index of $sidebar
	if (description of static text 1 of UI element 1 of theRow) starts with \"$1\" and (description of static text 1 of UI element 1 of theRow) contains \"Connected\" then set found to true
end repeat
return found" 2> /dev/null)" == true ]]; then
			return 0
		fi
		sleep 0.5
	done
	fail "'$1' did not connect"
}

# Starts the app with the connected demo and leaves #swift selected.
open_connected_app() {
	launch_app connected "$1"
	wait_window > /dev/null || fail "no main window appeared"
	place_window
	activate_app
	wait_row "Connection Example Network"
	connect_row "Connection Example Network"
	wait_connected "Connection Example Network"
	connect_row "Connection Demo Bouncer"
	wait_row "Connection Workshop Chat"
	connect_row "Connection Workshop Chat"
	wait_connected "Connection Workshop Chat"
	connect_row "Connection Open Source Hub"
	wait_connected "Connection Open Source Hub"
	sleep 3
}

focus_channel() {
	local label="$1"
	[[ "$(select_row "$label")" == true ]] || fail "no sidebar row '$label'"
	sleep 1.5
}

# --- scenes ----------------------------------------------------------------------

scene_main() {
	local appearance="$1" window
	log "main scene ($appearance)"
	open_connected_app "$appearance"

	focus_channel "Channel #swift"
	printf 'react #swift\n' > "$state/control"
	sleep 2
	osa 'tell window 1 of appProcess to set focused of (first text area whose description is "") to false' > /dev/null 2>&1 || true
	window="$(wait_window)"
	capture "$window" "main-window-$appearance"

	focus_channel "Channel #swiftui"
	sleep 1
	capture "$window" "networks-$appearance"

	scene_search "$appearance"
	scene_settings "$appearance"
	stop_app
}

scene_search() {
	local appearance="$1" window
	log "search scene ($appearance)"
	focus_channel "Channel #swift"
	menu_click Edit "Find in All Conversations…" Find
	sleep 2
	osa 'tell window "Search History" of appProcess to set size to {900, 600}' > /dev/null
	osa 'tell window "Search History" of appProcess to set position to {120, 80}' > /dev/null
	osa 'set focused of text field 1 of group 1 of window "Search History" of appProcess to true' > /dev/null
	osa 'keystroke "the"' > /dev/null
	osa 'key code 36' > /dev/null
	sleep 3
	window="$("$bin/website-window-id" "$app_pid" "Search History")" || fail "no search window"
	capture "$window" "search-$appearance"
	osa 'tell window "Search History" of appProcess to click (first button whose subrole is "AXCloseButton")' > /dev/null
	sleep 1
}

scene_settings() {
	local appearance="$1" window title
	log "settings scene ($appearance)"
	menu_click Glasstual "Settings…"
	sleep 2
	title="$(osa 'get name of window 1 of appProcess')"
	osa 'tell window 1 of appProcess to set position to {120, 80}' > /dev/null
	window="$("$bin/website-window-id" "$app_pid" "${title%%,*}")" || fail "no settings window ($title)"
	capture "$window" "settings-$appearance"
}

scene_welcome() {
	local appearance="$1" window
	log "welcome scene ($appearance)"
	launch_app onboarding "$appearance"
	window="$(wait_window "Welcome")" || fail "the welcome window never appeared"
	activate_app
	osa 'keystroke "casey"' > /dev/null
	sleep 2
	capture "$window" "welcome-$appearance"
	stop_app
}

# --- post-processing -----------------------------------------------------------

# finish <name>: bound the width, normalise colour, strip metadata, optimise.
finish() {
	local name="$1" file="$work/final/$1.png"
	mkdir -p "$work/final"
	cp "$raw/$name.png" "$file"
	local width
	width="$(sips -g pixelWidth "$file" | awk '/pixelWidth/ {print $2}')"
	if [[ "$width" -gt 2400 ]]; then
		sips --resampleWidth 2400 "$file" > /dev/null
	fi
	sips --matchTo '/System/Library/ColorSync/Profiles/sRGB Profile.icc' "$file" > /dev/null 2>&1 || true
	if command -v pngquant > /dev/null; then
		pngquant --force --strip --skip-if-larger --quality 85-100 --output "$file" "$file" || true
	fi
	cp "$file" "$OUTPUT/$name.png"
}

make_og() {
	local source="$work/final/main-window-light.png" file="$work/final/og.png"
	cp "$source" "$file"
	sips --resampleWidth 1200 "$file" > /dev/null
	local height offset
	height="$(sips -g pixelHeight "$file" | awk '/pixelHeight/ {print $2}')"
	offset=$(((height - 630) / 2))
	sips --cropToHeightWidth 630 1200 --cropOffset "$offset" 0 "$file" > /dev/null
	if command -v pngquant > /dev/null; then
		pngquant --force --strip --skip-if-larger --quality 85-100 --output "$file" "$file" || true
	fi
	cp "$file" "$OUTPUT/og.png"
}

# --- run -------------------------------------------------------------------------

main() {
	start_server
	log "demo server on ports $direct_port (direct) and $bouncer_port (bouncer)"

	rm -rf "$raw" "$work/final"
	mkdir -p "$raw"
	for appearance in ${APPEARANCES:-light dark}; do
		for scene in $SHOTS; do
			"scene_$scene" "$appearance"
		done
	done

	for file in "$raw"/*.png; do
		finish "$(basename "$file" .png)"
	done
	if [[ -f "$raw/main-window-light.png" ]]; then
		make_og
	fi
	log "wrote screenshots to $OUTPUT"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main
fi
