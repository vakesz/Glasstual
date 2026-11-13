// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Account registration flow", .timeLimit(.minutes(1)))
struct AccountRegistrationSessionTests {
	private let request = AccountRegistrationRequest(account: .currentNickname, email: nil, password: "correct horse")
	private let customRequest = AccountRegistrationRequest(
		account: .named("adal"), email: "ada@example.org", password: "hunter22"
	)

	@Test("After the welcome, REGISTER names the account and email or stars them")
	func registerShapeAfterWelcome() throws {
		let session = makeRegistrationSession()
		try session.negotiate("draft/account-registration=custom-account-name")
		try session.receive(":irc.example.net 001 ada :Welcome")
		let log = AccountRegistrationEventLog()

		session.registerAccount(request, observer: log.observer)
		#expect(session.wireLines.last == "REGISTER * * :correct horse")
		#expect(log.last == .started)

		session.cancelAccountRegistration()
		session.registerAccount(customRequest, observer: log.observer)
		#expect(session.wireLines.last == "REGISTER adal ada@example.org hunter22")
	}

	@Test("With before-connect, REGISTER follows the ACK and CAP END waits for the outcome")
	func beforeConnectHoldsCapabilityEnd() async throws {
		let session = makeRegistrationSession()
		let log = AccountRegistrationEventLog()

		session.registerAccount(request, observer: log.observer)
		#expect(session.accountRegistration.phase == .awaitingCapability(request))

		try session.negotiate("draft/account-registration=before-connect")
		#expect(session.wireLines.last == "REGISTER * * :correct horse")
		#expect(session.capabilityLines.contains("END") == false)

		try session.receive(":irc.example.net REGISTER SUCCESS ada :Account created")
		#expect(session.capabilityLines.last == "END")
		try await Eventually.until("the outcome") {
			log.last == .succeeded(account: "ada", serverMessage: "Account created", credentialsSaved: true)
		}

		try session.receive(":irc.example.net 900 ada ada!a@h ada :You are now logged in as ada")
		#expect(session.capabilityLines.filter { $0 == "END" }.count == 1)
	}

	@Test("Without before-connect, REGISTER waits for the welcome")
	func queuedUntilWelcome() throws {
		let session = makeRegistrationSession()
		try session.negotiate("draft/account-registration")

		session.registerAccount(request, observer: AccountRegistrationEventLog().observer)
		#expect(session.wireLines.contains { $0.hasPrefix("REGISTER") } == false)
		#expect(session.capabilityLines.last == "END")

		try session.receive(":irc.example.net 001 ada :Welcome")
		#expect(session.wireLines.last == "REGISTER * * :correct horse")
	}

	@Test("COMPLETE_CONNECTION_REQUIRED is retried once after the welcome, and a second one fails")
	func completeConnectionRetriedOnce() throws {
		let session = makeRegistrationSession()
		let log = AccountRegistrationEventLog()
		session.registerAccount(request, observer: log.observer)
		try session.negotiate("draft/account-registration=before-connect")

		try session.receive(":irc.example.net FAIL REGISTER COMPLETE_CONNECTION_REQUIRED :Finish connecting")
		#expect(session.capabilityLines.last == "END")
		#expect(session.accountRegistration.phase == .awaitingWelcome(.register(request), isRetry: true))

		try session.receive(":irc.example.net 001 ada :Welcome")
		#expect(session.wireLines.filter { $0.hasPrefix("REGISTER") }.count == 2)

		try session.receive(":irc.example.net FAIL REGISTER COMPLETE_CONNECTION_REQUIRED :Finish connecting")
		#expect(log.last == .failed(.completeConnectionRequired, serverMessage: "Finish connecting"))
		#expect(session.accountRegistration.phase == .idle)
	}

	@Test("A code is asked for, and VERIFY uses the account the server named")
	func verificationFlow() async throws {
		let session = makeRegistrationSession()
		try session.negotiate("draft/account-registration")
		try session.receive(":irc.example.net 001 ada :Welcome")
		let log = AccountRegistrationEventLog()

		session.registerAccount(request, observer: log.observer)
		try session.receive(":irc.example.net REGISTER VERIFICATION_REQUIRED Ada :Code sent to your email")
		#expect(log.last == .verificationRequired(account: "Ada", serverMessage: "Code sent to your email"))

		session.verifyAccount(code: "4242")
		#expect(session.wireLines.last == "VERIFY Ada 4242")

		try session.receive(":irc.example.net VERIFY SUCCESS Ada :Verified")
		try await Eventually.until("the outcome") {
			log.last == .succeeded(account: "Ada", serverMessage: "Verified", credentialsSaved: true)
		}
	}

