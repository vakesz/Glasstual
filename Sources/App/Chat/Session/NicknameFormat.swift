// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** A nickname written the way the theme's nickname format asks for.

 `%n` is the name, `%@` the sender's mode symbol in the conversation and `%%` a
 literal per cent; a number before any of them pads to that width, negative on
 the left. The format is the user's, so the padding width is clamped rather
 than trusted. */
nonisolated enum NicknameFormat {
	/** How a nickname reads before any theme says otherwise: the sender's mode
	 symbol, the name, a colon.

	 The one declaration of it. The transcript theme's own default is this value,
	 so a session with no theme installed and a theme that never edited the format
	 spell a nickname the same way. */
	static let `default` = "%@%n:"

	/// Ceiling on `%<width>n` style padding. The width comes from a user
	/// setting, so it needs a bound rather than trust.
	private static let maximumPaddingWidth = 256

	static func apply(_ nickname: String, modeSymbol: String, format: String) -> String {
		let scanner = Scanner(string: format)
		scanner.charactersToBeSkipped = nil

		var output = ""

		while scanner.isAtEnd == false {
			if let literal = scanner.scanUpToString("%") {
				output += literal
			}

			guard scanner.scanString("%") != nil else {
				break
			}

			let paddingWidth = scanner.scanInt() ?? 0
			let substitution: String? = if scanner.scanString("@") != nil {
				modeSymbol
			} else if scanner.scanString("n") != nil {
				nickname
			} else if scanner.scanString("%") != nil {
				"%"
			} else {
				nil
			}

			guard let substitution else {
				continue
			}

			let substitutionLength = (substitution as NSString).length
			// `abs(Int.min)` traps, and no sane format asks for more padding
			// than a line can hold, so the magnitude is clamped instead.
			let requestedWidth = Int(min(paddingWidth.magnitude, UInt(maximumPaddingWidth)))
			let padding = String(repeating: " ", count: max(0, requestedWidth - substitutionLength))

			if paddingWidth < 0 {
				output += padding
			}

			output += substitution

			if paddingWidth > 0 {
				output += padding
			}
		}

		return output
	}
}

@MainActor
extension ServerSession {
	/// The nickname as this connection's theme and the sender's rank in
	/// `conversation` spell it.
	func formatNickname(_ nickname: String, in conversation: Conversation?, withFormat format: String? = nil) -> String {
		let requestedFormat = format?.isEmpty == false ? format : nil
		let resolvedFormat = requestedFormat ?? environment.services.themeNicknameFormat()
		let finalFormat = resolvedFormat.isEmpty ? NicknameFormat.default : resolvedFormat
		let modeSymbol: String = if conversation?.isChannel == true, let member = conversation?.findMember(nickname) {
			member.mark
		} else {
			""
		}
		return NicknameFormat.apply(nickname, modeSymbol: modeSymbol, format: finalFormat)
	}
}
