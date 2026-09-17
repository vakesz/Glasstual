// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// One channel the spotlight can offer, as the row draws it.
///
/// A value rather than the channel itself: a channel can close while the
/// spotlight is open, so the row keeps the identity the world can be asked for
/// again and the counts as they stood when the list was built.
nonisolated struct ChannelSpotlightSearchResult: Identifiable, Hashable, Sendable {
	let id: String
	/// The server the channel belongs to, which channel navigation can be
	/// restricted to.
	let clientID: String
	let channelName: String
	/// Empty when the channel has no server, which is what the title falls back
	/// to the bare channel name for.
	let networkName: String
	let highlightCount: Int
	let unreadCount: Int
	/// How well the channel name matches what was typed. Zero until it is
	/// scored, which is also what an empty search leaves it at.
	var distance = 0.0

	init(
		id: String,
		clientID: String,
		channelName: String,
		networkName: String,
		highlightCount: Int = 0,
		unreadCount: Int = 0,
		distance: Double = 0
	) {
		self.id = id
		self.clientID = clientID
		self.channelName = channelName
		self.networkName = networkName
		self.highlightCount = highlightCount
		self.unreadCount = unreadCount
		self.distance = distance
	}

	/// The channel and the server it is on, or the bare name when it has no
	/// server to name.
	var title: String {
		guard networkName.isEmpty == false else { return channelName }
		return String(localized: .ChannelSpotlight.channelOnNetwork(channelName, networkName))
	}

	/** What is waiting in the channel, or nothing at all.

	 Every row used to read "0 highlights, 0 unread messages", which is the
	 state a channel is in for most of the time it is open. A count is worth a
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
			: Double(channelName.matchScore(against: searchString, lengthPenaltyWeight: 1.0))
		return scored
	}
}

extension ChannelSpotlightSearchResult {
	@MainActor
	init(channel: Channel) {
		self.init(
			id: channel.uniqueIdentifier,
			clientID: channel.associatedClient?.uniqueIdentifier ?? "",
			channelName: channel.name,
			networkName: channel.associatedClient?.networkNameAlt ?? "",
			highlightCount: channel.nicknameHighlightCount,
			unreadCount: channel.treeUnreadCount
		)
	}
}

/// Which search results the spotlight draws, and in what order.
///
/// This was an `NSArrayController` filter predicate (`distance >= 0.5`, plus
/// `clientId LIKE[c]` when channel navigation is per-server) and a sort
/// descriptor on `distance`. It is written out here so it can be read and
/// tested; the table only ever sees the answer.
nonisolated enum ChannelSpotlightSearchResults {
	/// The lowest match score worth showing.
	static let minimumDistance = 0.5

	/// The rows to draw, best match first.
	///
	/// - Parameter clientID: the only server to show channels from, or `nil`
	///   for every server. An empty string matches only results with no server,
	///   which is what the predicate did when no client was selected.
	static func displayed(
		_ results: [ChannelSpotlightSearchResult],
		restrictedToClient clientID: String?
	) -> [ChannelSpotlightSearchResult] {
		let matches = results.enumerated().filter { _, result in
			guard result.distance >= minimumDistance else {
				return false
			}

			guard let clientID else {
				return true
			}

			return result.clientID.caseInsensitiveCompare(clientID) == .orderedSame
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
