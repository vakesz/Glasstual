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

/// One line and the command atoms it has to produce.
nonisolated struct IRCSpecCommandCase: CustomTestStringConvertible { // nonisolated: value
	let line: String
	let command: String
	let numeric: UInt

	var testDescription: String {
		line.debugDescription
	}
}

/// The message grammar itself: RFC 1459 §2.3 / RFC 2812 §2.3.1 for the line,
/// and the IRCv3 `message-tags` specification for the tag section in front of
/// it. These are the rules the socket reader has to obey before any handler
/// sees a message.
@Suite("IRC message grammar")
@MainActor
struct IRCSpecMessageGrammarTests {
	// MARK: - RFC 1459 §2.3.1 line grammar

	/// RFC 1459 §2.3.1: a line is `[':' prefix SPACE] command [params]`, and a
	/// command is either a word or exactly three digits. Anything that cannot
	/// produce a command is not a message.
	@Test(
		"RFC 1459 §2.3.1: a line without a command is rejected",
		arguments: ["", " ", "   ", ":", "@", ":coolguy", "@tag=value", "@tag=value :coolguy", ":coolguy "]
	)
	func linesWithoutACommandAreRejected(_ line: String) {
		#expect(LineParser.parsedLine(fromLine: line) == nil)
	}

	/// RFC 1459 §2.3.1: commands are case-insensitive, so they are folded to
	/// one spelling before dispatch. Numerics are digits and must survive
	/// verbatim — `001` is not `1`.
	@Test(
		"RFC 1459 §2.3.1: commands fold to upper case, numerics are kept verbatim",
		arguments: [
			IRCSpecCommandCase(line: "privmsg foo :bar", command: "PRIVMSG", numeric: 0),
			IRCSpecCommandCase(line: "PrIvMsG foo :bar", command: "PRIVMSG", numeric: 0),
			IRCSpecCommandCase(line: ":server 001 me :Welcome", command: "001", numeric: 1),
			IRCSpecCommandCase(line: ":server 005 me PREFIX=(ov)@+ :x", command: "005", numeric: 5),
			IRCSpecCommandCase(line: ":server 903 me :SASL ok", command: "903", numeric: 903),
		]
	)
	func commandsFoldAndNumericsSurvive(_ testCase: IRCSpecCommandCase) throws {
		let parsed = try #require(LineParser.parsedLine(fromLine: testCase.line))

		#expect(parsed.command == testCase.command)
		#expect(parsed.commandNumeric == testCase.numeric)
	}

	/// A numeric is *exactly* three ASCII digits (RFC 1459 §2.3.1, and the
	/// numerics registry in RFC 2812 §5). Everything else is a word command
	/// with no numeric value, including digit runs of the wrong length and
	/// non-ASCII digits that `integerValue` would otherwise read as zero.
	@Test(
		"RFC 1459 §2.3.1: only three ASCII digits make a numeric",
		arguments: [
			("001", UInt(1)),
			("999", UInt(999)),
			("1", UInt(0)),
			("01", UInt(0)),
			("0001", UInt(0)),
			("12a", UInt(0)),
			("١٢٣", UInt(0)),
			("+12", UInt(0)),
		]
	)
	func onlyThreeASCIIDigitsAreNumerics(_ testCase: (command: String, numeric: UInt)) {
		#expect(ParsedLine.numericValue(of: testCase.command) == testCase.numeric)
	}

	/// RFC 1459 §2.3: "The prefix, command, and all parameters are separated
	/// by one (or more) ASCII space character(s)". Tabs are not spaces.
	@Test("RFC 1459 §2.3: only SPACE separates atoms")
	func onlySpaceSeparatesAtoms() throws {
		let parsed = try #require(LineParser.parsedLine(fromLine: ":cool\tguy foo\tbar   baz  qux"))

		#expect(parsed.senderSection == "cool\tguy")
		#expect(parsed.command == "FOO\tBAR")
		#expect(parsed.parameters == ["baz", "qux"])
	}

