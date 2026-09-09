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

/// IRCv3 `capability-negotiation` (version 3.2, the `CAP LS 302` form) and
/// `sasl-3.2`.
@Suite("IRCv3 capability negotiation")
@MainActor
struct IRCSpecCapabilityNegotiationTests {
	private func client(nickname: String = "me", password: String? = nil) -> GLTTestClient {
		GLTTestClient(
			configDictionary: ["nickname": nickname, "username": nickname],
			nicknamePassword: password,
			fixture: GLTClientEnvironmentFixture(preferences: ClientPreferences())
		)
	}

	private func receive(_ line: String, on client: GLTTestClient) throws {
		let message = try #require(Message(line: line, on: client))

		client.handleCapabilityOrAuthenticationRequest(message)
	}

	private func capabilityCommands(of client: GLTTestClient) -> [String] {
		client.sentCapabilityCommands.compactMap { $0 as? String }
	}

	// MARK: - CAP LS

	@Test("Wire CAP facts lose withdrawn dependencies without erasing SASL or ISUPPORT")
	func wireProjectionSeparatesFacts() {
		let client = client(password: "secret")
		client.isConnected = true
		let socket = Connection(config: IRCConnectionConfig(), onClient: client)
		client.socket = socket
		func receive(_ line: String) {
			client.ircConnection(socket, didReceiveData: line)
		}
		receive(":server 005 me MONITOR=100 :supported")
		receive("CAP * LS :sasl=PLAIN")
		receive("CAP me ACK :batch message-tags server-time chathistory labeled-response sasl example/unknown")
		receive(":server 903 me :Authenticated")
		#expect(client.isCapabilityEnabled(.chatHistory))
		#expect(client.enabledCapabilitiesStringValue.contains("example/unknown"))
		receive("CAP me DEL :message-tags sasl")
		#expect(client.isCapabilityEnabled(.chatHistory) == false)
		#expect(client.isCapabilityEnabled(.labeledResponse) == false)
		#expect(client.isCapabilityEnabled(.monitorCommand))
		#expect(client.isCapabilityEnabled(.isIdentifiedWithSASL))
		#expect(client.isCapabilityEnabled(.saslGeneric) == false)
		#expect(client.enabledCapabilityNames.contains("sasl") == false)
		receive("CAP me NEW :message-tags")
		receive("CAP me ACK :message-tags")
		#expect(client.isCapabilityEnabled(.chatHistory))
		#expect(client.isCapabilityEnabled(.labeledResponse))
	}

	@Test("ISUPPORT legacy facts and CAP names survive each other's withdrawal")
	func legacyFactsAreIndependent() {
		let client = client()
		client.isConnected = true
		let socket = Connection(config: IRCConnectionConfig(), onClient: client)
		client.socket = socket
		func receive(_ line: String) {
			client.ircConnection(socket, didReceiveData: line)
		}
		receive("CAP me ACK :multi-prefix userhost-in-names")
		receive(":server 005 me NAMESX UHNAMES MONITOR=100 WATCH=100 :supported")
		receive("CAP me DEL :multi-prefix userhost-in-names")
		#expect(client.isCapabilityEnabled([.multiPrefix, .userhostInNames, .monitorCommand, .watchCommand]))
		#expect(client.enabledCapabilityNames.isEmpty)
		receive("CAP me ACK :userhost-in-names")
		// A DEL capability needs a new advertisement before another ACK can enable it.
		receive("CAP me NEW :userhost-in-names")
		receive("CAP me ACK :userhost-in-names")
		receive(":server 005 me -NAMESX -UHNAMES -MONITOR -WATCH :withdrawn")
		#expect(client.isCapabilityEnabled(.userhostInNames))
		#expect(client.isCapabilityEnabled(.multiPrefix) == false)
		#expect(client.supportsAdvancedTracking == false)
	}

