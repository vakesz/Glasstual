// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// One conversation the spotlight can offer, as the row draws it.
///
/// A value rather than the conversation itself: one can close while the
/// spotlight is open, so the row keeps the identity the chat session can be
/// asked for again and the counts as they stood when the list was built.
nonisolated struct ChannelSpotlightSearchResult: Identifiable, Hashable, Sendable {
	let id: String
	/// The server the conversation belongs to, which conversation navigation can
	/// be restricted to.
	let sessionID: String
	let conversationName: String
	/// Empty when the conversation has no server, which is what the title falls
	/// back to the bare conversation name for.
	let networkName: String
	let highlightCount: Int
	let unreadCount: Int
	/// How well the conversation name matches what was typed. Zero until it is
	/// scored, which is also what an empty search leaves it at.
	var distance = 0.0

	init(
		id: String,
		sessionID: String,
		conversationName: String,
		networkName: String,
		highlightCount: Int = 0,
		unreadCount: Int = 0,
		distance: Double = 0
	) {
		self.id = id
		self.sessionID = sessionID
		self.conversationName = conversationName
		self.networkName = networkName
		self.highlightCount = highlightCount
		self.unreadCount = unreadCount
		self.distance = distance
	}

	/// The conversation and the server it is on, or the bare name when it has no
	/// server to name.
	var title: String {
		guard networkName.isEmpty == false else { return conversationName }
		return String(localized: .ChannelSpotlight.channelOnNetwork(conversationName, networkName))
	}

	/** What is waiting in the conversation, or nothing at all.

	 Every row used to read "0 highlights, 0 unread messages", which is the
	 state a conversation is in for most of the time it is open. A count is worth a
	 line when there is something to count. */
	var activity: String? {
		switch (highlightCount, unreadCount) {
		case (0, 0):
			nil
		case let (highlights, 0):
			String(localized: .ChannelSpotlight.highlightCount(highlights))
		case let (0, unread):
			String(localized: .ChannelSpotlight.unreadMessageCount(unread))
		case let (highlights, unread):
			String(localized: .ChannelSpotlight.joinsTwoChannelStatus(
				String(localized: .ChannelSpotlight.highlightCount(highlights)),
				String(localized: .ChannelSpotlight.unreadMessageCount(unread))
			))
		}
	}

	func scored(against searchString: String) -> Self {
		var scored = self
		scored.distance = searchString.isEmpty
			? 0
			: Double(conversationName.matchScore(against: searchString, lengthPenaltyWeight: 1.0))
		return scored
	}
}

extension ChannelSpotlightSearchResult {
	@MainActor
	init(conversation: Conversation) {
		self.init(
			id: conversation.uniqueIdentifier,
			sessionID: conversation.associatedSession?.uniqueIdentifier ?? "",
			conversationName: conversation.name,
			networkName: conversation.associatedSession?.networkNameAlt ?? "",
			highlightCount: conversation.nicknameHighlightCount,
			unreadCount: conversation.unreadCount
		)
	}
}

/// Which search results the spotlight draws, and in what order.
///
/// This was an `NSArrayController` filter predicate (`distance >= 0.5`, plus
/// `sessionId LIKE[c]` when conversation navigation is per-server) and a sort
/// descriptor on `distance`. It is written out here so it can be read and
/// tested; the table only ever sees the answer.
nonisolated enum ChannelSpotlightSearchResults {
	/// The lowest match score worth showing.
	static let minimumDistance = 0.5

	/// The rows to draw, best match first.
	///
	/// - Parameter sessionID: the only server to show conversations from, or `nil`
	///   for every server. An empty string matches only results with no server,
	///   which is what the predicate did when no session was selected.
	static func displayed(
		_ results: [ChannelSpotlightSearchResult],
		restrictedToSession sessionID: String?
	) -> [ChannelSpotlightSearchResult] {
		let matches = results.enumerated().filter { _, result in
			guard result.distance >= minimumDistance else {
				return false
			}

			guard let sessionID else {
				return true
			}

			return result.sessionID.caseInsensitiveCompare(sessionID) == .orderedSame
		}

		/* Ties keep the order they arrived in: the row a result lands on is
		 also its ⌘-number shortcut, so it must not shuffle between redraws. */
		return matches
			.sorted { lhs, rhs in
				if lhs.element.distance == rhs.element.distance {
					return lhs.offset < rhs.offset
				}

				return lhs.element.distance > rhs.element.distance
			}
			.map(\.element)
	}
}
