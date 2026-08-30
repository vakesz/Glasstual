#!/bin/bash
# Window list gate: a window is looked up by class, never by a spelled-out name.
#
# `WindowController` keys the window list on `NSStringFromClass`, so callers
# used to pass the Objective-C name as a `"TDC…"` literal. Those literals stop
# matching the moment a class gives up that name, and nothing says so: the
# lookup simply misses. Settings opened a second window on every invocation,
# About did the same, and a channel being destroyed stopped finding its sheets.
#
# So the string form is banned at the call sites. Callers pass a class and let
# `WindowController.windowDescription(forClass:)` derive the key, which cannot
# drift away from the class it addresses.
#
# Window *state* keys are a different thing: they are written into a user's
# saved window frames and have to stay spelled the way they were saved, so
# `Sources/App/UI/WindowStateKeys.swift` is not scanned.
#
# Usage
#   scripts/window-key-gate.sh

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

lookups='window\(fromWindowList:|windows\(fromWindowList:|maybeBringWindowForward\(|removeWindow\(fromWindowList:|withDescription:'

hits=$(git grep -nE "($lookups)[^)]*\"" -- 'Sources/**/*.swift' \
	':!Sources/App/UI/WindowStateKeys.swift' 2>/dev/null || true)

if [ -n "$hits" ]; then
	echo "window-key-gate: a window is looked up by a spelled-out name:" >&2
	echo "$hits" >&2
	echo "window-key-gate: pass the class to WindowController.windowDescription(forClass:) instead" >&2
	exit 1
fi

count=$(git grep -cE "windowDescription\(forClass:" -- 'Sources/**/*.swift' 2>/dev/null | wc -l | tr -d ' ')
printf 'window-key-gate: 0 name literals at the lookups, %s files deriving keys from a class\n' "$count"
