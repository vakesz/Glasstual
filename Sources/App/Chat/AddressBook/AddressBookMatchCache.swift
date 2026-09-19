// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Remembers which address book entry a hostmask matched.
///
/// The entries are passed in at every lookup rather than held: the cache
/// answers for whatever list the session holds now, and the session clears it
/// when that list changes.
final class AddressBookMatchCache {
	/** Hostmask to the rule that matched it, or to `nil` when nothing did.
	 The entry is a value type now, so this is a plain dictionary trimmed at a
	 fixed size rather than an `NSCache`. */
	private var matches: [String: AddressBookEntry?] = [:]
	private var matchOrder: [String] = []
	private static let matchLimit = 100

	func clearCachedMatches() {
		matches.removeAll()
		matchOrder.removeAll()
	}

	func clearCachedMatches(forHostmask hostmask: String) {
		matches.removeValue(forKey: hostmask)
		matchOrder.removeAll { $0 == hostmask }
	}

	func findIgnores(forHostmask hostmask: String, in entries: [AddressBookEntry]) -> [AddressBookEntry] {
		guard let match = findAddressBookEntry(forHostmask: hostmask, in: entries) else {
			return []
		}

		if match.entryType == .ignore {
			return [match]
		}

		guard match.entryType == .mixed else {
			return []
		}

		return match.parentEntries?.filter { $0.entryType == .ignore } ?? []
	}

	func findAddressBookEntry(forHostmask hostmask: String, in entries: [AddressBookEntry]) -> AddressBookEntry? {
		if let cached = matches[hostmask] {
			return cached
		}

		let match = uncachedMatch(forHostmask: hostmask, in: entries)

		matches[hostmask] = match
		matchOrder.append(hostmask)

		if matchOrder.count > Self.matchLimit {
			matches.removeValue(forKey: matchOrder.removeFirst())
		}

		return match
	}

	private func uncachedMatch(forHostmask hostmask: String, in entries: [AddressBookEntry]) -> AddressBookEntry? {
		var singleMatch: AddressBookEntry?
		var multipleMatches: [AddressBookEntry]?

		for entry in entries where entry.checkMatch(hostmask) {
			if multipleMatches != nil {
				multipleMatches?.append(entry)
			} else if let existingMatch = singleMatch {
				multipleMatches = [existingMatch, entry]
				singleMatch = nil
			} else {
				singleMatch = entry
			}
		}

		if let multipleMatches {
			return mergedEntry(from: multipleMatches)
		}

		return singleMatch
	}

	/** Every flag a merged entry takes from the rules it was merged from.

	 The merge is "any parent sets it" for all of them, so the list is what has
	 to stay current rather than ten hand-written lines of the same shape. */
	private static let mergedFlags: [WritableKeyPath<AddressBookEntry, Bool>] = [
		\.ignoreClientToClientProtocol,
		\.ignoreFileTransferRequests,
		\.ignoreGeneralEventMessages,
		\.ignoreInlineMedia,
		\.ignoreNoticeMessages,
		\.ignorePrivateMessageHighlights,
		\.ignorePrivateMessages,
		\.ignorePublicMessageHighlights,
		\.ignorePublicMessages,
		\.trackUserActivity,
	]

	private func mergedEntry(from entries: [AddressBookEntry]) -> AddressBookEntry {
		var mixedEntry = AddressBookEntry(entryType: .mixed)

		mixedEntry.parentEntries = entries

		for flag in Self.mergedFlags {
			mixedEntry[keyPath: flag] = entries.contains { $0[keyPath: flag] }
		}

		return mixedEntry
	}
}
