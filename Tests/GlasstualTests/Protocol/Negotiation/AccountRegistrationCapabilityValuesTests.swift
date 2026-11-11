// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@Suite("draft/account-registration capability values")
struct AccountRegistrationCapabilityValuesTests {
	@Test("The specification's example value names its two flags")
	func specificationExample() {
		let values = AccountRegistrationCapabilityValues(capabilityValues: ["before-connect", "email-required"])

		#expect(values.beforeConnect)
		#expect(values.emailRequired)
		#expect(values.customAccountName == false)
		#expect(values.minimumPasswordBytes == nil)
		#expect(values.maximumPasswordBytes == nil)
	}

	@Test("Password lengths are read as byte counts")
	func passwordLengths() {
		let values = AccountRegistrationCapabilityValues(
			capabilityValues: ["custom-account-name", "min-password-length=8", "max-password-length=64"]
		)

		#expect(values.customAccountName)
		#expect(values.minimumPasswordBytes == 8)
		#expect(values.maximumPasswordBytes == 64)
	}

	@Test("Unknown keys are ignored with their values")
	func unknownKeys() {
		let values = AccountRegistrationCapabilityValues(capabilityValues: ["x-future=1", "flavour=sweet"])

		#expect(values == AccountRegistrationCapabilityValues())
	}

	@Test("A repeated key keeps its first value")
	func repeatedKeyKeepsFirst() {
		let values = AccountRegistrationCapabilityValues(
			capabilityValues: ["min-password-length=8", "min-password-length=20"]
		)

		#expect(values.minimumPasswordBytes == 8)
	}

	@Test("A length that is not a positive number is ignored", arguments: ["0", "x", "-3", ""])
	func invalidLengthsAreIgnored(_ number: String) {
		let values = AccountRegistrationCapabilityValues(capabilityValues: ["min-password-length=\(number)"])

		#expect(values.minimumPasswordBytes == nil)
	}
}

@MainActor
@Suite("ISUPPORT ACCOUNTREQUIRED")
struct ISupportAccountRequiredTests {
	@Test("The draft and the bare token both say an account is required", arguments: [
		"draft/ACCOUNTREQUIRED", "ACCOUNTREQUIRED",
	])
	func tokenIsRead(_ token: String) {
		let support = ISupport()

		support.processConfigurationData(token)
		#expect(support.requiresAccount)

		support.processConfigurationData("-\(token)")
		#expect(support.requiresAccount == false)
	}
}
