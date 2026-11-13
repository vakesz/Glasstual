// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Register Account sheet model")
struct AccountRegistrationModelTests {
	private final class Calls {
		var registered: [AccountRegistrationRequest] = []
		var verified: [String] = []
		var stops = 0
		var finishes = 0
	}

	private func model(
		values: AccountRegistrationCapabilityValues? = AccountRegistrationCapabilityValues(),
		calls: Calls = Calls()
	) -> AccountRegistrationModel {
		let model = AccountRegistrationModel(
			networkName: "Example", currentNickname: "ada", values: values, isConnected: true
		)
		model.actions = AccountRegistrationModel.Actions(
			register: { calls.registered.append($0) },
			verify: { calls.verified.append($0) },
			stop: { calls.stops += 1 },
			finish: { calls.finishes += 1 },
			problems: { request in
				AccountRegistrationValidation.problems(
					in: request, values: values, currentNickname: "ada", casefold: { $0.lowercased() }
				)
			}
		)
		return model
	}

	@Test("The flow moves from the form to the code, then to success")
	func phaseTransitions() {
		let calls = Calls()
		let model = model(calls: calls)
		model.password = "secret"
		model.passwordConfirmation = "secret"

		model.confirm()
		#expect(model.phase == .submitting)
		#expect(calls.registered == [AccountRegistrationRequest(account: .currentNickname, email: nil, password: "secret")])
		#expect(model.confirmIsDisabled)

		model.handle(.verificationRequired(account: "ada", serverMessage: "Check email"))
		#expect(model.phase == .code)
		#expect(model.codeServerMessage == "Check email")

		model.code = "4242"
		model.confirm()
		#expect(model.phase == .verifying)
		#expect(calls.verified == ["4242"])

		model.handle(.succeeded(account: "ada", serverMessage: "", credentialsSaved: true))
		#expect(model.phase == .succeeded(account: "ada", credentialsSaved: true))
		#expect(model.password.isEmpty)

		model.confirm()
		#expect(calls.finishes == 1)
	}

	@Test("A refusal lands under the field it concerns, or at the top")
	func fieldErrorRouting() {
		let model = model()
		model.password = "pw"
		model.passwordConfirmation = "pw"
		model.confirm()

		model.handle(.failed(.weakPassword, serverMessage: "too weak"))
		#expect(model.phase == .form)
		#expect(model.fieldErrors[.password] == AccountRegistrationFailure.weakPassword.localizedDescription)
		#expect(model.focusRequest == .password)

		model.confirm()
		model.handle(.failed(.temporarilyUnavailable, serverMessage: "later"))
		#expect(model.shownGeneralError == AccountRegistrationFailure.temporarilyUnavailable.localizedDescription)
		#expect(model.generalServerMessage == "later")
	}

	@Test("A wrong code stays on the code step")
	func wrongCodeStays() {
		let model = model()
		model.handle(.verificationRequired(account: "ada", serverMessage: ""))
		model.code = "1"
		model.confirm()

		model.handle(.failed(.invalidCode, serverMessage: nil))

		#expect(model.phase == .code)
		#expect(model.fieldErrors[.code] == AccountRegistrationFailure.invalidCode.localizedDescription)
	}

	@Test("Local problems are shown only after a submission")
	func validationAfterSubmit() {
		let calls = Calls()
		let model = model(calls: calls)
		model.password = "a"
		model.passwordConfirmation = "b"

		#expect(model.fieldErrors.isEmpty)
		#expect(model.confirmIsDisabled == false)

		model.confirm()
		#expect(model.fieldErrors[.password] == AccountRegistrationValidation.passwordMismatch.localizedDescription)
		#expect(calls.registered.isEmpty)
		#expect(model.phase == .form)
	}

	@Test("Without custom account names the account is read-only and sent as a star")
	func readOnlyAccount() {
		let model = model()
		model.accountName = "lovelace"

		#expect(model.accountIsEditable == false)
		#expect(model.request.account == .currentNickname)

		var custom = AccountRegistrationCapabilityValues()
		custom.customAccountName = true
		let editable = self.model(values: custom)
		editable.accountName = "lovelace"
		#expect(editable.accountIsEditable)
		#expect(editable.request.account == .named("lovelace"))
		editable.accountName = "ADA"
		#expect(editable.request.account == .currentNickname)
	}

	@Test("The email caption follows the server's rules")
	func emailCaption() {
		var required = AccountRegistrationCapabilityValues()
		required.emailRequired = true

		#expect(model(values: required).emailRequirement == .required)
		#expect(model().emailRequirement == .optional)
		#expect(model(values: nil).emailRequirement == .requiredBySomeServers)
	}

	@Test("Stop cancels the flow, and the cancellation returns to the form")
	func stopCancels() {
		let calls = Calls()
		let model = model(calls: calls)
		model.password = "secret"
		model.passwordConfirmation = "secret"
		model.confirm()

		model.stop()
		model.handle(.cancelled)

		#expect(calls.stops == 1)
		#expect(model.phase == .form)
		#expect(model.phase.isInFlight == false)
	}
}
