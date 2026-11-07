// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// One match as the result list shows it: the stored hit and the names of the
/// conversation and server it belongs to.
struct ScrollbackSearchRow: Identifiable, Equatable, Sendable {
	let hit: ScrollbackSearchHit
	let conversationName: String
	let serverName: String

	var id: String {
		hit.id
	}
}

/// The rows of one conversation, which is how the list is grouped.
struct ScrollbackSearchGroup: Identifiable, Equatable, Sendable {
	let viewIdentifier: String
	let conversationName: String
	let serverName: String
	let rows: [ScrollbackSearchRow]

	var id: String {
		viewIdentifier
	}

	/// Rows grouped by conversation, the conversation with the newest match
	/// first, each group newest first. `rows` arrive newest first already.
	static func grouping(_ rows: [ScrollbackSearchRow]) -> [Self] {
		var order: [String] = []
		var grouped: [String: [ScrollbackSearchRow]] = [:]
		for row in rows {
			if grouped[row.hit.viewIdentifier] == nil {
				order.append(row.hit.viewIdentifier)
			}
			grouped[row.hit.viewIdentifier, default: []].append(row)
		}
		return order.compactMap { identifier in
			guard let rows = grouped[identifier], let first = rows.first else { return nil }
			return Self(
				viewIdentifier: identifier, conversationName: first.conversationName,
				serverName: first.serverName, rows: rows
			)
		}
	}
}
