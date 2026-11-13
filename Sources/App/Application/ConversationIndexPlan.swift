// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** One thing Spotlight is told about: a server or a conversation, by name.

 Nothing else is ever indexed. No message text, topic, nickname list, key or
 credential reaches the index. */
nonisolated struct ConversationIndexEntry: Sendable, Equatable {
	enum Kind: String, Sendable {
		case server
		case channel
		case directMessage
	}

	let id: String
	let kind: Kind
	let title: String
	let serverID: String
	let serverName: String
}

nonisolated struct ConversationIndexOptions: Sendable, Equatable {
	/// Servers and channels.
	var indexesConversations: Bool
	/// Direct conversations, which name people. Only when conversations are indexed too.
	var indexesDirectMessages: Bool
}

nonisolated struct ConversationIndexChanges: Sendable, Equatable {
	let upserts: [ConversationIndexEntry]
	let deletions: [String]

	var isEmpty: Bool {
		upserts.isEmpty && deletions.isEmpty
	}
}

/// What to index, and what changed since last time. Pure, so the privacy
/// rules and the diff are testable without a Spotlight index.
nonisolated enum ConversationIndexPlan {
	static func entries(
		servers: [IntentServerSnapshot],
		conversations: [IntentConversationSnapshot],
		options: ConversationIndexOptions
	) -> [ConversationIndexEntry] {
		guard options.indexesConversations else { return [] }

		var entries: [ConversationIndexEntry] = servers.map {
			ConversationIndexEntry(id: $0.id, kind: .server, title: $0.name, serverID: $0.id, serverName: $0.name)
		}
		for conversation in conversations {
			let kind: ConversationIndexEntry.Kind
			switch conversation.kind {
			case .channel:
				kind = .channel
			case .directMessage:
				guard options.indexesDirectMessages else { continue }
				kind = .directMessage
			}
			entries.append(ConversationIndexEntry(
				id: conversation.id,
				kind: kind,
				title: conversation.name,
				serverID: conversation.serverID,
				serverName: conversation.serverName
			))
		}

		var seen: Set<String> = []
		return entries.filter { $0.title.isEmpty == false && seen.insert($0.id).inserted }
	}

	/// The conversations Siri and Spotlight may offer by name as App Shortcut
	/// parameters. They follow the index settings: none with indexing off, and
	/// direct conversations, which name people, only when opted in.
	static func suggestedConversations(
		_ conversations: [IntentConversationSnapshot],
		options: ConversationIndexOptions
	) -> [IntentConversationSnapshot] {
		guard options.indexesConversations else { return [] }
		return conversations.filter { $0.kind == .channel || options.indexesDirectMessages }
	}

	static func changes(
		from previous: [String: ConversationIndexEntry],
		to current: [ConversationIndexEntry]
	) -> ConversationIndexChanges {
		let currentIDs = Set(current.map(\.id))
		return ConversationIndexChanges(
			upserts: current.filter { previous[$0.id] != $0 },
			deletions: previous.keys.filter { currentIDs.contains($0) == false }.sorted()
		)
	}
}