	@Test("DEL answers an outstanding request, and the stale ACK cannot resurrect it")
	func withdrawalAnswersOutstandingRequest() {
		let client = client()
		client.isConnected = true
		client.isLoggedIn = true
		let socket = Connection(config: IRCConnectionConfig(), onClient: client)
		client.socket = socket
		func receive(_ line: String) {
			client.ircConnection(socket, didReceiveData: line)
		}
		receive("CAP me NEW :message-tags")
		// `labeled-response` needs an acknowledged `message-tags`, so it waits.
		receive("CAP me NEW :labeled-response")
		#expect(capabilityCommands(of: client) == ["REQ message-tags"])

		receive("CAP me DEL :message-tags")
		#expect(client.capabilityNegotiation.outstandingRequests.isEmpty)
		#expect(capabilityCommands(of: client) == ["REQ message-tags"])

		// The answer to the withdrawn request arrives late and changes nothing.
		receive("CAP me ACK :message-tags")
		#expect(client.isCapabilityEnabled(.messageTags) == false)
		#expect(capabilityCommands(of: client) == ["REQ message-tags"])

		receive("CAP me NEW :message-tags")
		#expect(capabilityCommands(of: client) == ["REQ message-tags", "REQ message-tags"])
		receive("CAP me ACK :message-tags")
		#expect(client.isCapabilityEnabled(.messageTags))
		#expect(capabilityCommands(of: client).last == "REQ labeled-response")
		receive("CAP me ACK :labeled-response")
		#expect(client.labeledResponseTrackingEnabled())
	}

	/// A server that answers nothing must not stop `CAP END`: with the requests
	/// pipelined, the only thing holding registration open is an outstanding
	/// answer, and a `CAP DEL` of the name counts as one.
	@Test("A withdrawal of the last outstanding request releases CAP END")
	func withdrawalOfLastOutstandingRequestEndsNegotiation() throws {
		let client = client()

		try receive("CAP * LS :away-notify", on: client)
		#expect(capabilityCommands(of: client) == ["REQ away-notify"])

		try receive("CAP * DEL :away-notify", on: client)

		#expect(client.capabilityNegotiation.outstandingRequests.isEmpty)
		#expect(capabilityCommands(of: client) == ["REQ away-notify", "END"])
	}

	/// Requests are sent together rather than one at a time, so a capability
	/// the server simply never answers cannot hold up the ones it would have
	/// granted. What bounds an unanswered request is the registration timeout,
	/// not the negotiation.
	@Test("Every eligible request goes out before any answer arrives")
	func eligibleRequestsArePipelined() throws {
		let client = client()

		try receive("CAP * LS :away-notify multi-prefix setname", on: client)

		#expect(capabilityCommands(of: client) == ["REQ away-notify multi-prefix setname"])

		// Two of the three are answered; the third still holds CAP END.
		try receive("CAP me ACK :away-notify", on: client)
		try receive("CAP me NAK :setname", on: client)

		#expect(capabilityCommands(of: client).contains("END") == false)
		#expect(client.capabilityNegotiation.outstandingRequests == ["multi-prefix"])

		try receive("CAP me ACK :multi-prefix", on: client)

		#expect(capabilityCommands(of: client).last == "END")
		#expect(client.isCapabilityEnabled([.awayNotify, .multiPrefix]))
		#expect(client.isCapabilityEnabled(.setName) == false)
	}

	/// Answers may come back in any order, and each is matched to its request
	/// by name rather than by arrival.
	@Test("Answers are matched by name, not by the order they arrive")
	func answersAreMatchedByName() throws {
		let client = client()

		try receive("CAP * LS :away-notify multi-prefix setname", on: client)
		try receive("CAP me ACK :setname", on: client)
		try receive("CAP me ACK :multi-prefix", on: client)

		#expect(client.capabilityNegotiation.outstandingRequests == ["away-notify"])
		#expect(capabilityCommands(of: client).contains("END") == false)

		try receive("CAP me NAK :away-notify", on: client)

		#expect(capabilityCommands(of: client).last == "END")
		#expect(client.isCapabilityEnabled([.setName, .multiPrefix]))
	}

	/// `CAP NEW` during negotiation adds to the same pass: the new name is
	/// requested at once and joins the outstanding set that gates `CAP END`.
	@Test("CAP NEW during negotiation joins the same pass")
	func newDuringNegotiationJoinsTheSamePass() throws {
		let client = client()

		try receive("CAP * LS :away-notify", on: client)
		try receive("CAP * NEW :multi-prefix", on: client)

		#expect(capabilityCommands(of: client) == ["REQ away-notify", "REQ multi-prefix"])

		try receive("CAP me ACK :away-notify", on: client)

		#expect(capabilityCommands(of: client).contains("END") == false)

		try receive("CAP me ACK :multi-prefix", on: client)

		#expect(capabilityCommands(of: client) == ["REQ away-notify", "REQ multi-prefix", "END"])
	}

