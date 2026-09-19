// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation

/** What the transcript writes into its own text beside the characters: which
 line and which message a run belongs to, what clicking it does, and the pieces
 of layout that are not text at all.

 Every key is namespaced, because the storage is an `NSTextStorage` the system's
 own machinery also reads. */
nonisolated extension NSAttributedString.Key { // nonisolated: constants
	static let transcriptLineNumber = NSAttributedString.Key("GlasstualTranscriptLineNumber")
	/// The name the run itself spells: the author's, on the name that heads the
	/// line, and the mentioned member's, on a mention inside a message.
	static let transcriptNickname = NSAttributedString.Key("GlasstualTranscriptNickname")
	/** Who wrote the line this run belongs to. Every run of a line carries it,
	 including the timestamp and the body, which is what lets a reply raised
	 from anywhere in a message name its author. */
	static let transcriptLineNickname = NSAttributedString.Key("GlasstualTranscriptLineNickname")
	static let transcriptLineType = NSAttributedString.Key("GlasstualTranscriptLineType")
	static let transcriptMessageIdentifier = NSAttributedString.Key("GlasstualTranscriptMessageIdentifier")
	static let transcriptExcerpt = NSAttributedString.Key("GlasstualTranscriptExcerpt")
	/// A `TranscriptAction`: what the run stands for when it is clicked.
	static let transcriptAction = NSAttributedString.Key("GlasstualTranscriptAction")
	/// A `TranscriptReactionTarget`: the run is a reaction chip, and clicking
	/// it reacts to that message.
	static let transcriptReaction = NSAttributedString.Key("GlasstualTranscriptReaction")
	/// The address an inline image was fetched from, on the character that
	/// draws it.
	static let transcriptInlineImage = NSAttributedString.Key("GlasstualTranscriptInlineImage")
	static let transcriptSelectionSegment = NSAttributedString.Key("GlasstualTranscriptSelectionSegment")
	/** Characters the transcript drew for its own layout rather than for the
	 text: the thin spaces that pad a reaction chip, the zero-width space an
	 unread marker stands on, the isolates wire text is drawn inside. Copying
	 leaves exactly these out, and nothing the sender typed. */
	static let transcriptPadding = NSAttributedString.Key("GlasstualTranscriptPadding")
	/** A hairline drawn across the paragraph that carries it, in this colour,
	 `transcriptRuleInset` points below the paragraph's top; the paragraph's
	 layout fragment is a `TranscriptRuleLayoutFragment`. It stands in for an
	 `NSTextBlock` border: text blocks are TextKit 1 features, and a view whose
	 storage holds one is silently moved back to TextKit 1, where the
	 transcript's bottom alignment does not exist. */
	nonisolated static let transcriptRuleColor =
		NSAttributedString.Key("GlasstualTranscriptRuleColor")
	nonisolated static let transcriptRuleInset =
		NSAttributedString.Key("GlasstualTranscriptRuleInset")
}

struct CachedTranscriptImage {
	let linkIdentifier: String
	/// Where the image came from, so its run can offer the link it stands for.
	let sourceURL: URL
	let image: NSImage
	let originalSize: NSSize
	let attachment: NSTextAttachment
}
