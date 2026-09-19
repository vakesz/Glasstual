// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// IRCv3 `capability-negotiation` (version 3.2, the `CAP LS 302` form) and
/// `sasl-3.2`.
@Suite("IRCv3 capability negotiation")
@MainActor
struct IRCSpecCapabilityNegotiationTests {
	private func session(nickname: String = "me", password: String? = nil) -> TestServerSession {
		TestServerSession(
			configDictionary: ["nickname": nickname, "username": nickname],
			nicknamePassword: password,
			fixture: ChatEnvironmentFixture(settings: ChatSettings())
		)
	}

	private func receive(_ line: String, on session: TestServerSession) throws {
		let message = try #require(Message(line: line, on: session))

		session.handleCapabilityOrAuthenticationRequest(message)
	}

	/// Drives the authentication numeric handler the way `receiveNumericReply`
	/// routes to it.
	private func handleAuthentication(_ message: Message, on session: TestServerSession) throws {
		let numeric = try #require(ServerNumeric(rawValue: message.commandNumeric))

		#expect(numeric.group == .authentication)

		session.handleAuthenticationTrackingNumeric(numeric, message: message, shouldPrint: false)
	}

	private func capabilityCommands(of session: TestServerSession) -> [String] {
		session.sentCapabilityCommands.compactMap { $0 as? String }
	}

	// MARK: - CAP LS

	@Test("Wire CAP facts lose withdrawn dependencies without erasing SASL or ISUPPORT")
	func wireProjectionSeparatesFacts() {
		let session = session(password: "secret")
		session.isConnected = true
		let socket = Connection(config: ConnectionConfig(), onSession: session)
		session.socket = socket
		func receive(_ line: String) {
			session.connectionDidReceive(line)
		}
		receive(":server 005 me MONITOR=100 :supported")
		receive("CAP * LS :sasl=PLAIN")
		receive("CAP me ACK :batch message-tags server-time chathistory labeled-response sasl example/unknown")
		receive(":server 903 me :Authenticated")
		#expect(session.isCapabilityEnabled(.chatHistory))
		#expect(session.enabledCapabilitiesStringValue.contains("example/unknown"))
		receive("CAP me DEL :message-tags sasl")
		#expect(session.isCapabilityEnabled(.chatHistory) == false)
		#expect(session.isCapabilityEnabled(.labeledResponse) == false)
		#expect(session.isCapabilityEnabled(.monitorCommand))
		#expect(session.isCapabilityEnabled(.isIdentifiedWithSASL))
		#expect(session.isCapabilityEnabled(.saslGeneric) == false)
		#expect(session.enabledCapabilityNames.contains("sasl") == false)
		receive("CAP me NEW :message-tags")
		receive("CAP me ACK :message-tags")
		#expect(session.isCapabilityEnabled(.chatHistory))
		#expect(session.isCapabilityEnabled(.labeledResponse))
	}

	@Test("ISUPPORT legacy facts and CAP names survive each other's withdrawal")
	func legacyFactsAreIndependent() {
		let session = session()
		session.isConnected = true
		let socket = Connection(config: ConnectionConfig(), onSession: session)
		session.socket = socket
		func receive(_ line: String) {
			session.connectionDidReceive(line)
		}
		receive("CAP me ACK :multi-prefix userhost-in-names")
		receive(":server 005 me NAMESX UHNAMES MONITOR=100 WATCH=100 :supported")
		receive("CAP me DEL :multi-prefix userhost-in-names")
		#expect(session.isCapabilityEnabled([.multiPrefix, .userhostInNames, .monitorCommand, .watchCommand]))
		#expect(session.enabledCapabilityNames.isEmpty)
		receive("CAP me ACK :userhost-in-names")
		// A DEL capability needs a new advertisement before another ACK can enable it.
		receive("CAP me NEW :userhost-in-names")
		receive("CAP me ACK :userhost-in-names")
		receive(":server 005 me -NAMESX -UHNAMES -MONITOR -WATCH :withdrawn")
		#expect(session.isCapabilityEnabled(.userhostInNames))
		#expect(session.isCapabilityEnabled(.multiPrefix) == false)
		#expect(session.supportsAdvancedTracking == false)
	}

