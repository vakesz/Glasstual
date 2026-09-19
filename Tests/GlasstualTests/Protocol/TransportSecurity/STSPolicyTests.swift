// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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

	@Test("A policy written to user defaults is read back by a fresh store")
	func policyPersistsAndReloadsFromUserDefaults() throws {
		let suiteName = "STSPolicyTests.\(UUID().uuidString)"
		let userDefaults = try #require(UserDefaults(suiteName: suiteName))
		defer { userDefaults.removePersistentDomain(forName: suiteName) }

		let store = STSPolicyStore(userDefaults: userDefaults)
		let policy = STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: 300), preload: true)

		store.setPolicy(policy, forHost: "IRC.EXAMPLE.NET")

		let storedDictionary = try #require(userDefaults.dictionary(forKey: SettingsKeys.Connection.stsPolicies.name))

		#expect(storedDictionary["irc.example.net"] != nil)

		let reloadedStore = STSPolicyStore(userDefaults: userDefaults)
		let reloadedPolicy = try #require(reloadedStore.policy(forHost: "irc.example.net"))

		#expect(reloadedPolicy.port == 6697)
		#expect(reloadedPolicy.preload)
	}

	@Test("A host under policy is forced onto the policy's port")
	func applyPolicyForcesSecuredConnectionOnPolicyPort() {
		let store = makeStore()

		store.setPolicy(
			STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: 300), preload: false),
			forHost: "irc.example.net"
		)

		#expect(store.enforcedPort(forHost: "irc.example.net") == 6697)
	}

	@Test("A host with no policy is left with the endpoint the caller had")
	func applyPolicyNeverDowngrades() {
		let store = makeStore()

		/* No policy: nothing to enforce, so the caller keeps what it had. */
		#expect(store.enforcedPort(forHost: "irc.example.net") == nil)
	}

	@Test("A validated secure connection stores the policy on the port it connected to")
	func securedConnectionStoresPolicy() throws {
		let store = makeStore()
		let values = try #require(STSCapabilityValues.values(fromCapabilityValues: ["duration=300"]))
		let action: STSPolicyAction = store.applyCapabilityValues(
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

	/** A policy is about a name, not a spelling of it. `irc.example.com.` is the
	 root-anchored form of `irc.example.com`, a bracketed IPv6 literal is the
	 same host as a bare one, and DNS names are case-insensitive. Keying on the
	 text as typed filed those as separate hosts, so a policy stored under the
	 spelling one connection used never applied to the next. */
	@Test(arguments: [
		("irc.example.com.", "irc.example.com"),
		("irc.example.com", "irc.example.com."),
		("IRC.Example.COM", "irc.example.com"),
		("irc.example.com..", "IRC.EXAMPLE.COM."),
		("[2001:db8::1]", "2001:db8::1"),
	])
	func spellingsOfTheSameHostShareOnePolicy(_ stored: String, _ looked: String) {
		let store = makeStore()
		store.setPolicy(STSPolicy(port: 6697, expiresAt: .distantFuture, preload: false), forHost: stored)

		#expect(store.policy(forHost: looked) != nil)
	}

	/// Normalising has to stop at the host: two different names still get two
	/// different policies.
	@Test("Different hosts keep different policies")
	func differentHostsAreNotMerged() {
		let store = makeStore()
		store.setPolicy(STSPolicy(port: 6697, expiresAt: .distantFuture, preload: false), forHost: "irc.example.com")

		#expect(store.policy(forHost: "irc.example.net") == nil)
		#expect(store.policy(forHost: "other.irc.example.com") == nil)
	}

	/// Removing has to normalise the same way, or a policy the user cleared
	/// under one spelling stays in force under another.
	@Test("A policy is removed whichever spelling names it")
	func removalNormalisesTheSameWay() {
		let store = makeStore()
		store.setPolicy(STSPolicy(port: 6697, expiresAt: .distantFuture, preload: false), forHost: "irc.example.com")

		store.removePolicy(forHost: "IRC.example.com.")

		#expect(store.policy(forHost: "irc.example.com") == nil)
	}
}

/** `performedSTSUpgrade` stops one connection attempt from upgrading twice.

 It was cleared only by a successful TLS handshake, so an upgrade that failed to
 connect left it set for the life of the session object and every later STS offer
 from that server was ignored — the session kept talking in the clear to a server
 that had asked it not to. The session the flag guards ends at the disconnect. */
@MainActor
@Suite("STS upgrade state")
struct ConnectionSTSUpgradeResetTests {
	@Test("A disconnect clears the upgrade flag")
	func disconnectClearsTheUpgradeFlag() {
		let session = TestServerSession(configDictionary: ["nickname": "mara"])
		defer { session.stopAllTimers() }
		session.performedSTSUpgrade = true

		session.resetAllPropertyValues()

		#expect(session.performedSTSUpgrade == false)
	}
}
