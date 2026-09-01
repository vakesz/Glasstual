/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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

/// Behaviour corpus for the inbound line parser and message tag parser.
///
/// The corpus pins the IRC grammar's exact token separator (`0x20`) alongside
/// malformed-input and message-tag edge cases.
@MainActor
struct IRCLineParserCorpusTests {
	nonisolated struct LineCase: Sendable {
		let line: String
		let tagSection: String?
		let sender: String?
		let command: String
		let commandNumeric: UInt
		let parameters: [String]

		init(
			_ line: String,
			tagSection: String? = nil,
			sender: String? = nil,
			command: String,
			commandNumeric: UInt = 0,
			parameters: [String] = []
		) {
			self.line = line
			self.tagSection = tagSection
			self.sender = sender
			self.command = command
			self.commandNumeric = commandNumeric
			self.parameters = parameters
		}
	}

	nonisolated struct TagCase: Sendable {
		let section: String
		let name: String
		let value: String?

		init(_ section: String, _ name: String, _ value: String?) {
			self.section = section
			self.name = name
			self.value = value
		}
	}

	// MARK: - Structure

	nonisolated static let wellFormedLines: [LineCase] = [
		LineCase("PING :12345", command: "PING", parameters: ["12345"]),
		LineCase("PING", command: "PING"),
		LineCase(
			":irc.example.org 001 me :Welcome to the network",
			sender: "irc.example.org",
			command: "001",
			commandNumeric: 1,
			parameters: ["me", "Welcome to the network"]
		),
		LineCase(
			":nick!user@host PRIVMSG #chan :hello world",
			sender: "nick!user@host",
			command: "PRIVMSG",
			parameters: ["#chan", "hello world"]
		),
		/* Non-numeric commands are normalised to upper case. */
		LineCase(
			":nick!user@host privmsg #chan :hi",
			sender: "nick!user@host",
			command: "PRIVMSG",
			parameters: ["#chan", "hi"]
		),
		/* Numeric commands keep their wire form, including leading zeroes. */
		LineCase("005 me TOKEN :are supported", command: "005", commandNumeric: 5, parameters: [
			"me", "TOKEN", "are supported",
		]),
		/* An empty trailing parameter is a parameter, not an absent one. */
		LineCase(
			":nick!user@host PRIVMSG #chan :",
			sender: "nick!user@host",
			command: "PRIVMSG",
			parameters: ["#chan", ""]
		),
		/* Everything after the first ": " marker is trailing, colons included. */
		LineCase("PRIVMSG #chan :a : b", command: "PRIVMSG", parameters: ["#chan", "a : b"]),
		LineCase("PRIVMSG #chan :  padded  ", command: "PRIVMSG", parameters: ["#chan", "  padded  "]),
		/* Middle parameters need no trailing marker. */
		LineCase("PRIVMSG #chan hello", command: "PRIVMSG", parameters: ["#chan", "hello"]),
		/* Runs of spaces between tokens collapse. */
		LineCase("PING   :x", command: "PING", parameters: ["x"]),
		LineCase("ERROR :Closing Link", command: "ERROR", parameters: ["Closing Link"]),
		/* Eight-bit and non-ASCII payloads survive verbatim. */
		LineCase(
			":nick!user@host PRIVMSG #chan :h\u{00E9}llo \u{2713} \u{00FF}",
			sender: "nick!user@host",
			command: "PRIVMSG",
			parameters: ["#chan", "h\u{00E9}llo \u{2713} \u{00FF}"]
		),
		LineCase(
			"@id=42;+draft/reply=7 :nick!user@host TAGMSG #chan",
			tagSection: "id=42;+draft/reply=7",
			sender: "nick!user@host",
			command: "TAGMSG",
			parameters: ["#chan"]
		),
		LineCase(
			"@batch=abc :irc.example.org NOTICE * :queued",
			tagSection: "batch=abc",
			sender: "irc.example.org",
			command: "NOTICE",
			parameters: ["*", "queued"]
		),
	]

	@Test(arguments: Self.wellFormedLines)
	func parsesWellFormedLines(testCase: LineCase) throws {
		let parsed = try #require(LineParser.parsedLine(fromLine: testCase.line))

		#expect(parsed.messageTagSection == testCase.tagSection)
		#expect(parsed.senderSection == testCase.sender)
		#expect(parsed.command == testCase.command)
		#expect(parsed.commandNumeric == testCase.commandNumeric)
		#expect(parsed.parameters == testCase.parameters)
	}

