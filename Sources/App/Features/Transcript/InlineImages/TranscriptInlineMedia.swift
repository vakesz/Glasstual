// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** An image a line links to that waits for the reader to ask for it.

 A session on the reader's own SOCKS5 or HTTP proxy fetches inline images only
 on request (`InlineImageRoute.inlineImageFetch`). The line draws this in the
 image's place, and activating it starts the one fetch. The state is kept with
 the line, so redrawing the line for a theme or a width redraws the same state
 and never fetches. */
nonisolated struct TranscriptInlineImagePlaceholder: Hashable, Sendable {
	/// Where one placeholder sits: its line and the link it stands for. It is
	/// also the attribute value on the character that draws it.
	struct Key: Hashable, Sendable {
		let lineNumber: String
		let linkIdentifier: String
	}

	enum State: Hashable, Sendable {
		/// Waiting for the reader.
		case ready
		/// The fetch the reader asked for is under way.
		case loading
		/// That fetch failed; activating the placeholder tries once more.
		case failed

		var isActivatable: Bool {
			self != .loading
		}
	}

	let key: Key
	let sourceURL: URL
	var state = State.ready

	init(lineNumber: String, linkIdentifier: String, sourceURL: URL, state: State = .ready) {
		key = Key(lineNumber: lineNumber, linkIdentifier: linkIdentifier)
		self.sourceURL = sourceURL
		self.state = state
	}

	/// The host the fetch will contact, as the placeholder names it.
	var host: String {
		sourceURL.host(percentEncoded: false) ?? sourceURL.absoluteString
	}
}

/// What a line draws below its text for one link: the image, or the
/// placeholder that stands in for it until the reader asks for it.
enum TranscriptInlineMedia {
	case image(CachedTranscriptImage)
	case placeholder(TranscriptInlineImagePlaceholder)

	var linkIdentifier: String {
		switch self {
		case let .image(image): image.linkIdentifier
		case let .placeholder(placeholder): placeholder.key.linkIdentifier
		}
	}

	var placeholder: TranscriptInlineImagePlaceholder? {
		guard case let .placeholder(placeholder) = self else { return nil }
		return placeholder
	}
}
