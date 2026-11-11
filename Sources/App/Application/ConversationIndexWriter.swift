// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppIntents
import CoreSpotlight
import Foundation

/// What `ConversationIndex` needs from a Spotlight index, so the actor's
/// ordering can be exercised without CoreSpotlight.
nonisolated protocol ConversationIndexWriting: Sendable {
	/// Removes everything this app has indexed.
	func deleteAll() async throws
	func delete(ids: [String]) async throws
	func upsert(_ entries: [ConversationIndexEntry]) async throws
}

/// Writes to the default CoreSpotlight index. It opens the connection inside
/// each call, so no non-`Sendable` index is ever stored or shared.
nonisolated struct CoreSpotlightIndexWriter: ConversationIndexWriting {
	private static let domain = "conversations"

	func deleteAll() async throws {
		try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [Self.domain])
	}

	func delete(ids: [String]) async throws {
		try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids)
	}

	func upsert(_ entries: [ConversationIndexEntry]) async throws {
		try await CSSearchableIndex.default().indexSearchableItems(entries.map(Self.item(for:)))
	}

	private static func item(for entry: ConversationIndexEntry) -> CSSearchableItem {
		let attributes: CSSearchableItemAttributeSet
		switch entry.kind {
		case .server:
			attributes = CSSearchableItemAttributeSet(contentType: .item)
			attributes.contentDescription = String(localized: .ShortcutIntents.indexServerDescription)
		case .channel, .directMessage:
			let entity = ConversationEntity(entry: entry)
			attributes = entity.attributeSet
			attributes.associateAppEntity(entity)
		}
		attributes.title = entry.title
		attributes.displayName = entry.title
		attributes.keywords = [entry.serverName]

		let item = CSSearchableItem(uniqueIdentifier: entry.id, domainIdentifier: domain, attributeSet: attributes)
		item.expirationDate = .distantFuture
		return item
	}
}