	@Test("A NAK dependency blocks its dependents and CAP END is emitted only once")
	func rejectedDependencyDoesNotDeadlockOrRepeatEnd() throws {
		let client = client()
		try receive("CAP * LS :message-tags labeled-response", on: client)
		try receive("CAP * NAK :message-tags", on: client)
		try receive("CAP * DEL :labeled-response", on: client)
		#expect(capabilityCommands(of: client) == ["REQ message-tags", "END"])
		#expect(client.capabilityNegotiation.outstandingRequests.isEmpty)
	}

	@Test("NEW and DEL during a continued LS update the offer without sending premature requests")
	func listingInterleavesWithNotifications() throws {
		let client = client()
		try receive("CAP * LS * :message-tags", on: client)
		try receive("CAP * NEW :labeled-response", on: client)
		try receive("CAP * DEL :message-tags", on: client)
		#expect(capabilityCommands(of: client).isEmpty)
		try receive("CAP * LS :away-notify", on: client)
		#expect(capabilityCommands(of: client) == ["REQ away-notify"])
		#expect(client.capabilityNegotiation.outstandingRequests == ["away-notify"])
		try receive("CAP * ACK :away-notify", on: client)
		#expect(capabilityCommands(of: client) == ["REQ away-notify", "END"])
	}

	/// capability-negotiation §"The CAP LS subcommand": with version 302 the
	/// server may split the list over several lines, marking every line but
	/// the last with a lone `*` before the trailing parameter. Nothing may be
	/// requested until the last line lands.
	@Test("CAP LS 302: a multi-line list is requested only once it is complete")
	func multiLineCapabilityListIsHeldUntilComplete() throws {
		let client = client()

		try receive(":irc.example.net CAP * LS * :multi-prefix away-notify", on: client)

		#expect(capabilityCommands(of: client).isEmpty)

		try receive(":irc.example.net CAP * LS * :server-time", on: client)

		#expect(capabilityCommands(of: client).isEmpty)

		try receive(":irc.example.net CAP * LS :message-tags", on: client)

		#expect(capabilityCommands(of: client).isEmpty == false)
		#expect(client.capabilityNegotiation.outstandingRequests.isEmpty == false)
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
		let client = client()

		try receive(":irc.example.net CAP * LS :multi-prefix", on: client)

		#expect(capabilityCommands(of: client) == ["REQ multi-prefix"])
	}

	/// Case-sensitivity cuts both ways: `Multi-Prefix` is not `multi-prefix`,
	/// so it is a capability this client does not implement.
	@Test("CAP REQ does not ask for a capability advertised under another case")
	func differentlyCasedCapabilityIsNotRequested() throws {
		let client = client()

		try receive(":irc.example.net CAP * LS :Multi-Prefix", on: client)

		#expect(capabilityCommands(of: client) == ["END"])
	}

	/// A capability the client does not implement is never requested, however
	/// the server spells it.
	@Test("CAP REQ never asks for a capability the client does not implement")
	func unknownCapabilitiesAreNotRequested() throws {
		let client = client()

		try receive(":irc.example.net CAP * LS :example.com/vendor another-unknown", on: client)

		#expect(capabilityCommands(of: client) == ["END"])
	}

	// MARK: - ACK and NAK

	/// capability-negotiation §"The CAP ACK subcommand": an ACK enables the
	/// capabilities it names; a NAK enables nothing. Either way the client
	/// moves on to the next request, and sends `CAP END` when there are none.
	@Test("CAP ACK enables, CAP NAK does not, and CAP END closes negotiation")
	func acknowledgementEnablesAndNegotiationEnds() throws {
		let client = client()

		try receive(":irc.example.net CAP * LS :multi-prefix away-notify", on: client)
		try receive(":irc.example.net CAP me ACK :multi-prefix", on: client)

		#expect(client.isCapabilityEnabled(.multiPrefix))

		try receive(":irc.example.net CAP me NAK :away-notify", on: client)

		#expect(client.isCapabilityEnabled(.awayNotify) == false)
		#expect(capabilityCommands(of: client).last == "END")
	}

