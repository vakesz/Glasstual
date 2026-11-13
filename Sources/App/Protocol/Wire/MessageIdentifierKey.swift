// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/// IRC message IDs are opaque UTF-8: Unicode-equivalent spellings can name
/// different messages. Keep the original String at wire and archive adapters.
nonisolated struct MessageIdentifierKey: Hashable, Sendable, ExpressibleByStringLiteral {
	let rawValue: String

	init(_ value: String) {
		rawValue = value
	}

	init(stringLiteral value: String) {
		rawValue = value
	}

	static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.rawValue.utf8.elementsEqual(rhs.rawValue.utf8)
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(rawValue.utf8.count)
		for byte in rawValue.utf8 {
			hasher.combine(byte)
		}
	}

	static func equal(_ lhs: String?, _ rhs: String?) -> Bool {
		lhs.map { Self($0) } == rhs.map { Self($0) }
	}
}
