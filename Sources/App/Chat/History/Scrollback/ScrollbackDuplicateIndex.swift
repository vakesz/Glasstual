// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** What the app knows about the lines of one view, kept in memory so that chat
 history replayed by the server can be checked against the local scrollback.
 The index is filled from every line written and every line fetched, and
 withdrawn again when the store prunes the row behind it — otherwise it would
 hold a second copy of every message the process has ever seen.

 The two lookups are counted rather than set-valued: two lines can carry the
 same body at the same second from the same nickname, and dropping one of them
 must not make the other invisible to the duplicate check.

 The index itself is a value with no reference-typed state; the directory below
 owns the only copies and keeps them on the main actor. */
private nonisolated struct ScrollbackViewIndex: Sendable {
	/// What one indexed line contributed, so the contribution can be withdrawn
	/// when the line goes. `nil` where the line carried no such value.
	struct Contribution: Sendable {
		var messageIdentifier: String?
		var fallbackKey: String?
		var receivedAt: Date
		var isConversation: Bool
	}

	private struct Entry: Sendable {
		let contribution: Contribution
		let generation: UUID
	}

	private(set) var messageIdentifiers: [String: Int] = [:]
	private(set) var fallbackKeys: [String: Int] = [:]
	private var contributions: [String: Entry] = [:]
	private var generation = UUID()
	private(set) var newestDate: Date?
	/** The newest line a person wrote, as opposed to one the session narrated.

	 A read marker is answered against this rather than `newestDate`: joining a
	 channel prints a topic, a mode and a join line stamped now, and none of them
	 is news the badge should count. */
	private(set) var newestConversationDate: Date?

	/// Records what `uniqueIdentifier` contributes, and reports whether this
	/// call added it. A line the index already holds is left alone: the same
	/// row is indexed again on every fetch.
	@discardableResult
	mutating func add(
		_ contribution: Contribution,
		for uniqueIdentifier: String
	) -> Bool {
		guard uniqueIdentifier.isEmpty == false else {
			retain(contribution)
			return false
		}
		guard contributions[uniqueIdentifier] == nil else { return false }
		contributions[uniqueIdentifier] = Entry(contribution: contribution, generation: generation)
		retain(contribution)
		newestDate = max(newestDate ?? contribution.receivedAt, contribution.receivedAt)
		if contribution.isConversation {
			newestConversationDate = max(newestConversationDate ?? contribution.receivedAt, contribution.receivedAt)
		}
		return true
	}

	/// Later writes belong to a new generation. A successful deletion only
	/// withdraws the generations that existed when it was requested.
	mutating func beginRemoval() -> Set<UUID> {
		let removed = Set(contributions.values.map(\.generation))
		generation = UUID()
		return removed
	}

	mutating func remove(generations: Set<UUID>) {
		let identifiers = contributions.filter { generations.contains($0.value.generation) }.map(\.key)
		for identifier in identifiers {
			remove(identifier, updateDates: false)
		}
		refreshDates()
	}

	/// Withdraws what a pruned line contributed.
	mutating func remove(_ uniqueIdentifier: String, updateDates: Bool = true) {
		guard let contribution = contributions.removeValue(forKey: uniqueIdentifier)?.contribution else { return }
		Self.release(contribution.messageIdentifier, from: &messageIdentifiers)
		Self.release(contribution.fallbackKey, from: &fallbackKeys)
		if updateDates, contribution.receivedAt == newestDate || contribution.receivedAt == newestConversationDate {
			refreshDates()
		}
	}

	private mutating func refreshDates() {
		newestDate = contributions.values.map(\.contribution.receivedAt).max()
		newestConversationDate = contributions.values.filter(\.contribution.isConversation)
			.map(\.contribution.receivedAt).max()
	}

	private mutating func retain(_ contribution: Contribution) {
		if let messageIdentifier = contribution.messageIdentifier {
			messageIdentifiers[messageIdentifier, default: 0] += 1
		}
		if let fallbackKey = contribution.fallbackKey {
			fallbackKeys[fallbackKey, default: 0] += 1
		}
	}

	private static func release(_ key: String?, from counts: inout [String: Int]) {
		guard let key, let count = counts[key] else { return }
		if count <= 1 {
			counts.removeValue(forKey: key)
		} else {
			counts[key] = count - 1
		}
	}
}

