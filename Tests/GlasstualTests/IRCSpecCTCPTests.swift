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

/// One CTCP payload and the command and parameters it splits into.
nonisolated struct IRCSpecCTCPSplitCase: CustomTestStringConvertible {
	let text: String
	let command: String
	let arguments: String

	var testDescription: String {
		text.debugDescription
	}
}

/// The Client-To-Client Protocol as modern.ircdocs.horse defines it: a
/// PRIVMSG or NOTICE body wrapped in `0x01`, carrying a command and optional
/// parameters.
///
/// That document deliberately drops the 1994 specification's low-level and
/// CTCP-level quoting — "This document does not include any mechanism for
/// quoting plain text... Likewise, it does not define any mechanism for
/// quoting CTCP parameters" — so these tests hold the client to the modern
/// framing rules and pin what it does with a delimiter inside a payload.
@Suite("CTCP")
@MainActor
struct IRCSpecCTCPTests {
	private static let delimiter = "\u{01}"

	private func client(replyingToRequests: Bool = true) -> GLTTestClient {
		var preferences = ClientPreferences()

		preferences.replyToCTCPRequests = replyingToRequests

		return GLTTestClient(
			configDictionary: ["nickname": "me", "username": "me", "realName": "Me Myself"],
			nicknamePassword: nil,
			fixture: GLTClientEnvironmentFixture(preferences: preferences)
		)
	}

	private func deliver(_ line: String, on client: GLTTestClient) throws {
		let message = try #require(Message(line: line, on: client))

		client.receivePrivmsgAndNotice(message)
	}

	private func sentLines(of client: GLTTestClient) -> [String] {
		client.sentLines.compactMap { $0 as? String }
	}

	// MARK: - Framing

	/// modern.ircdocs.horse §"Message Format": `\x01<command>[ <params>]\x01`.
	@Test("A CTCP message is framed with 0x01 at both ends")
	func messagesAreFramedWithTheDelimiter() {
		let framed = CTCPPayload.framed(command: "VERSION", text: nil, sanitizingLineBreaks: false)

		#expect(framed == "\(Self.delimiter)VERSION\(Self.delimiter)")

		let withText = CTCPPayload.framed(command: "PING", text: "1234", sanitizingLineBreaks: false)

		#expect(withText == "\(Self.delimiter)PING 1234\(Self.delimiter)")
	}

	/// modern.ircdocs.horse: "The final `<delim>` MUST be sent, but parsers
	/// SHOULD accept incoming messages which lack it."
	@Test("A missing closing delimiter is still a CTCP message")
	func aMissingClosingDelimiterIsTolerated() {
		let closed = IRCInboundTextPolicy.classify(
			command: "PRIVMSG", payload: "\(Self.delimiter)VERSION\(Self.delimiter)"
		)
		let unclosed = IRCInboundTextPolicy.classify(
			command: "PRIVMSG", payload: "\(Self.delimiter)VERSION"
		)

		#expect(closed.lineType == .ctcpQuery)
		#expect(closed.text == "VERSION")
		#expect(unclosed.lineType == .ctcpQuery)
		#expect(unclosed.text == "VERSION")
	}

	/// A PRIVMSG carrying a CTCP is a query; the same body in a NOTICE is a
	/// reply, and a reply must never be answered.
	@Test("PRIVMSG carries queries and NOTICE carries replies")
	func queriesAndRepliesAreDistinguished() {
		let query = IRCInboundTextPolicy.classify(
			command: "PRIVMSG", payload: "\(Self.delimiter)VERSION\(Self.delimiter)"
		)
		let reply = IRCInboundTextPolicy.classify(
			command: "NOTICE", payload: "\(Self.delimiter)VERSION Some Client\(Self.delimiter)"
		)

		#expect(query.lineType == .ctcpQuery)
		#expect(reply.lineType == .ctcpReply)
	}

	/// A body with no leading delimiter is ordinary text, whatever it contains.
	@Test("An unframed body is ordinary text")
	func unframedBodiesAreOrdinaryText() {
		let plain = IRCInboundTextPolicy.classify(command: "PRIVMSG", payload: "VERSION")

		#expect(plain.lineType == .privateMessage)
		#expect(plain.text == "VERSION")
	}

