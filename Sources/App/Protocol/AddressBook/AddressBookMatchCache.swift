/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation

/// Remembers which address book entry a hostmask matched.
///
/// The entries are passed in at every lookup rather than held: the cache
/// answers for whatever list the client holds now, and the client clears it
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