	@Test("DEL answers an outstanding request, and the stale ACK cannot resurrect it")
	func withdrawalAnswersOutstandingRequest() {
		let session = session()
		session.isConnected = true
		session.isLoggedIn = true
		let socket = Connection(config: ConnectionConfig(), onSession: session)
		session.socket = socket
		func receive(_ line: String) {
			session.connectionDidReceive(line)
		}
		receive("CAP me NEW :message-tags")
		// `labeled-response` needs an acknowledged `message-tags`, so it waits.
		receive("CAP me NEW :labeled-response")
		#expect(capabilityCommands(of: session) == ["REQ message-tags"])

		receive("CAP me DEL :message-tags")
		#expect(session.capabilityNegotiation.outstandingRequests.isEmpty)
		#expect(capabilityCommands(of: session) == ["REQ message-tags"])

		// The answer to the withdrawn request arrives late and changes nothing.
		receive("CAP me ACK :message-tags")
		#expect(session.isCapabilityEnabled(.messageTags) == false)
		#expect(capabilityCommands(of: session) == ["REQ message-tags"])

		receive("CAP me NEW :message-tags")
		#expect(capabilityCommands(of: session) == ["REQ message-tags", "REQ message-tags"])
		receive("CAP me ACK :message-tags")
		#expect(session.isCapabilityEnabled(.messageTags))
		#expect(capabilityCommands(of: session).last == "REQ labeled-response")
		receive("CAP me ACK :labeled-response")
		#expect(session.labeledResponseTrackingEnabled())
	}

	/// A server that answers nothing must not stop `CAP END`: with the requests
	/// pipelined, the only thing holding registration open is an outstanding
	/// answer, and a `CAP DEL` of the name counts as one.
	@Test("A withdrawal of the last outstanding request releases CAP END")
	func withdrawalOfLastOutstandingRequestEndsNegotiation() throws {
		let session = session()

		try receive("CAP * LS :away-notify", on: session)
		#expect(capabilityCommands(of: session) == ["REQ away-notify"])

		try receive("CAP * DEL :away-notify", on: session)

		#expect(session.capabilityNegotiation.outstandingRequests.isEmpty)
		#expect(capabilityCommands(of: session) == ["REQ away-notify", "END"])
	}

	/// Requests are sent together rather than one at a time, so a capability
	/// the server simply never answers cannot hold up the ones it would have
	/// granted. What bounds an unanswered request is the registration timeout,
	/// not the negotiation.
	@Test("Every eligible request goes out before any answer arrives")
	func eligibleRequestsArePipelined() throws {
		let session = session()

		try receive("CAP * LS :away-notify multi-prefix setname", on: session)

		#expect(capabilityCommands(of: session) == ["REQ away-notify multi-prefix setname"])

		// Two of the three are answered; the third still holds CAP END.
		try receive("CAP me ACK :away-notify", on: session)
		try receive("CAP me NAK :setname", on: session)

		#expect(capabilityCommands(of: session).contains("END") == false)
		#expect(session.capabilityNegotiation.outstandingRequests == ["multi-prefix"])

		try receive("CAP me ACK :multi-prefix", on: session)

		#expect(capabilityCommands(of: session).last == "END")
		#expect(session.isCapabilityEnabled([.awayNotify, .multiPrefix]))
		#expect(session.isCapabilityEnabled(.setName) == false)
	}

	/// Answers may come back in any order, and each is matched to its request
	/// by name rather than by arrival.
	@Test("Answers are matched by name, not by the order they arrive")
	func answersAreMatchedByName() throws {
		let session = session()

		try receive("CAP * LS :away-notify multi-prefix setname", on: session)
		try receive("CAP me ACK :setname", on: session)
		try receive("CAP me ACK :multi-prefix", on: session)

		#expect(session.capabilityNegotiation.outstandingRequests == ["away-notify"])
		#expect(capabilityCommands(of: session).contains("END") == false)

		try receive("CAP me NAK :away-notify", on: session)

		#expect(capabilityCommands(of: session).last == "END")
		#expect(session.isCapabilityEnabled([.setName, .multiPrefix]))
	}

