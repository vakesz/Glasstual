// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

/// `CAP END` may be held back for more than one reason at a time, and each
/// reason is lifted on its own.
@MainActor
@Suite("Capability negotiation holds")
struct CapabilityNegotiationHoldsTests {
	@Test("CAP END waits until every hold lifts")
	func endWaitsForEveryHold() throws {
		let session = TestServerSession()

		session.pauseCapabilityNegotiation(.sasl)
		session.pauseCapabilityNegotiation(.accountRegistration)
		try receive(":irc.example.net CAP * LS :example.com/vendor", on: session)
		#expect(capabilityCommands(of: session).isEmpty)

		session.resumeCapabilityNegotiation(.sasl)
		#expect(capabilityCommands(of: session).isEmpty)
		#expect(session.capabilityNegotiation.holds == .accountRegistration)

		session.resumeCapabilityNegotiation(.accountRegistration)
		#expect(capabilityCommands(of: session) == ["END"])
	}

	@Test("Lifting one reason leaves the other in force")
	func liftingOneLeavesTheOther() {
		var state = CapabilityNegotiationState()

		state.holds.insert(.sasl)
		state.holds.insert(.accountRegistration)
		state.holds.remove(.accountRegistration)

		#expect(state.isPaused)
		#expect(state.holds == .sasl)
	}

	@Test("A reset clears every hold")
	func resetClearsHolds() {
		var state = CapabilityNegotiationState()

		state.holds = [.sasl, .accountRegistration]
		state.reset()

		#expect(state.holds.isEmpty)
		#expect(state.isPaused == false)
	}

	@Test("A logout during the registration exchange lifts the SASL hold and ends negotiation")
	func logoutDuringRegistrationExchangeLiftsHold() throws {
		let session = TestServerSession(configDictionary: ["usesSASL": true], nicknamePassword: "secret")
		defer { session.stopAllTimers() }
		session.setConnectionTransportForTesting(.connected)
		session.userNickname = "me"
		try receive(":irc.example.net CAP * LS :sasl=PLAIN", on: session)
		try receive(":irc.example.net CAP * ACK :sasl", on: session)
		#expect(session.capabilityNegotiation.holds.contains(.sasl))
		#expect(capabilityCommands(of: session).contains("END") == false)

		let logout = try #require(Message(line: ":irc.example.net 901 me me!u@h :You are now logged out", on: session))
		session.handleAuthenticationTrackingNumeric(.loggedout, message: logout, shouldPrint: false)

		#expect(session.capabilityNegotiation.holds.isEmpty)
		#expect(capabilityCommands(of: session).last == "END")
	}

	@Test("Ending SASL on teardown leaves only the other holds")
	func resetLiftsSASLHold() {
		let session = TestServerSession()
		session.pauseCapabilityNegotiation(.sasl)
		session.pauseCapabilityNegotiation(.accountRegistration)

		session.resetSASLNegotiation()

		#expect(session.capabilityNegotiation.holds == .accountRegistration)
	}

	@Test("A finished re-authentication lifts only its own hold", arguments: [true, false])
	func reauthenticationKeepsRegistrationHold(failed: Bool) {
		let session = TestServerSession()
		defer { session.stopAllTimers() }
		session.pauseCapabilityNegotiation(.sasl)
		session.pauseCapabilityNegotiation(.accountRegistration)

		session.finishSASLReauthentication(failed: failed, wasIdentified: false, mechanism: .plain)

		#expect(session.capabilityNegotiation.holds == .accountRegistration)
		#expect(capabilityCommands(of: session).isEmpty)
	}

	private func receive(_ line: String, on session: TestServerSession) throws {
		try session.handleCapabilityOrAuthenticationRequest(#require(Message(line: line, on: session)))
	}

	private func capabilityCommands(of session: TestServerSession) -> [String] {
		session.sentCapabilityCommands.compactMap { $0 as? String }
	}
}
