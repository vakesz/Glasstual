// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** A single mode change: the symbol, whether it is being set or unset, and the
 optional parameter that came with it. The symbol identifies the mode, so it is
 fixed for the lifetime of a value; the other two fields vary. */
nonisolated struct ModeInfo: Hashable, Sendable {
	let modeSymbol: String
	var modeIsSet: Bool
	var modeParameter: String?

	init(modeSymbol: String, modeIsSet: Bool = false, modeParameter: String? = nil) {
		precondition(modeSymbol.count == 1, "A mode symbol must contain exactly one character")

		self.modeSymbol = modeSymbol
		self.modeIsSet = modeIsSet
		self.modeParameter = modeParameter
	}

	@MainActor
	func isModeForChangingMemberMode(on client: Client) -> Bool {
		guard modeParameter?.isEmpty == false else {
			return false
		}

		return client.supportInfo.modeSymbolIsUserPrefix(modeSymbol)
	}
}
