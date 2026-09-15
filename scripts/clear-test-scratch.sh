#!/bin/bash
# Clear the unit tests' scratch state before a test run.
#
# GlasstualTests run inside a full launch of the Debug app. The Glasstual
# scheme's test action points that launch at a scratch defaults suite
# (GLASSTUAL_UI_REVIEW_SUITE) and a scratch "UI Reviews" directory
# (GLASSTUAL_UI_REVIEW_DIRECTORY), and runs this script as its pre-action so
# every run, from Xcode or from `make test`, starts from nothing instead of
# whatever the previous run left behind.
#
# Usage, with the Glasstual target's build settings in the environment as the
# scheme provides them
#   scripts/clear-test-scratch.sh <defaults suite> <review directory name>
#
# The script reports a failure, but the test action still runs. Xcode ignores a
# pre-action's exit status, and a stale scratch suite is still not the user's.

set -uo pipefail

suite="${1:?defaults suite}"
review_directory="${2:?review directory name}"
bundle_id="${GLASSTUAL_BUNDLE_IDENTIFIER:?run as the Glasstual scheme test pre-action}"
group_id="${GLASSTUAL_GROUP_CONTAINER_IDENTIFIER:?run as the Glasstual scheme test pre-action}"

# Refuse anything that could resolve to the real data: the review directory is
# a single path component, and the suite is never the app's own domain.
case "$review_directory" in
	"" | . | .. | */*)
		echo "clear-test-scratch: refusing review directory '$review_directory'" >&2
		exit 1
		;;
esac
if [ "$suite" = "$bundle_id" ] || [ "$suite" = "$group_id" ]; then
	echo "clear-test-scratch: refusing to clear the app's own defaults domain $suite" >&2
	exit 1
fi

container="$HOME/Library/Containers/$bundle_id/Data"
status=0

# Go through cfprefsd rather than deleting the plist, so a cached copy of the
# domain cannot outlive the file. `defaults delete` also fails on a domain that
# is already empty, so the check afterwards looks for keys that remain.
suite_plist="$container/Library/Preferences/$suite"
if [ -f "$suite_plist.plist" ]; then
	defaults delete "$suite_plist" > /dev/null 2>&1
	if defaults read "$suite_plist" 2> /dev/null | grep -q '='; then
		echo "clear-test-scratch: could not clear the defaults suite $suite" >&2
		status=1
	fi
fi

for path in \
	"$HOME/Library/Group Containers/$group_id/UI Reviews/$review_directory" \
	"$container/Library/Application Support/Glasstual/UI Reviews/$review_directory"; do
	if [ -e "$path" ] && ! rm -rf "$path"; then
		echo "clear-test-scratch: could not remove $path" >&2
		status=1
	fi
done

exit "$status"
