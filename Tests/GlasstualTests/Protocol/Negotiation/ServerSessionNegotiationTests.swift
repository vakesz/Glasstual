// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Server session capability negotiation")
struct ServerSessionNegotiationTests {
	@Test("Grouped requests fit the wire budget and preserve order")
	func groupedRequestsRespectByteLimit() {
		let names = (0 ..< 80).map { "vendor/capability-\($0)" }
		let groups = CapabilityRequestBatching.groups(names)
		#expect(groups.count > 1)
		#expect(groups.flatMap(\.self) == names)
		#expect(groups.allSatisfy { "CAP REQ :\($0.joined(separator: " "))\r\n".utf8.count <= 512 })
	}

	@Test("Disabling SASL skips negotiation while retaining the password for NickServ")
	func disabledSASLKeepsPassword() throws {
		let session = makeSession(configuration: ["usesSASL": false], nicknamePassword: "secret")
		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=PLAIN,SCRAM-SHA-256,EXTERNAL",
			on: session
		))
		#expect(capabilityCommands(of: session) == ["END"])
		#expect(session.sasl.mechanism == nil)
		#expect(session.config.nicknamePassword == "secret")
	}

	@Test("A continued capability listing is not answered until the last line arrives")
	func capabilityListContinuationDefersRequests() throws {
		let session = TestServerSession()

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS * :multi-prefix sasl=PLAIN,EXTERNAL",
			on: session
		))

		#expect(session.sentCapabilityCommands.count == 0)
		#expect(session.capabilityNegotiation.outstandingRequests.isEmpty)

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :server-time message-tags example.com/vendor",
			on: session
		))

		/* Every request the completed listing makes eligible goes out at once,
		 so one that is never answered cannot hold back the rest. */
		#expect(capabilityCommands(of: session) == ["REQ message-tags multi-prefix server-time"])
		#expect(session.capabilityNegotiation.outstandingRequests == ["message-tags", "multi-prefix", "server-time"])
	}

	@Test("An acknowledgement enables the capability and asks for the next one")
	func acknowledgementEnablesCapabilityAndContinuesNegotiation() throws {
		let session = TestServerSession()

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :multi-prefix server-time",
			on: session
		))
		#expect(capabilityCommands(of: session) == ["REQ multi-prefix server-time"])

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me ACK :multi-prefix",
			on: session
		))

		#expect(session.isCapabilityEnabled(.multiPrefix))
		#expect(session.isCapabilityEnabled(.serverTime) == false)
		// One answer arriving does not close a negotiation the other still holds.
		#expect(session.capabilityNegotiation.outstandingRequests == ["server-time"])

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me NAK :server-time",
			on: session
		))

		#expect(session.isCapabilityEnabled(.serverTime) == false)
		#expect(capabilityCommands(of: session).last == "END")
		#expect(session.enabledCapabilitiesStringValue == "multi-prefix")
	}

	@Test("A vendor spelling of server-time enables the generic capability")
	func vendorServerTimeEnablesGenericBit() throws {
		let session = TestServerSession()

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :znc.in/server-time-iso",
			on: session
		))
		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me ACK :znc.in/server-time-iso",
			on: session
		))

		#expect(session.isCapabilityEnabled(.serverTime))

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me DEL :znc.in/server-time-iso",
			on: session
		))

		#expect(session.isCapabilityEnabled(.serverTime) == false)
	}

	@Test("SASL is requested when the session has a password to send")
	func saslIsRequestedWhenPasswordIsConfigured() throws {
		let session = makeSession(
			configuration: ["nickname": "me", "username": "me"],
			nicknamePassword: "secret"
		)

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=PLAIN,EXTERNAL",
			on: session
		))
		#expect(capabilityCommands(of: session) == ["REQ sasl"])

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me ACK :sasl",
			on: session
		))

		#expect(session.isCapabilityEnabled(.isInSASLNegotiation))
		#expect(capabilityCommands(of: session) == ["REQ sasl"])
	}

	@Test("Negotiation ends when the server offers no mechanism the session speaks")
	func saslIsSkippedWhenOnlyUnsupportedMechanismsAreOffered() throws {
		let session = makeSession(configuration: [:], nicknamePassword: "secret")

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=SCRAM-SHA-512,GSSAPI",
			on: session
		))

		#expect(capabilityCommands(of: session) == ["END"])
	}

	@Test("SCRAM is preferred over PLAIN when both are offered")
	func scramIsPreferredOverPlain() {
		let session = makeSession(configuration: ["nickname": "me"], nicknamePassword: "secret")

		#expect(session.selectSASLMechanism(fromOffered: ["PLAIN", "SCRAM-SHA-256"]))
		#expect(session.sasl.mechanism == "SCRAM-SHA-256")
	}

	@Test("PLAIN is chosen when SCRAM is not offered")
	func plainIsChosenWhenSCRAMIsNotOffered() {
		let session = makeSession(configuration: ["nickname": "me"], nicknamePassword: "secret")

		#expect(session.selectSASLMechanism(fromOffered: ["PLAIN"]))
		#expect(session.sasl.mechanism == "PLAIN")
	}

	@Test("A retry moves to the next mechanism and never repeats one")
	func saslMechsRetryMovesToNextMechanism() {
		let session = makeSession(configuration: ["nickname": "me"], nicknamePassword: "secret")
		_ = session.selectSASLMechanism(fromOffered: ["PLAIN", "SCRAM-SHA-256"])

		#expect(session.sasl.mechanism == "SCRAM-SHA-256")
		#expect(session.retrySASLNegotiation(withMechanisms: ["PLAIN"]))
		#expect(session.sasl.mechanism == "PLAIN")
		#expect(session.sasl.triedMechanisms.contains("SCRAM-SHA-256"))
		#expect(session.retrySASLNegotiation(withMechanisms: ["PLAIN"]) == false)
	}

	@Test("Nested batches are replayed in the order the server sent them")
	func nestedBatchesAreReplayedInOrder() throws {
		let session = TestServerSession()
		session.enableCapability(.batch)
		let lines = [
			":irc.example.net BATCH +outer example.com/outer",
			"@batch=outer :irc.example.net BATCH +inner example.com/inner",
			"@batch=inner :a!u@h PRIVMSG #c :one",
			"@batch=outer :b!u@h PRIVMSG #c :two",
			"@batch=inner :c!u@h PRIVMSG #c :three",
			":irc.example.net BATCH -inner",
			"@batch=outer :d!u@h PRIVMSG #c :four",
			":irc.example.net BATCH -outer",
		]

		for line in lines {
			let parsedMessage = try message(line, on: session)

			if session.filterBatchCommandIncomingData(parsedMessage) {
				continue
			}

			if parsedMessage.command == "BATCH" {
				session.receiveBatch(parsedMessage)
			} else {
				session.processIncomingMessage(parsedMessage)
			}
		}

		let bodies = session.processedMessages.map(\.sequence)

		#expect(bodies == ["one", "two", "three", "four"])
	}

	@Test("A message tagged with an unknown batch is delivered rather than queued")
	func messagesOutsideAnOpenBatchAreNotQueued() throws {
		let session = TestServerSession()
		session.enableCapability(.batch)

		let filtered = try session.filterBatchCommandIncomingData(message(
			"@batch=unknown :a!u@h PRIVMSG #c :hi",
			on: session
		))

		#expect(filtered == false)
	}

	@Test("A standard reply is printed to the channel it names, or to the console")
	func standardRepliesArePrintedToConsoleOrChannel() throws {
		let session = TestServerSession()

		try session.receiveStandardReply(message(
			":irc.example.net FAIL BOX BOXES_INVALID STACK CLOCKWISE :Given boxes are not supported",
			on: session
		))

		#expect(session.printedLines.count == 1)
		try expectPrintedLine(
			at: 0,
			on: session,
			body: "FAIL BOX/BOXES_INVALID: Given boxes are not supported",
			type: .debug,
			channel: nil
		)

		try session.receiveStandardReply(message(
			":irc.example.net NOTE * OPER_MESSAGE :The message",
			on: session
		))
		try expectPrintedLine(
			at: 1,
			on: session,
			body: "NOTE */OPER_MESSAGE: The message",
			type: .notice,
			channel: nil
		)

		let channel = try #require(session.findConversationOrCreate("#chat"))
		try session.receiveStandardReply(message(
			":irc.example.net WARN REHASH CERTS_EXPIRED #chat :Certificate has expired",
			on: session
		))
		try expectPrintedLine(
			at: 2,
			on: session,
			body: "WARN REHASH/CERTS_EXPIRED: Certificate has expired",
			type: .notice,
			channel: channel
		)

		try session.receiveStandardReply(message(
			":irc.example.net WARN REHASH CERTS_EXPIRED #other :Certificate has expired",
			on: session
		))

		let unmatched = try #require(printedLine(at: 3, on: session))

		#expect(unmatched["channel"] == nil)
	}

	@Test("A tag message is only sent once message tags are negotiated")
	func tagMessageIsOnlySentWithMessageTagsEnabled() {
		let session = TestServerSession()
		let typing = ["+typing": "active"]

		#expect(session.sendTagMessage(typing, toTarget: "#c") == false)
		#expect(session.sentLines.count == 0)

		session.enableCapability(.messageTags)

		#expect(session.sendTagMessage(typing, toTarget: "#c"))
		#expect(sentLines(of: session) == ["@+typing=active TAGMSG #c"])
		#expect(session.sendTagMessage([:], toTarget: "#c") == false)
	}

	/// `CLIENTTAGDENY` names the client-only tags the server will not relay; a
	/// TAGMSG made of one is not sent, and a command keeps only the tags left.
	@Test("A client-only tag the server denies is not sent", arguments: [
		"CLIENTTAGDENY=typing",
		"CLIENTTAGDENY=*,-draft/reply",
	])
	func deniedClientTagsAreNotSent(denyToken: String) {
		let session = TestServerSession()
		session.enableCapability(.messageTags)
		session.supportInfo.processConfigurationData(denyToken)

		#expect(session.sendTagMessage(["+typing": "active"], toTarget: "#c") == false)
		#expect(session.sendTagMessage(["+typing": "active", "+draft/reply": "abc"], toTarget: "#c") == false)
		#expect(session.sentLines.count == 0)

		session.sendCommand(.privmsg, arguments: ["#c", "hello"], tags: ["+typing": "active", "+draft/reply": "abc"])

		#expect(sentLines(of: session) == ["@+draft/reply=abc PRIVMSG #c :hello"])
	}

	@Test("Typing notifications are unavailable where the server denies the typing tag")
	func typingNotificationsFollowClientTagDeny() throws {
		let session = TestServerSession()
		session.markAsLoggedIn()
		session.enableCapability(.messageTags)
		let channel = try #require(session.findConversationOrCreate("#c"))

		#expect(session.typingNotificationsAvailable(for: channel))

		session.supportInfo.processConfigurationData("CLIENTTAGDENY=typing")

		#expect(session.typingNotificationsAvailable(for: channel) == false)
	}

	@Test("Tags are dropped from a command until message tags are negotiated")
	func tagsAreDroppedFromCommandsWithoutMessageTags() {
		let session = TestServerSession()

		session.sendCommand(.privmsg, arguments: ["#c", "hello"], tags: ["+draft/reply": "abc"])
		#expect(sentLines(of: session) == ["PRIVMSG #c :hello"])

		session.enableCapability(.messageTags)
		session.sendCommand(.privmsg, arguments: ["#c", "hello"], tags: ["+draft/reply": "abc"])

		#expect(sentLines(of: session).last == "@+draft/reply=abc PRIVMSG #c :hello")
	}

	@Test("A received tag message carrying no client-only tag prints nothing")
	func receivedTagMessageWithoutClientTagsIsIgnored() throws {
		let session = TestServerSession()

		try session.receiveTagMessage(message("@msgid=1 :a!u@h TAGMSG #c", on: session))
		try session.receiveTagMessage(message("@+typing=active;msgid=2 :a!u@h TAGMSG #c", on: session))

		#expect(session.printedLines.count == 0)
	}

	// MARK: - SASL bounds

	/** `AUTHENTICATE` has no reply the protocol obliges the server to send, so a
	 server that acknowledges `sasl` and then says nothing left capability
	 negotiation paused with `CAP END` unsent. Nothing noticed until the
	 four-minute retry timer took the whole connection down, which reads to the
	 user as the network being broken rather than as authentication failing. */
	@Test("Acknowledging SASL starts a deadline, and answering it stops one")
	func saslNegotiationIsBounded() throws {
		let session = makeSession(configuration: ["usesSASL": true], nicknamePassword: "secret")
		defer { session.stopAllTimers() }
		session.setConnectionTransportForTesting(.connected)

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=PLAIN",
			on: session
		))
		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * ACK :sasl",
			on: session
		))

		#expect(session.isCapabilityEnabled(.isInSASLNegotiation))
		#expect(session.sasl.timeoutTimer.isActive)

		session.finishSASLNegotiation(failed: false)

		#expect(session.sasl.timeoutTimer.isActive == false)
	}

	/** The deadline bounds the wait for the server's next word, not the exchange
	 as a whole. SCRAM is three challenges, each of which the session answers and
	 then waits again; armed once, the last round got whatever was left of the
	 thirty seconds the first one had already spent. */
	@Test("Every AUTHENTICATE the server sends re-arms the deadline")
	func eachSASLRoundIsBounded() throws {
		let session = makeSession(configuration: ["usesSASL": true], nicknamePassword: "secret")
		defer { session.stopAllTimers() }
		session.setConnectionTransportForTesting(.connected)

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=PLAIN",
			on: session
		))
		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * ACK :sasl",
			on: session
		))

		#expect(session.sasl.timeoutTimer.isActive)

		/* Stopped so that the next round having its own deadline is what the
		 assertion sees, rather than the one the request already armed. */
		session.stopSASLTimeoutTimer()

		#expect(session.sasl.timeoutTimer.isActive == false)

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net AUTHENTICATE +",
			on: session
		))

		#expect(session.isCapabilityEnabled(.isInSASLNegotiation))
		#expect(session.sasl.timeoutTimer.isActive)
	}

	/// Giving up has to leave registration able to finish: the deadline aborts
	/// the exchange and lets capability negotiation run to `CAP END`.
	@Test("The deadline aborts SASL and lets registration continue")
	func saslDeadlineAbortsAndContinues() throws {
		let session = makeSession(configuration: ["usesSASL": true], nicknamePassword: "secret")
		defer { session.stopAllTimers() }
		session.setConnectionTransportForTesting(.connected)
		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=PLAIN",
			on: session
		))
		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * ACK :sasl",
			on: session
		))

		session.onSASLTimeoutTimer()

		#expect(session.isCapabilityEnabled(.isInSASLNegotiation) == false)
		#expect(session.isCapabilityEnabled(.isIdentifiedWithSASL) == false)
		#expect(session.sasl.timeoutTimer.isActive == false)
		#expect(sentLines(of: session).contains { $0.hasPrefix("AUTHENTICATE") && $0.hasSuffix("*") })
		#expect(capabilityCommands(of: session).contains("END"))
		expectPrintedLineContaining(ConnectionSafetyStrings.SASL.timedOut, on: session)
	}

	/// A server that offered no mechanism this session can speak gets no
	/// deadline either, because nothing was ever asked of it.
	@Test("No deadline runs when SASL was never requested")
	func noDeadlineWithoutSASL() throws {
		let session = makeSession(configuration: ["usesSASL": false], nicknamePassword: "secret")
		defer { session.stopAllTimers() }

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=PLAIN",
			on: session
		))

		#expect(session.sasl.timeoutTimer.isActive == false)
	}

	/** PLAIN is three fields separated by U+0000. A field containing one splits
	 somewhere else on the server, which either authenticates as a name the user
	 did not type or sends the tail of the password as a separate field. */
	@Test("A credential containing a null character is refused rather than sent")
	func nullCharactersInCredentialsAbortSASL() throws {
		let session = makeSession(configuration: ["usesSASL": true], nicknamePassword: "hunter\u{0}2")
		defer { session.stopAllTimers() }
		session.setConnectionTransportForTesting(.connected)
		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=PLAIN",
			on: session
		))
		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * ACK :sasl",
			on: session
		))

		try session.handleCapabilityOrAuthenticationRequest(message("AUTHENTICATE +", on: session))

		let lines = sentLines(of: session)

		#expect(lines.contains { $0.contains("hunter") } == false)
		#expect(lines.contains { $0.hasPrefix("AUTHENTICATE") && $0.hasSuffix("*") })
		#expect(session.isCapabilityEnabled(.isInSASLNegotiation) == false)
		expectPrintedLineContaining(
			ConnectionSafetyStrings.SASL.credentialsContainNullCharacter, on: session
		)
	}

	/** Asking whether SASL can be requested is a question. It is asked again on
	 every `CAP NEW` and `CAP DEL`, so choosing the mechanism inside it let a
	 late advertisement replace the mechanism of an exchange already in flight —
	 and the reply the session then sent belonged to neither. */
	@Test("A late SASL advertisement does not replace an in-flight mechanism")
	func aLateAdvertisementDoesNotReplaceTheMechanism() throws {
		let session = makeSession(
			configuration: ["usesSASL": true, "saslMechanismPreference": "SCRAM-SHA-256"],
			nicknamePassword: "secret"
		)
		defer { session.stopAllTimers() }
		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=SCRAM-SHA-256,PLAIN",
			on: session
		))
		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * ACK :sasl",
			on: session
		))

		let chosen = session.sasl.mechanism

		#expect(chosen == SCRAMClient.mechanismName)

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * NEW :sasl=PLAIN",
			on: session
		))

		#expect(session.sasl.mechanism == chosen)
	}

	/** A 904 refuses one attempt, not the login. A certificate the account does
	 not know fails EXTERNAL while the password would still pass, so the session
	 moves on to the next mechanism both sides speak and only gives up when none
	 is left. */
	@Test("A refused mechanism falls back to the next one before negotiation ends")
	func refusedMechanismFallsBack() throws {
		let session = makeSession(
			configuration: ["usesSASL": true, "saslMechanismPreference": "PLAIN"],
			nicknamePassword: "secret"
		)
		defer { session.stopAllTimers() }
		session.setConnectionTransportForTesting(.connected)
		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=PLAIN,SCRAM-SHA-256",
			on: session
		))
		try session.handleCapabilityOrAuthenticationRequest(message(":irc.example.net CAP * ACK :sasl", on: session))
		try #require(session.sasl.mechanism == "PLAIN")

		try receiveAuthenticationNumeric(":irc.example.net 904 me :SASL authentication failed", on: session)

		#expect(session.sasl.mechanism == SCRAMClient.mechanismName)
		#expect(sentLines(of: session).last == "AUTHENTICATE \(SCRAMClient.mechanismName)")
		#expect(session.isCapabilityEnabled(.isInSASLNegotiation))
		#expect(capabilityCommands(of: session).contains("END") == false)

		try receiveAuthenticationNumeric(":irc.example.net 904 me :SASL authentication failed", on: session)

		#expect(session.isCapabilityEnabled(.isInSASLNegotiation) == false)
		#expect(capabilityCommands(of: session).last == "END")
	}

	/** Once SASL has finished, a 900 answers something else — a NickServ
	 `IDENTIFY` after the login failed — and the SCRAM check that guards the
	 exchange must not turn it away on the strength of a leftover mechanism. */
	@Test("A 900 after a failed SCRAM exchange confirms the account")
	func loggedInAfterFailedSCRAMIsBelieved() throws {
		let session = makeSession(
			configuration: ["nickname": "me", "usesSASL": true, "saslMechanismPreference": SCRAMClient.mechanismName],
			nicknamePassword: "secret"
		)
		defer { session.stopAllTimers() }
		session.setConnectionTransportForTesting(.connected)
		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :sasl=SCRAM-SHA-256",
			on: session
		))
		try session.handleCapabilityOrAuthenticationRequest(message(":irc.example.net CAP * ACK :sasl", on: session))
		try receiveAuthenticationNumeric(":irc.example.net 904 me :SASL authentication failed", on: session)
		try #require(session.isCapabilityEnabled(.isInSASLNegotiation) == false)

		#expect(session.sasl.mechanism == nil)

		try receiveAuthenticationNumeric(
			":irc.example.net 900 me me!u@host account :You are now logged in as account",
			on: session
		)

		#expect(session.startup.authentication == .confirmed)
	}

	/// A `CAP REQ` line is granted or refused whole. Refusing a line of several
	/// names says nothing about which one was the problem.
	@Test("A refused group of capabilities is asked for again one name at a time")
	func refusedGroupIsRequestedIndividually() throws {
		let session = TestServerSession()

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP * LS :multi-prefix server-time",
			on: session
		))
		#expect(capabilityCommands(of: session) == ["REQ multi-prefix server-time"])

		try session.handleCapabilityOrAuthenticationRequest(message(
			":irc.example.net CAP me NAK :multi-prefix server-time",
			on: session
		))

		#expect(capabilityCommands(of: session).dropFirst() == ["REQ multi-prefix", "REQ server-time"])

		try session.handleCapabilityOrAuthenticationRequest(message(":irc.example.net CAP me ACK :multi-prefix", on: session))
		try session.handleCapabilityOrAuthenticationRequest(message(":irc.example.net CAP me NAK :server-time", on: session))

		#expect(session.isCapabilityEnabled(.multiPrefix))
		#expect(session.isCapabilityEnabled(.serverTime) == false)
		#expect(capabilityCommands(of: session).last == "END")
		#expect(capabilityCommands(of: session).filter { $0.hasPrefix("REQ") }.count == 3)
	}

	/// `PLAIN` sends the password as typed. On a connection that was meant to be
	/// encrypted and is not, it is left out; SCRAM, which never sends it, stays.
	@Test("PLAIN is withheld from a connection that lost the encryption it asked for", arguments: [true, false])
	func plainIsWithheldWithoutEncryption(_ serverPrefersTLS: Bool) throws {
		let session = makeSession(configuration: ["usesSASL": true], nicknamePassword: "secret")
		defer { session.stopAllTimers() }
		session.setConnectionTransportForTesting(.connected)
		session.server = ServerEndpoint(serverAddress: "irc.example.net", prefersSecuredConnection: serverPrefersTLS)

		try session.handleCapabilityOrAuthenticationRequest(message(":irc.example.net CAP * LS :sasl=PLAIN", on: session))

		#expect(capabilityCommands(of: session) == (serverPrefersTLS ? ["END"] : ["REQ sasl"]))
		#expect(session.selectSASLMechanism(fromOffered: ["PLAIN", "SCRAM-SHA-256"]))
		#expect(session.sasl.mechanism == SCRAMClient.mechanismName)
		#expect(session.retrySASLNegotiation(withMechanisms: ["PLAIN"]) == (serverPrefersTLS == false))
		let bodies = session.printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
		#expect(bodies.contains(ConnectionSafetyStrings.Credentials.withheldOverPlaintext) == serverPrefersTLS)
	}

	@Test("A changed configuration is what the next password read sees")
	func configurationChangeForgetsThePassword() {
		let session = makeSession(configuration: [:], nicknamePassword: "first")

		#expect(session.sessionNicknamePassword == "first")

		session.config.pendingNicknamePassword = .set("second")

		#expect(session.sessionNicknamePassword == "second")
	}

	private func receiveAuthenticationNumeric(_ line: String, on session: TestServerSession) throws {
		let parsed = try message(line, on: session)
		let numeric = try #require(ServerNumeric(rawValue: parsed.commandNumeric))
		session.handleAuthenticationTrackingNumeric(numeric, message: parsed, shouldPrint: false)
	}

	private func expectPrintedLineContaining(_ text: String, on session: TestServerSession) {
		let bodies = (session.printedLines as NSArray).compactMap {
			($0 as? [String: Any])?["messageBody"] as? String
		}

		#expect(bodies.contains { $0.contains(text) })
	}

	private func makeSession(configuration: NSDictionary, nicknamePassword: String) -> TestServerSession {
		guard let configuration = configuration as? [String: Any] else {
			preconditionFailure("Test configuration must bridge to a Swift dictionary")
		}

		return TestServerSession(
			configDictionary: configuration,
			nicknamePassword: nicknamePassword
		)
	}

	private func message(_ line: String, on session: ServerSession) throws -> Message {
		try #require(Message(line: line, on: session))
	}

	private func capabilityCommands(of session: TestServerSession) -> [String] {
		(session.sentCapabilityCommands as NSArray).compactMap { $0 as? String }
	}

	private func sentLines(of session: TestServerSession) -> [String] {
		(session.sentLines as NSArray).compactMap { $0 as? String }
	}

	private func printedLine(at index: Int, on session: TestServerSession) -> [String: Any]? {
		session.printedLines[index] as? [String: Any]
	}

	private func expectPrintedLine(
		at index: Int,
		on session: TestServerSession,
		body: String,
		type: ChatLineKind,
		channel: Conversation?,
		sourceLocation: SourceLocation = #_sourceLocation
	) throws {
		let printed = try #require(printedLine(at: index, on: session), sourceLocation: sourceLocation)

		#expect(printed["messageBody"] as? String == body, sourceLocation: sourceLocation)
		#expect((printed["lineType"] as? NSNumber)?.uintValue == type.rawValue, sourceLocation: sourceLocation)
		#expect(printed["channel"] as? Conversation === channel, sourceLocation: sourceLocation)
	}
}
