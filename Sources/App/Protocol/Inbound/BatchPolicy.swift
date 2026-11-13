// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

enum BatchPolicy {
	static let maximumParentDepth = 16

	static func normalizedToken(_ reference: String) -> (token: String, opens: Bool)? {
		guard reference.count > 1, let modifier = reference.first, modifier == "+" || modifier == "-" else {
			return nil
		}
		let token = String(reference.dropFirst())
		let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
		guard token.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
		return (token, modifier == "+")
	}
}
