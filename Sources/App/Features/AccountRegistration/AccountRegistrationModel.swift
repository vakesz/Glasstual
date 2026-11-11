// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Accessibility
import Foundation
import Observation

/** The Register Account sheet's state: the form, the step the flow is on, and
 what went wrong where.

 The session runs the flow and reports through ``handle(_:)``; the model only
 decides what the sheet shows and what the confirm button does next. Local
 problems appear after the first submission, as everywhere else in the app. */
@MainActor
@Observable
final class AccountRegistrationModel {
	enum Phase: Equatable {
		case form
		case submitting
		case code
		case verifying
		case succeeded(account: String, credentialsSaved: Bool)

		/// Whether the session has a flow running for this sheet.
		var isInFlight: Bool {
			switch self {
			case .submitting, .code, .verifying: true
			case .form, .succeeded: false
			}
		}
	}

	/// How the email field is captioned.
	enum EmailRequirement: Equatable {
		case required
		case optional
		/// The server's rules are not known yet.
		case requiredBySomeServers
	}

	/// Why a password may not go out as the connection stands.
	enum TransportWarning: Equatable {
		/// The certificate was not checked: Glasstual asks first.
		case asksFirst
		/// The connection is not encrypted although encryption was asked for.
		case refuses
	}

	/// What the sheet calls into. Set by the sheet that owns the model.
	struct Actions {
		var register: @MainActor (AccountRegistrationRequest) -> Void = { _ in }
		var verify: @MainActor (String) -> Void = { _ in }
		var stop: @MainActor () -> Void = {}
		var finish: @MainActor () -> Void = {}
		var problems: @MainActor (AccountRegistrationRequest) -> [AccountRegistrationValidation] = { _ in [] }
	}

	let networkName: String
	let currentNickname: String
	/// The server's rules, or `nil` before they are known.
	var values: AccountRegistrationCapabilityValues?
	var isConnected: Bool
	var transportWarning: TransportWarning?
	/// A password is already saved for this server and registering replaces it.
	var replacesSavedPassword: Bool

	var accountName: String
	var email = ""
	var password = ""
	var passwordConfirmation = ""
	var code = ""

	private(set) var phase = Phase.form
	/// The server's message on the code step.
	private(set) var codeServerMessage = ""
	private(set) var generalError: String?
	private(set) var generalServerMessage: String?
	/// The field the latest failure concerns, for the view to focus.
	private(set) var focusRequest: AccountRegistrationField?

	var actions = Actions()

	private var serverFieldErrors: [AccountRegistrationField: String] = [:]
	private var submission = SubmissionGate()
	private var codeSubmission = SubmissionGate()

	init(
		networkName: String,
		currentNickname: String,
		values: AccountRegistrationCapabilityValues?,
		isConnected: Bool,
		transportWarning: TransportWarning? = nil,
		replacesSavedPassword: Bool = false
	) {
		self.networkName = networkName
		self.currentNickname = currentNickname
		self.values = values
		self.isConnected = isConnected
		self.transportWarning = transportWarning
		self.replacesSavedPassword = replacesSavedPassword
		accountName = currentNickname
	}

	// MARK: - Form

	/// Whether the account can be named here. A server that names accounts
	/// after the nickname shows it read-only.
	var accountIsEditable: Bool {
		values?.customAccountName != false
	}

	var emailRequirement: EmailRequirement {
		guard let values else { return .requiredBySomeServers }

		return values.emailRequired ? .required : .optional
	}

	/// The request the form describes. The account is `*` unless it differs
	/// from the nickname on a server that allows that.
	var request: AccountRegistrationRequest {
		let typedAccount = accountName.trimmingCharacters(in: .whitespaces)
		let account: AccountRegistrationRequest.AccountName =
			accountIsEditable && typedAccount.isEmpty == false
				&& typedAccount.lowercased() != currentNickname.lowercased()
				? .named(typedAccount) : .currentNickname
		let typedEmail = email.trimmingCharacters(in: .whitespaces)

		return AccountRegistrationRequest(
			account: account,
			email: typedEmail.isEmpty ? nil : typedEmail,
			password: password
		)
	}

