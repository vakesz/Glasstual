/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
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

@objc(IRCParsedMessageTags)
public final class ParsedMessageTags: NSObject {
	@objc public let tags: [String: String]
	@objc public let messageIdentifier: String?
	@objc public let senderAccount: String?

	init(tags: [String: String]) {
		self.tags = tags
		messageIdentifier = tags["msgid"].flatMap { $0.isEmpty ? nil : $0 }
		senderAccount = tags["account"].flatMap { $0.isEmpty ? nil : $0 }

		super.init()
	}
}

@objc(IRCMessageTagParser)
public final class MessageTagParser: NSObject {
	@objc(parsedTagsFromSection:)
	public static func parsedTags(fromSection section: String) -> ParsedMessageTags {
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
