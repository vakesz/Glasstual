// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// What the connection sheet refuses to save. Onboarding asks some of the same
/// questions, which is why the rules are not on the sheet's model.
enum ServerPropertiesValidation {
	static func isSingleLine(_ value: String) -> Bool {
		value.rangeOfCharacter(from: .newlines) == nil
	}

	/** A real name the server will accept on the USER line: something other
	 than whitespace, on one line. Onboarding and the server properties sheet
	 both ask this, so a name one of them accepts the other does not refuse. */
	static func isRealName(_ value: String) -> Bool {
		value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && isSingleLine(value)
	}

	/// The protocol limits a line in bytes, so a disconnect message is measured
	/// in UTF-8 bytes rather than in characters, which undercount anything
	/// outside ASCII.
	static let maximumCommentLength = 390

	static func isLeavingComment(_ value: String) -> Bool {
		isSingleLine(value) && value.utf8.count <= maximumCommentLength
	}

	/// The first alternative nickname the server would refuse, or `nil` when
	/// every one of them is usable. The message names it, so the check reports
	/// which one rather than only that one of them failed.
	static func invalidAlternateNickname(in value: String) -> String? {
		value.components(separatedBy: .whitespaces)
			.first { $0.isEmpty == false && $0.isHostmaskNickname == false }
	}
}
