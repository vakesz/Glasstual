// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// How much of the stored history a search reads.
enum ScrollbackSearchScope: String, CaseIterable, Identifiable, Sendable {
	case all
	case server
	case conversation

	var id: String {
		rawValue
	}
}

/// One conversation a search can read, as the window knows it. A value, so the
/// scope is resolved on a snapshot and never against live objects.
nonisolated struct ScrollbackSearchTarget: Equatable, Sendable {
	let viewIdentifier: String
	let title: String
	let serverIdentifier: String
	let serverName: String
}

/** Every conversation that has history, and what is selected in the main
 window, which is what the narrower scopes are relative to. */
nonisolated struct ScrollbackSearchTargets: Equatable, Sendable {
	var entries: [ScrollbackSearchTarget] = []
	var selectedViewIdentifier: String?
	var selectedServerIdentifier: String?

	static let empty = Self()

	func isAvailable(_ scope: ScrollbackSearchScope) -> Bool {
		switch scope {
		case .all: entries.isEmpty == false
		case .server: selectedServerIdentifier != nil
		case .conversation: selectedViewIdentifier.map { id in entries.contains { $0.viewIdentifier == id } } == true
		}
	}

	/// The views a search of `scope` reads. A view that is not listed is never
	/// named, which keeps the history of a conversation that was closed out of
	/// the results.
	func viewIdentifiers(for scope: ScrollbackSearchScope) -> [String] {
		switch scope {
		case .all:
			entries.map(\.viewIdentifier)
		case .server:
			entries.filter { $0.serverIdentifier == selectedServerIdentifier }.map(\.viewIdentifier)
		case .conversation:
			entries.filter { $0.viewIdentifier == selectedViewIdentifier }.map(\.viewIdentifier)
		}
	}

	func target(forView identifier: String) -> ScrollbackSearchTarget? {
		entries.first { $0.viewIdentifier == identifier }
	}
}
