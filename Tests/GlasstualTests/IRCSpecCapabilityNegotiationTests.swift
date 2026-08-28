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
			nicknamePassword: password
		)
	}

	private func receive(_ line: String, on client: GLTTestClient) throws {
		let message = try #require(Message(line: line, on: client))

		client.receiveCapabilityOrAuthenticationRequest(message)
	}

	private func capabilityCommands(of client: GLTTestClient) -> [String] {
		client.sentCapabilityCommands.compactMap { $0 as? String }
	}

	// MARK: - CAP LS

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
		#expect(client.pendingCapabilityRequests.isEmpty == false)
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

	/// capability-negotiation: "Capability names are case-sensitive." Matching
	/// is done case-insensitively so an oddly-cased server still works, but
	/// what goes back out has to be the spelling the server advertised.
	@Test("CAP REQ echoes the spelling the server advertised")
	func requestsEchoTheAdvertisedSpelling() throws {
		let client = client()

		try receive(":irc.example.net CAP * LS :Multi-Prefix", on: client)

		#expect(capabilityCommands(of: client) == ["REQ Multi-Prefix"])
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

		// Standing in for the 903 that ends a real exchange.
		client.resumeQueuedCapabilityNegotiation()

		#expect(capabilityCommands(of: client) == ["REQ sasl", "END"])
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
	func saslMechanismsNumericDrivesARetry() {
		let client = client(password: "hunter2")

		#expect(client.selectSASLMechanism(fromOffered: ["SCRAM-SHA-256", "PLAIN"]))
		#expect(client.saslMechanism == SCRAMClient.mechanismName)

		#expect(client.retrySASLNegotiation(withMechanisms: ["PLAIN"]))
		#expect(client.saslMechanism == "PLAIN")

		#expect(client.retrySASLNegotiation(withMechanisms: ["PLAIN"]) == false)
	}

	/// A reassembled payload cannot be allowed to grow without bound: a server
	/// that keeps sending 400-byte chunks would otherwise be free to exhaust
	/// memory during registration.
	@Test("sasl-3.2: the reassembly buffer is bounded")
	func reassemblyBufferIsBounded() {
		#expect(ClientNegotiationUtilities.maximumSASLPayloadLength == 16384)
	}
}
