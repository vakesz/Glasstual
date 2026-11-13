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
	 account can vouch. A host with a wildcard in it pins nothing either. */
	static func isTrusted(
		senderHostmask: String?,
		senderAccount: String?,
		trackedNickname: String,
		entryHostmask: String,
		caseMapping: ISupportCaseMapping
	) -> Bool {
		if let senderAccount, senderAccount.isEmpty == false, senderAccount != "*",
		   IRCCaseFolding.fold(senderAccount, using: caseMapping)
		   == IRCCaseFolding.fold(trackedNickname, using: caseMapping)
		{
			return true
		}

		guard let senderHostmask, hasLiteralHost(entryHostmask) else {
			return false
		}

		return AddressBookEntryMatcher(entryType: .ignore, hostmask: entryHostmask, caseMapping: caseMapping)
			.matches(hostmask: senderHostmask)
	}

	/** Whether a hostmask pins the host: it names a `nick!user@host` whose host
	 is written out. `*` and `?` in the host leave it open to anyone the pattern
	 reaches, and an escaped `\*` is an ordinary character. The user part may
	 be a wildcard; the host is what the sender does not choose. */
	private static func hasLiteralHost(_ hostmask: String) -> Bool {
		let tokens = HostmaskGlob.compile(hostmask)

		guard let bang = tokens.firstIndex(of: .literal("!")),
		      let at = tokens[bang...].lastIndex(of: .literal("@"))
		else {
			return false
		}

		let host = tokens[tokens.index(after: at)...]

		return host.isEmpty == false && host.allSatisfy {
			if case .literal = $0 {
				true
			} else {
				false
			}
		}
	}
}