	/// RFC 1459 §2.3.1: the trailing parameter starts at the first `:` in
	/// parameter position and runs to the end of the line, spaces and further
	/// colons included. It may be empty.
	@Test(
		"RFC 1459 §2.3.1: the trailing parameter is taken verbatim",
		arguments: [
			("PRIVMSG #chan :", [""]),
			("PRIVMSG #chan :  ", ["  "]),
			("PRIVMSG #chan ::-)", [":-)"]),
			("PRIVMSG #chan :lol :) ", ["lol :) "]),
			("PRIVMSG #chan :a  b", ["a  b"]),
		]
	)
	func trailingParameterIsVerbatim(_ testCase: (line: String, trailing: [String])) throws {
		let parsed = try #require(LineParser.parsedLine(fromLine: testCase.line))

		#expect(Array(parsed.parameters.dropFirst()) == testCase.trailing)
	}

	/// RFC 1459 §2.3: "If the prefix is missing from the message, it is
	/// assumed to have originated from the connection from which it was
	/// received."
	@Test("RFC 1459 §2.3: a message with no prefix comes from the server")
	func absentPrefixMeansTheServerSentIt() throws {
		let client = GLTTestClient()
		let message = try #require(Message(line: "PING :12345", on: client))

		#expect(message.senderIsServer)
		#expect(message.command == "PING")
		#expect(message.params == ["12345"])
	}

	/// RFC 2812 §2.3.1 `prefix = servername / (nickname [[ "!" user ] "@" host ])`.
	/// A fully qualified prefix is split; anything else is treated as a server
	/// name, which is what a bare `servername` prefix is.
	@Test("RFC 2812 §2.3.1: a full hostmask prefix splits into nick, user and host")
	func fullHostmaskPrefixSplits() throws {
		let client = GLTTestClient()
		let message = try #require(Message(line: ":nick!user@example.org PRIVMSG #chan :hi", on: client))

		#expect(message.senderIsServer == false)
		#expect(message.senderNickname == "nick")
		#expect(message.senderUsername == "user")
		#expect(message.senderAddress == "example.org")
		#expect(message.senderHostmask == "nick!user@example.org")
	}

	@Test("RFC 2812 §2.3.1: a bare servername prefix is a server")
	func serverNamePrefixIsAServer() throws {
		let client = GLTTestClient()
		let message = try #require(Message(line: ":irc.example.org NOTICE * :hello", on: client))

		#expect(message.senderIsServer)
		#expect(message.senderNickname == "irc.example.org")
	}

	/// RFC 2812 §2.3 caps a message at 512 bytes including CR-LF, which is the
	/// 510-byte body `IRCProtocolLimits` reserves for. A longer line still has
	/// to parse: truncation is the server's job, and dropping the message
	/// would lose traffic the user can see in the raw view.
	@Test("RFC 2812 §2.3: an over-long line still parses")
	func overLongLinesStillParse() throws {
		let body = String(repeating: "x", count: 1000)
		let parsed = try #require(LineParser.parsedLine(fromLine: "PRIVMSG #chan :\(body)"))

		#expect(parsed.parameters == ["#chan", body])
		#expect(IRCProtocolLimits.maximumBodyLength == 510)
	}

	// MARK: - IRCv3 message-tags

	/// IRCv3 message-tags, escaping table: `\:` is `;`, `\s` is a space, `\\`
	/// is a backslash, `\r` is CR and `\n` is LF.
	@Test(
		"IRCv3 message-tags: the escape table",
		arguments: [
			("a=b\\:c", "b;c"),
			("a=b\\sc", "b c"),
			("a=b\\\\c", "b\\c"),
			("a=b\\rc", "b\rc"),
			("a=b\\nc", "b\nc"),
		]
	)
	func escapeTableIsApplied(_ testCase: (section: String, value: String)) {
		#expect(MessageTagParser.parsedTags(fromSection: testCase.section).tags["a"] == testCase.value)
	}

