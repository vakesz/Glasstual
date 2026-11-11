// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("STS upgrade transitions")
struct STSUpgradeStateTests {
	private let endpoint = PendingIRCEndpoint(
		host: "irc.example.net", port: 6697, secured: true, origin: nil, reason: .stsUpgrade
	)

	private func policy() throws -> STSConnectionPolicy {
		let values = try #require(STSCapabilityValues.values(fromCapabilityValues: ["duration=300", "port=6697"]))
		return STSConnectionPolicy(host: "irc.example.net", port: 6697, values: values)
	}

	@Test("One attempt upgrades once")
	func attemptUpgradesOnce() {
		var state = STSUpgradeState()

		let first = state.beginUpgrade(to: endpoint)
		let second = state.beginUpgrade(to: endpoint)

		#expect(first)
		#expect(second == false)
		#expect(state.lastAttempt?.host == "irc.example.net")
	}

	@Test("Securing reports the attempt once and allows another upgrade")
	func securingReportsTheAttempt() {
		var state = STSUpgradeState()
		_ = state.beginUpgrade(to: endpoint)

		let secured = state.noteSecured()
		let securedAgain = state.noteSecured()

		#expect(secured?.port == 6697)
		#expect(securedAgain == nil)
		#expect(state.performedUpgrade == false)
	}

	@Test("A failed close before TLS reports the attempt; a clean one keeps it")
	func failedCloseReportsTheAttempt() {
		var state = STSUpgradeState()
		_ = state.beginUpgrade(to: endpoint)

		let clean = state.noteDisconnect(withError: false, secured: false)
		#expect(clean == nil)
		#expect(state.lastAttempt != nil)

		let failed = state.noteDisconnect(withError: true, secured: false)
		#expect(failed?.host == "irc.example.net")
		#expect(state.lastAttempt == nil)
	}

	@Test("A secured close forgets the attempt without reporting it")
	func securedCloseForgetsTheAttempt() {
		var state = STSUpgradeState()
		_ = state.beginUpgrade(to: endpoint)

		let reported = state.noteDisconnect(withError: true, secured: true)

		#expect(reported == nil)
		#expect(state.lastAttempt == nil)
	}

	/// The flag guards one attempt: a connect that failed before TLS leaves it
	/// set until teardown, which clears it whatever happened.
	@Test("A failed connect before TLS leaves the flag for teardown to clear")
	func teardownClearsTheFlag() throws {
		var state = STSUpgradeState()
		_ = state.beginUpgrade(to: endpoint)
		_ = state.noteDisconnect(withError: true, secured: false)
		#expect(state.performedUpgrade)
		state.activePolicy = try policy()

		let persisted = state.resetForTeardown()
		let persistedAgain = state.resetForTeardown()

		#expect(persisted?.port == 6697)
		#expect(persistedAgain == nil)
		#expect(state.performedUpgrade == false)
	}
}
