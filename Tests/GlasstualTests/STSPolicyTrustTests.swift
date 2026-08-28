import Foundation
@testable import Glasstual
import Testing

/// An STS policy outlives the connection that offered it, so IRCv3 requires it
/// to be ignored when the certificate did not validate on its own.
@Suite("STS policy trust")
@MainActor
struct STSPolicyTrustTests {
	/// A nil user defaults store keeps everything in memory.
	private func store() -> STSPolicyStore {
		STSPolicyStore(userDefaults: nil)
	}

	private func values(_ list: [String]) throws -> STSCapabilityValues {
		try #require(STSCapabilityValues.values(fromCapabilityValues: list))
	}

	@Test("A policy offered over an overridden certificate is ignored")
	func overriddenCertificateIsIgnored() throws {
		let store = store()
		let action = try store.applyCapabilityValues(
			values(["duration=300"]),
			forHost: "irc.example.net",
			connectedPort: 6697,
			secured: true,
			certificateChainValidated: false,
			upgradePort: nil
		)

		#expect(action == .none)
		#expect(store.policy(forHost: "irc.example.net") == nil)
	}

	@Test("An overridden certificate cannot withdraw an existing policy either")
	func overriddenCertificateCannotClear() throws {
		let store = store()

		store.setPolicy(
			STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: 300), preload: false),
			forHost: "irc.example.net"
		)

		let action = try store.applyCapabilityValues(
			values(["duration=0"]),
			forHost: "irc.example.net",
			connectedPort: 6697,
			secured: true,
			certificateChainValidated: false,
			upgradePort: nil
		)

		#expect(action == .none)
		#expect(store.policy(forHost: "irc.example.net") != nil)
	}

	@Test("A validated certificate still stores the policy")
	func validatedCertificateStoresPolicy() throws {
		let store = store()
		let action = try store.applyCapabilityValues(
			values(["duration=300"]),
			forHost: "irc.example.net",
			connectedPort: 6697,
			secured: true,
			certificateChainValidated: true,
			upgradePort: nil
		)

		#expect(action == .stored)
		#expect(store.policy(forHost: "irc.example.net")?.port == 6697)
	}

	@Test("An unbounded duration is capped")
	func durationIsCapped() throws {
		let store = store()
		let action = try store.applyCapabilityValues(
			values(["duration=99999999999"]),
			forHost: "irc.example.net",
			connectedPort: 6697,
			secured: true,
			certificateChainValidated: true,
			upgradePort: nil
		)

		#expect(action == .stored)

		let policy = try #require(store.policy(forHost: "irc.example.net"))
		let cap = Date(timeIntervalSinceNow: STSPolicyStore.maximumPolicyDuration)

		/* Allow a little slack for the time the call itself took. */
		#expect(policy.expiresAt <= cap.addingTimeInterval(5))
	}

	@Test("A plaintext connection still upgrades regardless of validation")
	func plaintextStillUpgrades() throws {
		let store = store()
		var upgradePort: UInt16 = 0
		let action = try store.applyCapabilityValues(
			values(["port=6697", "duration=300"]),
			forHost: "irc.example.net",
			connectedPort: 6667,
			secured: false,
			certificateChainValidated: false,
			upgradePort: &upgradePort
		)

		#expect(action == .upgrade)
		#expect(upgradePort == 6697)
	}
}
