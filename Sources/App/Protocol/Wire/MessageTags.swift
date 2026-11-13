// Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// The message tags of one line, with the two the session reads by name pulled
/// out of them.
nonisolated struct ParsedMessageTags: Sendable, Equatable {
	let tags: [String: String]
	let messageIdentifier: String?
	let senderAccount: String?

	init(tags: [String: String]) {
		self.tags = tags
		messageIdentifier = tags["msgid"]?.nonEmpty
		senderAccount = tags["account"]?.nonEmpty
	}
}

nonisolated enum MessageTagParser {
	/// IRCv3 message-tags caps the tag section at 8191 bytes, counting the
	/// leading `@` and the space that ends it. Anything longer is a server
	/// that is not playing by the rules, so its tags are dropped rather than
	/// parsed into an unbounded dictionary.
	static let maximumSectionLength = 8191

	/// The `@` and the trailing space: counted by the cap, but already taken
	/// off the section this parser is handed.
	private static let sectionDelimiterLength = 2

	/// - Parameter section: The tags between the `@` and the space.
	static func parsedTags(fromSection section: String) -> ParsedMessageTags {
		guard section.utf8.count + sectionDelimiterLength <= maximumSectionLength else {
			return ParsedMessageTags(tags: [:])
		}

		var tags: [String: String] = [:]

		for component in section.split(separator: ";", omittingEmptySubsequences: true) {
			if let equals = component.firstIndex(of: "=") {
				let name = String(component[..<equals])
				let value = component[component.index(after: equals)...]

				tags[name] = decode(value)
			} else {
				tags[String(component)] = ""
			}
		}

		return ParsedMessageTags(tags: tags)
	}

	private static func decode(_ encoded: Substring) -> String {
		var output: [UInt16] = []
		let input = Array(encoded.utf16)
		var index = 0

		while index < input.count {
			let character = input[index]

			guard character == 0x5C else {
				output.append(character)
				index += 1
				continue
			}

			index += 1

			guard index < input.count else {
				break
			}

			switch input[index] {
			case 0x3A:
				output.append(0x3B)
			case 0x73:
				output.append(0x20)
			case 0x72:
				output.append(0x0D)
			case 0x6E:
				output.append(0x0A)
			default:
				output.append(input[index])
			}

			index += 1
		}

		return String(decoding: output, as: UTF16.self)
	}
}
