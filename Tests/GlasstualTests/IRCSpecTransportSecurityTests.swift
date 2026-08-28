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

/// IRCv3 `sts` — Strict Transport Security. The capability's value is a
/// comma-separated key list, and what the client does with it depends on
/// whether the connection it arrived over was itself secure.
@Suite("IRCv3 STS")
@MainActor
struct IRCSpecTransportSecurityTests {
	private func store() -> STSPolicyStore {
		STSPolicyStore(userDefaults: UserDefaults(suiteName: "com.vakesz.glasstual.tests.sts.\(UUID().uuidString)"))
	}

	private func values(_ token: String) throws -> STSCapabilityValues {
		let offered = CapabilityRegistry.parseCapabilityList("sts=\(token)")
		let capabilityValues = try #require(offered["sts"])

		return try #require(STSCapabilityValues.values(fromCapabilityValues: capabilityValues))
	}

	// MARK: - The capability value

	/// `sts`: the value is `key[=value]` pairs joined by commas, and the keys
	/// are `duration`, `port` and `preload`.
	@Test("sts: duration, port and preload are read")
	func capabilityKeysAreRead() throws {
		let parsed = try values("duration=2592000,port=6697,preload")

		#expect(parsed.hasDuration)
		#expect(parsed.duration == 2_592_000)
		#expect(parsed.port == 6697)
		#expect(parsed.preload)
	}

	/// `sts`: "Clients MUST ignore every key they do not understand", and a
	/// value made only of unknown keys says nothing at all.
	@Test("sts: unknown keys are ignored, and a value of only unknown keys is no offer")
	func unknownKeysAreIgnored() throws {
		let parsed = try values("duration=300,future-key=1")

		#expect(parsed.duration == 300)
		#expect(STSCapabilityValues.values(fromCapabilityValues: ["future-key=1"]) == nil)
		#expect(STSCapabilityValues.values(fromCapabilityValues: []) == nil)
	}

	/// A `duration` or `port` that is not a number is not a value the client
	/// can act on, and reading it as zero would silently clear a policy.
	@Test("sts: a non-numeric duration or port is not read")
	func nonNumericValuesAreNotRead() throws {
		let parsed = try values("duration=forever,port=six")

		#expect(parsed.hasDuration == false)
		#expect(parsed.port == 0)
	}

	/// A port outside the TCP range cannot be connected to.
	@Test("sts: a port outside the TCP range is discarded")
	func portsOutsideTheTCPRangeAreDiscarded() throws {
		#expect(try values("port=0,duration=1").port == 0)
		#expect(try values("port=65536,duration=1").port == 0)
		#expect(try values("port=65535,duration=1").port == 65535)
	}

	// MARK: - Acting on the offer

	/// `sts`: "If the client is not already connected securely ... it MUST
	/// close the connection and reconnect securely on the port given."
	@Test("sts: an offer over a cleartext connection upgrades it")
	func cleartextOffersUpgrade() throws {
		let action = try store().applyCapabilityValues(
			values("port=6697,duration=2592000"),
			forHost: "irc.example.net",
			connectedPort: 6667,
			secured: false,
			certificateChainValidated: false
		)

		#expect(action == .upgrade(port: 6697))
	}

	/// The `duration` half of the offer means nothing over cleartext: only the
	/// port matters, because the policy is stored on the secure connection.
	@Test("sts: a cleartext offer with no port does nothing")
	func cleartextOffersWithoutAPortDoNothing() throws {
		let action = try store().applyCapabilityValues(
			values("duration=2592000"),
			forHost: "irc.example.net",
			connectedPort: 6667,
			secured: false,
			certificateChainValidated: false
		)

		#expect(action == .none)
	}

	/// `sts`: "Clients MUST NOT save the policy if the connection's TLS
	/// certificate did not validate" — otherwise one clicked-through
	/// certificate pins the host.
	@Test("sts: a policy is not stored over an unvalidated certificate")
	func unvalidatedCertificatesStoreNoPolicy() throws {
		let policyStore = store()
		let action = try policyStore.applyCapabilityValues(
			values("duration=2592000,port=6697"),
			forHost: "irc.example.net",
			connectedPort: 6697,
			secured: true,
			certificateChainValidated: false
		)

		#expect(action == .none)
		#expect(policyStore.policy(forHost: "irc.example.net") == nil)
	}