	/// modern.ircdocs.horse §"Message Format": the command is the text up to
	/// the first space, and the rest is the parameters, verbatim.
	@Test(
		"The command ends at the first space and the rest is parameters",
		arguments: [
			IRCSpecCTCPSplitCase(text: "VERSION", command: "VERSION", arguments: ""),
			IRCSpecCTCPSplitCase(text: "PING 1234", command: "PING", arguments: "1234"),
			IRCSpecCTCPSplitCase(text: "ping 1234", command: "PING", arguments: "1234"),
			IRCSpecCTCPSplitCase(text: "DCC SEND f 1 2", command: "DCC", arguments: "SEND f 1 2"),
			IRCSpecCTCPSplitCase(text: "PING  two  spaces", command: "PING", arguments: " two  spaces"),
		]
	)
	func commandAndArgumentsSplitAtTheFirstSpace(_ testCase: IRCSpecCTCPSplitCase) throws {
		let parsed = try #require(IRCCTCPPolicy.commandAndArguments(from: testCase.text))

		#expect(parsed.command == testCase.command)
		#expect(parsed.arguments == testCase.arguments)
	}

	/// A frame with no command inside it is not a CTCP message.
	@Test("An empty frame carries no command")
	func emptyFramesCarryNoCommand() {
		#expect(IRCCTCPPolicy.commandAndArguments(from: "") == nil)
		#expect(IRCCTCPPolicy.commandAndArguments(from: " arguments only") == nil)
	}

	// MARK: - ACTION

	/// modern.ircdocs.horse §ACTION: "Clients MUST implement this CTCP
	/// message." It is `\x01ACTION <text>\x01` and gets no reply.
	@Test("ACTION is framed as a CTCP message and read back as an action")
	func actionIsFramedAndRead() {
		let framed = CTCPPayload.action("waves")

		#expect(framed == "\(Self.delimiter)ACTION waves\(Self.delimiter)")

		let classified = IRCInboundTextPolicy.classify(command: "PRIVMSG", payload: framed)

		#expect(classified.lineType == .action)
		#expect(classified.text == "waves")
	}

	/// ACTION is matched case-insensitively, the way every other CTCP command
	/// is, so `\x01action ...\x01` is still an action rather than an unknown
	/// query the client would answer.
	@Test("ACTION is recognised whatever its case")
	func actionIsCaseInsensitive() {
		let classified = IRCInboundTextPolicy.classify(
			command: "PRIVMSG", payload: "\(Self.delimiter)action waves\(Self.delimiter)"
		)

		#expect(classified.lineType == .action)
		#expect(classified.text == "waves")
	}

	/// An ACTION never earns a reply: it is a message, not a request.
	@Test("ACTION is never answered")
	func actionIsNeverAnswered() throws {
		let client = client()

		try deliver(":alice!a@h PRIVMSG #chan :\(Self.delimiter)ACTION waves\(Self.delimiter)", on: client)

		#expect(sentLines(of: client).isEmpty)
	}

	// MARK: - Replies

