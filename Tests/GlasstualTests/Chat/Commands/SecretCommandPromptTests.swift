// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** A command that needs a secret and was typed without it asks for it in a
 secure field, so the secret is never typed on the command line, never printed
 and never kept in input history. */
@MainActor
@Suite("Secret command prompts", .timeLimit(.minutes(1)))
struct SecretCommandPromptTests {
	private func printed(_ session: TestServerSession) -> [String] {
		session.printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
	}

	@Test("/register with an account and an email asks for the password and registers with it")
	func registerAsksForThePassword() async throws {
		let session = makeRegistrationSession()
		try session.negotiate("draft/account-registration=custom-account-name")
		try session.receive(":irc.example.net 001 ada :Welcome")
		session.recordedOutput.responseText = "correct horse"

		session.sendCommand("register adal ada@example.org", completeTarget: false, target: nil)
		try await Eventually.until("the registration") {
			session.wireLines.contains("REGISTER adal ada@example.org :correct horse")
		}

		let question = try #require(session.recordedOutput.presentedAlerts.first)
		#expect(question.field == .secure(placeholder: String(localized: .AccountRegistration.passwordPromptPlaceholder)))
		#expect(printed(session).contains { $0.contains("correct horse") } == false)
		#expect(LocalCommand.inputCarriesSecret("/register adal ada@example.org"))
	}

	@Test("Cancelling the password question registers nothing")
	func cancelledPassword() async throws {
		let session = makeRegistrationSession()
		try session.receive(":irc.example.net 001 ada :Welcome")
		session.recordedOutput.responseAnswer = .alternate
		session.recordedOutput.responseText = "never sent"

		session.sendCommand("register adal *", completeTarget: false, target: nil)
		try await Eventually.until("the question") { session.recordedOutput.responseRequests.count == 1 }

		#expect(session.wireLines.contains { $0.hasPrefix("REGISTER") } == false)
	}

	@Test("/sasl token alone asks for the token in a secure field")
	func tokenIsAskedFor() async throws {
		let session = TestServerSession()
		session.recordedOutput.responseAnswer = .alternate

		session.sendCommand("sasl token", completeTarget: false, target: nil)
		try await Eventually.until("the question") { session.recordedOutput.responseRequests.count == 1 }

		let question = try #require(session.recordedOutput.responseRequests.first)
		#expect(question.field?.isSecure == true)
		#expect(question.keyword(for: .default) == .submit)
	}
}
