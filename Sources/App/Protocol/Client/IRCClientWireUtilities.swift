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
import Darwin
import Foundation

/// Pure transformations used by `IRCClient` at the wire and presentation
/// seams. Keeping these transformations independent of connection state makes
/// protocol output deterministic and directly testable.
public nonisolated enum ClientWireUtilities { // nonisolated: value
	private static let credentialMask = "••••••"

	/// Ceiling on `%<width>n` style padding in the nickname format. The width
	/// comes from a user preference, so it needs a bound rather than trust.
	private static let maximumFormatPaddingWidth = 256
	/** The mechanism names an `AUTHENTICATE` may carry instead of a payload.

	 The first `AUTHENTICATE` of an exchange names the mechanism the client is
	 about to try, and that is the one parameter of the exchange that is not a
	 secret — masking it left a traffic log unable to say which mechanism the
	 login failed under, which is the first thing anyone reading one wants. Only
	 the names this client can send are spared; anything else is a payload. */
	private static let saslMechanismNames: Set<String> = [
		"EXTERNAL", "PLAIN", SCRAMClient.mechanismName,
	]
	private static let sensitiveServiceVerbs: Set<String> = [
		"AUTH", "CONFIRM", "GHOST", "GROUP", "IDENTIFY", "LOGIN", "PASSWD", "PASSWORD", "RECOVER",
		"REGAIN", "REGISTER", "RELEASE", "RESETPASS", "SENDPASS", "SET", "SETPASS", "SIDENTIFY",
	]

	/// The `MODE` commands that set or clear one mode over a list of parameters,
	/// or none when there is no single mode letter to change. The symbol can be
	/// one a server advertised and then withdrew, which is not a mode to send.
	///
	/// Structured rather than space-joined text: a mask or a key is a parameter
	/// of its own on the wire, and the caller that sends these has no business
	/// re-splitting a string this function had just assembled.
	public static func compileModeChanges(
		symbol: String,
		isSet: Bool,
		parameters: [String],
		maximumModes: UInt
	) -> [ModeChangeGroup] {
		guard (symbol as NSString).length == 1 else {
			return []
		}

		var results: [ModeChangeGroup] = []
		var modeSymbols = ""
		var modeParameters: [String] = []

		func flush() {
			guard modeSymbols.isEmpty == false, modeParameters.isEmpty == false else {
				return
			}

			results.append(ModeChangeGroup(symbols: modeSymbols, parameters: modeParameters))
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

	/** The outgoing line as the raw traffic log may show it.

	 The traffic window is a user-visible transcript that ends up pasted into
	 bug reports, so every parameter that carries a credential is masked while
	 the command and its routing parameters stay legible. Only the lines that
	 name a secret are rewritten; everything else is returned untouched. */
	public static func redactedRawLogLine(_ line: String) -> String {
		let body = line.trimmingCharacters(in: .whitespacesAndNewlines)
		let (prefix, remainder) = splitWirePrefix(Substring(body))
		var (parameters, hasTrailing) = wireParameters(remainder)

		guard let command = parameters.first?.uppercased() else {
			return line
		}

		switch command {
		case "PASS":
			guard parameters.count >= 2 else { return line }
			// A bouncer password can be several parameters wide, so none survive.
			parameters = [parameters[0], credentialMask]
			hasTrailing = false
		case "AUTHENTICATE":
			// "+" is the empty response and "*" aborts: neither is a secret,
			// and neither is the mechanism name that opens the exchange.
			guard parameters.count >= 2,
			      parameters[1] != "+",
			      parameters[1] != "*",
			      saslMechanismNames.contains(parameters[1].uppercased()) == false
			else { return line }
			parameters[1] = credentialMask
		case "OPER":
			guard parameters.count >= 3 else { return line }
			parameters[2] = credentialMask
		case "NICKSERV", "NS":
			guard parameters.count >= 2 else { return line }
			let message = parameters.dropFirst().joined(separator: " ")
			let redacted = redactedServiceMessage(message, sentTo: "NickServ")
			guard redacted != message else { return line }
			/* The verb and its secret arrive either as separate parameters or as
			 one trailing parameter, and the redaction answers with the same
			 tokens in the same order. Putting them back into the parameters they
			 came from is what keeps the logged line the shape that went out: the
			 flat split dropped the `:` from `NICKSERV :IDENTIFY hunter2`, so the
			 log no longer matched the wire it was a log of. */
			parameters = [parameters[0]] + regrouped(redacted, like: Array(parameters.dropFirst()))
		case "PRIVMSG", "SQUERY":
			guard parameters.count >= 3 else { return line }
			let redacted = redactedServiceMessage(parameters[2], sentTo: parameters[1])
			guard redacted != parameters[2] else { return line }
			parameters[2] = redacted
		default:
			return line
		}

		let lastIndex = parameters.count - 1

		return prefix + parameters.enumerated().map { index, value in
			index == lastIndex && hasTrailing ? ":\(value)" : value
		}.joined(separator: " ")
	}

	/** `redacted` cut back into parameters as wide as the ones it came from.

	 The redaction works on the parameters joined into one string, and each
	 parameter may itself be several tokens wide — a trailing parameter is the
	 rest of the line. Token counts are preserved by the redaction, so the widths
	 are enough to put the pieces back; a mismatch means something replaced more
	 than it masked, and the tokens go back one per parameter with the remainder
	 on the last. */
	private static func regrouped(_ redacted: String, like original: [String]) -> [String] {
		var tokens = redacted.components(separatedBy: " ")
		var result: [String] = []

		for parameter in original {
			let width = max(parameter.components(separatedBy: " ").count, 1)

			guard tokens.count >= width, result.count < original.count - 1 else {
				break
			}

			result.append(tokens.prefix(width).joined(separator: " "))
			tokens.removeFirst(width)
		}

		result.append(tokens.joined(separator: " "))

		return result
	}

	/// The message tags and source prefix, which name no secret and are kept
	/// whole, split from the command and its parameters.
	private static func splitWirePrefix(_ line: Substring) -> (prefix: String, remainder: Substring) {
		var prefix = ""
		var remainder = line

		while let marker = remainder.first, marker == "@" || marker == ":" {
			guard let space = remainder.firstIndex(of: " ") else {
				return (prefix, remainder)
			}

			let boundary = remainder.index(after: space)
			prefix += remainder[..<boundary]
			remainder = remainder[boundary...]
		}

		return (prefix, remainder)
	}

	/// The command and its parameters, with the trailing parameter's `:`
	/// removed and reported separately so it can be put back.
	private static func wireParameters(_ body: Substring) -> (parameters: [String], hasTrailing: Bool) {
		var parameters: [String] = []
		var remainder = body

		while remainder.isEmpty == false {
			if remainder.first == ":" {
				parameters.append(String(remainder.dropFirst()))

				return (parameters, true)
			}

			guard let space = remainder.firstIndex(of: " ") else {
				parameters.append(String(remainder))

				break
			}

			parameters.append(String(remainder[..<space]))
			remainder = remainder[remainder.index(after: space)...]

			while remainder.first == " " {
				remainder = remainder.dropFirst()
			}
		}

		return (parameters, false)
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
	///
	/// Both families are parsed into their address bytes and classified from
	/// them. Matching text prefixes let an IPv6 spelling of a refused IPv4
	/// address through — `::ffff:127.0.0.1` and `64:ff9b::7f00:1` both dial
	/// loopback, and `0:0:0:0:0:0:0:1` is `::1` written out in full.
	public static func isDialableDCCAddress(_ address: String) -> Bool {
		if let octets = ipv4Bytes(address) {
			return isDialableIPv4(octets)
		}

		guard let bytes = ipv6Bytes(address) else {
			return false
		}

		return isDialableIPv6(bytes)
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
		// 192.0.0.0/24 IETF protocol assignments and 192.0.2.0/24 TEST-NET-1.
		case (192, 0):
			octets[2] != 0 && octets[2] != 2
		// 198.18.0.0/15 benchmarking, and 198.51.100.0/24 TEST-NET-2.
		case (198, 18), (198, 19):
			false
		case (198, 51):
			octets[2] != 100
		// 203.0.113.0/24 TEST-NET-3.
		case (203, 0):
			octets[2] != 113
		case (224 ... 255, _):
			false
		default:
			true
		}
	}

	/// The IPv6 well-known NAT64 prefix, `64:ff9b::/96`. An address under it
	/// reaches the IPv4 address in its low 32 bits, so that is what decides.
	private static let nat64WellKnownPrefix: [UInt8] = [
		0x00, 0x64, 0xFF, 0x9B, 0, 0, 0, 0, 0, 0, 0, 0,
	]

	private static func isDialableIPv6(_ bytes: [UInt8]) -> Bool {
		// Unspecified (::) and loopback (::1), however they were spelled.
		if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes[15] <= 1 {
			return false
		}

		// ::ffff:0:0/96 mapped, ::/96 compatible, and 64:ff9b::/96 NAT64 all
		// carry an IPv4 address in their low 32 bits.
		let highBytes = Array(bytes.prefix(12))
		let isMapped = highBytes.prefix(10).allSatisfy { $0 == 0 } && highBytes[10] == 0xFF && highBytes[11] == 0xFF
		let isCompatible = highBytes.allSatisfy { $0 == 0 }

		if isMapped || isCompatible || highBytes == nat64WellKnownPrefix {
			return isDialableIPv4(Array(bytes.suffix(4)))
		}

		// fe80::/10 link-local, fc00::/7 unique-local, ff00::/8 multicast.
		if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 {
			return false
		}

		if bytes[0] & 0xFE == 0xFC || bytes[0] == 0xFF {
			return false
		}

		// 100::/64, the RFC 6666 discard-only prefix.
		if bytes[0] == 0x01, bytes[1] == 0x00, bytes.dropFirst(2).prefix(6).allSatisfy({ $0 == 0 }) {
			return false
		}

		return true
	}

	private static func ipv4Bytes(_ address: String) -> [UInt8]? {
		/* `inet_pton` reads a leading zero as decimal padding, and a resolver
		 that reads it as octal reaches a different host: `0177.0.0.1` is either
		 177.0.0.1 or loopback depending on who parses it. An offer written that
		 way is not one to resolve either way. */
		guard address.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({
			$0.count == 1 || $0.hasPrefix("0") == false
		}) else {
			return nil
		}

		return addressBytes(address, family: AF_INET, byteCount: 4)
	}

	private static func ipv6Bytes(_ address: String) -> [UInt8]? {
		addressBytes(address, family: AF_INET6, byteCount: 16)
	}

	// The address bytes `inet_pton` reads out of `address`, or `nil` when the
	// text is not an address of that family. `inet_pton` refuses a zone suffix
	// and any of the loose forms `inet_aton` accepts, which is what makes the
	// byte classification above exhaustive.
	/** `address` as the bytes it names, whichever family it is written in, or
	 `nil` when it is not a literal address at all.

	 Two spellings of one address are one address: `2001:0db8::1` and
	 `2001:db8::1` differ only in how they are written, and comparing the text
	 made a peer dialling from the address an offer named look like a stranger.
	 The bytes are what the comparison has to be made on. */
	public static func addressBytes(of address: String) -> [UInt8]? {
		ipv4Bytes(address) ?? ipv6Bytes(address)
	}

	private static func addressBytes(_ address: String, family: Int32, byteCount: Int) -> [UInt8]? {
		var bytes = [UInt8](repeating: 0, count: byteCount)
		var parsed: Int32 = 0

		bytes.withUnsafeMutableBytes { buffer in
			parsed = inet_pton(family, address, buffer.baseAddress)
		}

		return parsed == 1 ? bytes : nil
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

	/// The one command name every chat-history request goes out under.
	public static let chatHistoryCommand = "CHATHISTORY"

	/** The arguments of a `CHATHISTORY` request, as arguments rather than a
	 line.

	 The caller hands them to the outbound transport, which is what builds the
	 wire line and attaches the message tags a labelled request needs; a line
	 assembled here would have to have its `@label=` interpolated on top. */
	public static func chatHistoryArguments(
		subcommand: String,
		target: String,
		selector: String,
		limit: UInt
	) -> [String] {
		[subcommand, target, selector, String(limit)]
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
