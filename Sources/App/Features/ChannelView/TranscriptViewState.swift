/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *********************************************************************** */

import AppKit

extension NSAttributedString.Key {
	static let transcriptLineNumber = NSAttributedString.Key("GlasstualTranscriptLineNumber")
	static let transcriptNickname = NSAttributedString.Key("GlasstualTranscriptNickname")
	static let transcriptLineType = NSAttributedString.Key("GlasstualTranscriptLineType")
	static let transcriptMessageIdentifier = NSAttributedString.Key("GlasstualTranscriptMessageIdentifier")
	static let transcriptExcerpt = NSAttributedString.Key("GlasstualTranscriptExcerpt")
	static let transcriptAction = NSAttributedString.Key("GlasstualTranscriptAction")
	static let transcriptSelectionSegment = NSAttributedString.Key("GlasstualTranscriptSelectionSegment")
	/** A hairline drawn across the paragraph that carries it, in this colour,
	 `transcriptRuleInset` points below the paragraph's top; the paragraph's
	 layout fragment is a `TranscriptRuleLayoutFragment`. It stands in for an
	 `NSTextBlock` border: text blocks are TextKit 1 features, and a view whose
	 storage holds one is silently moved back to TextKit 1, where the
	 transcript's bottom alignment does not exist. */
	nonisolated static let transcriptRuleColor = // nonisolated: let
		NSAttributedString.Key("GlasstualTranscriptRuleColor")
	nonisolated static let transcriptRuleInset = // nonisolated: let
		NSAttributedString.Key("GlasstualTranscriptRuleInset")
}

/// Both UTF-16 endpoints are relative to a semantic segment within a stable row.
struct SelectionAnchor: Equatable {
	struct Endpoint: Equatable {
		let lineNumber: String
		let segment: String?
		let offset: Int
	}

	let start: Endpoint
	let end: Endpoint
}

struct CachedTranscriptImage {
	let linkIdentifier: String
	let image: NSImage
	let originalSize: NSSize
	let attachment: NSTextAttachment
}

struct TranscriptDisplayedBounds: Equatable {
	let oldest: String?
	let newest: String?
	let count: Int
	let remainingCapacity: Int
}

extension TranscriptMarker {
	var selectionSegment: String {
		switch self {
		case .date: "marker-date"
		case .currentSession: "marker-session"
		case .unread: "marker-unread"
		}
	}

	var isUnread: Bool {
		if case .unread = self {
			true
		} else {
			false
		}
	}
}
