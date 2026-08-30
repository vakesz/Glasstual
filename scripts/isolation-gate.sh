#!/bin/bash
# Isolation gate: counts concurrency escape hatches under Sources/ and fails
# when it finds any. Phase 8 took all three categories to zero, so the gate is
# a flat ban -- there is no ceiling to raise and nothing to ratchet.
#
# Categories
#   hatch        the five escape hatches that defeat the isolation checker
#   lockqueue    hand-rolled synchronisation the actor model replaces
#   nonisolated  plain `nonisolated` declaration sites without a marker comment
#
# One lock/queue site is documented rather than counted: FSEvents demands a
# serial dispatch queue and orders teardown against its own callbacks, so
# `XRFileSystemMonitor` keeps one and marks the line `// lock-queue: fsevents`.
# The marker is the whole allowance -- any other spelling counts.
#
# A plain `nonisolated` is only allowed for a pure function of Sendable inputs,
# a Sendable `let`, an @objc/XPC protocol requirement or its one-line
# forwarding shim, or a genuine value type. Each site records which by ending
# the line with `// nonisolated: pure|let|xpc-shim|value`; anything else counts
# as unmarked. The marker vocabulary is closed.
#
# Usage
#   scripts/isolation-gate.sh            require zero of each
#   scripts/isolation-gate.sh --ban      the same, spelled out

set -uo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

case "${1-}" in
	--ban | "") ;;
	--help | -h)
		sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		echo "isolation-gate: unknown argument '$1' (expected --ban)" >&2
		exit 2
		;;
esac

cd "$repo_root" || exit 2

# Vendored and generated Swift is not ours to isolate. `Sources/**/Vendor` is
# the convention; the GRMustache import is the one tree that predates it.
is_excluded() {
	case "$1" in
		*/Vendor/*) return 0 ;;
		"Sources/Frameworks/Static Libraries/GRMustache/"*) return 0 ;;
		*) return 1 ;;
	esac
}

files=()
while IFS= read -r file; do
	is_excluded "$file" && continue
	files+=("$file")
done < <(/usr/bin/git ls-files -- 'Sources/*.swift' | sort)

if [ "${#files[@]}" -eq 0 ]; then
	echo "isolation-gate: no Swift sources found under Sources/" >&2
	exit 2
fi

# One awk pass emits `category<TAB>file:line<TAB>evidence` for every site.
findings="$(awk '
	function record(category, token,   text) {
		text = $0
		sub(/^[ \t]+/, "", text)
		printf "%s\t%s:%d\t%s\n", category, FILENAME, FNR, text
	}

	# Blank out comments so prose about a hatch is not counted as one. Nested
	# block comments and "/*" inside a string literal are not modelled; no
	# source in the tree relies on either.
	function uncomment(s,   out, i, n, pair) {
		if (!in_block && index(s, "/") == 0) return s
		out = ""
		n = length(s)
		for (i = 1; i <= n; ) {
			pair = substr(s, i, 2)
			if (in_block) {
				if (pair == "*/") { in_block = 0; i += 2 } else { i++ }
			} else if (pair == "/*") {
				in_block = 1
				i += 2
			} else if (pair == "//") {
				break
			} else {
				out = out substr(s, i, 1)
				i++
			}
		}
		return out
	}

	FNR == 1 { in_block = 0 }

	{
		line = $0

		# The marker check below still reads the untouched line.
		code = uncomment(line)

		# (a) escape hatches
		if (index(code, "nonisolated(unsafe)")) record("hatch", "nonisolated(unsafe)")
		if (index(code, "@unchecked Sendable")) record("hatch", "@unchecked Sendable")
		if (index(code, "MainActor.assumeIsolated")) record("hatch", "MainActor.assumeIsolated")
		if (index(code, "Thread.isMainThread")) record("hatch", "Thread.isMainThread")
		if (index(code, "DispatchQueue.main.sync")) record("hatch", "DispatchQueue.main.sync")

		# (b) hand-rolled synchronisation. A line ending in the documented
		# `// lock-queue: fsevents` marker is the one allowance; the marker
		# check reads the untouched line, like the nonisolated one below.
		documented = (line ~ /\/\/[ \t]*lock-queue:[ \t]*fsevents[ \t]*$/)

		if (!documented) {
			if (index(code, "NSLock(")) record("lockqueue", "NSLock(")
			if (index(code, "NSRecursiveLock(")) record("lockqueue", "NSRecursiveLock(")
			if (index(code, "objc_sync_enter")) record("lockqueue", "objc_sync_enter")
			if (index(code, "DispatchQueue(label")) record("lockqueue", "DispatchQueue(label")
			if (index(code, "OperationQueue()")) record("lockqueue", "OperationQueue()")
			if (index(code, "performSynchronouslyOnMainQueue")) record("lockqueue", "performSynchronouslyOnMainQueue")
			if (index(code, "performAsynchronouslyOnMainQueue")) record("lockqueue", "performAsynchronouslyOnMainQueue")
		} else if (index(code, "DispatchQueue(label") == 0) {
			record("misplaced-marker", "// lock-queue: fsevents")
		}

		# (c) plain `nonisolated` declaration sites. `nonisolated(` in any
		# form (unsafe, nonsending) is a different modifier and is either
		# counted above or out of scope.
		if (code ~ /(^|[^A-Za-z0-9_@.])nonisolated([^A-Za-z0-9_(]|$)/) {
			if (line !~ /\/\/[ \t]*nonisolated:[ \t]*(pure|let|xpc-shim|value)[ \t]*$/) {
				record("nonisolated", "nonisolated")
			}
		}
	}
' "${files[@]}")"

count_of() {
	if [ -z "$findings" ]; then
		echo 0
		return
	fi
	printf '%s\n' "$findings" | grep -c "^$1	"
}

list_of() {
	printf '%s\n' "$findings" | awk -F'\t' -v c="$1" '$1 == c { printf "  %s\t%s\n", $2, $3 }'
}

hatch_count="$(count_of hatch)"
lockqueue_count="$(count_of lockqueue)"
nonisolated_count="$(count_of nonisolated)"
misplaced_count="$(count_of misplaced-marker)"

# The documented marker exempts exactly one construct. On any other line it is
# an exemption for nothing, so say so rather than let it sit there.
if [ "$misplaced_count" -ne 0 ]; then
	echo "isolation-gate: the fsevents lock/queue marker is on a line that does not create a queue" >&2
	list_of misplaced-marker >&2
	exit 1
fi

printf 'isolation-gate: %d hatches, %d lock/queue sites, %d unmarked nonisolated across %d files\n' \
	"$hatch_count" "$lockqueue_count" "$nonisolated_count" "${#files[@]}"

status=0

report_any() {
	local category="$1" count="$2" label="$3"
	[ "$count" -eq 0 ] && return 0
	echo "isolation-gate: $label: $count" >&2
	list_of "$category" >&2
	status=1
}

report_any hatch "$hatch_count" "escape hatches"
report_any lockqueue "$lockqueue_count" "lock/queue sites"
report_any nonisolated "$nonisolated_count" "unmarked nonisolated sites"

if [ "$status" -ne 0 ]; then
	echo "isolation-gate: none of these are allowed; there is no ceiling to raise" >&2
	echo "isolation-gate: move the state into the domain that uses it, or hand a Sendable snapshot across" >&2
fi

exit "$status"
