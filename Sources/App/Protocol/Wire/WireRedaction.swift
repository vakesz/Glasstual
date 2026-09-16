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

import Foundation

/** Masking the credentials an outgoing line carries.

 The raw traffic window is a user-visible transcript that ends up pasted into
 bug reports, so every parameter that carries a credential is masked while the
 command and its routing parameters stay legible. Only the lines that name a
 secret are rewritten; everything else is returned untouched.
 */
nonisolated enum WireRedaction { // nonisolated: value
	private static let credentialMask = "••••••"

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

	/// The outgoing line as the raw traffic log may show it.
	static func redactedRawLogLine(_ line: String) -> String {
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

	static func redactedServiceMessage(_ message: String, sentTo target: String?) -> String {
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

	static func targetLooksLikeService(_ target: String?) -> Bool {
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
}