	/// The problem with each field, local ones once submitting was tried and
	/// the server's from the latest refusal.
	var fieldErrors: [AccountRegistrationField: String] {
		var errors = serverFieldErrors

		for problem in submission.shown(localProblems) ?? [] {
			guard let field = problem.field, errors[field] == nil else { continue }
			errors[field] = problem.localizedDescription
		}
		if let problem = codeSubmission.shown(AccountRegistrationValidation.codeProblem(code)), errors[.code] == nil {
			errors[.code] = problem.localizedDescription
		}

		return errors
	}

	/// A problem that belongs to no single field, shown at the top.
	var shownGeneralError: String? {
		generalError ?? submission.shown(localProblems.first { $0.field == nil })?.localizedDescription
	}

	private var localProblems: [AccountRegistrationValidation] {
		var problems = actions.problems(request)

		if password != passwordConfirmation, problems.contains(where: { $0.field == .password }) == false {
			problems.append(.passwordMismatch)
		}

		return problems
	}

	// MARK: - Confirm button

	var confirmTitle: LocalizedStringResource {
		switch phase {
		case .form, .submitting: .AccountRegistrationSheet.registerButton
		case .code, .verifying: .AccountRegistrationSheet.verifyButton
		case .succeeded: .AccountRegistrationSheet.doneButton
		}
	}

	var confirmIsDisabled: Bool {
		switch phase {
		case .submitting, .verifying: true
		case .form: submission.wasAttempted && localProblems.isEmpty == false
		case .code: codeSubmission.wasAttempted && AccountRegistrationValidation.codeProblem(code) != nil
		case .succeeded: false
		}
	}

	/// The confirm button: register, verify or close, by step.
	func confirm() {
		switch phase {
		case .form:
			submission.attempt()
			clearRefusal()
			guard localProblems.isEmpty else {
				focusRequest = localProblems.first?.field
				announce(fieldErrors.values.first ?? shownGeneralError)
				return
			}
			phase = .submitting
			actions.register(request)
		case .code:
			codeSubmission.attempt()
			serverFieldErrors[.code] = nil
			guard AccountRegistrationValidation.codeProblem(code) == nil else {
				focusRequest = .code
				return
			}
			phase = .verifying
			actions.verify(code)
		case .succeeded:
			actions.finish()
		case .submitting, .verifying:
			break
		}
	}

	/// Stop while a request is out: the flow ends and the form comes back.
	func stop() {
		actions.stop()
	}

	/// The focus request was carried out.
	func didFocus() {
		focusRequest = nil
	}

	// MARK: - Session events

	func handle(_ event: AccountRegistrationEvent) {
		switch event {
		case .started:
			break
		case let .verificationRequired(account, serverMessage):
			phase = .code
			codeAccount = account
			codeServerMessage = serverMessage
			focusRequest = .code
			announce(String(localized: .AccountRegistrationSheet.codeFootnote))
		case let .succeeded(account, _, credentialsSaved):
			phase = .succeeded(account: account, credentialsSaved: credentialsSaved)
			password = ""
			passwordConfirmation = ""
			code = ""
			announce(String(localized: .AccountRegistrationSheet.successTitle(account)))
		case let .failed(failure, serverMessage):
			receive(failure, serverMessage: serverMessage)
		case .cancelled:
			phase = .form
		}
	}

	/// The account the code step is verifying.
	private(set) var codeAccount: String?

	private func receive(_ failure: AccountRegistrationFailure, serverMessage: String?) {
		let message = failure.localizedDescription

		if phase == .verifying, failure.field == .code {
			phase = .code
			serverFieldErrors[.code] = message
			focusRequest = .code
		} else {
			phase = .form
			if let field = failure.field, field != .code {
				serverFieldErrors[field] = message
				focusRequest = field
			} else {
				generalError = message
				generalServerMessage = serverMessage
			}
		}
		announce(message)
	}

	private func clearRefusal() {
		serverFieldErrors.removeAll()
		generalError = nil
		generalServerMessage = nil
	}

	private func announce(_ text: String?) {
		guard let text, text.isEmpty == false else { return }
		AccessibilityNotification.Announcement(text).post()
	}
}
