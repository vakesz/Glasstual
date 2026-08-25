import XCTest

// Preprocessor directives found in file:
// #import <XCTest/XCTest.h>
// #import "GLTTestClient.h"
// #import "IRCMessage.h"
// #import "IRCPrefix.h"
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
@objc
class IRCMessageTests: XCTestCase {
    @objc
    func testParsesPrefixCommandAndTrailingParameter() {
        let message: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: ":nick!user@host PRIVMSG #channel :hello  world")

        XCTAssertNotNil(message)

        XCTAssertEqualObjects(message.command, "PRIVMSG")

        XCTAssertEqual(message.commandNumeric, 0)

        XCTAssertEqualObjects(message.senderNickname, "nick")
        XCTAssertEqualObjects(message.senderUsername, "user")
        XCTAssertEqualObjects(message.senderAddress, "host")

        XCTAssertFalse(message.senderIsServer)

        XCTAssertEqual(message.paramsCount, 2)

        XCTAssertEqualObjects(message.paramAt(0), "#channel")
        XCTAssertEqualObjects(message.paramAt(1), "hello  world")

        let noTags = [:]

        XCTAssertEqualObjects(message.messageTags, noTags)
    }
    @objc
    func testParsesServerPrefixAndNumeric() {
        let message: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: ":irc.example.net 001 me :Welcome")

        XCTAssertNotNil(message)

        XCTAssertEqual(message.commandNumeric, 1)

        XCTAssertTrue(message.senderIsServer)

        XCTAssertEqualObjects(message.senderNickname, "irc.example.net")
        XCTAssertEqualObjects(message.paramAt(1), "Welcome")
    }
    @objc
    func testLowercaseCommandIsUppercased() {
        let message: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: "ping :token")

        XCTAssertEqualObjects(message.command, "PING")
        XCTAssertEqualObjects(message.paramAt(0), "token")
    }
    @objc
    func testParserConsumesWhitespaceBetweenProtocolSections() {
        let message: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: "@flag\\t:nick!user@host   privmsg\\t#channel :hello  world")

        XCTAssertNotNil(message)

        XCTAssertEqualObjects(message.messageTags["flag"], "")
        XCTAssertEqualObjects(message.senderNickname, "nick")
        XCTAssertEqualObjects(message.command, "PRIVMSG")
        XCTAssertEqualObjects(message.params, ["#channel", "hello  world"])
    }
    @objc
    func testParsesTagsWithEscapes() {
        let message: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: "@a=b\\\\:c\\\\sd\\\\\\\\e;flag;+draft/reply=x\\\\ny :nick!u@h TAGMSG #c")

        XCTAssertNotNil(message)

        XCTAssertEqualObjects(message.command, "TAGMSG")
        XCTAssertEqualObjects(message.messageTags["a"], "b;c d\\\\e")
        XCTAssertEqualObjects(message.messageTags["flag"], "")
        XCTAssertEqualObjects(message.messageTags["+draft/reply"], "x\\ny")
        XCTAssertEqualObjects(message.paramAt(0), "#c")
    }
    @objc
    func testEscapedBackslashFollowedByLetterIsNotAnEscape() {
        /* "\\s" is an escaped backslash followed by a literal s. */
        let message: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: "@k=a\\\\\\\\sb PING :x")

        XCTAssertEqualObjects(message.messageTags["k"], "a\\\\sb")
    }
    @objc
    func testParsesMessageIdentifierAndAccount() {
        let message: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: "@msgid=63E1033A0;account=alice :alice!a@h PRIVMSG #c :hi")

        XCTAssertEqualObjects(message.messageIdentifier, "63E1033A0")
        XCTAssertEqualObjects(message.senderAccount, "alice")

        let plain: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: ":alice!a@h PRIVMSG #c :hi")

        XCTAssertNil(plain.messageIdentifier)
        XCTAssertNil(plain.senderAccount)
    }
    @objc
    func testMessageIdentifierSurvivesCopy() {
        let message: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: "@msgid=abc;account=bob :bob!b@h PRIVMSG #c :hi")
        var mutableCopy: UnsafeMutablePointer<IRCMessageMutable>! = message.mutableCopy()

        XCTAssertEqualObjects(mutableCopy.messageIdentifier, "abc")
        XCTAssertEqualObjects(mutableCopy.senderAccount, "bob")
        mutableCopy.messageIdentifier = "def"

        let copy: UnsafeMutablePointer<IRCMessage>! = mutableCopy.copy()

        XCTAssertEqualObjects(copy.messageIdentifier, "def")
        XCTAssertEqualObjects(message.messageIdentifier, "abc")
    }
    @objc
    func testServerTimeIsAppliedWhenCapabilityIsEnabled() {
        let client: UnsafeMutablePointer<GLTTestClient>! = GLTTestClient.testClient()
        let ignored: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: "@time=2024-01-02T03:04:05.000Z :n!u@h PRIVMSG #c :hi", onClient: client)

        XCTAssertFalse(ignored.isHistoric)
        client.enableCapability(ClientIRCv3SupportedCapabilityServerTime)

        let message: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: "@time=2024-01-02T03:04:05.000Z :n!u@h PRIVMSG #c :hi", onClient: client)

        XCTAssertTrue(message.isHistoric)

        let components = NSDateComponents()

        components.year = 2024
        components.month = 1
        components.day = 2
        components.hour = 3
        components.minute = 4
        components.second = 5
        components.timeZone = TimeZone.timeZoneWithAbbreviation("UTC")

        let expected: Date! = Calendar(identifier: Calendar.Identifier.gregorian).dateFromComponents(components)

        XCTAssertEqualWithAccuracy(message.receivedAt.timeIntervalSince1970, expected.timeIntervalSince1970, 0.001)
    }
    @objc
    func testMissingSenderFallsBackToServerAddress() {
        let message: UnsafeMutablePointer<IRCMessage>! = IRCMessage(line: "NOTICE * :*** Looking up your hostname")

        XCTAssertTrue(message.senderIsServer)
        XCTAssertEqualObjects(message.senderNickname, "")
        XCTAssertEqualObjects(message.paramAt(1), "*** Looking up your hostname")
    }
    @objc
    func testEmptyTagSectionFailsToParse() {
        XCTAssertNil(IRCMessage(line: "@ PING :x"))
        XCTAssertNil(IRCMessage(line: ": PING :x"))
        XCTAssertNil(IRCMessage(line: ""))
    }
}