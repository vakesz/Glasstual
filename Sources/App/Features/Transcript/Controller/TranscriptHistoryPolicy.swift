// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Whether a transcript reads its stored scrollback when it loads.

 The console and one-to-one chats never replay stored lines. On the first load
 of a view the reader's settings decide: scrollback is replayed only when asked
 for, and a direct conversation only when direct conversations are remembered. */
nonisolated struct HistoryLoadPolicy: Sendable, Equatable {
	var firstLoad: Bool
	var reloadsScrollbackOnLaunch: Bool
	var isConsole: Bool
	var isDirectChat: Bool
	var isDirect: Bool
	var remembersDirectConversations: Bool

	var includesStoredHistory: Bool {
		if isConsole || isDirectChat {
			return false
		}
		guard firstLoad else {
			return true
		}
		return reloadsScrollbackOnLaunch && (!isDirect || remembersDirectConversations)
	}
}

/** The pure half of the initial history render: how a fetch outcome reads and
 which stored rows reuse a replayed line. */
nonisolated enum TranscriptHistoryMerge {
	struct Fetched: Sendable {
		var entries: [ScrollbackEntry]
		var failure: ScrollbackFetchFailure?
		var succeeded: Bool
	}

	/// How each stored row is drawn: from the line already rendered during the
	/// replay, or fresh.
	enum Slot: Sendable, Equatable {
		case replayed(lineNumber: String)
		case fresh
	}

	nonisolated static func fetched(_ outcome: ScrollbackFetchOutcome) -> Fetched { // nonisolated: pure
		switch outcome {
		case let .page(entries):
			Fetched(entries: entries, failure: nil, succeeded: true)
		case let .failed(reason):
			Fetched(entries: [], failure: reason, succeeded: false)
		case .cancelled:
			Fetched(entries: [], failure: nil, succeeded: false)
		}
	}

	/// Assigns each identifier, in row order, to the replayed line carrying it
	/// when that line has not been claimed yet. A repeated identifier is fresh.
	/// Returns the slots and the replayed line numbers that were claimed.
	nonisolated static func assign( // nonisolated: pure
		identifiers: [String], replayedLineNumbers: Set<String>
	) -> (slots: [Slot], consumed: Set<String>) {
		var consumed = Set<String>()
		let slots = identifiers.map { identifier -> Slot in
			if replayedLineNumbers.contains(identifier), consumed.insert(identifier).inserted {
				.replayed(lineNumber: identifier)
			} else {
				.fresh
			}
		}
		return (slots, consumed)
	}
}
