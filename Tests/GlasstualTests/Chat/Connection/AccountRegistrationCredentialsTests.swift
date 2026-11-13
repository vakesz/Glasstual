// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// A registration that succeeds saves its password for SASL, and only the one
/// the user asked for.
@MainActor
@Suite("Account registration credentials", .timeLimit(.minutes(1)))
struct AccountRegistrationCredentialsTests {
	private func registeredSession(keychainWorks: Bool = true) throws -> TestServerSession {
		let session = makeRegistrationSession(keychainWorks: keychainWorks)
		try session.negotiate("draft/account-registration=custom-account-name")
		try session.receive(":irc.example.net 001 ada :Welcome")

		return session
	}

	@Test("Success saves the password, turns SASL on and names the account only when it differs")
	func successSavesCredentials() async throws {
		let session = try registeredSession()
		let log = AccountRegistrationEventLog()

		session.registerAccount(
			AccountRegistrationRequest(account: .currentNickname, email: nil, password: "first pass"),
			observer: log.observer
		)
		try session.receive(":irc.example.net REGISTER SUCCESS ADA :Done")
		try await Eventually.until("the save") { log.events.count == 2 }

		#expect(log.last == .succeeded(account: "ADA", serverMessage: "Done", credentialsSaved: true))
		#expect(session.config.usesSASL)
		#expect(session.config.username.isEmpty)
		#expect(session.sessionCredentials.password(for: session.config.nicknamePasswordKeychainItem) == "first pass")

		let second = try registeredSession()
		let secondLog = AccountRegistrationEventLog()
		second.registerAccount(
			AccountRegistrationRequest(account: .named("lovelace"), email: nil, password: "second"),
			observer: secondLog.observer
		)
		try second.receive(":irc.example.net REGISTER SUCCESS lovelace :Done")
		try await Eventually.until("the save") { secondLog.events.count == 2 }

		#expect(second.config.username == "lovelace")
	}

	@Test("A success for another account saves nothing")
	func mismatchedAccountSavesNothing() throws {
		let session = try registeredSession()
		let log = AccountRegistrationEventLog()

		session.registerAccount(
			AccountRegistrationRequest(account: .named("lovelace"), email: nil, password: "pw"),
			observer: log.observer
		)
		try session.receive(":irc.example.net REGISTER SUCCESS babbage :Done")

		#expect(log.last == .succeeded(account: "babbage", serverMessage: "Done", credentialsSaved: false))
		#expect(session.config.usesSASL == false)
		#expect(session.sessionCredentials.password(for: session.config.nicknamePasswordKeychainItem) == nil)
	}

	@Test("A keychain failure is reported as not saved")
	func keychainFailure() async throws {
		let session = try registeredSession(keychainWorks: false)
		let log = AccountRegistrationEventLog()

		session.registerAccount(
			AccountRegistrationRequest(account: .currentNickname, email: nil, password: "pw"),
			observer: log.observer
		)
		try session.receive(":irc.example.net REGISTER SUCCESS ada :Done")
		try await Eventually.until("the save") { log.events.count == 2 }

		#expect(log.last == .succeeded(account: "ada", serverMessage: "Done", credentialsSaved: false))
	}

	@Test("A request never shows its password when described")
	func requestDescriptionHidesPassword() {
		let request = AccountRegistrationRequest(account: .named("ada"), email: "a@b.c", password: "hunter2")

		#expect(String(describing: request).contains("hunter2") == false)
		#expect(String(reflecting: request).contains("hunter2") == false)
		#expect(Mirror(reflecting: request).children.contains { "\($0.value)".contains("hunter2") } == false)
	}
}
