/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
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

@objc(IRCParsedLine)
public final nonisolated class ParsedLine: NSObject { // nonisolated: value
	@objc public let messageTagSection: String?
	@objc public let senderSection: String?
	@objc public let command: String
	@objc public let commandNumeric: UInt
	@objc public let parameters: [String]

	init(messageTagSection: String?, senderSection: String?, command: String, parameters: [String]) {
		self.messageTagSection = messageTagSection
		self.senderSection = senderSection
		self.command = command
		commandNumeric = Self.numericValue(of: command)
		self.parameters = parameters

		super.init()
	}

	/// IRC numerics are exactly three ASCII digits. `CharacterSet.decimalDigits`
	/// also matches non-ASCII digits, which `integerValue` then reads as 0,
	/// and an oversized run of digits saturates rather than being rejected.
	static func numericValue(of command: String) -> UInt {
		guard command.count == 3, isASCIIDigits(command), let numeric = UInt(command) else {
			return 0
		}

		return numeric
	}

	static func isASCIIDigits(_ string: String) -> Bool {
		string.isEmpty == false && string.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
	}
}

@objc(IRCLineParser)
public final nonisolated class LineParser: NSObject { // nonisolated: value
	/// RFC 1459/2812 and IRCv3 separate tokens on SPACE (0x20) only, never on
	/// the wider Unicode whitespace set.
	private static let space: Unicode.Scalar = " "

	/// Splits a wire string into tokens on SPACE (0x20), dropping empty runs.
	@objc(wireTokensInString:)
	public static func wireTokens(in string: String) -> [String] {
		string.unicodeScalars.split(separator: space).map(String.init)
	}

	@objc(parsedLineFromLine:)
	public static func parsedLine(fromLine line: String) -> ParsedLine? {
		var remainder = line.unicodeScalars[...]
		var messageTagSection: String?
		var senderSection: String?

		if remainder.first == "@" {
			let token = nextToken(from: &remainder)

			guard token.count > 1 else {
				return nil
			}

			messageTagSection = String(token.dropFirst())
		}

		if remainder.first == ":" {
			let token = nextToken(from: &remainder)

			guard token.count > 1 else {
				return nil
			}

			senderSection = String(token.dropFirst())
		}

		let commandToken = nextToken(from: &remainder)

		guard commandToken.isEmpty == false else {
			return nil
		}

		let command = ParsedLine.isASCIIDigits(commandToken) ? commandToken : commandToken.uppercased()
		var parameters: [String] = []

		while remainder.isEmpty == false {
			if remainder.first == ":" {
				parameters.append(String(remainder.dropFirst()))
				break
			}

			parameters.append(nextToken(from: &remainder))
		}

		return ParsedLine(
			messageTagSection: messageTagSection,
			senderSection: senderSection,
			command: command,
			parameters: parameters
		)
	}

	private static func nextToken(from remainder: inout Substring.UnicodeScalarView) -> String {
		guard let separator = remainder.firstIndex(of: space) else {
			let token = String(remainder)

			remainder = remainder[remainder.endIndex...]

			return token
		}

		let token = String(remainder[..<separator])
		let nextToken = remainder[separator...].firstIndex(where: { $0 != space })

		remainder = nextToken.map { remainder[$0...] } ?? remainder[remainder.endIndex...]

		return token
	}
}
