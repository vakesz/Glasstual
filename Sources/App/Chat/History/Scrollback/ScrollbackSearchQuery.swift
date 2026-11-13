// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What to look for in stored history, over which conversations, and between
 which times.

 The caller resolves its scope to view identifiers: the store knows views, not
 servers, and a view it was not asked about is never read. That is also what
 keeps the history of a conversation that no longer exists out of the results,
 because the caller names only the ones it still has. */
nonisolated struct ScrollbackSearchQuery: Equatable, Sendable {
	static let maximumTextLength = 256
	static let defaultResultLimit = 500

	/// What the person typed. Matched against message text and sender.
	var text = ""
	/// Restricts matches to senders whose nickname contains this.
	var sender = ""
	var viewIdentifiers: [String] = []
	var from: Date?
	var through: Date?
	var limit = defaultResultLimit

	init(
		text: String = "",
		sender: String = "",
		viewIdentifiers: [String] = [],
		from: Date? = nil,
		through: Date? = nil,
		limit: Int = defaultResultLimit
	) {
		self.text = text
		self.sender = sender
		self.viewIdentifiers = viewIdentifiers
		self.from = from
		self.through = through
		self.limit = limit
	}

	/// Whether the query asks for anything. A search with no text and no sender
	/// would list every line, which is a scroll and not a search.
	var isSearchable: Bool {
		trimmedText.isEmpty == false || trimmedSender.isEmpty == false
	}

	var trimmedText: String {
		String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumTextLength))
	}

	var trimmedSender: String {
		String(sender.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumTextLength))
	}

	/// The query as the store reads it: text folded the way stored text is,
	/// each view named once, and the limit a positive number.
	var normalized: Self {
		var seen = Set<String>()
		return Self(
			text: ScrollbackSearchFields.folded(trimmedText),
			sender: trimmedSender,
			viewIdentifiers: viewIdentifiers.filter { seen.insert($0).inserted },
			from: from,
			through: through,
			limit: max(1, limit)
		)
	}
}

/// One matching row: where it is, and what it says.
nonisolated struct ScrollbackSearchHit: Equatable, Identifiable, Sendable {
	let viewIdentifier: String
	let lineIdentifier: String
	let sender: String
	let text: String
	let timestamp: TimeInterval
	/// The row's own position, which names it even when another row shares its
	/// line identifier.
	let cursor: ScrollbackRowCursor

	var id: String {
		cursor.rowURI
	}

	var date: Date {
		Date(timeIntervalSince1970: timestamp)
	}

	/// Newest first; ties fall back on the row position so the order is stable.
	func sortsBefore(_ other: Self) -> Bool {
		timestamp != other.timestamp ? timestamp > other.timestamp : cursor > other.cursor
	}
}
