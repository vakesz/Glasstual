// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// The keywords a line is matched against, and the matches this session keeps
/// so the highlight sheet can be opened after the fact.
@MainActor
extension ServerSession {
	/** How many highlights one session keeps.

	 The cache exists so the highlight sheet can be opened after the fact; it
	 draws a finite list, and nothing else reads more than the newest entry.
	 Without a ceiling a long session on a highlight-heavy conversation holds every
	 `ChatLine` it ever matched for the life of the process. */
	static let maximumCachedHighlights = 500

	func clearCachedHighlights() {
		cachedHighlights = []
	}

	func cacheHighlight(in conversation: Conversation, with chatLine: ChatLine) {
		guard environment.settings.logHighlights else { return }

		let newEntry = HighlightRecord(
			lineLogged: chatLine,
			sessionId: uniqueIdentifier,
			conversationId: conversation.uniqueIdentifier
		)
		/* Appended rather than inserted at the front: inserting copied the whole
		 array on every highlight, and the one reader sorts by time anyway. */
		cachedHighlights.append(newEntry)

		if cachedHighlights.count > Self.maximumCachedHighlights {
			cachedHighlights.removeFirst(cachedHighlights.count - Self.maximumCachedHighlights)
		}

		output?.highlightWasLogged(newEntry)
	}

	/// The keyword lists a printed line carries: the user's, plus whatever the
	/// connection's own highlight conditions add for `conversation`.
	func highlightKeywordLists(
		for conversation: Conversation?,
		lineType: ChatLineKind,
		memberType: ChatLineMemberKind
	) -> (exclude: [String]?, match: [String]?) {
		guard LinePresentationPolicy.allowsHighlightMatching(
			conversationExists: conversation != nil,
			ignoresHighlights: conversation?.config.ignoreHighlights ?? false,
			lineType: lineType,
			memberType: memberType
		), let conversation else {
			return (nil, nil)
		}

		var excluded = environment.settings.highlightExcludeKeywords
		var matches = environment.settings.highlightMatchKeywords
		if environment.settings.highlightMatchingMethod != .regularExpression,
		   environment.settings.highlightCurrentNickname
		{
			appendIfMissing(userNickname, to: &matches)
		}
		for condition in config.highlightList {
			if let conversationIdentifier = condition.matchChannelId,
			   !conversationIdentifier.isEmpty,
			   conversationIdentifier != conversation.uniqueIdentifier
			{
				continue
			}
			if condition.matchIsExcluded {
				appendIfMissing(condition.matchKeyword, to: &excluded)
			} else {
				appendIfMissing(condition.matchKeyword, to: &matches)
			}
		}
		return (excluded, matches)
	}

	private func appendIfMissing(_ value: String, to values: inout [String]) {
		if !values.contains(value) {
			values.append(value)
		}
	}
}
