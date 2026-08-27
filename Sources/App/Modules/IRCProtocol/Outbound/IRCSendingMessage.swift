/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

@objc(IRCSendingMessage)
public final class SendingMessage: NSObject {
	@objc(stringWithCommand:arguments:)
	public static func string(command: String, arguments: [String]?) -> String {
		let uppercaseCommand = command.uppercased()

		guard let arguments, arguments.isEmpty == false else {
			return uppercaseCommand
		}

		var line = uppercaseCommand
		let colonPosition = CommandIndex.colonPosition(forRemoteCommand: command)

		for (index, argument) in arguments.enumerated() {
			guard argument.isEmpty == false else {
				break
			}

			line.append(" ")

			if colonPosition == NSNotFound {
				let isLastArgument = index == arguments.count - 1

				if isLastArgument, argument.hasPrefix(":") || argument.contains(" ") {
					line.append(":")
				}
			} else if index == colonPosition {
				line.append(":")
			}

			line.append(argument)
		}

		return line
	}

	@objc(stringWithCommand:arguments:tags:)
	public static func string(command: String, arguments: [String]?, tags: [String: String]?) -> String {
		let line = string(command: command, arguments: arguments)

		guard let tags, tags.isEmpty == false else {
			return line
		}

		return "@\(string(messageTags: tags)) \(line)"
	}

	@objc(stringWithMessageTags:)
	public static func string(messageTags tags: [String: String]) -> String {
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