	/// modern.ircdocs.horse: a reply is a NOTICE carrying the same command,
	/// and VERSION, PING and TIME are the ones a client must or should answer.
	@Test("VERSION, PING and TIME are answered with a NOTICE carrying the command")
	func standardQueriesAreAnswered() throws {
		let client = client()

		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)VERSION\(Self.delimiter)", on: client)
		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)PING 1234567\(Self.delimiter)", on: client)
		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)TIME\(Self.delimiter)", on: client)
		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)USERINFO\(Self.delimiter)", on: client)

		let lines = sentLines(of: client)

		#expect(lines.count == 4)
		#expect(lines.allSatisfy { $0.hasPrefix("NOTICE alice :\(Self.delimiter)") })
		#expect(lines[0].contains("\(Self.delimiter)VERSION "))
		#expect(lines[2].contains("\(Self.delimiter)TIME "))
		#expect(lines[3].contains("Me Myself"))
	}

	/// modern.ircdocs.horse §PING: "the reply ... MUST contain the same
	/// parameters as the query", so the sender can measure the round trip.
	@Test("PING echoes its parameter unchanged")
	func pingEchoesItsParameter() throws {
		let client = client()

		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)PING 1699999999.123\(Self.delimiter)", on: client)

		#expect(sentLines(of: client) == [
			"NOTICE alice :\(Self.delimiter)PING 1699999999.123\(Self.delimiter)",
		])
	}

	/// An unbounded PING parameter would let anyone use the client as an
	/// amplifier, so an oversized one earns no reply at all.
	@Test("An oversized PING parameter is not echoed")
	func oversizedPingIsNotEchoed() throws {
		let client = client()
		let payload = String(repeating: "9", count: 51)

		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)PING \(payload)\(Self.delimiter)", on: client)

		#expect(sentLines(of: client).isEmpty)
	}

	/// A CTCP the client does not implement gets no reply. modern.ircdocs.horse
	/// lists no error reply for one, and answering would only confirm the
	/// client is there.
	@Test("An unimplemented CTCP command is not answered")
	func unimplementedCommandsAreNotAnswered() throws {
		let client = client()

		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)SOURCE\(Self.delimiter)", on: client)
		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)AVATAR\(Self.delimiter)", on: client)

		#expect(sentLines(of: client).isEmpty)
	}

	/// modern.ircdocs.horse §CLIENTINFO: the reply "is a list of the CTCP
	/// messages this client supports and implements", so every command the
	/// client actually answers has to appear in it.
	@Test("CLIENTINFO lists the CTCP commands the client answers")
	func clientInfoListsWhatIsImplemented() throws {
		let client = client()

		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)CLIENTINFO\(Self.delimiter)", on: client)

		let reply = try #require(sentLines(of: client).first)

		#expect(reply.hasPrefix("NOTICE alice :\(Self.delimiter)CLIENTINFO "))

		for command in ["CLIENTINFO", "PING", "TIME", "USERINFO", "VERSION"] {
			#expect(reply.contains(command), "CLIENTINFO should list \(command)")
		}
	}

	/// A CTCP reply is a NOTICE, and a NOTICE must never produce another
	/// reply, or two clients would answer each other forever.
	@Test("A CTCP reply is never answered")
	func repliesAreNeverAnswered() throws {
		let client = client()

		try deliver(":alice!a@h NOTICE me :\(Self.delimiter)VERSION Some Client\(Self.delimiter)", on: client)

		#expect(sentLines(of: client).isEmpty)
	}

	/// Answering at all is the user's choice; with replies turned off the
	/// client stays silent.
	@Test("No CTCP is answered when replies are turned off")
	func noRepliesWhenTurnedOff() throws {
		let client = client(replyingToRequests: false)

		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)VERSION\(Self.delimiter)", on: client)

		#expect(sentLines(of: client).isEmpty)
	}

	// MARK: - Delimiters inside a payload

	/// modern.ircdocs.horse defines no way to quote a delimiter inside a CTCP
	/// message, so one that reached the wire would end the frame early at the
	/// receiver: the tail is dropped and what follows reads as a second
	/// extended message. The only way to send the text the user wrote is to
	/// remove the delimiter.
	@Test("A delimiter inside an outbound payload is removed")
	func delimitersInsideOutboundPayloadsAreRemoved() {
		let framed = CTCPPayload.action("waves\(Self.delimiter)VERSION")

		#expect(framed == "\(Self.delimiter)ACTION wavesVERSION\(Self.delimiter)")

		let classified = IRCInboundTextPolicy.classify(command: "PRIVMSG", payload: framed)

		#expect(classified.lineType == .action)
		#expect(classified.text == "wavesVERSION")
	}

	/// The same holds for a reply the client sends on the user's behalf: an
	/// echoed PING parameter must not be able to close the frame.
	@Test("A delimiter cannot be smuggled through a CTCP reply")
	func delimitersCannotBeSmuggledThroughAReply() {
		let framed = CTCPPayload.framed(
			command: "VERSION",
			text: "first\(Self.delimiter)\(Self.delimiter)second",
			sanitizingLineBreaks: true
		)

		#expect(framed == "\(Self.delimiter)VERSION firstsecond\(Self.delimiter)")
		#expect(framed.filter { String($0) == Self.delimiter }.count == 2)
	}

	/// A CTCP reply may not carry a line break: the reply is one line, and a
	/// payload that split it would let a request forge a second command.
	@Test("A line break in a reply payload cannot split the line")
	func lineBreaksInRepliesCannotSplitTheLine() {
		let framed = CTCPPayload.framed(
			command: "VERSION", text: "first\r\nPRIVMSG #chan :second", sanitizingLineBreaks: true
		)

		#expect(framed.contains("\r") == false)
		#expect(framed.contains("\n") == false)
	}
}
