// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppIntents
import CocoaExtensions
import CoreSpotlight
import Foundation
import os

/** Owns the Spotlight index and what this process has put in it.

 The index is constructed here and nothing else holds it. Callers hand over
 `Sendable` entries; the actor works out what changed and writes only that.
 A failed write leaves the remembered state alone, so the next call retries. */
actor ConversationIndex {
	private static let logger = Logger(subsystem: LogSubsystem.current, category: "ConversationIndex")
	private static let domain = "conversations"

	private let index = CSSearchableIndex.default()
	private var indexed: [String: ConversationIndexEntry] = [:]
	/// Whether this launch has reconciled with what an earlier launch left behind.
	private var hasReplacedStaleItems = false

	/// Brings the index to exactly `entries`.
	func apply(_ entries: [ConversationIndexEntry]) async {
		do {
			if hasReplacedStaleItems == false {
				try await index.deleteSearchableItems(withDomainIdentifiers: [Self.domain])
				indexed = [:]
				hasReplacedStaleItems = true
			}

			let changes = ConversationIndexPlan.changes(from: indexed, to: entries)
			guard changes.isEmpty == false else { return }

			if changes.deletions.isEmpty == false {
				try await index.deleteSearchableItems(withIdentifiers: changes.deletions)
			}
			if changes.upserts.isEmpty == false {
				try await index.indexSearchableItems(changes.upserts.map(Self.item(for:)))
			}
			indexed = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
		} catch {
			Self.logger.error("Spotlight index update failed: \(error.localizedDescription, privacy: .public)")
		}
	}

	/// Deletes everything this app has indexed, for when the setting is turned off.
	func removeAll() async {
		do {
			try await index.deleteSearchableItems(withDomainIdentifiers: [Self.domain])
			indexed = [:]
			hasReplacedStaleItems = true
		} catch {
			Self.logger.error("Spotlight index removal failed: \(error.localizedDescription, privacy: .public)")
		}
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
