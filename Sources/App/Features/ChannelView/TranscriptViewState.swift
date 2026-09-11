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
	/// A `TranscriptAction`, stored as its `attributeValue`.
	static let transcriptAction = NSAttributedString.Key("GlasstualTranscriptAction")
	/// A `TranscriptReactionTarget`, stored as its `attributeValue`: the run is
	/// a reaction chip, and clicking it reacts to that message.
	static let transcriptReaction = NSAttributedString.Key("GlasstualTranscriptReaction")
	/// The address an inline image was fetched from, on the character that
	/// draws it.
	static let transcriptInlineImage = NSAttributedString.Key("GlasstualTranscriptInlineImage")
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
	/// Where the image came from, so its run can offer the link it stands for.
	let sourceURL: URL
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

/** The reaction one chip in a message's details stands for. Like
 ``TranscriptAction`` it travels through the text storage as a string, and this
 is the one place that string is written and read. */
struct TranscriptReactionTarget: Equatable {
	let messageIdentifier: String
	let emoji: String

	/// A separator no message identifier and no emoji can contain.
	private static let separator: Character = "\u{1F}"

	var attributeValue: String {
		"\(messageIdentifier)\(Self.separator)\(emoji)"
	}

	init(messageIdentifier: String, emoji: String) {
		self.messageIdentifier = messageIdentifier
		self.emoji = emoji
	}

	init?(attributeValue: Any?) {
		guard let value = attributeValue as? String else { return nil }
		let parts = value.split(separator: Self.separator, maxSplits: 1, omittingEmptySubsequences: false)
		guard parts.count == 2, parts[0].isEmpty == false, parts[1].isEmpty == false else { return nil }
		messageIdentifier = String(parts[0])
		emoji = String(parts[1])
	}
}

/** What a run of transcript text stands for when it is clicked: a member's
 name or a channel's. It travels through the text storage as a string, and
 this is the one place that string is written and read. */
enum TranscriptAction: Equatable {
	case nickname(String)
	case channel(String)

	private static let nicknamePrefix = "nickname:"
	private static let channelPrefix = "channel:"

	var attributeValue: String {
		switch self {
		case let .nickname(name): Self.nicknamePrefix + name
		case let .channel(name): Self.channelPrefix + name
		}
	}

	init?(attributeValue: Any?) {
		guard let value = attributeValue as? String else { return nil }
		if value.hasPrefix(Self.nicknamePrefix) {
			self = .nickname(String(value.dropFirst(Self.nicknamePrefix.count)))
		} else if value.hasPrefix(Self.channelPrefix) {
			self = .channel(String(value.dropFirst(Self.channelPrefix.count)))
		} else {
			return nil
		}
	}
}