	/// `CAP NEW` during negotiation adds to the same pass: the new name is
	/// requested at once and joins the outstanding set that gates `CAP END`.
	@Test("CAP NEW during negotiation joins the same pass")
	func newDuringNegotiationJoinsTheSamePass() throws {
		let session = session()

		try receive("CAP * LS :away-notify", on: session)
		try receive("CAP * NEW :multi-prefix", on: session)

		#expect(capabilityCommands(of: session) == ["REQ away-notify", "REQ multi-prefix"])

		try receive("CAP me ACK :away-notify", on: session)

		#expect(capabilityCommands(of: session).contains("END") == false)

		try receive("CAP me ACK :multi-prefix", on: session)

		#expect(capabilityCommands(of: session) == ["REQ away-notify", "REQ multi-prefix", "END"])
	}

	@Test("A NAK dependency blocks its dependents and CAP END is emitted only once")
	func rejectedDependencyDoesNotDeadlockOrRepeatEnd() throws {
		let session = session()
		try receive("CAP * LS :message-tags labeled-response", on: session)
		try receive("CAP * NAK :message-tags", on: session)
		try receive("CAP * DEL :labeled-response", on: session)
		#expect(capabilityCommands(of: session) == ["REQ message-tags", "END"])
		#expect(session.capabilityNegotiation.outstandingRequests.isEmpty)
	}

	@Test("NEW and DEL during a continued LS update the offer without sending premature requests")
	func listingInterleavesWithNotifications() throws {
		let session = session()
		try receive("CAP * LS * :message-tags", on: session)
		try receive("CAP * NEW :labeled-response", on: session)
		try receive("CAP * DEL :message-tags", on: session)
		#expect(capabilityCommands(of: session).isEmpty)
		try receive("CAP * LS :away-notify", on: session)
		#expect(capabilityCommands(of: session) == ["REQ away-notify"])
		#expect(session.capabilityNegotiation.outstandingRequests == ["away-notify"])
		try receive("CAP * ACK :away-notify", on: session)
		#expect(capabilityCommands(of: session) == ["REQ away-notify", "END"])
	}

	/// capability-negotiation §"The CAP LS subcommand": with version 302 the
	/// server may split the list over several lines, marking every line but
	/// the last with a lone `*` before the trailing parameter. Nothing may be
	/// requested until the last line lands.
	@Test("CAP LS 302: a multi-line list is requested only once it is complete")
	func multiLineCapabilityListIsHeldUntilComplete() throws {
		let session = session()

		try receive(":irc.example.net CAP * LS * :multi-prefix away-notify", on: session)

		#expect(capabilityCommands(of: session).isEmpty)

		try receive(":irc.example.net CAP * LS * :server-time", on: session)

		#expect(capabilityCommands(of: session).isEmpty)

		try receive(":irc.example.net CAP * LS :message-tags", on: session)

		#expect(capabilityCommands(of: session).isEmpty == false)
		#expect(session.capabilityNegotiation.outstandingRequests.isEmpty == false)
	}

	/// capability-negotiation §"Capability values": with 302 a capability may
	/// carry `=`-delimited values, and the values are comma-separated. The
	/// capability name is what identifies it, values are extra.
	@Test("CAP LS 302: a capability may carry comma-separated values")
	func capabilityValuesAreParsed() {
		let offered = CapabilityRegistry.parseCapabilityList(
			"sasl=PLAIN,EXTERNAL multi-prefix draft/chathistory=50 sts=duration=300,port=6697"
		)

		#expect(offered["sasl"] == ["PLAIN", "EXTERNAL"])
		#expect(offered["multi-prefix"] == [])
		#expect(offered["draft/chathistory"] == ["50"])
		#expect(offered["sts"] == ["duration=300", "port=6697"])
	}