	@Test("A wrong code keeps the flow open for another")
	func invalidCodeKeepsFlow() throws {
		let session = makeRegistrationSession()
		try session.negotiate("draft/account-registration")
		try session.receive(":irc.example.net 001 ada :Welcome")
		let log = AccountRegistrationEventLog()
		session.registerAccount(request, observer: log.observer)
		try session.receive(":irc.example.net REGISTER VERIFICATION_REQUIRED ada :Check email")

		session.verifyAccount(code: "1111")
		try session.receive(":irc.example.net FAIL VERIFY INVALID_CODE ada :Wrong code")

		#expect(log.last == .failed(.invalidCode, serverMessage: "Wrong code"))
		#expect(session.accountRegistration.phase == .awaitingCode(account: "ada", request: request, holdsNegotiation: false))
	}

	@Test("The code hold lifts CAP END after 90 seconds, and VERIFY goes after the welcome")
	func codeHoldExpires() async throws {
		let clock = ManualTimerClock()
		defer { clock.finish() }
		let session = makeRegistrationSession()
		session.accountRegistration.clock = clock.timerClock
		session.registerAccount(request, observer: AccountRegistrationEventLog().observer)
		try session.negotiate("draft/account-registration=before-connect")
		try session.receive(":irc.example.net REGISTER VERIFICATION_REQUIRED ada :Check email")
		#expect(session.capabilityLines.contains("END") == false)

		await clock.advance(by: 89)
		#expect(session.capabilityLines.contains("END") == false)
		await clock.advance(by: 2)
		#expect(session.capabilityLines.last == "END")

		session.verifyAccount(code: "4242")
		#expect(session.wireLines.last?.hasPrefix("VERIFY") == false)
		try session.receive(":irc.example.net 001 ada :Welcome")
		#expect(session.wireLines.last == "VERIFY ada 4242")
	}

	@Test("A REGISTER the server never answers times out after 60 seconds")
	func answerTimesOut() async throws {
		let clock = ManualTimerClock()
		defer { clock.finish() }
		let session = makeRegistrationSession()
		session.accountRegistration.clock = clock.timerClock
		let log = AccountRegistrationEventLog()
		session.registerAccount(request, observer: log.observer)
		try session.negotiate("draft/account-registration=before-connect")

		await clock.advance(by: 61)

		#expect(log.last == .failed(.timedOut, serverMessage: nil))
		#expect(session.capabilityLines.last == "END")
	}

	@Test("Cancelling lifts the hold, and a late success saves nothing")
	func cancelThenLateSuccess() async throws {
		let session = makeRegistrationSession()
		let log = AccountRegistrationEventLog()
		session.registerAccount(request, observer: log.observer)
		try session.negotiate("draft/account-registration=before-connect")

		#expect(session.cancelAccountRegistration())
		#expect(log.last == .cancelled)
		#expect(session.capabilityLines.last == "END")

		try session.receive(":irc.example.net REGISTER SUCCESS ada :Account created")
		await Task.yield()
		#expect(log.events.count == 2)
		#expect(session.sessionCredentials.password(for: session.config.nicknamePasswordKeychainItem) == nil)
		#expect(session.printedBodies.contains(String(localized: .AccountRegistration.lateSuccessNotSaved("ada"))))
	}

	@Test("SASL is not requested while a registration is running on the connection")
	func saslSuppressed() throws {
		let session = TestServerSession(configDictionary: ["nickname": "ada", "usesSASL": true], nicknamePassword: "old")
		session.setConnectionTransportForTesting(.connected)
		session.registerAccount(request, observer: AccountRegistrationEventLog().observer)

		try session.receive(":irc.example.net CAP * LS :sasl=PLAIN draft/account-registration")

		#expect(session.capabilityLines == ["REQ draft/account-registration"])
	}

