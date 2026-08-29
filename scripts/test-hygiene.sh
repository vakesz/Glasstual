#!/bin/bash
# Test hygiene gate: a test that does not run has to be declared.
#
# `.disabled(...)` and `withKnownIssue { ... }` both make a red test green, and
# six `.disabled("Phase 1: ...")` traits sat in the suite for weeks hiding exit
# criteria that were never met. So both constructs are banned under Tests/
# unless `scripts/test-hygiene-allowlist.txt` accounts for them, one line per
# file and construct:
#
#   <path> <construct> <count> <reason>
#
# The count is exact: adding a seventh disabled test to a file that declared
# six fails, and so does an entry that outlives the construct it excused. The
# reason is free text and may not be empty -- it is what someone reads before
# deciding the exemption still stands.
#
# Usage
#   scripts/test-hygiene.sh

set -uo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

case "${1-}" in
	"") ;;
	--help | -h)
		sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		echo "test-hygiene: unknown argument '$1'" >&2
		exit 2
		;;
esac

cd "$repo_root" || exit 2

allowlist="scripts/test-hygiene-allowlist.txt"

if [ ! -f "$allowlist" ]; then
	echo "test-hygiene: missing $allowlist" >&2
	exit 2
fi

files=()
while IFS= read -r file; do
	files+=("$file")
done < <(/usr/bin/git ls-files -- 'Tests/*.swift' | sort)

if [ "${#files[@]}" -eq 0 ]; then
	echo "test-hygiene: no Swift sources found under Tests/" >&2
	exit 2
fi

awk -v allowlist="$allowlist" -v file_count="${#files[@]}" '
	# Comments are blanked before counting so prose about a disabled test is
	# not read as one. Same limits as the isolation gate: no nested block
	# comments, no "/*" inside a string literal.
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

	FILENAME == allowlist {
		if ($0 ~ /^[ \t]*(#|$)/) next

		if (NF < 4) {
			printf "test-hygiene: %s:%d needs <path> <construct> <count> <reason>\n", allowlist, FNR > "/dev/stderr"
			bad = 1
			next
		}

		if ($2 != "disabled" && $2 != "withKnownIssue") {
			printf "test-hygiene: %s:%d has unknown construct \"%s\"\n", allowlist, FNR, $2 > "/dev/stderr"
			bad = 1
			next
		}

		allowed[$2 "\t" $1] = $3 + 0
		declared[$2 "\t" $1] = 1
		next
	}

	FNR == 1 { in_block = 0 }

	{
		code = uncomment($0)

		text = code
		found = gsub(/\.disabled\(/, "", text)
		if (found > 0) seen["disabled\t" FILENAME] += found

		text = code
		found = gsub(/withKnownIssue/, "", text)
		if (found > 0) seen["withKnownIssue\t" FILENAME] += found
	}

	END {
		for (key in seen) {
			split(key, part, "\t")

			if (seen[key] > allowed[key]) {
				printf "test-hygiene: %s has %d %s site(s), %d allowed\n", \
					part[2], seen[key], part[1], allowed[key] > "/dev/stderr"
				bad = 1
			}
		}

		for (key in declared) {
			split(key, part, "\t")

			if (allowed[key] > seen[key]) {
				printf "test-hygiene: %s allows %d %s site(s) but has %d -- update the allowlist\n", \
					part[2], allowed[key], part[1], seen[key] + 0 > "/dev/stderr"
				bad = 1
			}
		}

		total = 0
		for (key in seen) total += seen[key]
		printf "test-hygiene: %d non-running test site(s) across %d test files\n", total, file_count

		exit bad ? 1 : 0
	}
' "$allowlist" "${files[@]}"

status=$?

if [ "$status" -ne 0 ]; then
	echo "test-hygiene: a test that does not run is not a passing test" >&2
	echo "test-hygiene: fix the code, delete the test, or record the exemption in $allowlist" >&2
fi

exit "$status"
