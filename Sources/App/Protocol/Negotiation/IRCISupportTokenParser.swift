/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_
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

@objc(IRCISupportPrefixConfiguration)
public final nonisolated class ISupportPrefixConfiguration: NSObject { // nonisolated: value
	@objc public let modeSymbols: [String]
	@objc public let characters: [String]

	init(modeSymbols: [String], characters: [String]) {
		self.modeSymbols = modeSymbols
		self.characters = characters
		super.init()
	}
}

@objc(IRCISupportExtendedBanConfiguration)
public final nonisolated class ISupportExtendedBanConfiguration: NSObject { // nonisolated: value
	@objc public let prefix: String?
	@objc public let types: [String]

	init(prefix: String?, types: [String]) {
		self.prefix = prefix
		self.types = types
		super.init()
	}
}

@objc(IRCISupportTokenParser)
public final nonisolated class ISupportTokenParser: NSObject { // nonisolated: value
	@available(*, unavailable)
	override public init() {
		fatalError("ISupportTokenParser is a static namespace")
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

	@objc(extendedBanConfigurationFromToken:)
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

	@objc(userPrefixConfigurationFromToken:)
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

	@objc(isClientTag:deniedByEntries:)
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

	@objc(chunkTargets:limit:)
	public static func chunkTargets(_ targets: [String], limit: UInt) -> [[String]] {
		let chunkSize = max(Int(limit), 1)
		var chunks: [[String]] = []
		var start = 0

		while start < targets.count {
			let end = min(start + chunkSize, targets.count)
			chunks.append(Array(targets[start ..< end]))
			start = end
		}

		return chunks
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
