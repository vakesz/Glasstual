// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// `PREFIX`: the membership mode symbols the server ranks, highest first, and
/// the prefix character each one is written with.
nonisolated struct ISupportPrefixConfig: Sendable, Equatable {
	let modeSymbols: [String]
	let characters: [String]
}

/// `EXTBAN`: the character an extended ban mask starts with, if any, and the
/// types the server accepts after it.
nonisolated struct ISupportExtendedBanConfig: Sendable, Equatable {
	let prefix: String?
	let types: [String]
}

nonisolated enum ISupportTokenParser {
	/** A token value with its `\xHH` escapes decoded.

	 ISUPPORT values cannot carry a space, a backslash or an `=` as written, so
	 the server sends each as `\x` and two hexadecimal digits naming a byte:
	 `NETWORK=Example\x20Network`. The bytes are UTF-8. An escape that is not
	 followed by two hexadecimal digits is not an escape and is kept as written. */
	static func unescapedValue(_ value: Substring) -> String {
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
	static func channelLimits(from token: String) -> [Character: UInt] {
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
	static func maximumTargets(from token: String) -> [String: UInt] {
		var limits: [String: UInt] = [:]

		for (command, value) in colonSeparatedEntries(in: token) {
			limits[command.uppercased()] = nonNegativeInteger(value)
		}

		return limits
	}

	/// `MAXLIST`, keyed by the list mode each limit applies to. An entry with no
	/// positive limit says nothing and is left out.
	static func maximumListEntries(from token: String) -> [Character: UInt] {
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

	static func extendedBanConfiguration(from token: String) -> ISupportExtendedBanConfig {
		guard let comma = token.firstIndex(of: ",") else {
			return ISupportExtendedBanConfig(prefix: nil, types: characters(in: token))
		}

		let prefix = String(token[..<comma])
		let types = String(token[token.index(after: comma)...])

		return ISupportExtendedBanConfig(
			prefix: prefix.isEmpty ? nil : prefix,
			types: characters(in: types)
		)
	}

	static func userPrefixConfiguration(from token: String) -> ISupportPrefixConfig? {
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

		return ISupportPrefixConfig(
			modeSymbols: modeSymbolCharacters,
			characters: prefixCharacters
		)
	}

	/// The `CHANMODES` groups, merged over what the server has already
	/// advertised. Groups past D have no defined meaning, so their modes are
	/// left out and read back as "takes no parameter".
	static func channelModeKinds(
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