	/// `sts`: over a validated secure connection the policy is stored for the
	/// advertised duration, pinned to the advertised port — or, when none is
	/// given, to the port the client is already on.
	@Test("sts: a validated offer stores a policy")
	func validatedOffersStoreAPolicy() throws {
		let policyStore = store()
		let action = try policyStore.applyCapabilityValues(
			values("duration=2592000,port=6697"),
			forHost: "irc.example.net",
			connectedPort: 6697,
			secured: true,
			certificateChainValidated: true
		)

		#expect(action == .stored(port: 6697))

		let policy = try #require(policyStore.policy(forHost: "irc.example.net"))

		#expect(policy.port == 6697)
		#expect(policy.isExpired == false)
		#expect(policyStore.enforcedEndpoint(forHost: "irc.example.net") == STSPolicyEndpoint(port: 6697))
	}

	@Test("sts: an offer with no port pins the port already in use")
	func offersWithoutAPortPinTheCurrentPort() throws {
		let policyStore = store()
		let action = try policyStore.applyCapabilityValues(
			values("duration=2592000"),
			forHost: "irc.example.net",
			connectedPort: 7000,
			secured: true,
			certificateChainValidated: true
		)

		#expect(action == .stored(port: 7000))
	}

	/// `sts`: "A duration of 0 means the policy expires immediately", which is
	/// how a server withdraws one.
	@Test("sts: duration=0 withdraws a stored policy")
	func zeroDurationWithdrawsThePolicy() throws {
		let policyStore = store()

		_ = try policyStore.applyCapabilityValues(
			values("duration=2592000,port=6697"),
			forHost: "irc.example.net",
			connectedPort: 6697,
			secured: true,
			certificateChainValidated: true
		)

		let action = try policyStore.applyCapabilityValues(
			values("duration=0"),
			forHost: "irc.example.net",
			connectedPort: 6697,
			secured: true,
			certificateChainValidated: true
		)

		#expect(action == .cleared)
		#expect(policyStore.policy(forHost: "irc.example.net") == nil)
	}

	/// An offer with no `duration` at all is not a policy to store; only the
	/// upgrade half of the specification applies to it.
	@Test("sts: an offer with no duration stores nothing")
	func offersWithoutADurationStoreNothing() throws {
		let policyStore = store()
		let action = try policyStore.applyCapabilityValues(
			values("port=6697"),
			forHost: "irc.example.net",
			connectedPort: 6697,
			secured: true,
			certificateChainValidated: true
		)

		#expect(action == .none)
		#expect(policyStore.policy(forHost: "irc.example.net") == nil)
	}

	/// `duration` is otherwise unbounded, so a server that speaks for a host
	/// once could pin it for centuries. The stored lifetime is capped.
	@Test("sts: an absurd duration is capped")
	func absurdDurationsAreCapped() throws {
		let policyStore = store()

		_ = try policyStore.applyCapabilityValues(
			values("duration=999999999,port=6697"),
			forHost: "irc.example.net",
			connectedPort: 6697,
			secured: true,
			certificateChainValidated: true
		)

		let policy = try #require(policyStore.policy(forHost: "irc.example.net"))
		let cap = STSPolicyStore.maximumPolicyDuration

		#expect(policy.expiresAt.timeIntervalSinceNow <= cap + 1)
	}

	/// Host names are case-insensitive, so a policy stored for one spelling
	/// has to be found under any other.
	@Test("sts: a stored policy is found whatever the host's case")
	func storedPoliciesAreFoundCaseInsensitively() throws {
		let policyStore = store()

		_ = try policyStore.applyCapabilityValues(
			values("duration=2592000,port=6697"),
			forHost: "IRC.Example.NET",
			connectedPort: 6697,
			secured: true,
			certificateChainValidated: true
		)

		#expect(policyStore.policy(forHost: "irc.example.net") != nil)
	}

	/// An expired policy no longer pins anything.
	@Test("sts: an expired policy is not enforced")
	func expiredPoliciesAreNotEnforced() {
		let policyStore = store()
		let expired = STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: -1), preload: false)

		policyStore.setPolicy(expired, forHost: "irc.example.net")

		#expect(expired.isExpired)
		#expect(policyStore.policy(forHost: "irc.example.net") == nil)
		#expect(policyStore.enforcedEndpoint(forHost: "irc.example.net") == nil)
	}
}
