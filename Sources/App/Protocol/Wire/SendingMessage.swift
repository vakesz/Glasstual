/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

enum SendingMessage {
	/// Why an argument list has no wire spelling.
	enum ArgumentError: Error, Equatable {
		/// A parameter before the last is empty, holds a space, or starts with
		/// a colon. Only the trailing parameter can be any of those; anywhere
		/// else it becomes a different number of parameters on the wire.
		case malformedMiddleArgument(index: Int)
	}

	/** The line `command` with `arguments` is written as.

	 The last argument travels as the trailing parameter whenever it has to — it
	 is empty, holds a space, or starts with a colon — or wherever the command
	 declares its text goes. Every argument before it has to be one wire token.
	 An empty one used to be skipped, which moved every later argument up a
	 place, and one holding a space went out as two; `/nick :foo` tripped a debug
	 assertion. User input reaches here, so each of those is refused with an
	 error instead. */
	static func string(command: String, arguments: [String]?) throws(ArgumentError) -> String {
		let uppercaseCommand = command.uppercased()

		guard let arguments, arguments.isEmpty == false else {
			return uppercaseCommand
		}

		var line = uppercaseCommand
		let trailingParameter = RemoteCommand(wireName: command)?.trailingParameter

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

		return line
	}

	static func string(
		command: String,
		arguments: [String]?,
		tags: [String: String]?
	) throws(ArgumentError) -> String {
		let line = try string(command: command, arguments: arguments)

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
