// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Sign In Again sheet")
struct SASLSignInModelTests {
	private func session(offering mechanisms: [String]) -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "usesSASL": true], nicknamePassword: "secret")
		session.setConnectionTransportForTesting(.connected)
		session.capabilityNegotiation.offer("sasl", values: mechanisms)
		_ = session.capabilityNegotiation.acknowledge("sasl")
		session.markAsLoggedIn()
		return session
	}

	@Test("The options are the offered mechanisms the session knows, gated ones with their reason")
	func optionsFollowTheOffer() {
		let session = session(offering: ["PLAIN", "EXTERNAL", "GSSAPI"])
		let model = SASLSignInModel(session: session)

		#expect(model.options.map(\.mechanism) == [.external, .plain])
		#expect(model.options.first?.unavailableReason == SASLAvailabilityText.describe(.noClientCertificate))
		#expect(model.options.last?.unavailableReason == nil)
		withExtendedLifetime(session) {}
	}

	@Test("A refusal becomes the failed state")
	func refusalFails() {
		let session = session(offering: ["PLAIN"])
		let model = SASLSignInModel(session: session)
		model.selection = .mechanism(.external)

		model.signIn()
		withExtendedLifetime(session) {}

		#expect(model.state == .failed(SASLReauthenticationRefusal.mechanismNotOffered(.external).localizedDescription))
		#expect(model.isFinished)
	}

	@Test("The exchange drives the result row")
	func statusDrivesTheResult() throws {
		let session = session(offering: ["PLAIN"])
		defer { session.stopAllTimers() }
		let model = SASLSignInModel(session: session)
		#expect(model.canSignIn)

		model.signIn()
		#expect(model.state == .inProgress)
		#expect(model.canSignIn == false)

		let account = try #require(Message(line: ":irc.example.net 900 me me!u@h acct :Logged in", on: session))
		let success = try #require(Message(line: ":irc.example.net 903 me :Success", on: session))
		session.handleAuthenticationTrackingNumeric(.loggedin, message: account, shouldPrint: false)
		session.handleAuthenticationTrackingNumeric(.saslsuccess, message: success, shouldPrint: false)

		#expect(model.state == .succeeded(String(localized: .AccountSignIn.signedInWith("acct", "PLAIN"))))
		#expect(model.account == "acct")
	}
}