	/// capability-negotiation: an ACK may carry a `-` prefixed name, which
	/// acknowledges *disabling* that capability.
	@Test("CAP ACK with a leading - disables the capability")
	func negatedAcknowledgementDisables() throws {
		let client = client()

		try receive(":irc.example.net CAP * LS :multi-prefix", on: client)
		try receive(":irc.example.net CAP me ACK :multi-prefix", on: client)

		#expect(client.isCapabilityEnabled(.multiPrefix))

		try receive(":irc.example.net CAP me ACK :-multi-prefix", on: client)

		#expect(client.isCapabilityEnabled(.multiPrefix) == false)
		#expect(client.enabledCapabilitiesStringValue.contains("multi-prefix") == false)
	}

	// MARK: - CAP NEW and CAP DEL

	@Test("Removing one alias preserves the bits supplied by another", arguments: [true, false])
	func aliasRemovalProjectsRemainingCapabilities(_ removeStableFirst: Bool) throws {
		let client = client()
		client.enableCapability(.monitorCommand)
		try receive("CAP me ACK :server-time znc.in/server-time-iso read-marker draft/read-marker", on: client)
		let first = removeStableFirst ? "server-time read-marker" : "znc.in/server-time-iso draft/read-marker"
		let last = removeStableFirst ? "znc.in/server-time-iso draft/read-marker" : "server-time read-marker"

		try receive("CAP me DEL :\(first)", on: client)
		#expect(client.isCapabilityEnabled(.serverTime))
		#expect(client.isCapabilityEnabled(.readMarker))
		#expect(client.isCapabilityEnabled(.zncServerTimeISO) == removeStableFirst)
		#expect(client.isCapabilityEnabled(.monitorCommand))

		try receive("CAP me ACK :-" + last.replacingOccurrences(of: " ", with: " -"), on: client)
		#expect(client.isCapabilityEnabled(.serverTime) == false)
		#expect(client.isCapabilityEnabled(.readMarker) == false)
		#expect(client.isCapabilityEnabled(.zncServerTimeISO) == false)
		#expect(client.isCapabilityEnabled(.monitorCommand))
	}

	@Test("NAK leaves an already enabled capability unchanged")
	func negativeAcknowledgementDoesNotDisableExistingCapability() throws {
		let client = client()
		try receive("CAP me ACK :server-time", on: client)
		try receive("CAP me NAK :-server-time", on: client)
		#expect(client.isCapabilityEnabled(.serverTime))
	}

	@Test(
		"CAP NEW uses dependencies already enabled by an earlier ACK",
		arguments: ["server-time", "znc.in/server-time", "znc.in/server-time-iso"]
	)
	func newCapabilityUsesEnabledDependencies(_ serverTimeName: String) throws {
		var preferences = ClientPreferences()
		preferences.requestChatHistory = true
		let client = GLTTestClient(
			configDictionary: [:], nicknamePassword: nil,
			fixture: GLTClientEnvironmentFixture(preferences: preferences)
		)
		client.markAsLoggedIn()
		try receive("CAP me ACK :batch message-tags \(serverTimeName)", on: client)
		try receive("CAP me NEW :chathistory", on: client)
		#expect(capabilityCommands(of: client) == ["REQ chathistory"])

		/* Withdrawing the dependency stops the re-offer: `chathistory` itself is
		 withdrawn too so that the request is weighed afresh, not skipped for
		 being outstanding already. */
		try receive("CAP me DEL :message-tags chathistory", on: client)
		client.sentCapabilityCommands.removeAllObjects()
		try receive("CAP me NEW :chathistory", on: client)
		#expect(capabilityCommands(of: client).isEmpty)
	}

	/// capability-negotiation §"The CAP NEW subcommand": after registration a
	/// server may advertise new capabilities, which the client requests the
	/// same way — but without a further `CAP END`, since registration is over.
	@Test("CAP NEW requests the new capability without reopening negotiation")
	func capabilityNewRequestsWithoutEnding() throws {
		let client = client()

		client.markAsLoggedIn()

		try receive(":irc.example.net CAP me NEW :away-notify", on: client)

		#expect(capabilityCommands(of: client) == ["REQ away-notify"])
		#expect(capabilityCommands(of: client).contains("END") == false)
	}

	/// capability-negotiation §"The CAP DEL subcommand": the named capability
	/// stops being available and its effects stop applying at once.
	@Test("CAP DEL disables the capability")
	func capabilityDeleteDisables() throws {
		let client = client()

		try receive(":irc.example.net CAP * LS :away-notify", on: client)
		try receive(":irc.example.net CAP me ACK :away-notify", on: client)

		#expect(client.isCapabilityEnabled(.awayNotify))

		try receive(":irc.example.net CAP me DEL :away-notify", on: client)

		#expect(client.isCapabilityEnabled(.awayNotify) == false)
	}

