// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("/register and /verify")
struct AccountRegistrationCommandTests {
	@Test("The password is the rest of the line and may hold spaces")
	func passwordWithSpaces() {
		#expect(
			AccountRegistrationCommandRequest(command: .register, arguments: "* * correct horse battery")
				== .register(AccountRegistrationRequest(account: .currentNickname, email: nil, password: "correct horse battery"))
		)
		#expect(
			AccountRegistrationCommandRequest(command: .register, arguments: "ada ada@example.org pw")
				== .register(AccountRegistrationRequest(account: .named("ada"), email: "ada@example.org", password: "pw"))
		)
	}

	@Test("A lone cancel cancels, and two tokens are not a request")
	func cancelAndShortForms() {
		#expect(AccountRegistrationCommandRequest(command: .register, arguments: "") == .describe)
		#expect(AccountRegistrationCommandRequest(command: .register, arguments: "CANCEL") == .cancel)
		#expect(AccountRegistrationCommandRequest(command: .register, arguments: "cancel me") == .invalidSyntax)
		#expect(AccountRegistrationCommandRequest(command: .register, arguments: "ada") == .invalidSyntax)
	}

	@Test("/verify takes a code, or an account and a code")
	func verifyForms() {
		#expect(AccountRegistrationCommandRequest(command: .verify, arguments: "4242") == .verify(account: nil, code: "4242"))
		#expect(
			AccountRegistrationCommandRequest(command: .verify, arguments: "ada 4242") == .verify(account: "ada", code: "4242")
		)
		#expect(AccountRegistrationCommandRequest(command: .verify, arguments: "") == .invalidSyntax)
		#expect(AccountRegistrationCommandRequest(command: .verify, arguments: "a b c") == .invalidSyntax)
	}

	@Test("/register alone prints what this server accepts")
	func usageWithoutArguments() throws {
		let session = makeRegistrationSession()
		try session.negotiate("draft/account-registration=email-required,min-password-length=8")
		try session.receive(":irc.example.net 001 ada :Welcome")

		session.sendCommand("/register")

		let printed = session.printedBodies
		#expect(printed.contains(String(localized: .AccountRegistration.summaryEmailRequired)))
		#expect(printed.contains(String(localized: .AccountRegistration.summaryPasswordMinimum(8))))
		#expect(printed.contains(String(localized: .AccountRegistration.summaryNicknameAccountName)))
	}

	@Test("/register sends REGISTER and never prints the password")
	func registerCommandSends() throws {
		let session = makeRegistrationSession()
		try session.negotiate("draft/account-registration")
		try session.receive(":irc.example.net 001 ada :Welcome")

		session.sendCommand("/register * * open sesame")

		#expect(session.wireLines.last == "REGISTER * * :open sesame")
		#expect(session.printedBodies.contains { $0.contains("sesame") } == false)
	}

	@Test("Only /pass, /register and /verify carry a secret")
	func carriesSecret() {
		#expect(LocalCommand.register.carriesSecret)
		#expect(LocalCommand.verify.carriesSecret)
		#expect(LocalCommand.pass.carriesSecret)
		#expect(LocalCommand.msg.carriesSecret == false)
	}
}
