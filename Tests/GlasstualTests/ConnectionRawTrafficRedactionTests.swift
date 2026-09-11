/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** The raw traffic window is a transcript of everything the client writes, and
 people paste it into bug reports. Everything the client writes includes the
 server password, the SASL exchange, the oper password and a NickServ
 IDENTIFY — so what the window shows has to say which command went out without
 saying what the credential was. */
@MainActor
@Suite("Raw traffic redaction")
struct ConnectionRawTrafficRedactionTests {
	private let mask = "••••••"

	@Test("A server password is masked and the command stays legible")
	func serverPasswordIsMasked() {
		#expect(ClientWireUtilities.redactedRawLogLine("PASS :hunter2") == "PASS \(mask)")
		#expect(ClientWireUtilities.redactedRawLogLine("PASS hunter2") == "PASS \(mask)")
	}

	/// A bouncer password is several parameters wide (`PASS user/network:pass`
	/// is one form, `PASS pass 0210 ident` another), so none of them survive.
	@Test("Every parameter of a multi-parameter PASS is masked")
	func multiParameterPasswordsAreFullyMasked() {
		let redacted = ClientWireUtilities.redactedRawLogLine("PASS hunter2 0210 ident")

		#expect(redacted == "PASS \(mask)")
		#expect(redacted.contains("hunter2") == false)
		#expect(redacted.contains("ident") == false)
	}

	@Test("A SASL payload is masked, and its two control answers are not")
	func saslPayloadsAreMasked() {
		#expect(ClientWireUtilities.redactedRawLogLine("AUTHENTICATE bWFyYQBtYXJhAHM=") == "AUTHENTICATE \(mask)")
		// "+" is the empty response and "*" aborts: neither carries a secret.
		#expect(ClientWireUtilities.redactedRawLogLine("AUTHENTICATE +") == "AUTHENTICATE +")
		#expect(ClientWireUtilities.redactedRawLogLine("AUTHENTICATE *") == "AUTHENTICATE *")
		/* The mechanism name is what makes the exchange readable at all: masked,
		 the log could not say which mechanism a login failed under. Only the
		 names this client is able to send are spared; anything else is a
		 payload. */
		#expect(ClientWireUtilities.redactedRawLogLine("AUTHENTICATE PLAIN") == "AUTHENTICATE PLAIN")
		#expect(ClientWireUtilities.redactedRawLogLine("AUTHENTICATE EXTERNAL") == "AUTHENTICATE EXTERNAL")
		#expect(
			ClientWireUtilities.redactedRawLogLine("AUTHENTICATE SCRAM-SHA-256")
				== "AUTHENTICATE SCRAM-SHA-256"
		)
		#expect(ClientWireUtilities.redactedRawLogLine("AUTHENTICATE ANONYMOUS") == "AUTHENTICATE \(mask)")
	}

	/// The oper name is not the secret, and losing it would leave the line
	/// saying nothing about which account was used.
	@Test("OPER keeps its account name and loses its password")
	func operPasswordIsMasked() {
		#expect(ClientWireUtilities.redactedRawLogLine("OPER mara hunter2") == "OPER mara \(mask)")
	}

	@Test("A NickServ IDENTIFY is masked whichever command carried it")
	func nickServIdentificationIsMasked() {
		#expect(
			ClientWireUtilities.redactedRawLogLine("PRIVMSG NickServ :IDENTIFY hunter2")
				== "PRIVMSG NickServ :IDENTIFY \(mask)"
		)
		#expect(
			ClientWireUtilities.redactedRawLogLine("NICKSERV IDENTIFY hunter2")
				== "NICKSERV IDENTIFY \(mask)"
		)
		#expect(ClientWireUtilities.redactedRawLogLine("NS IDENTIFY mara hunter2").contains("hunter2") == false)
	}

	/** The redacted line is a log of what went out, so it has to keep the shape
	 that went out. Rebuilding the parameters flat dropped the trailing `:`, and
	 a line that no longer parses the way the wire did is one nobody reading a
	 bug report can match against the server's side of it. */
	@Test("A trailing parameter stays a trailing parameter")
	func trailingParametersKeepTheirColon() {
		#expect(
			ClientWireUtilities.redactedRawLogLine("NICKSERV :IDENTIFY hunter2")
				== "NICKSERV :IDENTIFY \(mask)"
		)
		#expect(
			ClientWireUtilities.redactedRawLogLine("NICKSERV IDENTIFY :hunter2 extra")
				== "NICKSERV IDENTIFY :\(mask) \(mask)"
		)
		#expect(
			ClientWireUtilities.redactedRawLogLine("NS SET PASSWORD :hunter2")
				== "NS SET PASSWORD :\(mask)"
		)
	}

	/// Message tags and a source prefix name nothing secret, and dropping them
	/// would make the logged line stop matching what went out.
	@Test("Tags and a source prefix are kept whole")
	func tagsAndPrefixSurvive() {
		#expect(
			ClientWireUtilities.redactedRawLogLine("@label=42 PRIVMSG NickServ :IDENTIFY hunter2")
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
		#expect(ClientWireUtilities.redactedRawLogLine(line) == line)
	}

	/// A message to somebody who merely happens to start a line with IDENTIFY
	/// is a message, not a credential.
	@Test("A conversation with a person is not treated as a service exchange")
	func messagesToPeopleAreNotRedacted() {
		let line = "PRIVMSG mara :IDENTIFY yourself"

		#expect(ClientWireUtilities.redactedRawLogLine(line) == line)
	}

	/// The window prints what this returns, so the whole path is what matters:
	/// a client with the traffic window open must not log the password.
	@Test("The traffic window prints the redacted line")
	func theWindowPrintsTheRedactedLine() {
		let client = GLTTestClient(configDictionary: ["nickname": "mara"])
		client.createRawDataLogQuery()

		client.rawDataLogOutgoingTraffic("PASS :hunter2")

		let bodies = (client.printedLines as NSArray).compactMap {
			($0 as? [String: Any])?["messageBody"] as? String
		}

		#expect(bodies.contains { $0.contains("hunter2") } == false)
		#expect(bodies.contains { $0.contains(mask) })
	}
}
