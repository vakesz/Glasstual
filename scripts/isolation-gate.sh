#!/bin/bash
# Isolation gate for Phase 8: counts concurrency escape hatches under Sources/
# and fails when a category rises above its recorded ceiling.
#
# Categories
#   hatch        the five escape hatches that defeat the isolation checker
#   lockqueue    hand-rolled synchronisation the actor model replaces
#   nonisolated  plain `nonisolated` declaration sites without a marker comment
#
# A plain `nonisolated` is only allowed for a pure function of Sendable inputs,
# a Sendable `let`, an @objc/XPC protocol requirement or its one-line
# forwarding shim, or a genuine value type. Each site records which by ending
# the line with `// nonisolated: pure|let|xpc-shim|value`; anything else counts
# as unmarked. The marker vocabulary is closed.
#
# Usage
#   scripts/isolation-gate.sh            check the tree against the ceilings
#   scripts/isolation-gate.sh --ratchet  rewrite the ceilings to today's counts
#
# Ceilings live in scripts/isolation-ceilings.env and only ever go down: run
# --ratchet at each merge that removes hatches, and commit the result.

set -uo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
ceilings_file="$script_dir/isolation-ceilings.env"

ratchet=0
case "${1-}" in
	--ratchet) ratchet=1 ;;
	"") ;;
	--help | -h)
		sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		echo "isolation-gate: unknown argument '$1' (expected --ratchet)" >&2
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

		# (b) hand-rolled synchronisation
		if (index(code, "NSLock(")) record("lockqueue", "NSLock(")
		if (index(code, "NSRecursiveLock(")) record("lockqueue", "NSRecursiveLock(")
		if (index(code, "objc_sync_enter")) record("lockqueue", "objc_sync_enter")
		if (index(code, "DispatchQueue(label")) record("lockqueue", "DispatchQueue(label")
		if (index(code, "OperationQueue()")) record("lockqueue", "OperationQueue()")
		if (index(code, "performSynchronouslyOnMainQueue")) record("lockqueue", "performSynchronouslyOnMainQueue")
		if (index(code, "performAsynchronouslyOnMainQueue")) record("lockqueue", "performAsynchronouslyOnMainQueue")

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

write_ceilings() {
	cat > "$ceilings_file" <<EOF
# Isolation-gate ceilings, written by scripts/isolation-gate.sh --ratchet.
# Each count is a maximum, never a target: the gate fails when the tree rises
# above one. Ratchet after every merge that removes sites, so the numbers only
# fall. Phase 8 finishes when all three read 0 and the gate becomes a ban.
ISOLATION_CEILING_HATCH=$hatch_count
ISOLATION_CEILING_LOCKQUEUE=$lockqueue_count
ISOLATION_CEILING_NONISOLATED_UNMARKED=$nonisolated_count
EOF
}

if [ "$ratchet" -eq 1 ]; then
	write_ceilings
	echo "isolation-gate: ceilings rewritten to hatch=$hatch_count lock/queue=$lockqueue_count unmarked-nonisolated=$nonisolated_count"
	echo "isolation-gate: commit ${ceilings_file#"$repo_root"/}"
	exit 0
fi

if [ ! -f "$ceilings_file" ]; then
	echo "isolation-gate: $ceilings_file is missing; run scripts/isolation-gate.sh --ratchet to create it" >&2
	exit 2
fi

# shellcheck source=/dev/null
. "$ceilings_file"

: "${ISOLATION_CEILING_HATCH:?isolation-gate: ISOLATION_CEILING_HATCH missing from the ceilings file}"
: "${ISOLATION_CEILING_LOCKQUEUE:?isolation-gate: ISOLATION_CEILING_LOCKQUEUE missing from the ceilings file}"
: "${ISOLATION_CEILING_NONISOLATED_UNMARKED:?isolation-gate: ISOLATION_CEILING_NONISOLATED_UNMARKED missing from the ceilings file}"

printf 'isolation-gate: %d hatches (max %d), %d lock/queue sites (max %d), %d unmarked nonisolated (max %d) across %d files\n' \
	"$hatch_count" "$ISOLATION_CEILING_HATCH" \
	"$lockqueue_count" "$ISOLATION_CEILING_LOCKQUEUE" \
	"$nonisolated_count" "$ISOLATION_CEILING_NONISOLATED_UNMARKED" \
	"${#files[@]}"

status=0

report_over() {
	local category="$1" count="$2" ceiling="$3" label="$4"
	[ "$count" -le "$ceiling" ] && return 0
	echo "isolation-gate: $label rose to $count, above the ceiling of $ceiling" >&2
	list_of "$category" >&2
	status=1
}

report_over hatch "$hatch_count" "$ISOLATION_CEILING_HATCH" "escape hatches"
report_over lockqueue "$lockqueue_count" "$ISOLATION_CEILING_LOCKQUEUE" "lock/queue sites"
report_over nonisolated "$nonisolated_count" "$ISOLATION_CEILING_NONISOLATED_UNMARKED" "unmarked nonisolated sites"

if [ "$status" -ne 0 ]; then
	echo "isolation-gate: remove the new sites, or run scripts/isolation-gate.sh --ratchet if the ceiling is genuinely lower now" >&2
fi

exit "$status"
