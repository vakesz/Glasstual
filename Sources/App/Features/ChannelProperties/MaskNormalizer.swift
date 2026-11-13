// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Turns what the user typed into the mask an access list is asked to hold.

 A pure function of the text: nothing here touches a session, so what a bare
 nickname, a host or an extended ban becomes can be asserted without a server.
 The server remains the authority on whether a mask is acceptable; this only
 rules out what could never reach it as one parameter. */
enum MaskNormalizer {
	/// Why a mask cannot be sent.
	enum Rejection: Error, Equatable, Sendable {
		case empty
		case containsWhitespace
		/// A leading colon would turn the mask into the trailing parameter.
		case startsWithColon
		case tooLong
	}

	/// The longest mask accepted. Servers cap a mask well below a line; this keeps
	/// a pasted paragraph from being sent at all.
	static let maximumLength = 200

	static func normalize(_ input: String) -> Result<String, Rejection> {
		let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
		guard text.isEmpty == false else { return .failure(.empty) }
		guard text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
			return .failure(.containsWhitespace)
		}
		guard text.hasPrefix(":") == false else { return .failure(.startsWithColon) }
		guard text.utf8.count <= maximumLength else { return .failure(.tooLong) }

		return .success(expanded(text))
	}

	/// The `nick!user@host` form of `text`, or `text` itself when it is already a
	/// full mask or an extended ban, whose syntax belongs to the network.
	private static func expanded(_ text: String) -> String {
		if isExtendedBan(text) {
			return text
		}

		let hasBang = text.contains("!")
		let hasAt = text.contains("@")
		switch (hasBang, hasAt) {
		case (true, true):
			return text
		case (false, true):
			return "*!\(text)"
		case (true, false):
			return "\(text)@*"
		case (false, false):
			/* A nickname cannot hold a dot or a colon, so either one makes this a
			 host or an address rather than a nick. */
			if text.contains(".") || text.contains(":") {
				return "*!*@\(text)"
			}
			return "\(text)!*@*"
		}
	}

	/// `$a:account` (Libera, Solanum) and `~a:account` (UnrealIRCd) both lead with
	/// a sigil, and a bare `$a` names an account-less match.
	private static func isExtendedBan(_ text: String) -> Bool {
		guard let first = text.first, first == "$" || first == "~" else { return false }
		return text.count > 1
	}
}
