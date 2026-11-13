// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What the user asked to register.

 The password never reaches a log, the transcript or the raw-traffic view:
 the description and the mirror leave it out, and the raw log masks the line
 that carries it. */
nonisolated struct AccountRegistrationRequest: Sendable, Equatable, CustomStringConvertible, CustomReflectable {
	enum AccountName: Sendable, Equatable {
		/// `*`: the account is named after the nickname the server knows.
		case currentNickname
		case named(String)
	}

	var account: AccountName
	/// `nil` sends `*`.
	var email: String?
	var password: String

	/// The account parameter as it goes on the wire.
	var wireAccount: String {
		switch account {
		case .currentNickname: "*"
		case let .named(name): name
		}
	}

	/// The email parameter as it goes on the wire.
	var wireEmail: String {
		email ?? "*"
	}

	var description: String {
		"AccountRegistrationRequest(account: \(wireAccount), email: \(email == nil ? "none" : "set"), password: ••••••)"
	}

	var customMirror: Mirror {
		Mirror(self, children: ["account": wireAccount, "hasEmail": email != nil], displayStyle: .struct)
	}
}

/// A line the registration flow sends.
nonisolated enum AccountRegistrationCommand: Sendable, Equatable {
	case register(AccountRegistrationRequest)
	/// `request` is the registration this code completes, or `nil` for a code
	/// typed with `/verify` for an account registered earlier.
	case verify(account: String, code: String, request: AccountRegistrationRequest?)

	var request: AccountRegistrationRequest? {
		switch self {
		case let .register(request): request
		case let .verify(_, _, request): request
		}
	}
}

/// When a registration line went out.
nonisolated enum AccountRegistrationTiming: Sendable, Equatable {
	/// Before the server's welcome, with `CAP END` held for the outcome.
	case beforeConnect
	case afterWelcome
}

/// Where one registration flow stands on this connection.
nonisolated enum AccountRegistrationPhase: Sendable, Equatable {
	case idle
	/// Connecting, or waiting for `CAP LS` to say whether the server can register.
	case awaitingCapability(AccountRegistrationRequest)
	/// Asking whether the password may go to a server whose certificate was not checked.
	case awaitingConsent(AccountRegistrationCommand, timing: AccountRegistrationTiming, isRetry: Bool)
	/// Queued for the server's welcome.
	case awaitingWelcome(AccountRegistrationCommand, isRetry: Bool)
	/// The line went out and its answer has not arrived.
	case sent(AccountRegistrationCommand, timing: AccountRegistrationTiming, isRetry: Bool)
	/// The server sent a code to the user. `holdsNegotiation` while `CAP END`
	/// waits for it.
	case awaitingCode(account: String, request: AccountRegistrationRequest?, holdsNegotiation: Bool)

	var isIdle: Bool {
		self == .idle
	}

	/// The registration this flow is about, if it holds one.
	var request: AccountRegistrationRequest? {
		switch self {
		case .idle: nil
		case let .awaitingCapability(request): request
		case let .awaitingConsent(command, _, _), let .awaitingWelcome(command, _), let .sent(command, _, _):
			command.request
		case let .awaitingCode(_, request, _): request
		}
	}
}

/// What a registration flow reports to whoever started it.
nonisolated enum AccountRegistrationEvent: Sendable, Equatable {
	/// `REGISTER` or `VERIFY` went out.
	case started
	case verificationRequired(account: String, serverMessage: String)
	case succeeded(account: String, serverMessage: String, credentialsSaved: Bool)
	case failed(AccountRegistrationFailure, serverMessage: String?)
	case cancelled
}

/// The field of the form a problem is about.
nonisolated enum AccountRegistrationField: Sendable, Hashable, CaseIterable {
	case account
	case email
	case password
	case code
}

/// Why a password stayed off the wire.
nonisolated enum CredentialWithholding: Sendable, Equatable {
	/// The connection went to a host that is not one of the configured servers.
	case unconfiguredHost
	/// The certificate was not checked and the user declined to send it.
	case unverifiedCertificate
	/// The connection is not encrypted although encryption was asked for.
	case plaintext
}