	/// capability-negotiation: "Capability names are case-sensitive." A name
	/// that matches is therefore already the spelling to echo back.
	@Test("CAP REQ echoes the name the server advertised")
	func requestsEchoTheAdvertisedSpelling() throws {
		let session = session()

		try receive(":irc.example.net CAP * LS :multi-prefix", on: session)

		#expect(capabilityCommands(of: session) == ["REQ multi-prefix"])
	}

	/// Case-sensitivity cuts both ways: `Multi-Prefix` is not `multi-prefix`,
	/// so it is a capability this session does not implement.
	@Test("CAP REQ does not ask for a capability advertised under another case")
	func differentlyCasedCapabilityIsNotRequested() throws {
		let session = session()

		try receive(":irc.example.net CAP * LS :Multi-Prefix", on: session)

		#expect(capabilityCommands(of: session) == ["END"])
	}

	/// A capability the session does not implement is never requested, however
	/// the server spells it.
	@Test("CAP REQ never asks for a capability the session does not implement")
	func unknownCapabilitiesAreNotRequested() throws {
		let session = session()

		try receive(":irc.example.net CAP * LS :example.com/vendor another-unknown", on: session)

		#expect(capabilityCommands(of: session) == ["END"])
	}

	// MARK: - ACK and NAK

	/// capability-negotiation §"The CAP ACK subcommand": an ACK enables the
	/// capabilities it names; a NAK enables nothing. Either way the session
	/// moves on to the next request, and sends `CAP END` when there are none.
	@Test("CAP ACK enables, CAP NAK does not, and CAP END closes negotiation")
	func acknowledgementEnablesAndNegotiationEnds() throws {
		let session = session()

		try receive(":irc.example.net CAP * LS :multi-prefix away-notify", on: session)
		try receive(":irc.example.net CAP me ACK :multi-prefix", on: session)

		#expect(session.isCapabilityEnabled(.multiPrefix))

		try receive(":irc.example.net CAP me NAK :away-notify", on: session)

		#expect(session.isCapabilityEnabled(.awayNotify) == false)
		#expect(capabilityCommands(of: session).last == "END")
	}

	/// capability-negotiation: an ACK may carry a `-` prefixed name, which
	/// acknowledges *disabling* that capability.
	@Test("CAP ACK with a leading - disables the capability")
	func negatedAcknowledgementDisables() throws {
		let session = session()

		try receive(":irc.example.net CAP * LS :multi-prefix", on: session)
		try receive(":irc.example.net CAP me ACK :multi-prefix", on: session)

		#expect(session.isCapabilityEnabled(.multiPrefix))

		try receive(":irc.example.net CAP me ACK :-multi-prefix", on: session)

		#expect(session.isCapabilityEnabled(.multiPrefix) == false)
		#expect(session.enabledCapabilitiesStringValue.contains("multi-prefix") == false)
	}

	// MARK: - CAP NEW and CAP DEL

	@Test("Removing one alias preserves the bits supplied by another", arguments: [true, false])
	func aliasRemovalProjectsRemainingCapabilities(_ removeStableFirst: Bool) throws {
		let session = session()
		session.enableCapability(.monitorCommand)
		try receive("CAP me ACK :server-time znc.in/server-time-iso read-marker draft/read-marker", on: session)
		let first = removeStableFirst ? "server-time read-marker" : "znc.in/server-time-iso draft/read-marker"
		let last = removeStableFirst ? "znc.in/server-time-iso draft/read-marker" : "server-time read-marker"

		try receive("CAP me DEL :\(first)", on: session)
		#expect(session.isCapabilityEnabled(.serverTime))
		#expect(session.isCapabilityEnabled(.readMarker))
		#expect(session.isCapabilityEnabled(.zncServerTimeISO) == removeStableFirst)
		#expect(session.isCapabilityEnabled(.monitorCommand))

		try receive("CAP me ACK :-" + last.replacingOccurrences(of: " ", with: " -"), on: session)
		#expect(session.isCapabilityEnabled(.serverTime) == false)
		#expect(session.isCapabilityEnabled(.readMarker) == false)
		#expect(session.isCapabilityEnabled(.zncServerTimeISO) == false)
		#expect(session.isCapabilityEnabled(.monitorCommand))
	}

