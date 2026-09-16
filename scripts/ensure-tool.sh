#!/bin/bash
# Make a pinned developer tool available to the Makefile.
#
# The quality gate has to mean the same thing on every machine and on every CI
# run, so each tool is pinned to one release and one SHA-256. A copy already on
# PATH at the pinned version is used as it is; otherwise the release artifact is
# downloaded, checked against its digest and unpacked under build/tools. Either
# way the tool ends up behind a wrapper in build/tools/bin, and the Makefile
# runs that wrapper by its full path: Apple's GNU Make 3.81 (/usr/bin/make on
# the CI runner) ignores a PATH exported from the Makefile when it execs a
# recipe line itself. Nothing is installed system-wide.
#
# Usage
#   scripts/ensure-tool.sh <swiftformat|swiftlint|actionlint|shellcheck|xcodegen>
#
# To bump a tool, change its version, URL and digest together below. GitHub
# lists each release asset's digest, and `gh release view <tag> --repo
# <owner/name> --json assets` prints it.

set -euo pipefail
umask 022

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
tools_root="${GLASSTUAL_TOOLS_DIR:-$repo_root/build/tools}"

fail() {
	echo "ensure-tool: $*" >&2
	exit 1
}

tool="${1:-}"
case "$tool" in
	swiftformat)
		version=0.63.0
		url="https://github.com/nicklockwood/SwiftFormat/releases/download/$version/swiftformat.zip"
		sha256=28c7802e11fa5ae113d903066439c6bb1be20a8ac1ad9709c42616a7e273fb0f
		executable=swiftformat
		;;
	swiftlint)
		version=0.65.1
		url="https://github.com/realm/SwiftLint/releases/download/$version/portable_swiftlint.zip"
		sha256=c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0
		executable=swiftlint
		;;
	actionlint)
		version=1.7.12
		url="https://github.com/rhysd/actionlint/releases/download/v$version/actionlint_${version}_darwin_arm64.tar.gz"
		sha256=aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f
		executable=actionlint
		;;
	shellcheck)
		version=0.11.0
		url="https://github.com/koalaman/shellcheck/releases/download/v$version/shellcheck-v$version.darwin.aarch64.tar.gz"
		sha256=339b930feb1ea764467013cc1f72d09cd6b869ebf1013296ba9055ab2ffbd26f
		executable="shellcheck-v$version/shellcheck"
		;;
	xcodegen)
		version=2.46.0
		url="https://github.com/yonaskolb/XcodeGen/releases/download/$version/xcodegen.zip"
		sha256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
		# XcodeGen finds its setting presets in ../share beside the binary, so
		# the whole unpacked tree stays together.
		executable=xcodegen/bin/xcodegen
		;;
	*)
		fail "usage: $0 <swiftformat|swiftlint|actionlint|shellcheck|xcodegen>"
		;;
esac

# Each tool prints its version differently; the pinned version appearing as a
# whole word in that output is the check.
installed_version_matches() {
	local output
	case "$tool" in
		swiftlint) output="$("$1" version 2> /dev/null)" ;;
		*) output="$("$1" --version 2> /dev/null)" ;;
	esac
	[[ "$output" =~ (^|[^0-9.])${version//./\\.}($|[^0-9.]) ]]
}

bin_dir="$tools_root/bin"
install_dir="$tools_root/$tool-$version"
target="$install_dir/$executable"
if found="$(command -v "$tool")" && installed_version_matches "$found"; then
	target="$found"
elif [ ! -x "$target" ]; then
	if [ -n "${found:-}" ]; then
		echo "ensure-tool: $found is not $tool $version; installing the pinned release under $tools_root" >&2
	else
		echo "ensure-tool: installing $tool $version under $tools_root" >&2
	fi
	command -v curl > /dev/null || fail "curl is required to download $tool $version"

	staging="$(mktemp -d "${TMPDIR:-/tmp}/glasstual-$tool.XXXXXX")"
	trap 'rm -rf "$staging"' EXIT
	archive="$staging/${url##*/}"
	curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
		--retry 3 --output "$archive" "$url" ||
		fail "could not download $url. Install $tool $version yourself and put it on PATH."
	actual="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)"
	[ "$actual" = "$sha256" ] ||
		fail "checksum mismatch for $url: expected $sha256, got $actual"

	mkdir -p "$staging/unpacked"
	case "$archive" in
		*.zip) ditto -x -k "$archive" "$staging/unpacked" ;;
		*.tar.gz) tar -xzf "$archive" -C "$staging/unpacked" ;;
		*) fail "unsupported archive $archive" ;;
	esac
	[ -f "$staging/unpacked/$executable" ] || fail "$url did not contain $executable"
	chmod +x "$staging/unpacked/$executable"

	mkdir -p "$tools_root"
	rm -rf "$install_dir"
	mv "$staging/unpacked" "$install_dir"
fi

# The wrapper runs the real binary by its full path, where a symlink would not,
# so XcodeGen still finds its presets beside it.
mkdir -p "$bin_dir"
printf '#!/bin/bash\nexec %q "$@"\n' "$target" > "$bin_dir/$tool"
chmod +x "$bin_dir/$tool"
installed_version_matches "$bin_dir/$tool" ||
	fail "$target does not report version $version"
