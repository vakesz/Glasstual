/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

@objc(IRCAddressBookMatchCache)
public final class AddressBookMatchCache: NSObject {
	@objc public private(set) weak var client: IRCClient?

	private let matches = NSCache<NSString, AnyObject>()

	@objc(initWithClient:)
	public init(client: IRCClient) {
		self.client = client
		matches.countLimit = 100

		super.init()
	}

	@objc public func clearCachedMatches() {
		matches.removeAllObjects()
	}

	@objc(clearCachedMatchesForHostmask:)
	public func clearCachedMatches(forHostmask hostmask: String) {
		matches.removeObject(forKey: hostmask as NSString)
	}

	@objc(findIgnoresForHostmask:)
	public func findIgnores(forHostmask hostmask: String) -> [AddressBookEntry] {
		guard let match = findAddressBookEntry(forHostmask: hostmask) else {
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

	@objc(findAddressBookEntryForHostmask:)
	public func findAddressBookEntry(forHostmask hostmask: String) -> AddressBookEntry? {
		let cacheKey = hostmask as NSString

		if let cached = matches.object(forKey: cacheKey) {
			return cached is NSNull ? nil : cached as? AddressBookEntry
		}

		let match = uncachedMatch(forHostmask: hostmask)

		matches.setObject(match ?? NSNull(), forKey: cacheKey)

		return match
	}

	private func uncachedMatch(forHostmask hostmask: String) -> AddressBookEntry? {
		var singleMatch: AddressBookEntry?
		var multipleMatches: [AddressBookEntry]?

		for entry in client?.config.ignoreList ?? [] where entry.checkMatch(hostmask) {
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

	private func mergedEntry(from entries: [AddressBookEntry]) -> AddressBookEntry {
		let mixedEntry = MutableAddressBookEntry()

		mixedEntry.entryType = .mixed
		mixedEntry.parentEntries = entries
		mixedEntry.ignoreClientToClientProtocol = entries.contains { $0.ignoreClientToClientProtocol }
		mixedEntry.ignoreGeneralEventMessages = entries.contains { $0.ignoreGeneralEventMessages }
		mixedEntry.ignoreNoticeMessages = entries.contains { $0.ignoreNoticeMessages }
		mixedEntry.ignorePrivateMessageHighlights = entries.contains { $0.ignorePrivateMessageHighlights }
		mixedEntry.ignorePrivateMessages = entries.contains { $0.ignorePrivateMessages }
		mixedEntry.ignorePublicMessageHighlights = entries.contains { $0.ignorePublicMessageHighlights }
		mixedEntry.ignorePublicMessages = entries.contains { $0.ignorePublicMessages }
		mixedEntry.ignoreFileTransferRequests = entries.contains { $0.ignoreFileTransferRequests }
		mixedEntry.ignoreInlineMedia = entries.contains { $0.ignoreInlineMedia }
		mixedEntry.trackUserActivity = entries.contains { $0.trackUserActivity }

		return mixedEntry.copy() as! AddressBookEntry
	}
}
