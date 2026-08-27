/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
@objc(IRCClientWireUtilities)
public final class ClientWireUtilities: NSObject {
	private static let credentialMask = "••••••"
	private static let sensitiveServiceVerbs: Set<String> = [
		"AUTH", "CONFIRM", "GHOST", "GROUP", "IDENTIFY", "LOGIN", "PASSWD", "PASSWORD", "RECOVER",
		"REGAIN", "REGISTER", "RELEASE", "RESETPASS", "SENDPASS", "SET", "SETPASS", "SIDENTIFY",
	]

	@objc(compileModeChangesWithSymbol:isSet:parameters:maximumModes:)
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

	@objc(redactedServiceMessage:sentTo:)
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

	@objc(targetLooksLikeService:)
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

	@objc(formatNickname:modeSymbol:format:)
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
			let requestedWidth = abs(paddingWidth)
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

	@objc(escapedDCCFilename:)
	public static func escapedDCCFilename(_ filename: String) -> String {
		var escaped = (filename as NSString).ceSafeFilename as String

		guard escaped.contains(" ") else {
			return escaped
		}

		escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")

		return "\"\(escaped)\""
	}

	@objc(wireDCCAddress:)
	public static func wireDCCAddress(_ address: String) -> String? {
		if address.isIPv6Address {
			return address
		}

		let octets = address.components(separatedBy: ".")

		guard octets.count == 4 else {
			return nil
		}

		var packed: UInt64 = 0

		for (index, octet) in octets.enumerated() {
			let value = (octet as NSString).integerValue
			packed |= UInt64(bitPattern: Int64(value))
			if index < octets.count - 1 {
				packed &<<= 8
			}
		}

		return String(packed)
	}

	@objc(displayDCCAddress:)
	public static func displayDCCAddress(_ address: String) -> String {
		guard address.isEmpty == false,
		      address.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 })
		else {
			return address
		}

		var packed = UInt64(address) ?? UInt64.max
		var octets: [String] = []

		for _ in 0 ..< 4 {
			octets.append(String(packed & 0xFF))
			packed >>= 8
		}

		return octets.reversed().joined(separator: ".")
	}

	@objc(chatHistoryLatestCommandForTarget:selector:limit:)
	public static func chatHistoryLatestCommand(target: String, selector: String, limit: UInt) -> String {
		"CHATHISTORY LATEST \(target) \(selector) \(limit)"
	}

	@objc(chatHistoryBeforeCommandForTarget:selector:limit:)
	public static func chatHistoryBeforeCommand(target: String, selector: String, limit: UInt) -> String {
		"CHATHISTORY BEFORE \(target) \(selector) \(limit)"
	}

	@objc(netsplitNicknameList:limit:)
	public static func netsplitNicknameList(_ nicknames: NSOrderedSet, limit: UInt) -> String {
		let allNicknames = nicknames.array.compactMap { $0 as? String }

		guard UInt(allNicknames.count) > limit else {
			return allNicknames.joined(separator: ", ")
		}

		let shown = allNicknames.prefix(Int(limit)).joined(separator: ", ")

		return IRCInboundStrings.History.abbreviatedNicknames(
			shown,
			remaining: UInt(allNicknames.count - Int(limit))
		)
	}
}
