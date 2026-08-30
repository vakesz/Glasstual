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
@testable import Glasstual
import Testing

@MainActor
@Suite("Incoming message")
struct IRCMessageTests {
	@Test("A prefix, a command and a trailing parameter are pulled apart")
	func parsesPrefixCommandAndTrailingParameter() throws {
		let message = try #require(Message(line: ":nick!user@host PRIVMSG #channel :hello  world"))

		#expect(message.command == "PRIVMSG")
		#expect(message.commandNumeric == 0)
		#expect(message.senderNickname == "nick")
		#expect(message.senderUsername == "user")
		#expect(message.senderAddress == "host")
		#expect(message.senderIsServer == false)
		#expect(message.paramsCount == 2)
		#expect(message.param(at: 0) == "#channel")
		#expect(message.param(at: 1) == "hello  world")
		#expect(message.messageTags == [:])
	}

	@Test("A server prefix marks the sender as a server and the command as a numeric")
	func parsesServerPrefixAndNumeric() throws {
		let message = try #require(Message(line: ":irc.example.net 001 me :Welcome"))

		#expect(message.commandNumeric == 1)
		#expect(message.senderIsServer)
		#expect(message.senderNickname == "irc.example.net")
		#expect(message.param(at: 1) == "Welcome")
	}

	@Test("A lowercase command is uppercased")
	func lowercaseCommandIsUppercased() throws {
		let message = try #require(Message(line: "ping :token"))

		#expect(message.command == "PING")
		#expect(message.param(at: 0) == "token")
	}

	@Test("Tag values have their escapes resolved")
	func parsesTagsWithEscapes() throws {
		let message = try #require(Message(line: "@a=b\\:c\\sd\\\\e;flag;+draft/reply=x\\ny :nick!u@h TAGMSG #c"))

		#expect(message.command == "TAGMSG")
		#expect(message.messageTags?["a"] == "b;c d\\e")
		#expect(message.messageTags?["flag"] == "")
		#expect(message.messageTags?["+draft/reply"] == "x\ny")
		#expect(message.param(at: 0) == "#c")
	}

	@Test("An escaped backslash ends the escape, so the letter after it is literal")
	func escapedBackslashFollowedByLetterIsNotAnEscape() throws {
		let message = try #require(Message(line: "@k=a\\\\sb PING :x"))

		#expect(message.messageTags?["k"] == "a\\sb")
	}

	@Test("The message identifier and account are lifted out of the tags")
	func parsesMessageIdentifierAndAccount() throws {
		let message = try #require(Message(line: "@msgid=63E1033A0;account=alice :alice!a@h PRIVMSG #c :hi"))

		#expect(message.messageIdentifier == "63E1033A0")
		#expect(message.senderAccount == "alice")

		let plain = try #require(Message(line: ":alice!a@h PRIVMSG #c :hi"))

		#expect(plain.messageIdentifier == nil)
		#expect(plain.senderAccount == nil)
	}

	@Test("A copy carries the identifier, and editing the copy leaves the original alone")
	func messageIdentifierSurvivesCopy() throws {
		let message = try #require(Message(line: "@msgid=abc;account=bob :bob!b@h PRIVMSG #c :hi"))
		let copy = message.duplicate()

		#expect(copy.messageIdentifier == "abc")
		#expect(copy.senderAccount == "bob")

		copy.messageIdentifier = "def"

		#expect(copy.messageIdentifier == "def")
		#expect(message.messageIdentifier == "abc")
	}

	@Test("A server time is only honored once the capability is negotiated")
	func serverTimeIsAppliedWhenCapabilityIsEnabled() throws {
		let client = GLTTestClient()
		let line = "@time=2024-01-02T03:04:05.000Z :n!u@h PRIVMSG #c :hi"
		let ignored = try #require(Message(line: line, on: client))

		#expect(ignored.isHistoric == false)

		client.enableCapability(.serverTime)
		let message = try #require(Message(line: line, on: client))

		#expect(message.isHistoric)

		var components = DateComponents()
		components.year = 2024
		components.month = 1
		components.day = 2
		components.hour = 3
		components.minute = 4
		components.second = 5
		components.timeZone = TimeZone(abbreviation: "UTC")
		let expected = try #require(Calendar(identifier: .gregorian).date(from: components))

		#expect(abs(message.receivedAt.timeIntervalSince1970 - expected.timeIntervalSince1970) < 0.001)
	}

	@Test("A line with no prefix is treated as coming from the server")
	func missingSenderFallsBackToServerAddress() throws {
		let message = try #require(Message(line: "NOTICE * :*** Looking up your hostname"))

		#expect(message.senderIsServer)
		#expect(message.senderNickname == "")
		#expect(message.param(at: 1) == "*** Looking up your hostname")
	}

	@Test("An empty tag section, an empty prefix, or an empty line does not parse")
	func emptyTagSectionFailsToParse() {
		#expect(Message(line: "@ PING :x") == nil)
		#expect(Message(line: ": PING :x") == nil)
		#expect(Message(line: "") == nil)
	}
}
