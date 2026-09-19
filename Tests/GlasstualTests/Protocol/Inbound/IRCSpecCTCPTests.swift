// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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
/// quoting CTCP parameters" — so these tests hold the session to the modern
/// framing rules and pin what it does with a delimiter inside a payload.
@Suite("CTCP")
@MainActor
struct IRCSpecCTCPTests {
	private static let delimiter = "\u{01}"

	private func session(replyingToRequests: Bool = true) -> TestServerSession {
		var settings = ChatSettings()

		settings.replyToCTCPRequests = replyingToRequests

		return TestServerSession(
			configDictionary: ["nickname": "me", "username": "me", "realName": "Me Myself"],
			nicknamePassword: nil,
			fixture: ChatEnvironmentFixture(settings: settings)
		)
	}

	private func deliver(_ line: String, on session: TestServerSession) throws {
		let message = try #require(Message(line: line, on: session))

		session.receivePrivmsgAndNotice(message)
	}

	private func sentLines(of session: TestServerSession) -> [String] {
		session.sentLines.compactMap { $0 as? String }
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
		let closed = InboundTextPolicy.classify(
			command: .privmsg, payload: "\(Self.delimiter)VERSION\(Self.delimiter)"
		)
		let unclosed = InboundTextPolicy.classify(
			command: .privmsg, payload: "\(Self.delimiter)VERSION"
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
		let query = InboundTextPolicy.classify(
			command: .privmsg, payload: "\(Self.delimiter)VERSION\(Self.delimiter)"
		)
		let reply = InboundTextPolicy.classify(
			command: .notice, payload: "\(Self.delimiter)VERSION Some Client\(Self.delimiter)"
		)

		#expect(query.lineType == .ctcpQuery)
		#expect(reply.lineType == .ctcpReply)
	}

	/// A body with no leading delimiter is ordinary text, whatever it contains.
	@Test("An unframed body is ordinary text")
	func unframedBodiesAreOrdinaryText() {
		let plain = InboundTextPolicy.classify(command: .privmsg, payload: "VERSION")

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
		let parsed = try #require(CTCPPolicy.commandAndArguments(from: testCase.text))

		#expect(parsed.rawCommand == testCase.command)
		#expect(parsed.arguments == testCase.arguments)
	}

	/// A frame with no command inside it is not a CTCP message.
	@Test("An empty frame carries no command")
	func emptyFramesCarryNoCommand() {
		#expect(CTCPPolicy.commandAndArguments(from: "") == nil)
		#expect(CTCPPolicy.commandAndArguments(from: " arguments only") == nil)
	}

	// MARK: - ACTION

	/// modern.ircdocs.horse §ACTION: "Sessions MUST implement this CTCP
	/// message." It is `\x01ACTION <text>\x01` and gets no reply.
	@Test("ACTION is framed as a CTCP message and read back as an action")
	func actionIsFramedAndRead() {
		let framed = CTCPPayload.action("waves")

		#expect(framed == "\(Self.delimiter)ACTION waves\(Self.delimiter)")

		let classified = InboundTextPolicy.classify(command: .privmsg, payload: framed)

		#expect(classified.lineType == .action)
		#expect(classified.text == "waves")
	}

	/// ACTION is matched case-insensitively, the way every other CTCP command
	/// is, so `\x01action ...\x01` is still an action rather than an unknown
	/// query the session would answer.
	@Test("ACTION is recognised whatever its case")
	func actionIsCaseInsensitive() {
		let classified = InboundTextPolicy.classify(
			command: .privmsg, payload: "\(Self.delimiter)action waves\(Self.delimiter)"
		)

		#expect(classified.lineType == .action)
		#expect(classified.text == "waves")
	}

	/// An ACTION never earns a reply: it is a message, not a request.
	@Test("ACTION is never answered")
	func actionIsNeverAnswered() throws {
		let session = session()

		try deliver(":alice!a@h PRIVMSG #chan :\(Self.delimiter)ACTION waves\(Self.delimiter)", on: session)

		#expect(sentLines(of: session).isEmpty)
	}

	// MARK: - Replies

	/// modern.ircdocs.horse: a reply is a NOTICE carrying the same command,
	/// and VERSION, PING and TIME are the ones a session must or should answer.
	@Test("VERSION, PING and TIME are answered with a NOTICE carrying the command")
	func standardQueriesAreAnswered() throws {
		let session = session()

		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)VERSION\(Self.delimiter)", on: session)
		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)PING 1234567\(Self.delimiter)", on: session)
		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)TIME\(Self.delimiter)", on: session)
		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)USERINFO\(Self.delimiter)", on: session)

		let lines = sentLines(of: session)

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
		let session = session()

		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)PING 1699999999.123\(Self.delimiter)", on: session)

		#expect(sentLines(of: session) == [
			"NOTICE alice :\(Self.delimiter)PING 1699999999.123\(Self.delimiter)",
		])
	}

	/// An unbounded PING parameter would let anyone use the session as an
	/// amplifier, so an oversized one earns no reply at all.
	@Test("An oversized PING parameter is not echoed")
	func oversizedPingIsNotEchoed() throws {
		let session = session()
		let payload = String(repeating: "9", count: 51)

		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)PING \(payload)\(Self.delimiter)", on: session)

		#expect(sentLines(of: session).isEmpty)
	}

	/// A CTCP the session does not implement gets no reply. modern.ircdocs.horse
	/// lists no error reply for one, and answering would only confirm the
	/// session is there.
	@Test("An unimplemented CTCP command is not answered")
	func unimplementedCommandsAreNotAnswered() throws {
		let session = session()

		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)SOURCE\(Self.delimiter)", on: session)
		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)AVATAR\(Self.delimiter)", on: session)

		#expect(sentLines(of: session).isEmpty)
	}

	/// modern.ircdocs.horse §CLIENTINFO: the reply "is a list of the CTCP
	/// messages this session supports and implements", so every command the
	/// session actually answers has to appear in it.
	@Test("CLIENTINFO lists the CTCP commands the session answers")
	func clientInfoListsWhatIsImplemented() throws {
		let session = session()

		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)CLIENTINFO\(Self.delimiter)", on: session)

		let reply = try #require(sentLines(of: session).first)

		#expect(reply.hasPrefix("NOTICE alice :\(Self.delimiter)CLIENTINFO "))

		for command in ["CLIENTINFO", "PING", "TIME", "USERINFO", "VERSION"] {
			#expect(reply.contains(command), "CLIENTINFO should list \(command)")
		}
	}

	/// A CTCP reply is a NOTICE, and a NOTICE must never produce another
	/// reply, or two sessions would answer each other forever.
	@Test("A CTCP reply is never answered")
	func repliesAreNeverAnswered() throws {
		let session = session()

		try deliver(":alice!a@h NOTICE me :\(Self.delimiter)VERSION Some Client\(Self.delimiter)", on: session)

		#expect(sentLines(of: session).isEmpty)
	}

	/// Answering at all is the user's choice; with replies turned off the
	/// session stays silent.
	@Test("No CTCP is answered when replies are turned off")
	func noRepliesWhenTurnedOff() throws {
		let session = session(replyingToRequests: false)

		try deliver(":alice!a@h PRIVMSG me :\(Self.delimiter)VERSION\(Self.delimiter)", on: session)

		#expect(sentLines(of: session).isEmpty)
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

		let classified = InboundTextPolicy.classify(command: .privmsg, payload: framed)

		#expect(classified.lineType == .action)
		#expect(classified.text == "wavesVERSION")
	}

	/// The same holds for a reply the session sends on the user's behalf: an
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
