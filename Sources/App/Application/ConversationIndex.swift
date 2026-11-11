// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

/** Owns what this process has put in the Spotlight index.

 Callers hand over `Sendable` entries; the actor works out what changed and
 writes only that. An actor does not serialize calls across suspension points,
 so every operation runs after the previous one has finished: each reads its
 bookkeeping only once the earlier write has landed.
 A failed write leaves the remembered state alone, so the next call retries. */
actor ConversationIndex {
	private static let logger = Logger(subsystem: LogSubsystem.current, category: "ConversationIndex")

	private let writer: any ConversationIndexWriting
	private var indexed: [String: ConversationIndexEntry] = [:]
	/// Whether this launch has reconciled with what an earlier launch left behind.
	private var hasReplacedStaleItems = false
	/// Whether the index is known to hold nothing of ours, so another delete would do nothing.
	private var isKnownEmpty = false
	/// The most recently queued operation, which the next one waits for.
	private var tail: Task<Void, Never>?

	init(writer: some ConversationIndexWriting = CoreSpotlightIndexWriter()) {
		self.writer = writer
	}

	/// Brings the index to exactly `entries`.
	func apply(_ entries: [ConversationIndexEntry]) async {
		await serialized { await self.performApply(entries) }
	}

	/// Deletes everything this app has indexed, for when the setting is turned off.
	func removeAll() async {
		await serialized { await self.performRemoveAll() }
	}

	private func serialized(_ work: @escaping @Sendable () async -> Void) async {
		let previous = tail
		let task = Task {
			await previous?.value
			await work()
		}
		tail = task
		await task.value
		if tail == task {
			tail = nil
		}
	}

	private func performApply(_ entries: [ConversationIndexEntry]) async {
		do {
			if hasReplacedStaleItems == false {
				try await writer.deleteAll()
				indexed = [:]
				hasReplacedStaleItems = true
				isKnownEmpty = true
			}

			let changes = ConversationIndexPlan.changes(from: indexed, to: entries)
			guard changes.isEmpty == false else { return }

			if changes.deletions.isEmpty == false {
				try await writer.delete(ids: changes.deletions)
			}
			if changes.upserts.isEmpty == false {
				// A failed upsert may still have landed in part.
				isKnownEmpty = false
				try await writer.upsert(changes.upserts)
			}
			indexed = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
		} catch {
			Self.logger.error("Spotlight index update failed: \(error.localizedDescription, privacy: .public)")
		}
	}

	private func performRemoveAll() async {
		guard isKnownEmpty == false else { return }
		do {
			try await writer.deleteAll()
			indexed = [:]
			hasReplacedStaleItems = true
			isKnownEmpty = true
		} catch {
			Self.logger.error("Spotlight index removal failed: \(error.localizedDescription, privacy: .public)")
		}
	}
}
