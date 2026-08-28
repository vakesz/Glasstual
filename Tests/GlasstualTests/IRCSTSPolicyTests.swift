/*  *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

@MainActor
@Suite("Strict transport security policy", .serialized)
struct STSPolicyTests {
	/** A nil user defaults store keeps everything in memory. */
	private func makeStore() -> STSPolicyStore {
		STSPolicyStore(userDefaults: nil)
	}

	@Test("Every capability value the specification defines is read")
	func parseFullCapabilityValues() throws {
		let values = try #require(STSCapabilityValues.values(fromCapabilityValues: [
			"port=6697",
			"duration=300",
			"preload",
		]))

		#expect(values.port == 6697)
		#expect(values.hasDuration)
		#expect(values.duration == 300)
		#expect(values.preload)
	}

	@Test("A duration on its own leaves the other values at their defaults")
	func parseDurationOnly() throws {
		let values = try #require(STSCapabilityValues.values(fromCapabilityValues: ["duration=0"]))

		#expect(values.port == 0)
		#expect(values.hasDuration)
		#expect(values.duration == 0)
		#expect(values.preload == false)
	}

	@Test("An unparsable port is zero, and a value made only of unknown keys is nothing")
	func parseRejectsInvalidPortAndUnknownKeys() throws {
		/* "port" is a key the parser knows, so the value survives even when the
		 port itself does not parse. */
		let values = try #require(STSCapabilityValues.values(fromCapabilityValues: [
			"port=notaport",
			"port=99999",
		]))

		#expect(values.port == 0)

		#expect(STSCapabilityValues.values(fromCapabilityValues: []) == nil)
		#expect(STSCapabilityValues.values(fromCapabilityValues: ["vendor=thing"]) == nil)
	}

	@Test("A stored policy is found again under any casing of its host")
	func storeAndRetrievePolicy() throws {
		let store = makeStore()
		let policy = STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: 300), preload: false)

		store.setPolicy(policy, forHost: "irc.example.net")

		let stored = try #require(store.policy(forHost: "IRC.EXAMPLE.NET")) // Case insensitive

		#expect(stored.port == 6697)
	}

	@Test("A policy past its expiry is no longer reported")
	func expiredPolicyIsForgotten() {
		let store = makeStore()
		let policy = STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: -1), preload: false)

		store.setPolicy(policy, forHost: "irc.example.net")

		#expect(store.policy(forHost: "irc.example.net") == nil)
	}

	@Test("A policy written to user defaults is read back by a fresh store")
	func policyPersistsAndReloadsFromUserDefaults() throws {
		let suiteName = "STSPolicyTests.\(UUID().uuidString)"
		let userDefaults = try #require(UserDefaults(suiteName: suiteName))
		defer { userDefaults.removePersistentDomain(forName: suiteName) }

		let store = STSPolicyStore(userDefaults: userDefaults)
		let policy = STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: 300), preload: true)

		store.setPolicy(policy, forHost: "IRC.EXAMPLE.NET")

		let storedDictionary = try #require(userDefaults.dictionary(forKey: IRCSTSPolicyStoreDefaultsKey))

		#expect(storedDictionary["irc.example.net"] != nil)

		let reloadedStore = STSPolicyStore(userDefaults: userDefaults)
		let reloadedPolicy = try #require(reloadedStore.policy(forHost: "irc.example.net"))

		#expect(reloadedPolicy.port == 6697)
		#expect(reloadedPolicy.preload)
	}

	@Test("A host under policy is forced onto the policy's port")
	func applyPolicyForcesSecuredConnectionOnPolicyPort() throws {
		let store = makeStore()

		store.setPolicy(
			STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: 300), preload: false),
			forHost: "irc.example.net"
		)

		let enforced = try #require(store.enforcedEndpoint(forHost: "irc.example.net"))

		#expect(enforced.port == 6697)
	}

	@Test("A host with no policy is left with the endpoint the caller had")
	func applyPolicyNeverDowngrades() {
		let store = makeStore()

		/* No policy: nothing to enforce, so the caller keeps what it had. */
		#expect(store.enforcedEndpoint(forHost: "irc.example.net") == nil)
	}

	@Test("An advertised port on a plaintext connection upgrades without being stored")
	func plaintextConnectionWithPortDecidesUpgrade() throws {
		let store = makeStore()
		let values = try #require(STSCapabilityValues.values(fromCapabilityValues: [
			"port=6697",
			"duration=300",
		]))
		let action: IRCSTSPolicyAction = store.applyCapabilityValues(
			values,
			forHost: "irc.example.net",
			connectedPort: 6667,
			secured: false,
			certificateChainValidated: false
		)

		#expect(action == .upgrade(port: 6697))
		/* Nothing is stored from an insecure connection. */
		#expect(store.policy(forHost: "irc.example.net") == nil)
	}

	@Test("A validated secure connection stores the policy on the port it connected to")
	func securedConnectionStoresPolicy() throws {
		let store = makeStore()
		let values = try #require(STSCapabilityValues.values(fromCapabilityValues: ["duration=300"]))
		let action: IRCSTSPolicyAction = store.applyCapabilityValues(
			values,
			forHost: "irc.example.net",
			connectedPort: 6697,
			secured: true,
			certificateChainValidated: true
		)

		#expect(action == .stored(port: 6697))

		let policy = try #require(store.policy(forHost: "irc.example.net"))

		#expect(policy.port == 6697) // The connected port when none advertised
	}

	@Test("A zero duration over a secure connection withdraws the stored policy")
	func securedConnectionWithZeroDurationClearsPolicy() throws {
		let store = makeStore()

		store.setPolicy(
			STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: 300), preload: false),
			forHost: "irc.example.net"
		)

		let values = try #require(STSCapabilityValues.values(fromCapabilityValues: ["duration=0"]))
		let action: IRCSTSPolicyAction = store.applyCapabilityValues(
			values,
			forHost: "irc.example.net",
			connectedPort: 6697,
			secured: true,
			certificateChainValidated: true
		)

		#expect(action == .cleared)
		#expect(store.policy(forHost: "irc.example.net") == nil)
	}
}