	// MARK: - SASL and CAP END timing

	@Test("Successful SASL results do not apply the failure policy", arguments: [903, 907])
	func successfulSASLResult(_ numeric: Int) throws {
		let client = GLTTestClient(
			configDictionary: ["disconnectOnSASLFailure": true], nicknamePassword: "secret",
			fixture: GLTClientEnvironmentFixture(preferences: ClientPreferences())
		)
		client.isConnected = true
		try receive("CAP * LS :sasl=PLAIN", on: client)
		try receive("CAP me ACK :sasl", on: client)
		let result = try #require(Message(line: ":irc.example.net \(numeric) me :Authenticated", on: client))
		#expect(client.handleTrackingNumeric(result.commandNumeric, message: result, shouldPrint: false))
		#expect(client.isCapabilityEnabled(.isIdentifiedWithSASL))
		#expect(client.isCapabilityEnabled(.isInSASLNegotiation) == false)
		#expect(client.isQuitting == false)
		#expect(capabilityCommands(of: client).last == "END")
	}

	@Test("All terminal SASL failures use the configured policy", arguments: [902, 904, 905, 906, 908], [true, false])
	func terminalSASLFailurePolicy(_ numeric: Int, _ disconnect: Bool) throws {
		let client = GLTTestClient(
			configDictionary: ["nickname": "me", "username": "me", "disconnectOnSASLFailure": disconnect],
			nicknamePassword: "secret",
			fixture: GLTClientEnvironmentFixture(preferences: ClientPreferences())
		)
		client.isConnected = true
		try receive("CAP * LS :sasl=PLAIN", on: client)
		try receive("CAP me ACK :sasl", on: client)
		let result = try #require(Message(line: ":irc.example.net \(numeric) me PLAIN :Failed", on: client))
		#expect(client.handleTrackingNumeric(result.commandNumeric, message: result, shouldPrint: false))
		#expect(client.isCapabilityEnabled(.isInSASLNegotiation) == false)
		#expect(client.isCapabilityEnabled(.isIdentifiedWithSASL) == false)
		#expect(client.isQuitting == disconnect)
		#expect(capabilityCommands(of: client).contains("END") == !disconnect)
		#expect(client.saslIncomingPayload == nil)
		#expect(client.saslScramClient == nil)
	}