	/// Lines that carry no command, or only a marker character, are rejected.
	@Test(arguments: ["", " ", "   PING :x", "@ PING", ": PING", "@", ":"])
	func rejectsLinesWithoutACommand(line: String) {
		#expect(LineParser.parsedLine(fromLine: line) == nil)
	}

	// MARK: - Token splitting

	/// Parameters are separated by `0x20` and by nothing else. Everything below
	/// splits or merges tokens incorrectly today.
	nonisolated static let splittingLines: [LineCase] = [
		/* U+00A0 NO-BREAK SPACE is a channel-name character, not a separator. */
		LineCase(
			":nick!user@host PRIVMSG #ch\u{00A0}an :hi",
			sender: "nick!user@host",
			command: "PRIVMSG",
			parameters: ["#ch\u{00A0}an", "hi"]
		),
		/* Neither is a tab. */
		LineCase(
			":nick!user@host PRIVMSG #a\tb :hi",
			sender: "nick!user@host",
			command: "PRIVMSG",
			parameters: ["#a\tb", "hi"]
		),
		/* A combining mark after a space does not glue the space to the
			following token: the space still ends the command. */
		LineCase("PING \u{0301}x", command: "PING", parameters: ["\u{0301}x"]),
	]

	@Test(arguments: Self.splittingLines)
	func splitsTokensOnSpaceOnly(testCase: LineCase) throws {
		let parsed = try #require(LineParser.parsedLine(fromLine: testCase.line))

		#expect(parsed.senderSection == testCase.sender)
		#expect(parsed.command == testCase.command)
		#expect(parsed.parameters == testCase.parameters)
	}

	// MARK: - Message tags

	nonisolated static let tagCases: [TagCase] = [
		TagCase("msgid=abc", "msgid", "abc"),
		TagCase("account=alice", "account", "alice"),
		/* A tag with no "=" is present with an empty value. */
		TagCase("flag", "flag", ""),
		TagCase("empty=", "empty", ""),
		/* Escape sequences defined by the message-tags specification. */
		TagCase("a=b\\:c", "a", "b;c"),
		TagCase("a=b\\sc", "a", "b c"),
		TagCase("a=b\\rc", "a", "b\rc"),
		TagCase("a=b\\nc", "a", "b\nc"),
		TagCase("a=b\\\\c", "a", "b\\c"),
		/* "\s" after an escaped backslash is literal text, not a space. */
		TagCase("a=x\\\\sy", "a", "x\\sy"),
		/* An escaped backslash followed by a real escape still unescapes. */
		TagCase("a=x\\\\\\sy", "a", "x\\ y"),
		/* Unknown escapes drop the backslash and keep the character. */
		TagCase("a=x\\qy", "a", "xqy"),
		/* A dangling backslash at the end of a value is dropped. */
		TagCase("a=end\\", "a", "end"),
		/* The last occurrence of a duplicated tag wins. */
		TagCase("a=first;a=second", "a", "second"),
		/* Empty components are skipped rather than producing an empty tag. */
		TagCase("a=kept;;b=also", "b", "also"),
		TagCase("a=kept;;b=also", "", nil),
		/* Vendor and client-only tag names are kept verbatim. */
		TagCase("example.com/foo=bar", "example.com/foo", "bar"),
		TagCase("+typing=active", "+typing", "active"),
		/* Values are not interpreted, only unescaped. */
		TagCase("time=2021-01-01T00:00:00.000Z", "time", "2021-01-01T00:00:00.000Z"),
		TagCase("label=xyz", "label", "xyz"),
		TagCase("unset=x", "other", nil),
	]

	@Test(arguments: Self.tagCases)
	func parsesMessageTags(testCase: TagCase) {
		let parsed = MessageTagParser.parsedTags(fromSection: testCase.section)

		#expect(parsed.tags[testCase.name] == testCase.value)
	}

	@Test
	func promotesMessageIdentifierAndAccountTags() {
		let parsed = MessageTagParser.parsedTags(fromSection: "msgid=abc;account=alice;batch=b1")

		#expect(parsed.messageIdentifier == "abc")
		#expect(parsed.senderAccount == "alice")
		#expect(parsed.tags["batch"] == "b1")
	}