/// Why a registration did not complete.
nonisolated enum AccountRegistrationFailure: Sendable, Equatable {
	case accountExists
	case badAccountName
	case accountNameMustBeNickname
	case needsNickname
	case alreadyAuthenticated
	case weakPassword
	case unacceptablePassword
	case invalidEmail
	case unacceptableEmail
	case completeConnectionRequired
	case invalidCode
	case temporarilyUnavailable
	case accountRequired
	/// Another registration is already running on this connection.
	case alreadyInProgress
	/// A code this client does not know.
	case other(code: String)
	case unsupported
	case notConnected
	case timedOut
	case disconnected
	case credentialsWithheld(CredentialWithholding)
	case unsupportedOnBouncerNetwork
	case invalidRequest(AccountRegistrationValidation)

	init(code: String) {
		guard let known = AccountRegistrationReplyCode(rawValue: code) else {
			self = .other(code: code)
			return
		}

		switch known {
		case .accountExists: self = .accountExists
		case .badAccountName: self = .badAccountName
		case .accountNameMustBeNickname: self = .accountNameMustBeNickname
		case .needNickname: self = .needsNickname
		case .alreadyAuthenticated: self = .alreadyAuthenticated
		case .weakPassword: self = .weakPassword
		case .unacceptablePassword: self = .unacceptablePassword
		case .invalidEmail: self = .invalidEmail
		case .unacceptableEmail: self = .unacceptableEmail
		case .completeConnectionRequired: self = .completeConnectionRequired
		case .invalidCode: self = .invalidCode
		case .temporarilyUnavailable: self = .temporarilyUnavailable
		case .accountRequired: self = .accountRequired
		}
	}

	/// The field the failure concerns, or `nil` for the form as a whole.
	var field: AccountRegistrationField? {
		switch self {
		case .accountExists, .badAccountName, .accountNameMustBeNickname: .account
		case .weakPassword, .unacceptablePassword: .password
		case .invalidEmail, .unacceptableEmail: .email
		case .invalidCode: .code
		case let .invalidRequest(validation): validation.field
		default: nil
		}
	}

	var localizedDescription: String {
		switch self {
		case .accountExists: String(localized: .AccountRegistration.failureAccountExists)
		case .badAccountName: String(localized: .AccountRegistration.failureBadAccountName)
		case .accountNameMustBeNickname: String(localized: .AccountRegistration.failureAccountNameMustBeNickname)
		case .needsNickname: String(localized: .AccountRegistration.failureNeedsNickname)
		case .alreadyAuthenticated: String(localized: .AccountRegistration.failureAlreadyAuthenticated)
		case .weakPassword: String(localized: .AccountRegistration.failureWeakPassword)
		case .unacceptablePassword: String(localized: .AccountRegistration.failureUnacceptablePassword)
		case .invalidEmail: String(localized: .AccountRegistration.failureInvalidEmail)
		case .unacceptableEmail: String(localized: .AccountRegistration.failureUnacceptableEmail)
		case .completeConnectionRequired: String(localized: .AccountRegistration.failureCompleteConnectionRequired)
		case .invalidCode: String(localized: .AccountRegistration.failureInvalidCode)
		case .temporarilyUnavailable: String(localized: .AccountRegistration.failureTemporarilyUnavailable)
		case .accountRequired: String(localized: .AccountRegistration.failureAccountRequired)
		case .alreadyInProgress: String(localized: .AccountRegistration.failureAlreadyInProgress)
		case let .other(code): String(localized: .AccountRegistration.failureOther(code))
		case .unsupported: String(localized: .AccountRegistration.failureUnsupported)
		case .notConnected: String(localized: .AccountRegistration.failureNotConnected)
		case .timedOut: String(localized: .AccountRegistration.failureTimedOut)
		case .disconnected: String(localized: .AccountRegistration.failureDisconnected)
		case .credentialsWithheld(.unconfiguredHost):
			String(localized: .AccountRegistration.failureWithheldUnconfiguredHost)
		case .credentialsWithheld(.unverifiedCertificate):
			String(localized: .AccountRegistration.failureWithheldUnverifiedCertificate)
		case .credentialsWithheld(.plaintext): String(localized: .AccountRegistration.failureWithheldPlaintext)
		case .unsupportedOnBouncerNetwork: String(localized: .AccountRegistration.failureBouncerNetwork)
		case let .invalidRequest(validation): validation.localizedDescription
		}
	}
}

/// Why registration is not offered for a session right now.
nonisolated enum AccountRegistrationUnavailability: Sendable, Equatable {
	case alreadyAuthenticated
	case unsupported
	case bouncerNetwork
	case inFlight
}

/// Whether a session can register an account, and on what terms.
nonisolated enum AccountRegistrationAvailability: Sendable, Equatable {
	/// Connected, with the server's rules known.
	case available(AccountRegistrationCapabilityValues)
	/// Not connected yet: Glasstual connects to find out.
	case availableAfterConnecting
	case unavailable(AccountRegistrationUnavailability)

	var isAvailable: Bool {
		if case .unavailable = self {
			return false
		}

		return true
	}

	/// The server's rules, when they are known.
	var values: AccountRegistrationCapabilityValues? {
		if case let .available(values) = self {
			return values
		}

		return nil
	}
}

/** One account registration on one connection.

 A value the session owns, beside the SASL exchange. The password lives only in
 the phase, and only until the outcome. */
struct AccountRegistrationSession {
	/// How long the server has to answer a `REGISTER` or `VERIFY`.
	static let answerTimeout: TimeInterval = 60
	/// How long `CAP END` is held while the user fetches a code.
	static let codeHoldTimeout: TimeInterval = 90

	var phase = AccountRegistrationPhase.idle
	/// One sink per flow: the sheet's model or the transcript printer.
	var observer: (@MainActor (AccountRegistrationEvent) -> Void)?
	var deadline: SessionTimer?
	var codeHold: SessionTimer?
	/// Set by `ACCOUNT_NAME_MUST_BE_NICK`: the server named the account after
	/// the nickname whatever it advertised.
	var refusesCustomAccountNames = false
	/// Paces the deadlines; tests step their own.
	var clock = TimerClock.continuous

	/// Ends the flow without reporting it. The clock stays.
	mutating func reset() {
		stopTimers()
		phase = .idle
		observer = nil
		refusesCustomAccountNames = false
	}

	func stopTimers() {
		deadline?.stop()
		codeHold?.stop()
	}
}
