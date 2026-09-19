// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

enum SendingMessage {
	/// Why an argument list has no wire spelling.
	enum ArgumentError: Error, Equatable {
		/// A parameter before the last is empty, holds a space, or starts with
		/// a colon. Only the trailing parameter can be any of those; anywhere
		/// else it becomes a different number of parameters on the wire.
		case malformedMiddleArgument(index: Int)
	}

	/** The line `command` with `arguments` and `tags` is written as.

	 The last argument travels as the trailing parameter whenever it has to — it
	 is empty, holds a space, or starts with a colon — or wherever the command
	 declares its text goes. Every argument before it has to be one wire token.
	 An empty one used to be skipped, which moved every later argument up a
	 place, and one holding a space went out as two; `/nick :foo` tripped a debug
	 assertion. User input reaches here, so each of those is refused with an
	 error instead. */
	static func string(
		command: RemoteCommand,
		arguments: [String]?,
		tags: [String: String]? = nil
	) throws(ArgumentError) -> String {
		try string(
			wireCommand: command.wireName,
			trailingParameter: command.trailingParameter,
			arguments: arguments,
			tags: tags
		)
	}

	/** The same line for a verb this session's vocabulary has no case for.

	 Nothing the session sends of its own takes this form — a `RemoteCommand`
	 carries both the spelling and the trailing-parameter rule. The IRCv3
	 `msg-join` corpus encodes verbs such as `foo`, which is what it is for. */
	static func string(
		wireCommand: String,
		trailingParameter: TrailingParameter? = nil,
		arguments: [String]?,
		tags: [String: String]? = nil
	) throws(ArgumentError) -> String {
		var line = wireCommand.uppercased()

		guard let arguments, arguments.isEmpty == false else {
			return tagged(line, with: tags)
		}

		for (index, argument) in arguments.enumerated() {
			line.append(" ")

			guard index == arguments.count - 1 else {
				guard argument.isEmpty == false, argument.hasPrefix(":") == false, argument.contains(" ") == false else {
					throw .malformedMiddleArgument(index: index)
				}

				line.append(argument)
				continue
			}

			/* RFC 1459 2.3.1 lets the trailing parameter be empty, and dropping it
			 changes what the command means -- "AWAY :" clears an away message where
			 "AWAY" asks for nothing at all. A parameter with a space in it can only
			 travel as the trailing one, whatever the command's declared position
			 says: `RemoteCommand` knows where PRIVMSG puts its text, but not that
			 this CAP REQ names eleven capabilities. */
			if argument.isEmpty || argument.hasPrefix(":") || argument.contains(" ")
				|| trailingParameter == .startsAtArgument(index)
			{
				line.append(":")
			}

			line.append(argument)
		}

		return tagged(line, with: tags)
	}

	private static func tagged(_ line: String, with tags: [String: String]?) -> String {
		guard let tags, tags.isEmpty == false else {
			return line
		}

		return "@\(string(messageTags: tags)) \(line)"
	}

	static func string(messageTags tags: [String: String]) -> String {
		tags.keys.sorted().map { key in
			guard let value = tags[key], value.isEmpty == false else {
				return key
			}

			return "\(key)=\(encode(messageTagValue: value))"
		}.joined(separator: ";")
	}

	private static func encode(messageTagValue value: String) -> String {
		value
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: ";", with: "\\:")
			.replacingOccurrences(of: " ", with: "\\s")
			.replacingOccurrences(of: "\r", with: "\\r")
			.replacingOccurrences(of: "\n", with: "\\n")
	}
}