	@Test("NAK leaves an already enabled capability unchanged")
	func negativeAcknowledgementDoesNotDisableExistingCapability() throws {
		let session = session()
		try receive("CAP me ACK :server-time", on: session)
		try receive("CAP me NAK :-server-time", on: session)
		#expect(session.isCapabilityEnabled(.serverTime))
	}

	@Test(
		"CAP NEW uses dependencies already enabled by an earlier ACK",
		arguments: ["server-time", "znc.in/server-time", "znc.in/server-time-iso"]
	)
	func newCapabilityUsesEnabledDependencies(_ serverTimeName: String) throws {
		var settings = ChatSettings()
		settings.requestChatHistory = true
		let session = TestServerSession(
			configDictionary: [:], nicknamePassword: nil,
			fixture: ChatEnvironmentFixture(settings: settings)
		)
		session.markAsLoggedIn()
		try receive("CAP me ACK :batch message-tags \(serverTimeName)", on: session)
		try receive("CAP me NEW :chathistory", on: session)
		#expect(capabilityCommands(of: session) == ["REQ chathistory"])

		/* Withdrawing the dependency stops the re-offer: `chathistory` itself is
		 withdrawn too so that the request is weighed afresh, not skipped for
		 being outstanding already. */
		try receive("CAP me DEL :message-tags chathistory", on: session)
		session.sentCapabilityCommands.removeAllObjects()
		try receive("CAP me NEW :chathistory", on: session)
		#expect(capabilityCommands(of: session).isEmpty)
	}

	/// capability-negotiation §"The CAP NEW subcommand": after registration a
	/// server may advertise new capabilities, which the session requests the
	/// same way — but without a further `CAP END`, since registration is over.
	@Test("CAP NEW requests the new capability without reopening negotiation")
	func capabilityNewRequestsWithoutEnding() throws {
		let session = session()

		session.markAsLoggedIn()

		try receive(":irc.example.net CAP me NEW :away-notify", on: session)

		#expect(capabilityCommands(of: session) == ["REQ away-notify"])
		#expect(capabilityCommands(of: session).contains("END") == false)
	}

	/// capability-negotiation §"The CAP DEL subcommand": the named capability
	/// stops being available and its effects stop applying at once.
	@Test("CAP DEL disables the capability")
	func capabilityDeleteDisables() throws {
		let session = session()

		try receive(":irc.example.net CAP * LS :away-notify", on: session)
		try receive(":irc.example.net CAP me ACK :away-notify", on: session)

		#expect(session.isCapabilityEnabled(.awayNotify))

		try receive(":irc.example.net CAP me DEL :away-notify", on: session)

		#expect(session.isCapabilityEnabled(.awayNotify) == false)
	}

	// MARK: - SASL and CAP END timing

	@Test("Successful SASL results do not apply the failure policy", arguments: [903, 907])
	func successfulSASLResult(_ numeric: Int) throws {
		let session = TestServerSession(
			configDictionary: ["disconnectOnSASLFailure": true], nicknamePassword: "secret",
			fixture: ChatEnvironmentFixture(settings: ChatSettings())
		)
		session.isConnected = true
		try receive("CAP * LS :sasl=PLAIN", on: session)
		try receive("CAP me ACK :sasl", on: session)
		let result = try #require(Message(line: ":irc.example.net \(numeric) me :Authenticated", on: session))
		try handleAuthentication(result, on: session)
		#expect(session.isCapabilityEnabled(.isIdentifiedWithSASL))
		#expect(session.isCapabilityEnabled(.isInSASLNegotiation) == false)
		#expect(session.isQuitting == false)
		#expect(capabilityCommands(of: session).last == "END")
	}

