// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The part of a matching line a result row shows: the text around the first
 match, with every match marked.

 Matching ignores case and accents exactly as the search itself does, so a row
 never shows a line without the words that found it. */
nonisolated enum ScrollbackSearchSnippet {
	static let maximumLength = 160
	/// How much text before the first match is kept, so the match is not at the edge.
	static let leadingContext = 40

	static func make(text: String, query: String) -> AttributedString {
		let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
		let flat = text.replacingOccurrences(of: "\n", with: " ")
		let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
		var start = flat.startIndex
		var prefix = ""
		if needle.isEmpty == false, let first = flat.range(of: needle, options: options) {
			let offset = flat.distance(from: flat.startIndex, to: first.lowerBound)
			if offset > leadingContext {
				start = flat.index(first.lowerBound, offsetBy: -leadingContext)
				prefix = "\u{2026}"
			}
		}
		var shown = String(flat[start...].prefix(maximumLength))
		let truncated = flat[start...].count > maximumLength
		if truncated {
			shown += "\u{2026}"
		}
		var result = AttributedString(prefix + shown)
		guard needle.isEmpty == false else { return result }

		let plain = String(result.characters)
		var searchStart = plain.startIndex
		while searchStart < plain.endIndex,
		      let found = plain.range(of: needle, options: options, range: searchStart ..< plain.endIndex)
		{
			if let range = Range(found, in: result) {
				result[range].inlinePresentationIntent = .stronglyEmphasized
			}
			searchStart = found.upperBound
		}
		return result
	}
}
