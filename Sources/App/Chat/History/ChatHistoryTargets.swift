// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// One line of a `draft/chathistory-targets` batch: a conversation with
/// history, and the time of its latest message.
struct ChatHistoryTarget: Equatable {
	let name: String
	let latest: Date

	/// Reads `CHATHISTORY TARGETS <name> timestamp=<time>`, or `nil` for a
	/// line of any other shape.
	init?(parameters: [String]) {
		guard parameters.count == 3, parameters[0].uppercased() == "TARGETS",
		      parameters[1].isEmpty == false,
		      parameters[2].hasPrefix("timestamp="),
		      let date = DateFormatting.date(fromISO8601: String(parameters[2].dropFirst("timestamp=".count)))
		else { return nil }
		name = parameters[1]
		latest = date
	}

	init(name: String, latest: Date) {
		self.name = name
		self.latest = latest
	}
}

/// What a `TARGETS` sweep does with the conversations it found.
enum ChatHistoryTargetsPolicy {
	/// How many direct conversations an automatic sweep opens; the rest are listed.
	static let maximumDiscoveredConversations = 20
	/// How many targets one sweep asks for.
	static let requestLimit: UInt = 50
	/// How far each bound is moved outwards, for clock skew between client and server.
	static let timestampFuzz: TimeInterval = 5

	/** The direct conversations worth opening, in the server's order (most
	 recently active first), split at `cap`. Channels are left out — joined
	 ones catch up by themselves and others are never joined from here — and
	 so are the user's own name, ignored senders and conversations that are
	 already open. */
	static func discovered(
		_ targets: [ChatHistoryTarget],
		isChannel: (String) -> Bool,
		isSelf: (String) -> Bool,
		isIgnored: (String) -> Bool,
		hasConversation: (String) -> Bool,
		cap: Int
	) -> (open: [String], overflow: [String]) {
		var seen = Set<String>()
		let candidates = targets.map(\.name).filter { name in
			guard isChannel(name) == false, isSelf(name) == false, isIgnored(name) == false,
			      hasConversation(name) == false
			else { return false }
			return seen.insert(name.lowercased()).inserted
		}
		let limit = max(cap, 0)
		return (Array(candidates.prefix(limit)), Array(candidates.dropFirst(limit)))
	}
}