	@Test("All terminal SASL failures use the configured policy", arguments: [902, 904, 905, 906], [true, false])
	func terminalSASLFailurePolicy(_ numeric: Int, _ disconnect: Bool) throws {
		let session = TestServerSession(
			configDictionary: ["nickname": "me", "username": "me", "disconnectOnSASLFailure": disconnect],
			nicknamePassword: "secret",
			fixture: ChatEnvironmentFixture(settings: ChatSettings())
		)
		session.isConnected = true
		try receive("CAP * LS :sasl=PLAIN", on: session)
		try receive("CAP me ACK :sasl", on: session)
		let result = try #require(Message(line: ":irc.example.net \(numeric) me PLAIN :Failed", on: session))
		try handleAuthentication(result, on: session)
		#expect(session.isCapabilityEnabled(.isInSASLNegotiation) == false)
		#expect(session.isCapabilityEnabled(.isIdentifiedWithSASL) == false)
		#expect(session.isQuitting == disconnect)
		#expect(capabilityCommands(of: session).contains("END") == !disconnect)
		#expect(session.sasl.incomingPayload == nil)
		#expect(session.sasl.scramSession == nil)
	}

	@Test("SCRAM integrity failures use the same terminal policy", arguments: [900, 903, 907, 0], [true, false])
	func scramIntegrityFailurePolicy(_ numeric: Int, _ disconnect: Bool) throws {
		let session = TestServerSession(
			configDictionary: ["nickname": "me", "username": "me", "disconnectOnSASLFailure": disconnect],
			nicknamePassword: "secret",
			fixture: ChatEnvironmentFixture(settings: ChatSettings())
		)
		session.isConnected = true
		try receive("CAP * LS :sasl=SCRAM-SHA-256,PLAIN", on: session)
		try receive("CAP me ACK :sasl", on: session)
		try receive("AUTHENTICATE +", on: session)
		if numeric == 0 {
			try receive("AUTHENTICATE !not-base64!", on: session)
		} else {
			let result = try #require(Message(
				line: ":irc.example.net \(numeric) me me!u@h account :Authenticated",
				on: session
			))
			try handleAuthentication(result, on: session)
		}
		#expect(session.isCapabilityEnabled(.isInSASLNegotiation) == false)
		#expect(session.isCapabilityEnabled(.isIdentifiedWithSASL) == false)
		#expect(session.isQuitting == disconnect)
		#expect(capabilityCommands(of: session).contains("END") == !disconnect)
		#expect(session.sentLines.contains("AUTHENTICATE *"))

		// The server's response to our abort cannot retry PLAIN or resume twice.
		let aborted = try #require(Message(line: ":irc.example.net 906 me :Aborted", on: session))
		try handleAuthentication(aborted, on: session)
		#expect(capabilityCommands(of: session).filter { $0 == "END" }.count == (disconnect ? 0 : 1))
		#expect(session.sentLines.contains("AUTHENTICATE PLAIN") == false)
	}

	/// sasl-3.2: "Sessions... MUST NOT send CAP END until the authentication
	/// exchange has completed." Requesting `sasl` therefore pauses the queue.
	@Test("sasl-3.2: CAP END waits for the authentication exchange")
	func capabilityEndWaitsForSASL() throws {
		let session = session(password: "hunter2")

		try receive(":irc.example.net CAP * LS :sasl=PLAIN,EXTERNAL", on: session)

		#expect(capabilityCommands(of: session) == ["REQ sasl"])

		try receive(":irc.example.net CAP me ACK :sasl", on: session)

		#expect(session.isCapabilityEnabled(.isInSASLNegotiation))
		#expect(capabilityCommands(of: session) == ["REQ sasl"])

		let result = try #require(Message(line: ":irc.example.net 903 me :SASL authentication successful", on: session))
		try handleAuthentication(result, on: session)

		#expect(capabilityCommands(of: session) == ["REQ sasl", "END"])
		#expect(session.isCapabilityEnabled(.isInSASLNegotiation) == false)
	}

	/// sasl-3.2: a session with no way to authenticate must not ask for `sasl`
	/// and must not stall registration waiting for an exchange that will never
	/// start.
	@Test("sasl-3.2: SASL is skipped when no offered mechanism is usable")
	func saslIsSkippedWithoutAUsableMechanism() throws {
		let session = session(password: "hunter2")

		try receive(":irc.example.net CAP * LS :sasl=GSSAPI,ANONYMOUS", on: session)

		#expect(capabilityCommands(of: session) == ["END"])
	}

	/// sasl-3.2: the mechanism list in the `sasl` value is advisory, and the
	/// session picks the strongest mechanism it shares with the server.
	@Test("sasl-3.2: mechanism selection prefers the strongest shared mechanism")
	func mechanismSelectionPrefersTheStrongest() {
		#expect(
			SASLPolicy.nextMechanism(
				from: ["SCRAM-SHA-256", "PLAIN"],
				offered: ["PLAIN", "SCRAM-SHA-256"],
				tried: []
			) == "SCRAM-SHA-256"
		)
		#expect(
			SASLPolicy.nextMechanism(
				from: ["SCRAM-SHA-256", "PLAIN"],
				offered: ["PLAIN"],
				tried: []
			) == "PLAIN"
		)
		#expect(
			SASLPolicy.nextMechanism(
				from: ["SCRAM-SHA-256", "PLAIN"],
				offered: ["PLAIN", "SCRAM-SHA-256"],
				tried: ["scram-sha-256"]
			) == "PLAIN"
		)
		#expect(
			SASLPolicy.nextMechanism(
				from: ["PLAIN"],
				offered: ["PLAIN"],
				tried: ["PLAIN"]
			) == nil
		)
	}

	/// sasl-3.2 §"The AUTHENTICATE command": the payload is base64 and is sent
	/// in chunks of at most 400 bytes. A chunk shorter than 400 ends the
	/// payload, so a payload that is an exact multiple of 400 needs a trailing
	/// `+` to say "that was all".
	@Test("sasl-3.2: the payload is chunked at 400 bytes")
	func saslPayloadIsChunkedAt400Bytes() {
		let short = SASLPolicy.wireChunks(for: "me\0me\0hunter2")

		#expect(short.count == 1)
		#expect(short[0] == Data("me\0me\0hunter2".utf8).base64EncodedString())

		// 300 bytes encode to exactly 400 base64 characters.
		let exact = SASLPolicy.wireChunks(for: String(repeating: "a", count: 300))

		#expect(exact.count == 2)
		#expect(exact[0].count == 400)
		#expect(exact[1] == "+")

		// 600 bytes encode to 800 characters: two full chunks, then the `+`.
		let twoFullChunks = SASLPolicy.wireChunks(for: String(repeating: "a", count: 600))

		#expect(twoFullChunks.count == 3)
		#expect(twoFullChunks[0].count == 400)
		#expect(twoFullChunks[1].count == 400)
		#expect(twoFullChunks[2] == "+")

		// 601 bytes encode to 804 characters, so the short last chunk ends it.
		let shortLastChunk = SASLPolicy.wireChunks(for: String(repeating: "a", count: 601))

		#expect(shortLastChunk.count == 3)
		#expect(shortLastChunk[0].count == 400)
		#expect(shortLastChunk[1].count == 400)
		#expect(shortLastChunk[2].count == 4)
	}

	/// sasl-3.2: "If the session wishes to send an empty response, it MUST send
	/// `AUTHENTICATE +`" — the mechanisms that carry no initial response, such
	/// as EXTERNAL, rely on this.
	@Test("sasl-3.2: an empty payload is sent as a single +")
	func emptyPayloadIsASinglePlus() {
		#expect(SASLPolicy.wireChunks(for: "") == ["+"])
	}

	/// sasl-3.2: EXTERNAL needs a client certificate; PLAIN needs a password.
	/// Offering a mechanism the session has no credential for would only earn a
	/// 904.
	@Test("sasl-3.2: the mechanism list follows the credentials the session holds")
	func mechanismListFollowsCredentials() {
		#expect(
			SASLPolicy.supportedMechanisms(
				hasClientCertificate: true,
				externalMechanismDisabled: false,
				hasPassword: true,
				preferredMechanism: nil
			) == ["EXTERNAL", SCRAMClient.mechanismName, "PLAIN"]
		)
		#expect(
			SASLPolicy.supportedMechanisms(
				hasClientCertificate: false,
				externalMechanismDisabled: false,
				hasPassword: false,
				preferredMechanism: nil
			).isEmpty
		)
		#expect(
			SASLPolicy.supportedMechanisms(
				hasClientCertificate: true,
				externalMechanismDisabled: true,
				hasPassword: true,
				preferredMechanism: "plain"
			) == ["PLAIN", SCRAMClient.mechanismName]
		)
	}

	/// sasl-3.2: 902, 904, 905 and 906 all end the attempt; 903 and 907 mean
	/// the session is authenticated. The numerics table has to agree with the
	/// specification's assignment before any of the handling can be right.
	@Test("sasl-3.2: the authentication numerics")
	func saslNumericsMatchTheSpecification() {
		#expect(ServerNumeric.loggedin.rawValue == 900)
		#expect(ServerNumeric.loggedout.rawValue == 901)
		#expect(ServerNumeric.nicklocked.rawValue == 902)
		#expect(ServerNumeric.saslsuccess.rawValue == 903)
		#expect(ServerNumeric.saslfail.rawValue == 904)
		#expect(ServerNumeric.sasltoolong.rawValue == 905)
		#expect(ServerNumeric.saslaborted.rawValue == 906)
		#expect(ServerNumeric.saslalready.rawValue == 907)
		#expect(ServerNumeric.saslmechs.rawValue == 908)
	}

	/// The 9xx numerics sit outside the 400-596 error band, so they must not
	/// be routed to the generic error printer that would swallow them.
	@Test("sasl-3.2: the 9xx numerics are not generic error replies")
	func saslNumericsAreNotGenericErrors() {
		for numeric in UInt(900) ... UInt(908) {
			#expect(ServerNumeric.isErrorReply(numeric) == false)
		}
	}

	/// sasl-3.2 §"RPL_SASLMECHS": a 908 lists the mechanisms the server will
	/// accept and is followed by the 904 for the refused attempt. The 904 is
	/// what moves the session on, to one it has not tried yet; a retry sent on
	/// the 908 was ended by the 904 that belonged to the attempt before it.
	@Test("sasl-3.2: 908 then 904 drives a retry with an untried mechanism")
	func saslMechanismsNumericDrivesARetry() throws {
		let session = session(password: "hunter2")
		defer { session.stopAllTimers() }
		session.isConnected = true
		try receive("CAP * LS :sasl=SCRAM-SHA-256,PLAIN", on: session)
		try receive("CAP me ACK :sasl", on: session)

		#expect(session.sasl.mechanism == SCRAMClient.mechanismName)

		let mechanisms = try #require(Message(line: ":irc.example.net 908 me PLAIN :Available mechanisms", on: session))
		let failure = try #require(Message(line: ":irc.example.net 904 me :SASL authentication failed", on: session))
		try handleAuthentication(mechanisms, on: session)
		#expect(session.sasl.mechanism == SCRAMClient.mechanismName)
		#expect(session.sentLines.contains("AUTHENTICATE PLAIN") == false)

		try handleAuthentication(failure, on: session)
		#expect(session.sasl.mechanism == "PLAIN")
		#expect(session.sentLines.contains("AUTHENTICATE PLAIN"))
		#expect(session.isCapabilityEnabled(.isInSASLNegotiation))
		#expect(capabilityCommands(of: session).contains("END") == false)

		try handleAuthentication(mechanisms, on: session)
		try handleAuthentication(failure, on: session)
		#expect(session.isCapabilityEnabled(.isInSASLNegotiation) == false)
		#expect(capabilityCommands(of: session).last == "END")
	}

	/// A reassembled payload cannot be allowed to grow without bound: a server
	/// that keeps sending 400-byte chunks would otherwise be free to exhaust
	/// memory during registration.
	@Test("sasl-3.2: the reassembly buffer is bounded")
	func reassemblyBufferIsBounded() {
		#expect(SASLPolicy.maximumPayloadLength == 16384)
	}
}
