// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** What every view has stored, as far as this process knows.

 The IRC layer asks this synchronously while it decides whether a line replayed
 by the server is one the reader already has, which is why the answers are held
 on the main actor rather than behind the store's actor: a history batch is
 filtered line by line in the turn it arrives.

 Each view holds its newest ``defaultRecentLimit`` lines whole and the older
 ones in a reduced form; ``ScrollbackViewIndex`` says what each keeps. */
@MainActor
final class ScrollbackDuplicateIndex {
	/** How many lines per view are held whole.

	 Four times the transcript's 1,000-line display cap and about forty times
	 the 100-line page a CHATHISTORY request asks for, so a replay lands in
	 this tier and a line the reader can still see is never outside it. */
	static let defaultRecentLimit = 4096

	private var viewIndexes: [String: ScrollbackViewIndex] = [:]
	private var nextGeneration = ScrollbackGeneration.initial
	private let recentLimit: Int

	init(recentLimit: Int = ScrollbackDuplicateIndex.defaultRecentLimit) {
		self.recentLimit = recentLimit
	}

	private func makeGeneration() -> ScrollbackGeneration {
		defer { nextGeneration = nextGeneration.advanced() }
		return nextGeneration
	}

	private static func fallbackKey(
		for date: Date?,
		nickname: String?,
		messageBody: String?
	) -> LineDigest? {
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
		return LineDigest.fallback(milliseconds: milliseconds, nickname: nickname ?? "", messageBody: messageBody)
	}

	/// Indexes `chatLine` for the duplicate checks, and reports whether this call
	/// added it rather than finding it already there.
	@discardableResult
	func indexChatLine(_ chatLine: ChatLine, forView viewIdentifier: String) -> Bool {
		let contribution = Self.contribution(of: chatLine)
		if let added = viewIndexes[viewIdentifier]?.add(contribution, for: chatLine.uniqueIdentifier) {
			return added
		}
		var index = ScrollbackViewIndex(generation: makeGeneration(), recentLimit: recentLimit)
		let added = index.add(contribution, for: chatLine.uniqueIdentifier)
		viewIndexes[viewIdentifier] = index
		return added
	}

	@discardableResult
	func replaceChatLine(_ chatLine: ChatLine, forView viewIdentifier: String) -> Bool {
		viewIndexes[viewIdentifier]?.replace(Self.contribution(of: chatLine), for: chatLine.uniqueIdentifier) ?? false
	}

	private static func contribution(of line: ChatLine) -> ScrollbackContribution {
		ScrollbackContribution(
			messageIdentifier: line.messageIdentifier.flatMap { $0.isEmpty ? nil : LineDigest.messageIdentifier($0) },
			fallbackKey: fallbackKey(for: line.receivedAt, nickname: line.nickname, messageBody: line.messageBody),
			receivedAt: line.receivedAt, isConversation: line.lineType.isConversation,
			readMarkerTimestamp: line.readMarkerTimestamp
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
		viewIndexes[viewIdentifier]?.messageIdentifiers[LineDigest.messageIdentifier(messageIdentifier)] != nil
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

	/// Only timestamps actually supplied by the server can be sent as MARKREAD.
	func newestReadMarkerTimestamp(forView viewIdentifier: String) -> Date? {
		viewIndexes[viewIdentifier]?.newestReadMarkerTimestamp
	}

	// MARK: - Deletion

	/// Marks everything the view holds now as belonging to the removal being
	/// requested, so lines written while it runs survive it.
	func beginRemoval(inView viewIdentifier: String) -> Set<ScrollbackGeneration> {
		let next = makeGeneration()
		return viewIndexes[viewIdentifier]?.beginRemoval(next: next) ?? []
	}

	/// Withdraws the contributions a completed removal covered.
	func removeGenerations(_ generations: Set<ScrollbackGeneration>, inView viewIdentifier: String) {
		viewIndexes[viewIdentifier]?.remove(generations: generations)
	}

	/// Drops a view the store has been told to forget, unless lines arrived for
	/// it while the deletion ran.
	func forgetViewIfEmpty(_ viewIdentifier: String) {
		guard viewIndexes[viewIdentifier]?.isEmpty == true else { return }
		viewIndexes.removeValue(forKey: viewIdentifier)
	}
}
