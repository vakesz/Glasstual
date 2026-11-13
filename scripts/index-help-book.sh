#!/bin/bash
# Copyright (c) 2026 Codeux Software, LLC & respective contributors.
# SPDX-License-Identifier: BSD-3-Clause
#
# Builds the Core Spotlight search index for the Help Book from its English
# pages. Run by the Glasstual target's "Index Help Book" build phase, which
# declares the pages as inputs (scripts/help-book-pages.xcfilelist) and the
# index as its output, so user script sandboxing permits exactly those paths.
#
#   index-help-book.sh <source en.lproj folder> <page file list> <output .cshelpindex>
#
# A page missing from the file list would be indexed but never trigger a
# rebuild when it changes, so the build stops and names it instead.
#
# hiutil reads only the folder it is given and writes only the output path.
# The index content depends on the pages alone; hiutil stamps the file with
# its creation time, so only the bytes of that header differ between runs.

set -euo pipefail

source_folder="$1"
page_list="$2"
output_index="$3"

[ -d "$source_folder" ] || { echo "error: Help Book pages not found at $source_folder" >&2; exit 1; }

unlisted=0
while IFS= read -r -d '' page; do
	# Xcode hands the phase the list with every path resolved.
	if ! grep -qxF "$page" "$page_list"; then
		echo "error: $page is not listed in $page_list" >&2
		unlisted=1
	fi
done < <(find "$source_folder" -type f -name '*.html' -print0)
[ "$unlisted" -eq 0 ] || exit 1

mkdir -p "$(dirname "$output_index")"
rm -f "$output_index"
/usr/bin/hiutil -I corespotlight -C -a -s en -l en -f "$output_index" "$source_folder"
[ -s "$output_index" ] || { echo "error: hiutil produced no index at $output_index" >&2; exit 1; }
