// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@Suite("Account registration validation")
struct AccountRegistrationValidationTests {
	private func problems(
		_ request: AccountRegistrationRequest,
		values: AccountRegistrationCapabilityValues? = AccountRegistrationCapabilityValues(),
		nickname: String = "ada"
	) -> [AccountRegistrationValidation] {
		AccountRegistrationValidation.problems(
			in: request, values: values, currentNickname: nickname, casefold: { $0.lowercased() }
		)
	}

	private func request(
		_ account: AccountRegistrationRequest.AccountName = .currentNickname,
		email: String? = nil,
		password: String = "password"
	) -> AccountRegistrationRequest {
		AccountRegistrationRequest(account: account, email: email, password: password)
	}

	@Test("Byte limits count bytes, so a multibyte password is longer than it looks")
	func byteLimits() {
		var values = AccountRegistrationCapabilityValues()
		values.minimumPasswordBytes = 8
		values.maximumPasswordBytes = 10

		#expect(problems(request(password: "ééé"), values: values) == [.passwordTooShort(minimumBytes: 8)])
		#expect(problems(request(password: "éééé"), values: values) == [])
		#expect(problems(request(password: "ééééé!"), values: values) == [.passwordTooLong(maximumBytes: 10)])
	}

	@Test("Glasstual caps a password at 300 bytes whatever the server allows")
	func ownCeiling() {
		var values = AccountRegistrationCapabilityValues()
		values.maximumPasswordBytes = 1000

		#expect(problems(request(password: String(repeating: "a", count: 300)), values: values) == [])
		#expect(
			problems(request(password: String(repeating: "a", count: 301)), values: values)
				== [.passwordTooLong(maximumBytes: 300)]
		)
	}

	@Test("A password with NUL, CR or LF is refused", arguments: ["a\0b", "a\rb", "a\nb"])
	func controlCharacters(_ password: String) {
		#expect(problems(request(password: password)) == [.passwordControlCharacters])
	}

	@Test("An empty password is refused")
	func emptyPassword() {
		#expect(problems(request(password: "")) == [.passwordEmpty])
	}

	@Test("An email needs one @ and no spaces, and a required one has to be there")
	func emailShape() {
		var required = AccountRegistrationCapabilityValues()
		required.emailRequired = true

		#expect(problems(request(email: "ada@example.org")) == [])
		#expect(problems(request(email: "ada example.org")) == [.emailInvalid])
		#expect(problems(request(email: "ada@")) == [.emailInvalid])
		#expect(problems(request(email: ":ada@example.org")) == [.emailInvalid])
		#expect(problems(request(email: nil), values: required) == [.emailRequired])
	}

	@Test("A star stands for the nickname; a named account is one token")
	func accountNames() {
		#expect(problems(request(.currentNickname)) == [])
		#expect(problems(request(.named("ada lovelace"))) == [.accountNameInvalid])
		#expect(problems(request(.named("*"))) == [.accountNameInvalid])
	}

	@Test("Without custom account names, a typed account has to be the nickname")
	func customNameRule() {
		var custom = AccountRegistrationCapabilityValues()
		custom.customAccountName = true

		#expect(problems(request(.named("lovelace"))) == [.accountMustMatchNickname])
		#expect(problems(request(.named("ADA"))) == [])
		#expect(problems(request(.named("lovelace")), values: custom) == [])
		// Unknown rules: the server decides.
		#expect(problems(request(.named("lovelace")), values: nil) == [])
	}

	@Test("The whole line has to fit 512 bytes")
	func lineLength() {
		var values = AccountRegistrationCapabilityValues()
		values.customAccountName = true
		let longAccount = String(repeating: "a", count: 200)
		let longEmail = String(repeating: "b", count: 100) + "@example.org"

		#expect(
			problems(request(.named(longAccount), email: longEmail, password: String(repeating: "c", count: 250)), values: values)
				== [.lineTooLong]
		)
	}

	@Test("A verification code is one token")
	func codes() {
		#expect(AccountRegistrationValidation.codeProblem("A1B2") == nil)
		#expect(AccountRegistrationValidation.codeProblem("") == .codeInvalid)
		#expect(AccountRegistrationValidation.codeProblem("12 34") == .codeInvalid)
	}
}
