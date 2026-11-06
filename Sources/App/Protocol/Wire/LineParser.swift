// Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

nonisolated struct ParsedLine: Sendable {
	let messageTagSection: String?
	let senderSection: String?
	let command: String
	let commandNumeric: UInt
	let parameters: [String]

	init(messageTagSection: String?, senderSection: String?, command: String, parameters: [String]) {
		self.messageTagSection = messageTagSection
		self.senderSection = senderSection
		self.command = command
		commandNumeric = Self.numericValue(of: command)
		self.parameters = parameters
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

nonisolated enum LineParser {
	/// RFC 1459/2812 and IRCv3 separate tokens on SPACE (0x20) only, never on
	/// the wider Unicode whitespace set.
	private static let space: Unicode.Scalar = " "

	/// Splits a wire string into tokens on SPACE (0x20), dropping empty runs.
	static func wireTokens(in string: String) -> [String] {
		string.unicodeScalars.split(separator: space).map(String.init)
	}

	static func parsedLine(fromLine line: String) -> ParsedLine? {
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

			/* The last slot takes everything that is left, verbatim: a line of
			 single-character parameters would otherwise cost one array element
			 per two bytes received, before any handler sees the command. */
			if parameters.count == ProtocolLimits.maximumInboundParameterCount - 1 {
				parameters.append(String(remainder))
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
