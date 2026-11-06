// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

/** Whether the person behind a nickname is the one an address book entry names. */
nonisolated enum FileTransferPeerTrust {
	/** The sender is trusted when the server reports a services account for
	 them that is the tracked name, or when the entry pins a `user@host` that
	 the sender's real hostmask matches.

	 An entry written as a bare nickname pins no host, so for it only the
	 account can vouch. A wildcard `user@host` pins nothing either. */
	static func isTrusted(
		senderHostmask: String?,
		senderAccount: String?,
		trackedNickname: String,
		entryHostmask: String,
		caseMapping: ISupportCaseMapping
	) -> Bool {
		if let senderAccount, senderAccount.isEmpty == false, senderAccount != "*",
		   HostmaskGlob.casefold(senderAccount, caseMapping: caseMapping)
		   == HostmaskGlob.casefold(trackedNickname, caseMapping: caseMapping)
		{
			return true
		}

		guard let senderHostmask, hasPinnedUserAndHost(entryHostmask) else {
			return false
		}

		return AddressBookEntryMatcher(entryType: .ignore, hostmask: entryHostmask, caseMapping: caseMapping)
			.matches(hostmask: senderHostmask)
	}

	/// Whether a hostmask names a `user@host`: a bare nickname or a pair of
	/// wildcards names nobody in particular.
	private static func hasPinnedUserAndHost(_ hostmask: String) -> Bool {
		guard let separator = hostmask.firstIndex(of: "!") else {
			return false
		}

		let fragment = hostmask[hostmask.index(after: separator)...]

		return fragment.isEmpty == false && fragment.allSatisfy { $0 == "*" || $0 == "@" } == false
	}
}
