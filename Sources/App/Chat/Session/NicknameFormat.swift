// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Synchronization

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

	/// One piece of a parsed format.
	private enum Token: Sendable {
		case literal(String)
		/// `width` is signed and already clamped to `maximumPaddingWidth`.
		case substitution(width: Int, kind: Kind)
	}

	private enum Kind: Sendable {
		case modeSymbol
		case nickname
		case percent
	}

	/// The last format parsed. Every row of a transcript asks for the same
	/// format, so one entry is the whole working set.
	private static let parsedCache = Mutex<(format: String, tokens: [Token])?>(nil)

	private static func tokens(for format: String) -> [Token] {
		if let cached = parsedCache.withLock({ $0 }), cached.format == format {
			return cached.tokens
		}
		let tokens = parse(format)
		parsedCache.withLock { $0 = (format, tokens) }
		return tokens
	}

	/// Reads the format the way a `Scanner` with no skipped characters does: a
	/// `%`, an optional signed decimal width, then `@`, `n` or `%`. Anything
	/// else after the width leaves the width consumed and the next character to
	/// read as literal text.
	private static func parse(_ format: String) -> [Token] {
		let bytes = Array(format.utf8)
		var tokens: [Token] = []
		var literalStart = 0
		var index = 0
		let percent = UInt8(ascii: "%")

		func flushLiteral(upTo end: Int) {
			if end > literalStart {
				tokens.append(.literal(String(bytes: bytes[literalStart ..< end], encoding: .utf8) ?? ""))
			}
		}

		while index < bytes.count {
			guard bytes[index] == percent else {
				index += 1
				continue
			}

			flushLiteral(upTo: index)
			index += 1

			var cursor = index
			var negative = false
			if cursor < bytes.count, bytes[cursor] == UInt8(ascii: "-") || bytes[cursor] == UInt8(ascii: "+") {
				negative = bytes[cursor] == UInt8(ascii: "-")
				cursor += 1
			}
			var magnitude = 0
			var digitCount = 0
			while cursor < bytes.count, bytes[cursor] >= UInt8(ascii: "0"), bytes[cursor] <= UInt8(ascii: "9") {
				if magnitude <= maximumPaddingWidth {
					magnitude = magnitude * 10 + Int(bytes[cursor] - UInt8(ascii: "0"))
				}
				digitCount += 1
				cursor += 1
			}

			var width = 0
			if digitCount > 0 {
				index = cursor
				width = min(magnitude, maximumPaddingWidth)
				if negative {
					width = -width
				}
			}

			let kind: Kind? = if index < bytes.count {
				switch bytes[index] {
				case UInt8(ascii: "@"): .modeSymbol
				case UInt8(ascii: "n"): .nickname
				case percent: .percent
				default: nil
				}
			} else {
				nil
			}

			if let kind {
				index += 1
				tokens.append(.substitution(width: width, kind: kind))
			}
			literalStart = index
		}

		flushLiteral(upTo: bytes.count)
		return tokens
	}

	static func apply(_ nickname: String, modeSymbol: String, format: String) -> String {
		var output = ""

		for token in tokens(for: format) {
			switch token {
			case let .literal(text):
				output += text
			case let .substitution(width, kind):
				let substitution = switch kind {
				case .modeSymbol: modeSymbol
				case .nickname: nickname
				case .percent: "%"
				}
				// The width is clamped when the format is parsed, so no sane
				// format asks for more padding than a line can hold.
				let padding = String(
					repeating: " ",
					count: max(0, abs(width) - (substitution as NSString).length)
				)
				if width < 0 {
					output += padding
				}
				output += substitution
				if width > 0 {
					output += padding
				}
			}
		}

		return output
	}
}

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
