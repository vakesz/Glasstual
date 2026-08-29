/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
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

import CocoaExtensions
import Foundation

/// Pure transformations used by `IRCClient` at the wire and presentation
/// seams. Keeping these transformations independent of connection state makes
/// protocol output deterministic and directly testable.
public final nonisolated class ClientWireUtilities: NSObject { // nonisolated: value
	private static let credentialMask = "••••••"

	/// Ceiling on `%<width>n` style padding in the nickname format. The width
	/// comes from a user preference, so it needs a bound rather than trust.
	private static let maximumFormatPaddingWidth = 256
	private static let sensitiveServiceVerbs: Set<String> = [
		"AUTH", "CONFIRM", "GHOST", "GROUP", "IDENTIFY", "LOGIN", "PASSWD", "PASSWORD", "RECOVER",
		"REGAIN", "REGISTER", "RELEASE", "RESETPASS", "SENDPASS", "SET", "SETPASS", "SIDENTIFY",
	]

	public static func compileModeChanges(
		symbol: String,
		isSet: Bool,
		parameters: [String],
		maximumModes: UInt
	) -> [String] {
		precondition((symbol as NSString).length == 1)

		var results: [String] = []
		var modeSymbols = ""
		var modeParameters: [String] = []

		func flush() {
			guard modeSymbols.isEmpty == false, modeParameters.isEmpty == false else {
				return
			}

			results.append("\(modeSymbols) \(modeParameters.joined(separator: " "))")
			modeSymbols = ""
			modeParameters.removeAll(keepingCapacity: true)
		}

		for parameter in parameters where parameter.isEmpty == false {
			if modeSymbols.isEmpty {
				modeSymbols = isSet ? "+\(symbol)" : "-\(symbol)"
			} else {
				modeSymbols += symbol
			}

			modeParameters.append(parameter)

			if maximumModes > 0, UInt(modeParameters.count) == maximumModes {
				flush()
			}
		}

		flush()

		return results
	}

	public static func redactedServiceMessage(_ message: String, sentTo target: String?) -> String {
		guard targetLooksLikeService(target) else {
			return message
		}

		let tokens = message.components(separatedBy: " ")

		guard tokens.count >= 2, sensitiveServiceVerbs.contains(tokens[0].uppercased()) else {
			return message
		}

		var visibleTokenCount = 1

		if tokens[0].caseInsensitiveCompare("SET") == .orderedSame {
			guard tokens.count >= 3, tokens[1].caseInsensitiveCompare("PASSWORD") == .orderedSame else {
				return message
			}

			visibleTokenCount = 2
		}

		return tokens.enumerated().map { index, token in
			guard index >= visibleTokenCount, token.isEmpty == false else {
				return token
			}

			return credentialMask
		}.joined(separator: " ")
	}

	public static func targetLooksLikeService(_ target: String?) -> Bool {
		guard var nickname = target, nickname.isEmpty == false else {
			return false
		}

		if let separator = nickname.firstIndex(of: "@") {
			nickname = String(nickname[..<separator])
		}

		let lowercaseNickname = nickname.lowercased()

		return lowercaseNickname.hasSuffix("serv")
			|| ["authserv", "l", "q", "x"].contains(lowercaseNickname)
	}

	public static func formatNickname(_ nickname: String, modeSymbol: String, format: String) -> String {
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
			let requestedWidth = Int(min(paddingWidth.magnitude, UInt(maximumFormatPaddingWidth)))
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

	/// Truncates `text` to at most `maximumByteCount` UTF-8 bytes without
	/// splitting a character. A `maximumByteCount` of zero means no limit.
	///
	/// ISUPPORT `AWAYLEN`, `KICKLEN` and `TOPICLEN` are byte budgets, so
	/// measuring them in UTF-16 code units under-counts every non-ASCII
	/// string and lets the server do the truncating instead.
	public static func truncated(_ text: String, toByteCount maximumByteCount: Int) -> String {
		guard maximumByteCount > 0, text.utf8.count > maximumByteCount else {
			return text
		}

		var truncated = ""
		var byteCount = 0

		for character in text {
			let characterBytes = String(character).utf8.count

			guard byteCount + characterBytes <= maximumByteCount else {
				break
			}

			byteCount += characterBytes
			truncated.append(character)
		}

		return truncated
	}

	public static func escapedDCCFilename(_ filename: String) -> String {
		var escaped = filename.safeFilename

		guard escaped.contains(" ") else {
			return escaped
		}

		escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")

		return "\"\(escaped)\""
	}

	public static func wireDCCAddress(_ address: String) -> String? {
		if address.isIPv6Address {
			return address
		}

		guard let octets = ipv4Octets(address) else {
			return nil
		}

		var packed: UInt32 = 0

		for octet in octets {
			packed = (packed << 8) | UInt32(octet)
		}

		return String(packed)
	}

	public static func displayDCCAddress(_ address: String) -> String {
		guard address.isEmpty == false,
		      address.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
		      // Anything wider than 32 bits is not a packed IPv4 address, and
		      // saturating it would fabricate one the peer never sent.
		      let packedValue = UInt32(address)
		else {
			return address
		}

		var packed = packedValue
		var octets: [String] = []

		for _ in 0 ..< 4 {
			octets.append(String(packed & 0xFF))
			packed >>= 8
		}

		return octets.reversed().joined(separator: ".")
	}

	/// `true` when a peer supplied address is one the client is willing to
	/// dial. The peer, not the user, chooses this address, so loopback,
	/// link-local, multicast and private ranges are refused.
	public static func isDialableDCCAddress(_ address: String) -> Bool {
		if let octets = ipv4Octets(address) {
			return isDialableIPv4(octets)
		}

		guard address.isIPv6Address else {
			return false
		}

		let normalized = address.lowercased()

		guard normalized != "::1", normalized != "::" else {
			return false
		}

		// fe80::/10 link-local and fc00::/7 unique-local.
		let firstGroup = normalized.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""

		guard firstGroup.hasPrefix("fe8") == false, firstGroup.hasPrefix("fe9") == false,
		      firstGroup.hasPrefix("fea") == false, firstGroup.hasPrefix("feb") == false,
		      firstGroup.hasPrefix("fc") == false, firstGroup.hasPrefix("fd") == false
		else {
			return false
		}

		return true
	}

	private static func isDialableIPv4(_ octets: [UInt8]) -> Bool {
		switch (octets[0], octets[1]) {
		case (0, _), (10, _), (127, _):
			false
		case (169, 254):
			false
		case (172, 16 ... 31):
			false
		case (192, 168):
			false
		case (100, 64 ... 127):
			false
		case (224 ... 255, _):
			false
		default:
			true
		}
	}

	private static func ipv4Octets(_ address: String) -> [UInt8]? {
		let components = address.components(separatedBy: ".")

		guard components.count == 4 else {
			return nil
		}

		var octets: [UInt8] = []

		for component in components {
			guard component.isEmpty == false,
			      component.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
			      let value = UInt8(component)
			else {
				return nil
			}

			octets.append(value)
		}

		return octets
	}

	public static func chatHistoryLatestCommand(target: String, selector: String, limit: UInt) -> String {
		"CHATHISTORY LATEST \(target) \(selector) \(limit)"
	}

	public static func chatHistoryBeforeCommand(target: String, selector: String, limit: UInt) -> String {
		"CHATHISTORY BEFORE \(target) \(selector) \(limit)"
	}

	public static func netsplitNicknameList(_ nicknames: [String], limit: UInt) -> String {
		guard UInt(nicknames.count) > limit else {
			return nicknames.joined(separator: ", ")
		}

		let shown = nicknames.prefix(Int(limit)).joined(separator: ", ")

		return IRCInboundStrings.History.abbreviatedNicknames(
			shown,
			remaining: UInt(nicknames.count - Int(limit))
		)
	}
}
