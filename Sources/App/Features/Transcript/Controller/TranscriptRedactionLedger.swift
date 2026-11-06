// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The messages a server told this view were deleted.

 A redaction is carried by the connection, not by the line it removes, and it
 can arrive before that line has been drawn: a replay, or a line still
 rendering. The ledger is what every row is checked against as it is drawn, so
 a deleted message never reaches the screen after the news of its deletion, and
 server history that replays the text later cannot bring it back.

 Bounded, oldest first: an identifier a view has not been shown for thousands
 of deletions is not one a replay can still reach. */
nonisolated struct TranscriptRedactionLedger: Sendable {
	/// How many deletions are remembered.
	static let capacity = 4096

	private var identifiers: Set<MessageIdentifierKey> = []
	private var order: [MessageIdentifierKey] = []

	var all: [MessageIdentifierKey] {
		order
	}

	func contains(_ identifier: String?) -> Bool {
		guard let identifier, identifier.isEmpty == false else { return false }
		return identifiers.contains(MessageIdentifierKey(identifier))
	}

	/// Remembers a deletion, and reports whether it was news.
	@discardableResult
	mutating func record(_ identifier: String) -> Bool {
		guard identifier.isEmpty == false else { return false }
		let key = MessageIdentifierKey(identifier)
		guard identifiers.insert(key).inserted else { return false }
		order.append(key)
		if order.count > Self.capacity {
			identifiers.remove(order.removeFirst())
		}
		return true
	}

	mutating func removeAll() {
		identifiers.removeAll()
		order.removeAll()
	}
}
