// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** The raw traffic window is a transcript of everything the session writes, and
 people paste it into bug reports. Everything the session writes includes the
 server password, the SASL exchange, the oper password and a NickServ
 IDENTIFY — so what the window shows has to say which command went out without
 saying what the credential was. */
@MainActor
@Suite("Raw traffic redaction")
struct WireRedactionTests {
	private let mask = "••••••"

	@Test("A server password is masked and the command stays legible")
	func serverPasswordIsMasked() {
		#expect(WireRedaction.redactedRawChatLine("PASS :hunter2") == "PASS \(mask)")
		#expect(WireRedaction.redactedRawChatLine("PASS hunter2") == "PASS \(mask)")
	}

	/// A bouncer password is several parameters wide (`PASS user/network:pass`
	/// is one form, `PASS pass 0210 ident` another), so none of them survive.
	@Test("Every parameter of a multi-parameter PASS is masked")
	func multiParameterPasswordsAreFullyMasked() {
		let redacted = WireRedaction.redactedRawChatLine("PASS hunter2 0210 ident")

		#expect(redacted == "PASS \(mask)")
		#expect(redacted.contains("hunter2") == false)
		#expect(redacted.contains("ident") == false)
	}

	@Test("A SASL payload is masked, and its two control answers are not")
	func saslPayloadsAreMasked() {
		#expect(WireRedaction.redactedRawChatLine("AUTHENTICATE bWFyYQBtYXJhAHM=") == "AUTHENTICATE \(mask)")
		// "+" is the empty response and "*" aborts: neither carries a secret.
		#expect(WireRedaction.redactedRawChatLine("AUTHENTICATE +") == "AUTHENTICATE +")
		#expect(WireRedaction.redactedRawChatLine("AUTHENTICATE *") == "AUTHENTICATE *")
		/* The mechanism name is what makes the exchange readable at all: masked,
		 the log could not say which mechanism a login failed under. Only the
		 names this session is able to send are spared; anything else is a
		 payload. */
		#expect(WireRedaction.redactedRawChatLine("AUTHENTICATE PLAIN") == "AUTHENTICATE PLAIN")
		#expect(WireRedaction.redactedRawChatLine("AUTHENTICATE EXTERNAL") == "AUTHENTICATE EXTERNAL")
		#expect(
			WireRedaction.redactedRawChatLine("AUTHENTICATE SCRAM-SHA-256")
				== "AUTHENTICATE SCRAM-SHA-256"
		)
		#expect(WireRedaction.redactedRawChatLine("AUTHENTICATE ANONYMOUS") == "AUTHENTICATE \(mask)")
	}

	/// The oper name is not the secret, and losing it would leave the line
	/// saying nothing about which account was used.
	@Test("OPER keeps its account name and loses its password")
	func operPasswordIsMasked() {
		#expect(WireRedaction.redactedRawChatLine("OPER mara hunter2") == "OPER mara \(mask)")
	}

	@Test("A NickServ IDENTIFY is masked whichever command carried it")
	func nickServIdentificationIsMasked() {
		#expect(
			WireRedaction.redactedRawChatLine("PRIVMSG NickServ :IDENTIFY hunter2")
				== "PRIVMSG NickServ :IDENTIFY \(mask)"
		)
		#expect(
			WireRedaction.redactedRawChatLine("NICKSERV IDENTIFY hunter2")
				== "NICKSERV IDENTIFY \(mask)"
		)
		#expect(WireRedaction.redactedRawChatLine("NS IDENTIFY mara hunter2").contains("hunter2") == false)
	}

	/** The redacted line is a log of what went out, so it has to keep the shape
	 that went out. Rebuilding the parameters flat dropped the trailing `:`, and
	 a line that no longer parses the way the wire did is one nobody reading a
	 bug report can match against the server's side of it. */
	@Test("A trailing parameter stays a trailing parameter")
	func trailingParametersKeepTheirColon() {
		#expect(
			WireRedaction.redactedRawChatLine("NICKSERV :IDENTIFY hunter2")
				== "NICKSERV :IDENTIFY \(mask)"
		)
		#expect(
			WireRedaction.redactedRawChatLine("NICKSERV IDENTIFY :hunter2 extra")
				== "NICKSERV IDENTIFY :\(mask) \(mask)"
		)
		#expect(
			WireRedaction.redactedRawChatLine("NS SET PASSWORD :hunter2")
				== "NS SET PASSWORD :\(mask)"
		)
	}

	/// Message tags and a source prefix name nothing secret, and dropping them
	/// would make the logged line stop matching what went out.
	@Test("Tags and a source prefix are kept whole")
	func tagsAndPrefixSurvive() {
		#expect(
			WireRedaction.redactedRawChatLine("@label=42 PRIVMSG NickServ :IDENTIFY hunter2")
				== "@label=42 PRIVMSG NickServ :IDENTIFY \(mask)"
		)
	}

	/// Redaction that rewrote ordinary traffic would make the window useless
	/// for the thing it exists for.
	@Test(arguments: [
		"PRIVMSG #glasstual :hello there",
		"JOIN #glasstual",
		"CAP REQ :sasl multi-prefix",
		"PING irc.example.net",
		"",
	])
	func ordinaryTrafficIsUntouched(_ line: String) {
		#expect(WireRedaction.redactedRawChatLine(line) == line)
	}

	/// A message to somebody who merely happens to start a line with IDENTIFY
	/// is a message, not a credential.
	@Test("A conversation with a person is not treated as a service exchange")
	func messagesToPeopleAreNotRedacted() {
		let line = "PRIVMSG mara :IDENTIFY yourself"

		#expect(WireRedaction.redactedRawChatLine(line) == line)
	}

	/// The window prints what this returns, so the whole path is what matters:
	/// a session with the traffic window open must not log the password.
	@Test("The traffic window prints the redacted line")
	func theWindowPrintsTheRedactedLine() {
		let session = TestServerSession(configDictionary: ["nickname": "mara"])
		session.createRawDataLogConsole()

		session.rawDataLogOutgoingTraffic("PASS :hunter2")

		let bodies = (session.printedLines as NSArray).compactMap {
			($0 as? [String: Any])?["messageBody"] as? String
		}

		#expect(bodies.contains { $0.contains("hunter2") } == false)
		#expect(bodies.contains { $0.contains(mask) })
	}

	/// `echo-message` sends the session's own `IDENTIFY` back, so incoming
	/// traffic carries the password too.
	@Test("The traffic window masks an echoed identification")
	func theWindowMasksIncomingCredentials() {
		let session = TestServerSession(configDictionary: ["nickname": "mara"])
		session.createRawDataLogConsole()

		session.rawDataLogIncomingTraffic("@msgid=abc :mara!m@host PRIVMSG NickServ :IDENTIFY hunter2")

		let bodies = (session.printedLines as NSArray).compactMap {
			($0 as? [String: Any])?["messageBody"] as? String
		}

		#expect(bodies.contains { $0.contains("hunter2") } == false)
		#expect(bodies.contains { $0.hasPrefix(">> @msgid=abc :mara!m@host PRIVMSG NickServ :IDENTIFY") })
	}

	@Test("A credential sent to services is redacted without changing its spacing")
	func serviceCredentialsAreRedactedWithoutChangingSpacing() {
		#expect(
			WireRedaction.redactedServiceMessage("IDENTIFY hunter2", sentTo: "NickServ")
				== "IDENTIFY ••••••"
		)
		#expect(
			WireRedaction.redactedServiceMessage("SET PASSWORD old  new", sentTo: "Q@CServe.quakenet.org")
				== "SET PASSWORD ••••••  ••••••"
		)
		#expect(
			WireRedaction.redactedServiceMessage("SET EMAIL me@example.com", sentTo: "NickServ")
				== "SET EMAIL me@example.com"
		)
		#expect(
			WireRedaction.redactedServiceMessage("IDENTIFY hunter2", sentTo: "friend")
				== "IDENTIFY hunter2"
		)
	}
}