/** What every view has stored, as far as this process knows.

 The IRC layer asks this synchronously while it decides whether a line replayed
 by the server is one the reader already has, which is why the answers are held
 on the main actor rather than behind the store's actor: a history batch is
 filtered line by line in the turn it arrives. */
@MainActor
final class ScrollbackDuplicateIndex {
	private var viewIndexes: [String: ScrollbackViewIndex] = [:]

	private static func fallbackKey(
		for date: Date?,
		nickname: String?,
		messageBody: String?
	) -> String? {
		guard let date, let messageBody else {
			return nil
		}

		/* Server timestamps carry millisecond precision. Rounding to the
		 millisecond keeps a value parsed twice from the same string equal.

		 A date so far from the epoch that its millisecond count leaves `Int64`
		 cannot have been written by anything that reads it back, so it gets no
		 fallback key rather than trapping the conversion. */
		guard let milliseconds = Int64(exactly: (date.timeIntervalSince1970 * 1000.0).rounded()) else {
			return nil
		}
		return String(format: "%lld\u{001f}%@\u{001f}%@", milliseconds, nickname ?? "", messageBody)
	}

	/// Indexes `chatLine` for the duplicate checks, and reports whether this call
	/// added it rather than finding it already there.
	@discardableResult
	func indexChatLine(_ chatLine: ChatLine, forView viewIdentifier: String) -> Bool {
		let messageIdentifier = chatLine.messageIdentifier

		return viewIndexes[viewIdentifier, default: ScrollbackViewIndex()].add(
			ScrollbackViewIndex.Contribution(
				messageIdentifier: messageIdentifier?.isEmpty == false ? messageIdentifier : nil,
				fallbackKey: Self.fallbackKey(
					for: chatLine.receivedAt,
					nickname: chatLine.nickname,
					messageBody: chatLine.messageBody
				),
				receivedAt: chatLine.receivedAt,
				isConversation: chatLine.lineType.isConversation
			),
			for: chatLine.uniqueIdentifier
		)
	}

	func indexChatLines(_ chatLines: [ChatLine], forView viewIdentifier: String) {
		for chatLine in chatLines {
			indexChatLine(chatLine, forView: viewIdentifier)
		}
	}

	/// Withdraws the lines the store has pruned from the view's index.
	func forgetLines(_ uniqueIdentifiers: [String], inView viewIdentifier: String) {
		for uniqueIdentifier in uniqueIdentifiers {
			viewIndexes[viewIdentifier]?.remove(uniqueIdentifier)
		}
	}

	func containsMessageIdentifier(_ messageIdentifier: String, forView viewIdentifier: String) -> Bool {
		viewIndexes[viewIdentifier]?.messageIdentifiers[messageIdentifier] != nil
	}

	func containsLine(
		receivedAt: Date,
		nickname: String?,
		messageBody: String,
		forView viewIdentifier: String
	) -> Bool {
		guard let index = viewIndexes[viewIdentifier],
		      let fallbackKey = Self.fallbackKey(
		      	for: receivedAt,
		      	nickname: nickname,
		      	messageBody: messageBody
		      )
		else {
			return false
		}

		return index.fallbackKeys[fallbackKey] != nil
	}

	func newestLineDate(forView viewIdentifier: String) -> Date? {
		viewIndexes[viewIdentifier]?.newestDate
	}

	/// The newest stored line a person wrote. What a read marker is compared
	/// against; `newestLineDate` is what a history request asks from.
	func newestConversationLineDate(forView viewIdentifier: String) -> Date? {
		viewIndexes[viewIdentifier]?.newestConversationDate
	}

	// MARK: - Deletion

	/// Marks everything the view holds now as belonging to the removal being
	/// requested, so lines written while it runs survive it.
	func beginRemoval(inView viewIdentifier: String) -> Set<UUID> {
		viewIndexes[viewIdentifier]?.beginRemoval() ?? []
	}

	/// Withdraws the contributions a completed removal covered.
	func removeGenerations(_ generations: Set<UUID>, inView viewIdentifier: String) {
		viewIndexes[viewIdentifier]?.remove(generations: generations)
	}

	/// Drops a view the store has been told to forget, unless lines arrived for
	/// it while the deletion ran.
	func forgetViewIfEmpty(_ viewIdentifier: String) {
		guard viewIndexes[viewIdentifier]?.newestDate == nil else { return }
		viewIndexes.removeValue(forKey: viewIdentifier)
	}
}
