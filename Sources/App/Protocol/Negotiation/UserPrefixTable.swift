// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The ISUPPORT values a channel member needs in order to rank and mark itself.
 Members are ranked, compared and rendered off the main actor, so the session
 republishes these as a value rather than exposing the live table. */
nonisolated struct UserPrefixTable: Sendable {
	/// The rank the server's highest prefix mode is given; each mode below it
	/// ranks one lower, and a member with no prefix ranks zero.
	static let highestRank: UInt = 100

	/// Mode symbols in the order the server ranked them, highest first.
	var modeSymbols = ["o", "v"]
	/// The prefix character for the mode symbol at the same index.
	var prefixCharacters = ["@", "+"]
	var caseMapping = ISupportCaseMapping.rfc1459

	func userPrefix(forModeSymbol modeSymbol: String) -> String? {
		guard let index = modeSymbols.firstIndex(of: modeSymbol),
		      index < prefixCharacters.count
		else {
			return nil
		}

		return prefixCharacters[index]
	}

	func rank(forModeSymbol modeSymbol: String) -> UInt {
		guard let index = modeSymbols.firstIndex(of: modeSymbol) else {
			return 0
		}

		// A server may advertise more prefix modes than the rank ceiling; the
		// lowest-ranked ones all collapse to rank 1 rather than underflowing.
		guard UInt(index) < Self.highestRank else {
			return 1
		}

		return Self.highestRank - UInt(index)
	}

	func casefold(_ string: String) -> String {
		IRCCaseFolding.fold(string, using: caseMapping)
	}
}