	/// IRCv3 message-tags: "If a lone `\` exists at the end of an escaped
	/// value (with no escape character following it), then there SHOULD be no
	/// output character."
	@Test("IRCv3 message-tags: a lone trailing backslash produces nothing")
	func loneTrailingBackslashIsDropped() {
		#expect(MessageTagParser.parsedTags(fromSection: "tag1=value1\\").tags["tag1"] == "value1")
		#expect(MessageTagParser.parsedTags(fromSection: "tag1=\\").tags["tag1"] == "")
	}

	/// IRCv3 message-tags: "If a `\` exists with no valid escape character
	/// ... then the invalid backslash SHOULD be dropped."
	@Test("IRCv3 message-tags: an invalid escape drops the backslash")
	func invalidEscapeDropsTheBackslash() {
		#expect(MessageTagParser.parsedTags(fromSection: "tag1=value\\1").tags["tag1"] == "value1")
		#expect(MessageTagParser.parsedTags(fromSection: "tag1=va\\lue").tags["tag1"] == "value")
	}

	/// IRCv3 message-tags: escape sequences are read one character at a time,
	/// so an unescaped `n` after a decoded backslash is not re-read as `\n`.
	@Test("IRCv3 message-tags: decoding never re-reads its own output")
	func decodingIsSinglePass() {
		#expect(MessageTagParser.parsedTags(fromSection: "tag1=value\\\\ntest").tags["tag1"] == "value\\ntest")
	}

	/// IRCv3 message-tags: "Implementations receiving messages with more than
	/// one occurrence of a tag key SHOULD disregard all but the last."
	@Test("IRCv3 message-tags: the last occurrence of a duplicate key wins")
	func lastDuplicateKeyWins() {
		let tags = MessageTagParser.parsedTags(fromSection: "tag1=1;tag2=3;tag3=4;tag1=5").tags

		#expect(tags == ["tag1": "5", "tag2": "3", "tag3": "4"])
	}

	/// IRCv3 message-tags: a vendor-prefixed key is a distinct key, even when
	/// the part after the `/` collides with a plain key.
	@Test("IRCv3 message-tags: a vendored key does not collide with a plain one")
	func vendoredKeysAreDistinct() {
		let tags = MessageTagParser.parsedTags(fromSection: "tag2=3;vendor/tag2=8;example.com/x=1").tags

		#expect(tags == ["tag2": "3", "vendor/tag2": "8", "example.com/x": "1"])
	}

	/// IRCv3 message-tags: "A tag without a value is equivalent to a tag with
	/// an empty value", and both are distinct from the tag being absent.
	@Test("IRCv3 message-tags: a missing value reads as the empty string")
	func missingValueIsEmpty() {
		let tags = MessageTagParser.parsedTags(fromSection: "a;b=;c=1").tags

		#expect(tags == ["a": "", "b": "", "c": "1"])
		#expect(tags["d"] == nil)
	}

	/// IRCv3 message-tags: escapes are only defined for values. A key is taken
	/// as written.
	@Test("IRCv3 message-tags: keys are not unescaped")
	func keysAreNotUnescaped() {
		#expect(MessageTagParser.parsedTags(fromSection: "a\\sb=1").tags["a\\sb"] == "1")
	}