	@Test("SCRAM integrity failures use the same terminal policy", arguments: [900, 903, 907, 0], [true, false])
	func scramIntegrityFailurePolicy(_ numeric: Int, _ disconnect: Bool) throws {
		let client = GLTTestClient(
			configDictionary: ["nickname": "me", "username": "me", "disconnectOnSASLFailure": disconnect],
			nicknamePassword: "secret",
			fixture: GLTClientEnvironmentFixture(preferences: ClientPreferences())
		)
		client.isConnected = true
		try receive("CAP * LS :sasl=SCRAM-SHA-256,PLAIN", on: client)
		try receive("CAP me ACK :sasl", on: client)
		try receive("AUTHENTICATE +", on: client)
		if numeric == 0 {
			try receive("AUTHENTICATE !not-base64!", on: client)
		} else {
			let result = try #require(Message(
				line: ":irc.example.net \(numeric) me me!u@h account :Authenticated",
				on: client
			))
			#expect(client.handleTrackingNumeric(result.commandNumeric, message: result, shouldPrint: false))
		}
		#expect(client.isCapabilityEnabled(.isInSASLNegotiation) == false)
		#expect(client.isCapabilityEnabled(.isIdentifiedWithSASL) == false)
		#expect(client.isQuitting == disconnect)
		#expect(capabilityCommands(of: client).contains("END") == !disconnect)
		#expect(client.sentLines.contains("AUTHENTICATE *"))

		// The server's response to our abort cannot retry PLAIN or resume twice.
		let aborted = try #require(Message(line: ":irc.example.net 906 me :Aborted", on: client))
		#expect(client.handleTrackingNumeric(aborted.commandNumeric, message: aborted, shouldPrint: false))
		#expect(capabilityCommands(of: client).filter { $0 == "END" }.count == (disconnect ? 0 : 1))
		#expect(client.sentLines.contains("AUTHENTICATE PLAIN") == false)
	}

	/// sasl-3.2: "Clients... MUST NOT send CAP END until the authentication
	/// exchange has completed." Requesting `sasl` therefore pauses the queue.
	@Test("sasl-3.2: CAP END waits for the authentication exchange")
	func capabilityEndWaitsForSASL() throws {
		let client = client(password: "hunter2")

		try receive(":irc.example.net CAP * LS :sasl=PLAIN,EXTERNAL", on: client)

		#expect(capabilityCommands(of: client) == ["REQ sasl"])

		try receive(":irc.example.net CAP me ACK :sasl", on: client)

		#expect(client.isCapabilityEnabled(.isInSASLNegotiation))
		#expect(capabilityCommands(of: client) == ["REQ sasl"])

		let result = try #require(Message(line: ":irc.example.net 903 me :SASL authentication successful", on: client))
		#expect(client.handleTrackingNumeric(result.commandNumeric, message: result, shouldPrint: false))

		#expect(capabilityCommands(of: client) == ["REQ sasl", "END"])
		#expect(client.isCapabilityEnabled(.isInSASLNegotiation) == false)
	}

	/// sasl-3.2: a client with no way to authenticate must not ask for `sasl`
	/// and must not stall registration waiting for an exchange that will never
	/// start.
	@Test("sasl-3.2: SASL is skipped when no offered mechanism is usable")
	func saslIsSkippedWithoutAUsableMechanism() throws {
		let client = client(password: "hunter2")

		try receive(":irc.example.net CAP * LS :sasl=GSSAPI,ANONYMOUS", on: client)

		#expect(capabilityCommands(of: client) == ["END"])
	}

	/// sasl-3.2: the mechanism list in the `sasl` value is advisory, and the
	/// client picks the strongest mechanism it shares with the server.
	@Test("sasl-3.2: mechanism selection prefers the strongest shared mechanism")
	func mechanismSelectionPrefersTheStrongest() {
		#expect(
			ClientNegotiationUtilities.nextSASLMechanism(
				from: ["SCRAM-SHA-256", "PLAIN"],
				offered: ["PLAIN", "SCRAM-SHA-256"],
				tried: []
			) == "SCRAM-SHA-256"
		)
		#expect(
			ClientNegotiationUtilities.nextSASLMechanism(
				from: ["SCRAM-SHA-256", "PLAIN"],
				offered: ["PLAIN"],
				tried: []
			) == "PLAIN"
		)
		#expect(
			ClientNegotiationUtilities.nextSASLMechanism(
				from: ["SCRAM-SHA-256", "PLAIN"],
				offered: ["PLAIN", "SCRAM-SHA-256"],
				tried: ["scram-sha-256"]
			) == "PLAIN"
		)
		#expect(
			ClientNegotiationUtilities.nextSASLMechanism(
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
		let short = ClientNegotiationUtilities.saslWireChunks(for: "me\0me\0hunter2")

		#expect(short.count == 1)
		#expect(short[0] == Data("me\0me\0hunter2".utf8).base64EncodedString())

		// 300 bytes encode to exactly 400 base64 characters.
		let exact = ClientNegotiationUtilities.saslWireChunks(for: String(repeating: "a", count: 300))

		#expect(exact.count == 2)
		#expect(exact[0].count == 400)
		#expect(exact[1] == "+")

		// 600 bytes encode to 800 characters: two full chunks, then the `+`.
		let twoFullChunks = ClientNegotiationUtilities.saslWireChunks(for: String(repeating: "a", count: 600))

		#expect(twoFullChunks.count == 3)
		#expect(twoFullChunks[0].count == 400)
		#expect(twoFullChunks[1].count == 400)
		#expect(twoFullChunks[2] == "+")

		// 601 bytes encode to 804 characters, so the short last chunk ends it.
		let shortLastChunk = ClientNegotiationUtilities.saslWireChunks(for: String(repeating: "a", count: 601))

		#expect(shortLastChunk.count == 3)
		#expect(shortLastChunk[0].count == 400)
		#expect(shortLastChunk[1].count == 400)
		#expect(shortLastChunk[2].count == 4)
	}

	/// sasl-3.2: "If the client wishes to send an empty response, it MUST send
	/// `AUTHENTICATE +`" — the mechanisms that carry no initial response, such
	/// as EXTERNAL, rely on this.
	@Test("sasl-3.2: an empty payload is sent as a single +")
	func emptyPayloadIsASinglePlus() {
		#expect(ClientNegotiationUtilities.saslWireChunks(for: "") == ["+"])
	}

	/// sasl-3.2: EXTERNAL needs a client certificate; PLAIN needs a password.
	/// Offering a mechanism the client has no credential for would only earn a
	/// 904.
	@Test("sasl-3.2: the mechanism list follows the credentials the client holds")
	func mechanismListFollowsCredentials() {
		#expect(
			ClientNegotiationUtilities.supportedSASLMechanisms(
				hasClientCertificate: true,
				externalMechanismDisabled: false,
				hasPassword: true,
				preferredMechanism: nil
			) == ["EXTERNAL", SCRAMClient.mechanismName, "PLAIN"]
		)
		#expect(
			ClientNegotiationUtilities.supportedSASLMechanisms(
				hasClientCertificate: false,
				externalMechanismDisabled: false,
				hasPassword: false,
				preferredMechanism: nil
			).isEmpty
		)
		#expect(
			ClientNegotiationUtilities.supportedSASLMechanisms(
				hasClientCertificate: true,
				externalMechanismDisabled: true,
				hasPassword: true,
				preferredMechanism: "plain"
			) == ["PLAIN", SCRAMClient.mechanismName]
		)
	}

	/// sasl-3.2: 902, 904, 905 and 906 all end the attempt; 903 and 907 mean
	/// the client is authenticated. The numerics table has to agree with the
	/// specification's assignment before any of the handling can be right.
	@Test("sasl-3.2: the authentication numerics")
	func saslNumericsMatchTheSpecification() {
		#expect(IRCNumeric.loggedin.rawValue == 900)
		#expect(IRCNumeric.loggedout.rawValue == 901)
		#expect(IRCNumeric.nicklocked.rawValue == 902)
		#expect(IRCNumeric.saslsuccess.rawValue == 903)
		#expect(IRCNumeric.saslfail.rawValue == 904)
		#expect(IRCNumeric.sasltoolong.rawValue == 905)
		#expect(IRCNumeric.saslaborted.rawValue == 906)
		#expect(IRCNumeric.saslalready.rawValue == 907)
		#expect(IRCNumeric.saslmechs.rawValue == 908)
	}

	/// The 9xx numerics sit outside the 400-596 error band, so they must not
	/// be routed to the generic error printer that would swallow them.
	@Test("sasl-3.2: the 9xx numerics are not generic error replies")
	func saslNumericsAreNotGenericErrors() {
		for numeric in UInt(900) ... UInt(908) {
			#expect(IRCNumeric.isErrorReply(numeric) == false)
		}
	}

	/// sasl-3.2 §"RPL_SASLMECHS": a 908 lists the mechanisms the server will
	/// accept, and the client retries with one it has not tried yet.
	@Test("sasl-3.2: 908 drives a retry with an untried mechanism")
	func saslMechanismsNumericDrivesARetry() throws {
		let client = client(password: "hunter2")
		client.isConnected = true
		try receive("CAP * LS :sasl=SCRAM-SHA-256,PLAIN", on: client)
		try receive("CAP me ACK :sasl", on: client)

		#expect(client.saslMechanism == SCRAMClient.mechanismName)

		let mechanisms = try #require(Message(line: ":irc.example.net 908 me PLAIN :Available mechanisms", on: client))
		#expect(client.handleTrackingNumeric(mechanisms.commandNumeric, message: mechanisms, shouldPrint: false))
		#expect(client.saslMechanism == "PLAIN")
		#expect(client.sentLines.contains("AUTHENTICATE PLAIN"))
		#expect(capabilityCommands(of: client).contains("END") == false)

		#expect(client.handleTrackingNumeric(mechanisms.commandNumeric, message: mechanisms, shouldPrint: false))
		#expect(client.isCapabilityEnabled(.isInSASLNegotiation) == false)
		#expect(capabilityCommands(of: client).last == "END")
	}

	/// A reassembled payload cannot be allowed to grow without bound: a server
	/// that keeps sending 400-byte chunks would otherwise be free to exhaust
	/// memory during registration.
	@Test("sasl-3.2: the reassembly buffer is bounded")
	func reassemblyBufferIsBounded() {
		#expect(ClientNegotiationUtilities.maximumSASLPayloadLength == 16384)
	}
}