	/// Empty values do not become empty identifiers.
	@Test(arguments: ["msgid=;account=", "flag"])
	func emptyIdentifierTagsAreAbsent(section: String) {
		let parsed = MessageTagParser.parsedTags(fromSection: section)

		#expect(parsed.messageIdentifier == nil)
		#expect(parsed.senderAccount == nil)
	}
}

/// Tag handling that depends on the capabilities a client negotiated.
@MainActor
struct IRCMessageTagCorpusTests {
	@Test
	func messageWithoutClientKeepsTagsButNoBatchOrTime() throws {
		let line = "@time=2021-01-01T00:00:00.000Z;msgid=m1;batch=b1;label=l1"
			+ " :nick!user@host PRIVMSG #chan :hi"
		let message = try #require(Message(line: line))

		#expect(message.messageTags?["label"] == "l1")
		#expect(message.messageTags?["batch"] == "b1")
		#expect(message.messageIdentifier == "m1")
		/* Without the capabilities the tags are carried, not acted upon. */
		#expect(message.batchToken == nil)
		#expect(message.isHistoric == false)
	}

	@Test
	func serverTimeCapabilityMarksMessageHistoric() throws {
		let client = GLTTestClient()
		client.enableCapability(.serverTime)

		let message = try #require(
			Message(line: "@time=2021-01-01T00:00:00.000Z :nick!user@host PRIVMSG #chan :hi", on: client)
		)

		#expect(message.isHistoric)
		#expect(message.receivedAt == Date(timeIntervalSince1970: 1_609_459_200))
	}

	@Test
	func serverTimeAcceptsNumericTimestamps() throws {
		let client = GLTTestClient()
		client.enableCapability(.serverTime)

		let message = try #require(Message(line: "@t=1609459200 :nick!user@host PRIVMSG #chan :hi", on: client))

		#expect(message.isHistoric)
		#expect(message.receivedAt == Date(timeIntervalSince1970: 1_609_459_200))
	}

	@Test
	func unparsableServerTimeLeavesMessageCurrent() throws {
		let client = GLTTestClient()
		client.enableCapability(.serverTime)

		let message = try #require(Message(line: "@time=not-a-date :nick!user@host PRIVMSG #chan :hi", on: client))

		#expect(message.isHistoric == false)
	}

	nonisolated struct BatchCase: Sendable {
		let tagSection: String
		let token: String?

		init(_ tagSection: String, _ token: String?) {
			self.tagSection = tagSection
			self.token = token
		}
	}

	/// Batch tokens are restricted to the characters the specification allows.
	@Test(arguments: [
		BatchCase("batch=abc_1-2", "abc_1-2"),
		BatchCase("batch=ABC123", "ABC123"),
		BatchCase("batch=bad+token", nil),
		BatchCase("batch=bad/token", nil),
		BatchCase("msgid=only", nil),
	])
	func batchTokenIsValidated(testCase: BatchCase) throws {
		let client = GLTTestClient()
		client.enableCapability(.batch)

		let line = "@\(testCase.tagSection) :nick!user@host PRIVMSG #chan :hi"
		let message = try #require(Message(line: line, on: client))

		#expect(message.batchToken == testCase.token)
	}

	@Test
	func absentSenderFallsBackToTheServer() throws {
		let message = try #require(Message(line: "PING :12345"))

		#expect(message.senderIsServer)
		#expect(message.params == ["12345"])
		#expect(message.sequence == "12345")
	}

	@Test
	func senderComponentsAreSplitFromTheHostmask() throws {
		let message = try #require(Message(line: ":nick!user@host PRIVMSG #chan :hi"))

		#expect(message.senderNickname == "nick")
		#expect(message.senderUsername == "user")
		#expect(message.senderAddress == "host")
		#expect(message.senderHostmask == "nick!user@host")
		#expect(message.senderIsServer == false)
	}

	@Test
	func sequenceStartsAtTheSecondParameterWhenThereIsOne() throws {
		let message = try #require(Message(line: ":irc.example.org 372 me :- motd line"))

		#expect(message.sequence == "- motd line")
		#expect(message.param(at: 0) == "me")
		#expect(message.param(at: 9) == "")
	}
}
