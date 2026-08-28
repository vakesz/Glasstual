@testable import Glasstual
import XCTest

/// Preprocessor directives found in file:
/// #import <XCTest/XCTest.h>
/// #import "GLTTestClient.h"
/// #import "IRCMessage.h"
/// #import "IRCPrefix.h"
/** *********************************************************************
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
@objc
@MainActor
final class IRCMessageTests: XCTestCase {
	func testParsesPrefixCommandAndTrailingParameter() throws {
		let message = try XCTUnwrap(Message(line: ":nick!user@host PRIVMSG #channel :hello  world"))
		XCTAssertEqual(message.command, "PRIVMSG")
		XCTAssertEqual(message.commandNumeric, 0)
		XCTAssertEqual(message.senderNickname, "nick")
		XCTAssertEqual(message.senderUsername, "user")
		XCTAssertEqual(message.senderAddress, "host")
		XCTAssertFalse(message.senderIsServer)
		XCTAssertEqual(message.paramsCount, 2)
		XCTAssertEqual(message.param(at: 0), "#channel")
		XCTAssertEqual(message.param(at: 1), "hello  world")
		XCTAssertEqual(message.messageTags, [:])
	}

	func testParsesServerPrefixAndNumeric() throws {
		let message = try XCTUnwrap(Message(line: ":irc.example.net 001 me :Welcome"))
		XCTAssertEqual(message.commandNumeric, 1)
		XCTAssertTrue(message.senderIsServer)
		XCTAssertEqual(message.senderNickname, "irc.example.net")
		XCTAssertEqual(message.param(at: 1), "Welcome")
	}

	func testLowercaseCommandIsUppercased() throws {
		let message = try XCTUnwrap(Message(line: "ping :token"))
		XCTAssertEqual(message.command, "PING")
		XCTAssertEqual(message.param(at: 0), "token")
	}

	func testParsesTagsWithEscapes() throws {
		let message = try XCTUnwrap(Message(line: "@a=b\\:c\\sd\\\\e;flag;+draft/reply=x\\ny :nick!u@h TAGMSG #c"))
		XCTAssertEqual(message.command, "TAGMSG")
		XCTAssertEqual(message.messageTags?["a"], "b;c d\\e")
		XCTAssertEqual(message.messageTags?["flag"], "")
		XCTAssertEqual(message.messageTags?["+draft/reply"], "x\ny")
		XCTAssertEqual(message.param(at: 0), "#c")
	}

	func testEscapedBackslashFollowedByLetterIsNotAnEscape() throws {
		let message = try XCTUnwrap(Message(line: "@k=a\\\\sb PING :x"))
		XCTAssertEqual(message.messageTags?["k"], "a\\sb")
	}

	func testParsesMessageIdentifierAndAccount() throws {
		let message = try XCTUnwrap(Message(line: "@msgid=63E1033A0;account=alice :alice!a@h PRIVMSG #c :hi"))
		XCTAssertEqual(message.messageIdentifier, "63E1033A0")
		XCTAssertEqual(message.senderAccount, "alice")

		let plain = try XCTUnwrap(Message(line: ":alice!a@h PRIVMSG #c :hi"))
		XCTAssertNil(plain.messageIdentifier)
		XCTAssertNil(plain.senderAccount)
	}

	func testMessageIdentifierSurvivesCopy() throws {
		let message = try XCTUnwrap(Message(line: "@msgid=abc;account=bob :bob!b@h PRIVMSG #c :hi"))
		let copy = message.modified { copy in
			XCTAssertEqual(copy.messageIdentifier, "abc")
			XCTAssertEqual(copy.senderAccount, "bob")
			copy.messageIdentifier = "def"
		}

		XCTAssertEqual(copy.messageIdentifier, "def")
		XCTAssertEqual(message.messageIdentifier, "abc")
	}

	func testServerTimeIsAppliedWhenCapabilityIsEnabled() throws {
		let client = GLTTestClient()
		let line = "@time=2024-01-02T03:04:05.000Z :n!u@h PRIVMSG #c :hi"
		let ignored = try XCTUnwrap(Message(line: line, on: client))
		XCTAssertFalse(ignored.isHistoric)

		client.enableCapability(.serverTime)
		let message = try XCTUnwrap(Message(line: line, on: client))
		XCTAssertTrue(message.isHistoric)

		var components = DateComponents()
		components.year = 2024
		components.month = 1
		components.day = 2
		components.hour = 3
		components.minute = 4
		components.second = 5
		components.timeZone = TimeZone(abbreviation: "UTC")
		let expected = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: components))

		XCTAssertEqual(message.receivedAt.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
	}

	func testMissingSenderFallsBackToServerAddress() throws {
		let message = try XCTUnwrap(Message(line: "NOTICE * :*** Looking up your hostname"))
		XCTAssertTrue(message.senderIsServer)
		XCTAssertEqual(message.senderNickname, "")
		XCTAssertEqual(message.param(at: 1), "*** Looking up your hostname")
	}

	func testEmptyTagSectionFailsToParse() {
		XCTAssertNil(Message(line: "@ PING :x"))
		XCTAssertNil(Message(line: ": PING :x"))
		XCTAssertNil(Message(line: ""))
	}
}
