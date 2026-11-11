// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppIntents
import CoreSpotlight

/// A configured server, as Shortcuts lists it.
nonisolated struct ServerEntity: AppEntity {
	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("server-type", table: "ShortcutIntents"))
	static let defaultQuery = ServerEntityQuery()

	let id: String
	let name: String

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(title: "\(name)")
	}
}

/// A channel or direct conversation on a server.
nonisolated struct ConversationEntity: IndexedEntity {
	static let typeDisplayRepresentation = TypeDisplayRepresentation(
		name: LocalizedStringResource("conversation-type", table: "ShortcutIntents")
	)
	static let defaultQuery = ConversationEntityQuery()

	let id: String
	let name: String
	let serverID: String
	let serverName: String
	let isDirect: Bool

	init(snapshot: IntentConversationSnapshot) {
		id = snapshot.id
		name = snapshot.name
		serverID = snapshot.serverID
		serverName = snapshot.serverName
		isDirect = snapshot.kind == .directMessage
	}

	init(entry: ConversationIndexEntry) {
		id = entry.id
		name = entry.title
		serverID = entry.serverID
		serverName = entry.serverName
		isDirect = entry.kind == .directMessage
	}

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(title: "\(name)", subtitle: "\(serverName)")
	}

	/// Names only. The description says where the conversation is, and nothing
	/// of what was said in it.
	var attributeSet: CSSearchableItemAttributeSet {
		let attributes = CSSearchableItemAttributeSet(contentType: .item)
		attributes.title = name
		attributes.displayName = name
		attributes.contentDescription = isDirect
			? String(localized: .ShortcutIntents.indexDirectDescription(serverName))
			: String(localized: .ShortcutIntents.indexChannelDescription(serverName))
		return attributes
	}
}

nonisolated struct ServerEntityQuery: EntityStringQuery {
	func entities(for identifiers: [String]) async throws -> [ServerEntity] {
		await IntentCatalog.servers().filter { identifiers.contains($0.id) }
	}

	func entities(matching string: String) async throws -> [ServerEntity] {
		await IntentCatalog.servers().filter { IntentCatalog.matches(string, in: [$0.name]) }
	}

	func suggestedEntities() async throws -> [ServerEntity] {
		await IntentCatalog.servers()
	}
}

nonisolated struct ConversationEntityQuery: EntityStringQuery {
	func entities(for identifiers: [String]) async throws -> [ConversationEntity] {
		await IntentCatalog.conversations().filter { identifiers.contains($0.id) }
	}

	func entities(matching string: String) async throws -> [ConversationEntity] {
		await IntentCatalog.conversations().filter { IntentCatalog.matches(string, in: [$0.name, $0.serverName]) }
	}

	func suggestedEntities() async throws -> [ConversationEntity] {
		await IntentCatalog.suggestedConversations()
	}
}

/// Entity lists from the live application, read on the main actor.
nonisolated enum IntentCatalog {
	@MainActor
	static func servers() -> [ServerEntity] {
		actions().servers().map { ServerEntity(id: $0.id, name: $0.name) }
	}

	@MainActor
	static func conversations() -> [ConversationEntity] {
		actions().conversations().map(ConversationEntity.init(snapshot:))
	}

	/// The conversations offered as suggestions, which follow the Spotlight
	/// settings. Lookups by identifier or text stay unfiltered, so the Shortcuts
	/// editor and explicit intents still reach every conversation.
	@MainActor
	static func suggestedConversations() -> [ConversationEntity] {
		ConversationIndexPlan.suggestedConversations(
			actions().conversations(),
			options: ConversationIndexCoordinator.storedOptions()
		).map(ConversationEntity.init(snapshot:))
	}

	@MainActor
	static func actions() -> any IntentActions {
		AppServices.intentActions
	}

	/// Case- and diacritic-insensitive substring match; an empty query matches everything.
	static func matches(_ query: String, in fields: [String]) -> Bool {
		let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard query.isEmpty == false else { return true }
		return fields.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
	}
}