	@Test("A withdrawn capability fails the flow and lifts the hold")
	func capabilityWithdrawn() throws {
		let session = makeRegistrationSession()
		let log = AccountRegistrationEventLog()
		session.registerAccount(request, observer: log.observer)
		try session.negotiate("draft/account-registration=before-connect")

		try session.receive(":irc.example.net CAP ada DEL :draft/account-registration")

		#expect(log.last == .failed(.unsupported, serverMessage: nil))
		#expect(session.capabilityLines.last == "END")
	}

	@Test("A server without the capability fails the flow at the welcome")
	func unsupportedAtWelcome() throws {
		let session = makeRegistrationSession()
		let log = AccountRegistrationEventLog()
		session.registerAccount(request, observer: log.observer)

		try session.negotiate("multi-prefix")
		try session.receive(":irc.example.net 001 ada :Welcome")

		#expect(log.last == .failed(.unsupported, serverMessage: nil))
	}

	@Test("A disconnect fails the flow")
	func disconnectFails() throws {
		let session = makeRegistrationSession()
		let log = AccountRegistrationEventLog()
		session.registerAccount(request, observer: log.observer)
		try session.negotiate("draft/account-registration=before-connect")

		session.resetAllPropertyValues()

		#expect(log.last == .failed(.disconnected, serverMessage: nil))
		#expect(session.accountRegistration.phase == .idle)
	}

	@Test("FAIL * ACCOUNT_REQUIRED prints the hint to register")
	func accountRequiredHint() throws {
		let session = makeRegistrationSession()

		try session.receive(":irc.example.net FAIL * ACCOUNT_REQUIRED :You need an account")

		#expect(session.printedBodies.contains(String(localized: .AccountRegistration.accountRequiredHint)))
	}

	@Test(
		"Every FAIL code maps to its failure and the field it concerns",
		arguments: [
			RegistrationFailureCase("ACCOUNT_EXISTS", .accountExists, .account),
			RegistrationFailureCase("BAD_ACCOUNT_NAME", .badAccountName, .account),
			RegistrationFailureCase("ACCOUNT_NAME_MUST_BE_NICK", .accountNameMustBeNickname, .account),
			RegistrationFailureCase("NEED_NICK", .needsNickname, nil),
			RegistrationFailureCase("ALREADY_AUTHENTICATED", .alreadyAuthenticated, nil),
			RegistrationFailureCase("WEAK_PASSWORD", .weakPassword, .password),
			RegistrationFailureCase("UNACCEPTABLE_PASSWORD", .unacceptablePassword, .password),
			RegistrationFailureCase("INVALID_EMAIL", .invalidEmail, .email),
			RegistrationFailureCase("UNACCEPTABLE_EMAIL", .unacceptableEmail, .email),
			RegistrationFailureCase("COMPLETE_CONNECTION_REQUIRED", .completeConnectionRequired, nil),
			RegistrationFailureCase("INVALID_CODE", .invalidCode, .code),
			RegistrationFailureCase("TEMPORARILY_UNAVAILABLE", .temporarilyUnavailable, nil),
			RegistrationFailureCase("ACCOUNT_REQUIRED", .accountRequired, nil),
			RegistrationFailureCase("SOMETHING_NEW", .other(code: "SOMETHING_NEW"), nil),
		]
	)
	func failureCodes(_ testCase: RegistrationFailureCase) {
		let failure = AccountRegistrationFailure(code: testCase.code)

		#expect(failure == testCase.failure)
		#expect(failure.field == testCase.field)
		#expect(failure.localizedDescription.isEmpty == false)
	}

	@Test("A refusal after the welcome reaches the observer with the server's message")
	func failureAfterWelcome() throws {
		let session = makeRegistrationSession()
		try session.negotiate("draft/account-registration")
		try session.receive(":irc.example.net 001 ada :Welcome")
		let log = AccountRegistrationEventLog()
		session.registerAccount(request, observer: log.observer)

		try session.receive(":irc.example.net FAIL REGISTER WEAK_PASSWORD ada :\u{02}Too\u{02} weak\u{202E}")

		#expect(log.last == .failed(.weakPassword, serverMessage: "Too weak"))
	}
}

nonisolated struct RegistrationFailureCase: Sendable {
	let code: String
	let failure: AccountRegistrationFailure
	let field: AccountRegistrationField?

	init(_ code: String, _ failure: AccountRegistrationFailure, _ field: AccountRegistrationField?) {
		self.code = code
		self.failure = failure
		self.field = field
	}
}