	/// IRCv3 message-tags caps the tag section at 8191 bytes. A section past
	/// the cap is a server that is not playing by the rules and its tags are
	/// dropped wholesale rather than parsed into an unbounded dictionary.
	///
	/// The specification counts the leading `@` and the trailing space inside
	/// that 8191, so the largest conforming section is 8189 bytes; the parser
	/// measures only the section and is therefore two bytes more permissive.
	/// See the report for the deviation.
	@Test("IRCv3 message-tags: the section length cap")
	func sectionLengthCapIsEnforced() {
		#expect(MessageTagParser.maximumSectionLength == 8191)

		let atTheCap = "a=" + String(repeating: "b", count: 8189)
		#expect(atTheCap.utf8.count == 8191)
		#expect(MessageTagParser.parsedTags(fromSection: atTheCap).tags.count == 1)

		let pastTheCap = "a=" + String(repeating: "b", count: 8190)
		#expect(MessageTagParser.parsedTags(fromSection: pastTheCap).tags.isEmpty)
	}

	/// IRCv3 message-tags: a client-only tag is a tag whose key starts with
	/// `+`. The `+` is part of the key on the wire and is stripped only when
	/// the tag is handed to the feature that reads it.
	@Test("IRCv3 message-tags: client-only tags keep their `+` on the wire")
	func clientOnlyTagsKeepTheirPlus() {
		let tags = MessageTagParser.parsedTags(fromSection: "+typing=active;+draft/reply=abc;msgid=1").tags

		#expect(tags["+typing"] == "active")
		#expect(tags["+draft/reply"] == "abc")

		let clientTags = IRCIdentityPolicy.clientTags(from: tags)

		#expect(clientTags == ["typing": "active", "draft/reply": "abc"])
	}

	/// IRCv3 message-tags: `msgid` and `account` are ordinary tags, and an
	/// empty value says nothing rather than naming an empty account.
	@Test("IRCv3 message-tags: empty msgid and account tags are not values")
	func emptyIdentityTagsAreIgnored() {
		let empty = MessageTagParser.parsedTags(fromSection: "msgid=;account=")

		#expect(empty.messageIdentifier == nil)
		#expect(empty.senderAccount == nil)

		let present = MessageTagParser.parsedTags(fromSection: "msgid=abc;account=alice")

		#expect(present.messageIdentifier == "abc")
		#expect(present.senderAccount == "alice")
	}

	/// The tag section and the line it prefixes are parsed together: the tags
	/// stop at the first space, and everything after it is an ordinary line.
	@Test("IRCv3 message-tags: the section ends at the first space")
	func tagSectionEndsAtTheFirstSpace() throws {
		let line = "@id=123;+typing=active :nick!user@host TAGMSG #chan"
		let parsed = try #require(LineParser.parsedLine(fromLine: line))

		#expect(parsed.messageTagSection == "id=123;+typing=active")
		#expect(parsed.senderSection == "nick!user@host")
		#expect(parsed.command == "TAGMSG")
		#expect(parsed.parameters == ["#chan"])
	}

	// MARK: - IRCv3 message-tags, outbound

	/// The escape table again, in the other direction: what the client writes
	/// has to survive a round trip through a conforming parser.
	@Test("IRCv3 message-tags: outbound values are escaped and round trip")
	func outboundTagValuesRoundTrip() throws {
		let tags = ["a": "b\\and\nk", "d": "gh;764", "e": "with space", "f": "carriage\rreturn"]
		let line = SendingMessage.string(command: "TAGMSG", arguments: ["#chan"], tags: tags)
		let parsed = try #require(LineParser.parsedLine(fromLine: line))
		let section = try #require(parsed.messageTagSection)

		#expect(section.contains(" ") == false)
		#expect(section.contains(";") == true)
		#expect(MessageTagParser.parsedTags(fromSection: section).tags == tags)
	}

	/// IRCv3 message-tags: "Implementations MAY normalise tag values by
	/// converting the empty form to the missing form", which is what the
	/// client does, and never the other way around.
	@Test("IRCv3 message-tags: an empty outbound value is written without `=`")
	func emptyOutboundValueIsWrittenWithoutEquals() {
		#expect(SendingMessage.string(messageTags: ["asd": ""]) == "asd")
		#expect(SendingMessage.string(messageTags: ["a": "", "b": "1"]) == "a;b=1")
	}
}
