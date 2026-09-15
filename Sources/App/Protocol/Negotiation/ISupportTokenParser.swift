/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation

/// `PREFIX`: the membership mode symbols the server ranks, highest first, and
/// the prefix character each one is written with.
public nonisolated struct ISupportPrefixConfiguration: Sendable, Equatable { // nonisolated: value
	public let modeSymbols: [String]
	public let characters: [String]
}

/// `EXTBAN`: the character an extended ban mask starts with, if any, and the
/// types the server accepts after it.
public nonisolated struct ISupportExtendedBanConfiguration: Sendable, Equatable { // nonisolated: value
	public let prefix: String?
	public let types: [String]
}

public nonisolated enum ISupportTokenParser { // nonisolated: value
	/** A token value with its `\xHH` escapes decoded.

	 ISUPPORT values cannot carry a space, a backslash or an `=` as written, so
	 the server sends each as `\x` and two hexadecimal digits naming a byte:
	 `NETWORK=Example\x20Network`. The bytes are UTF-8. An escape that is not
	 followed by two hexadecimal digits is not an escape and is kept as written. */
	public static func unescapedValue(_ value: Substring) -> String {
		guard value.contains("\\") else {
			return String(value)
		}

		let input = Array(value.utf8)
		var output: [UInt8] = []
		output.reserveCapacity(input.count)
		var index = 0

		while index < input.count {
			if input[index] == UInt8(ascii: "\\"), index + 3 < input.count,
			   input[index + 1] == UInt8(ascii: "x"),
			   let high = hexadecimalDigit(input[index + 2]),
			   let low = hexadecimalDigit(input[index + 3])
			{
				output.append(high << 4 | low)
				index += 4
			} else {
				output.append(input[index])
				index += 1
			}
		}

		// Escaped bytes that do not make UTF-8 were never text; keep them as sent.
		return String(bytes: output, encoding: .utf8) ?? String(value)
	}

	private static func hexadecimalDigit(_ byte: UInt8) -> UInt8? {
		switch byte {
		case UInt8(ascii: "0") ... UInt8(ascii: "9"): byte - UInt8(ascii: "0")
		case UInt8(ascii: "a") ... UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
		case UInt8(ascii: "A") ... UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
		default: nil
		}
	}

	/// `CHANLIMIT`, keyed by the channel prefix each limit applies to.
	public static func channelLimits(from token: String) -> [Character: UInt] {
		var limits: [Character: UInt] = [:]

		for (keys, value) in colonSeparatedEntries(in: token) {
			let limit = nonNegativeInteger(value)

			for prefix in keys {
				limits[prefix] = limit
			}
		}

		return limits
	}

	/// `TARGMAX`, keyed by the uppercased command name.
	public static func maximumTargets(from token: String) -> [String: UInt] {
		var limits: [String: UInt] = [:]

		for (command, value) in colonSeparatedEntries(in: token) {
			limits[command.uppercased()] = nonNegativeInteger(value)
		}

		return limits
	}

	/// `MAXLIST`, keyed by the list mode each limit applies to. An entry with no
	/// positive limit says nothing and is left out.
	public static func maximumListEntries(from token: String) -> [Character: UInt] {
		var limits: [Character: UInt] = [:]

		for (modeSymbols, value) in colonSeparatedEntries(in: token) {
			let limit = nonNegativeInteger(value)

			guard limit > 0 else {
				continue
			}

			for modeSymbol in modeSymbols {
				limits[modeSymbol] = limit
			}
		}

		return limits
	}

	/// A token's value as a count. A server that sends something that is not a
	/// number is saying nothing, which is zero.
	private static func nonNegativeInteger(_ value: String) -> UInt {
		UInt(value) ?? 0
	}

	public static func extendedBanConfiguration(from token: String) -> ISupportExtendedBanConfiguration {
		guard let comma = token.firstIndex(of: ",") else {
			return ISupportExtendedBanConfiguration(prefix: nil, types: characters(in: token))
		}

		let prefix = String(token[..<comma])
		let types = String(token[token.index(after: comma)...])

		return ISupportExtendedBanConfiguration(
			prefix: prefix.isEmpty ? nil : prefix,
			types: characters(in: types)
		)
	}

	public static func userPrefixConfiguration(from token: String) -> ISupportPrefixConfiguration? {
		let token = token as NSString
		let openingParenthesis = token.range(of: "(").location
		let closingParenthesis = token.range(of: ")").location

		guard openingParenthesis == 0, closingParenthesis != NSNotFound, closingParenthesis > 1 else {
			return nil
		}

		let modeSymbols = token.substring(with: NSRange(location: 1, length: closingParenthesis - 1))
		let prefixStart = closingParenthesis + 1
		let prefixes = token.substring(from: prefixStart)

		// Compare the arrays that are actually indexed later, not the UTF-16
		// lengths of the strings they came from: `characters(in:)` maps
		// grapheme clusters, so "(ab)👍" has matching UTF-16 lengths but
		// produces two mode symbols and one prefix.
		let modeSymbolCharacters = characters(in: modeSymbols)
		let prefixCharacters = characters(in: prefixes)

		guard modeSymbolCharacters.count == prefixCharacters.count else {
			return nil
		}

		return ISupportPrefixConfiguration(
			modeSymbols: modeSymbolCharacters,
			characters: prefixCharacters
		)
	}

	/// The `CHANMODES` groups, merged over what the server has already
	/// advertised. Groups past D have no defined meaning, so their modes are
	/// left out and read back as "takes no parameter".
	public static func channelModeKinds(
		from token: String,
		merging existingModes: [Character: ChannelModeKind]
	) -> [Character: ChannelModeKind] {
		var channelModes = existingModes

		for (index, modeClass) in token.split(separator: ",", omittingEmptySubsequences: false).enumerated() {
			guard let kind = ChannelModeKind(chanModesGroupIndex: index) else {
				continue
			}

			for modeSymbol in modeClass {
				channelModes[modeSymbol] = kind
			}
		}

		return channelModes
	}

	public static func casefold(_ string: String, caseMapping: IRCISupportInfoCaseMapping) -> String {
		guard string.isEmpty == false else {
			return string
		}

		guard caseMapping != .rfc7613 else {
			/* RFC 7613 §3.3 (UsernameCaseMapped): lowercase the whole string
			 under Unicode's rules, then normalise to NFC, so two spellings of
			 the same name compare equal. None of the RFC 1459 punctuation
			 equivalences apply — "[Alice]" and "{alice}" are different people. */
			return string.lowercased().precomposedStringWithCanonicalMapping
		}

		let scalars = string.unicodeScalars.map { scalar -> UnicodeScalar in
			let value = scalar.value

			if value >= 65, value <= 90, let lowercase = UnicodeScalar(value + 32) {
				return lowercase
			}

			guard caseMapping != .ascii else {
				return scalar
			}

			switch scalar {
			case "[": return "{"
			case "]": return "}"
			case "\\": return "|"
			case "~" where caseMapping == .rfc1459: return "^"
			default: return scalar
			}
		}

		return String(String.UnicodeScalarView(scalars))
	}

	public static func isClientTag(_ tagName: String, deniedBy entries: [String]) -> Bool {
		var denied = false

		for entry in entries {
			if entry == "*" {
				denied = true
			} else if entry.hasPrefix("-") {
				if entry.dropFirst().caseInsensitiveCompare(tagName) == .orderedSame {
					return false
				}
			} else if entry.caseInsensitiveCompare(tagName) == .orderedSame {
				denied = true
			}
		}

		return denied
	}

	/// Splits `targets` into lists of at most `limit` entries, in order.
	///
	/// Zero is a server that advertised no limit, and it chunks the same way as
	/// one: a target list the server never said it accepts is not sent.
	public static func chunkTargets(_ targets: [String], limit: UInt) -> [[String]] {
		WireBatching.pack(targets, maximumCount: max(Int(min(limit, UInt(targets.count))), 1))
	}

	private static func colonSeparatedEntries(in token: String) -> [(String, String)] {
		token.split(separator: ",", omittingEmptySubsequences: false).compactMap { entry in
			guard let colon = entry.firstIndex(of: ":"), colon != entry.startIndex else {
				return nil
			}

			return (
				String(entry[..<colon]),
				String(entry[entry.index(after: colon)...])
			)
		}
	}

	private static func characters(in string: String) -> [String] {
		string.map(String.init)
	}
}
