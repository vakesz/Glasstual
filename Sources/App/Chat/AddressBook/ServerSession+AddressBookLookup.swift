// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

enum AddressBookLookupPolicy {
	/// A nickname as the hostmask a user-tracking rule is written with.
	static func trackingHostmask(forNickname nickname: String) -> String {
		"\(nickname)!*@*"
	}

	/// Both keys a hostmask's match may be cached under: the hostmask itself,
	/// and the tracking mask its nickname alone is looked up by.
	static func cacheKeys(forHostmask hostmask: String) -> [String] {
		[hostmask, trackingHostmask(forNickname: hostmask.nicknameFromHostmask)]
	}

	/** The tracking rule inside a match, or `nil` when the match only ignores.

	 The cache answers with whatever rule the hostmask matched, and an
	 `/ignore spammer` matches `spammer!*@*` exactly as a tracking rule for the
	 same person does. Taking the match unfiltered made WATCH and MONITOR
	 numerics treat an ignore as something to report presence for, and left the
	 nickname on the watch list because the ignore looked like a reason to keep
	 it there. A `.mixed` match is the merge the cache built, so the tracking
	 half is one of its parents — and it is the parent, not the merge, that
	 carries the nickname being tracked. */
	static func userTrackingEntry(in match: AddressBookEntry?) -> AddressBookEntry? {
		guard let match else {
			return nil
		}

		if match.entryType == .userTracking {
			return match.trackUserActivity ? match : nil
		}

		guard match.entryType == .mixed else {
			return nil
		}

		return match.parentEntries?.first { $0.entryType == .userTracking && $0.trackUserActivity }
	}
}

extension ServerSession {
	func isUserMuted(nickname: String) -> Bool {
		let hostmask = findUser(nickname)?.hostmask ?? "\(nickname)!*@*"
		return config.ignoreList.contains {
			$0.muteMessages && $0.checkMatch(hostmask, caseMapping: supportInfo.caseMapping)
		}
	}

	/// A quick mute follows the nickname, including when the sender has left.
	/// It does not discard messages or broaden to other users on the same host.
	func setUserMuted(_ muted: Bool, nickname: String) {
		guard nickname.isHostmaskNickname(on: self), !nicknameIsMyself(nickname), isTerminating == false,
		      isUserMuted(nickname: nickname) != muted else { return }
		var newConfig = config
		if muted {
			let mask = AddressBookEntryMatcher.escapedGlobLiteral(nickname) + "!*@*"
			var entry = AddressBookEntry(hostmask: mask)
			entry.muteMessages = true
			newConfig.ignoreList.append(entry)
		} else {
			let hostmask = findUser(nickname)?.hostmask ?? "\(nickname)!*@*"
			newConfig.ignoreList = newConfig.ignoreList.compactMap { entry in
				guard entry.muteMessages, entry.checkMatch(hostmask, caseMapping: supportInfo.caseMapping) else { return entry }
				var unmuted = entry
				unmuted.muteMessages = false
				return unmuted.ignoresEvents || unmuted.trackUserActivity ? unmuted : nil
			}
		}
		updateConfig(newConfig)
		if let chatSession, chatSession.sessions.contains(where: { $0 === self }) {
			chatSession.save()
		}
	}

	func findIgnores(forHostmask hostmask: String) -> [AddressBookEntry] {
		addressBookMatchCache.findIgnores(forHostmask: hostmask, in: config.ignoreList)
	}

	func findUserTrackingAddressBookEntry(forNickname nickname: String) -> AddressBookEntry? {
		AddressBookLookupPolicy.userTrackingEntry(
			in: findAddressBookEntry(
				forHostmask: AddressBookLookupPolicy.trackingHostmask(forNickname: nickname)
			)
		)
	}

	func findAddressBookEntry(forHostmask hostmask: String) -> AddressBookEntry? {
		addressBookMatchCache.findAddressBookEntry(forHostmask: hostmask, in: config.ignoreList)
	}

	func clearAddressBookCache() {
		addressBookMatchCache.clearCachedMatches()
	}

	func clearAddressBookCache(forHostmask hostmask: String) {
		for cacheKey in AddressBookLookupPolicy.cacheKeys(forHostmask: hostmask) {
			addressBookMatchCache.clearCachedMatches(forHostmask: cacheKey)
		}
	}
}
