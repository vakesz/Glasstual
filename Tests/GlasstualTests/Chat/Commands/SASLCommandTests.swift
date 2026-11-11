// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// `/sasl` shows how the connection signs in and changes the preferred mechanism.
@MainActor
@Suite("/sasl")
struct SASLCommandTests {
	private func session() -> TestServerSession {
		TestServerSession(configDictionary: ["nickname": "me", "username": "me"], nicknamePassword: "secret")
	}

	private func printed(by session: TestServerSession) -> [String] {
		(session.printedLines as NSArray).compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
	}

	@Test("The subcommands are read into requests", arguments: [
		("", SASLCommandRequest.status),
		("status", .status),
		("mechanism plain", .mechanism(.plain, only: false)),
		("mechanism SCRAM-SHA-256 only", .mechanism(.scramSHA256, only: true)),
		("mechanism automatic", .mechanism(nil, only: false)),
		("mechanism automatic only", .invalid),
		("mechanism gssapi", .unknownMechanism("gssapi")),
		("mechanism", .invalid),
		("mechanism plain later", .invalid),
		("status extra", .invalid),
		("frobnicate", .invalid),
	])
	func requestsAreParsed(_ line: String, _ expected: SASLCommandRequest) {
		#expect(SASLCommandRequest(CommandArguments(line)) == expected)
	}

	@Test("Status lists the account, the offer, the preference and every mechanism")
	func statusListsEverything() {
		let session = session()
		session.capabilityNegotiation.offer("sasl", values: ["SCRAM-SHA-256", "PLAIN"])
		session.config.saslMechanismPreference = .plain
		session.identity.account = "alice"

		session.sendCommand("sasl status", completeTarget: false)

		let lines = printed(by: session)
		#expect(lines.contains(String(localized: .IRC.saslStatusAccount("alice"))))
		#expect(lines.contains(String(localized: .IRC.saslStatusOffered("SCRAM-SHA-256, PLAIN"))))
		#expect(lines.contains(String(localized: .IRC.saslStatusPreference("PLAIN"))))
		for mechanism in SASLMechanism.defaultOrder {
			#expect(lines.contains { $0.hasPrefix(mechanism.wireName) })
		}
		#expect(lines.contains(String(localized: .IRC.saslStatusMechanismLine(
			"EXTERNAL",
			String(localized: .IRC.saslUnavailableNoClientCertificate)
		))))
	}

	@Test("Status says when the server offers no SASL and nobody is signed in")
	func statusWithoutOffer() {
		let session = session()

		session.sendCommand("sasl", completeTarget: false)

		let lines = printed(by: session)
		#expect(lines.contains(String(localized: .IRC.saslStatusNotSignedIn)))
		#expect(lines.contains(String(localized: .IRC.saslStatusNotOffered)))
		#expect(lines.contains(String(localized: .IRC.saslStatusPreferenceAutomatic)))
	}

	@Test("Choosing a mechanism stores it, and only stops fallback")
	func mechanismIsStored() {
		let session = session()

		session.sendCommand("sasl mechanism plain", completeTarget: false)
		#expect(session.config.saslMechanismPreference == .plain)
		#expect(session.config.saslUsesOnlyPreferredMechanism == false)

		session.sendCommand("sasl mechanism scram-sha-256 only", completeTarget: false)
		#expect(session.config.saslMechanismPreference == .scramSHA256)
		#expect(session.config.saslUsesOnlyPreferredMechanism)
		#expect(printed(by: session).last == String(localized: .IRC.saslMechanismSetOnly("SCRAM-SHA-256")))
	}

	@Test("Automatic clears the preference and the switch")
	func automaticClears() {
		let session = session()
		session.config.saslMechanismPreference = .plain
		session.config.saslUsesOnlyPreferredMechanism = true

		session.sendCommand("sasl mechanism automatic", completeTarget: false)

		#expect(session.config.saslMechanismPreference == nil)
		#expect(session.config.saslUsesOnlyPreferredMechanism == false)
	}

	@Test("An unknown mechanism is reported and changes nothing")
	func unknownMechanismChangesNothing() {
		let session = session()
		session.config.saslMechanismPreference = .plain

		session.sendCommand("sasl mechanism gssapi", completeTarget: false)

		#expect(session.config.saslMechanismPreference == .plain)
		#expect(printed(by: session).last == String(localized: .IRC.saslMechanismUnknown(
			"gssapi",
			SASLMechanism.defaultOrder.map(\.wireName).joined(separator: ", ")
		)))
	}

	/// With only this mechanism allowed, a refused attempt ends SASL rather than
	/// falling back to a weaker one.
	@Test("Use Only This Mechanism stops the fallback from SCRAM to PLAIN")
	func onlyThisMechanismStopsFallback() {
		let session = session()
		session.config.saslMechanismPreference = .scramSHA256
		session.config.saslUsesOnlyPreferredMechanism = true

		#expect(session.selectSASLMechanism(fromOffered: ["PLAIN", "SCRAM-SHA-256"]))
		#expect(session.sasl.mechanism == .scramSHA256)
		#expect(session.retrySASLNegotiation(withMechanisms: ["PLAIN"]) == false)
	}
}
