/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

/// Editor presentation stays on the main actor and never enters a render job.
struct LogRendererConfiguration {
	var preferredFont: NSFont?
	var preferredFontColor: NSColor?
}

/** The preference values the renderer branches on, read once on the main actor
 and carried into the render with the line.

 Reading them from inside the renderer made a render a function of hidden global
 state: the same body and the same options could produce two different results
 and nothing in the signature said so. */
nonisolated struct TranscriptTextPolicy: Sendable { // nonisolated: value
	var filtersUnicodeTextSpam = false
	var highlightMatchingMethod = NicknameHighlightMatchMode.exact
	var detectsHighlightSpam = true
	var linkSchemes = LinkSchemePolicy()

	init(
		filtersUnicodeTextSpam: Bool = false,
		highlightMatchingMethod: NicknameHighlightMatchMode = .exact,
		detectsHighlightSpam: Bool = true,
		linkSchemes: LinkSchemePolicy = LinkSchemePolicy()
	) {
		self.filtersUnicodeTextSpam = filtersUnicodeTextSpam
		self.highlightMatchingMethod = highlightMatchingMethod
		self.detectsHighlightSpam = detectsHighlightSpam
		self.linkSchemes = linkSchemes
	}

	/// The policy the reader's preferences describe right now.
	@MainActor static func current() -> TranscriptTextPolicy {
		TranscriptTextPolicy(
			filtersUnicodeTextSpam: Preferences.Messages.filterUnicodeTextSpam.value,
			highlightMatchingMethod: Preferences.Highlights.matchingMethod.value,
			detectsHighlightSpam: Preferences.Messages.detectHighlightSpam.value,
			linkSchemes: .current()
		)
	}
}

nonisolated struct TranscriptRenderOptions: Sendable { // nonisolated: value
	var renderLinks = false
	var lineType = LogLineType.undefined
	var memberType = LogLineMemberType.normal
	var highlightKeywords: [String] = []
	var excludedKeywords: [String] = []
	/// The preference facts the render needs, taken on the main actor.
	var textPolicy = TranscriptTextPolicy()
}
