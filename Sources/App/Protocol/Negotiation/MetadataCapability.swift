// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What a network says about `draft/metadata-2`.

 The server lists its limits in the capability's value, as in
 `draft/metadata-2=before-connect,max-subs=50`. Unknown tokens are silently
 ignored, as the specification requires, and so is a limit that is not a
 positive number. */
nonisolated struct MetadataCapabilityValues: Sendable, Equatable {
	static let capabilityName = "draft/metadata-2"

	/// `before-connect`: metadata commands work before registration completes.
	var beforeConnect = false
	/// `max-subs`: how many keys one connection may subscribe to.
	var maximumSubscriptions: Int?
	/// `max-keys`: how many keys a target may hold.
	var maximumKeys: Int?
	/// `max-value-bytes`: the longest value the server accepts, in bytes.
	var maximumValueBytes: Int?

	init() {}

	/// - Parameter values: The capability value split at its commas.
	init(capabilityValues values: [String]) {
		for value in values {
			let parts = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
			let number = parts.count == 2 ? Int(parts[1]).flatMap { $0 > 0 ? $0 : nil } : nil

			switch parts[0] {
			case "before-connect": beforeConnect = true
			case "max-subs": maximumSubscriptions = number
			case "max-keys": maximumKeys = number
			case "max-value-bytes": maximumValueBytes = number
			default: continue
			}
		}
	}
}

/** Metadata key names this client reads, and the key grammar.

 The names are the IRCv3 registry's user and channel keys. */
nonisolated enum MetadataKey {
	static let avatar = "avatar"
	static let displayName = "display-name"
	static let color = "color"

	/// The keys a profile is made of, in order of preference.
	static let profileKeys = [displayName, avatar, color]

	/// A valid key is non-empty and holds only `a-z`, `0-9`, `_`, `.`, `/` and `-`.
	static func isValid(_ key: String) -> Bool {
		key.isEmpty == false && key.utf8.allSatisfy { byte in
			switch byte {
			case UInt8(ascii: "a") ... UInt8(ascii: "z"), UInt8(ascii: "0") ... UInt8(ascii: "9"),
			     UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: "/"), UInt8(ascii: "-"):
				true
			default:
				false
			}
		}
	}
}
