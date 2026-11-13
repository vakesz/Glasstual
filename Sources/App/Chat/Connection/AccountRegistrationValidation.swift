// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** A problem with a registration found before anything is sent.

 The sheet and `/register` check the same rules: each value has to be one wire
 token, the password has to fit the server's byte limits and this client's own
 ceiling, and the whole line has to fit the protocol's. */
nonisolated enum AccountRegistrationValidation: Sendable, Equatable {
	case accountNameInvalid
	case accountMustMatchNickname
	case emailRequired
	case emailInvalid
	case passwordEmpty
	case passwordTooShort(minimumBytes: Int)
	case passwordTooLong(maximumBytes: Int)
	case passwordControlCharacters
	case passwordMismatch
	case codeInvalid
	case lineTooLong

	/// The ceiling this client puts on a password whatever the server allows:
	/// the specification calls it a safe reasonable limit.
	static let maximumPasswordBytes = 300

	var field: AccountRegistrationField? {
		switch self {
		case .accountNameInvalid, .accountMustMatchNickname: .account
		case .emailRequired, .emailInvalid: .email
		case .passwordEmpty, .passwordTooShort, .passwordTooLong, .passwordControlCharacters, .passwordMismatch: .password
		case .codeInvalid: .code
		case .lineTooLong: nil
		}
	}

	var localizedDescription: String {
		switch self {
		case .accountNameInvalid: String(localized: .AccountRegistration.validationAccountNameInvalid)
		case .accountMustMatchNickname: String(localized: .AccountRegistration.validationAccountMustMatchNickname)
		case .emailRequired: String(localized: .AccountRegistration.validationEmailRequired)
		case .emailInvalid: String(localized: .AccountRegistration.validationEmailInvalid)
		case .passwordEmpty: String(localized: .AccountRegistration.validationPasswordEmpty)
		case let .passwordTooShort(bytes): String(localized: .AccountRegistration.validationPasswordTooShort(bytes))
		case let .passwordTooLong(bytes): String(localized: .AccountRegistration.validationPasswordTooLong(bytes))
		case .passwordControlCharacters: String(localized: .AccountRegistration.validationPasswordControlCharacters)
		case .passwordMismatch: String(localized: .AccountRegistration.validationPasswordMismatch)
		case .codeInvalid: String(localized: .AccountRegistration.validationCodeInvalid)
		case .lineTooLong: String(localized: .AccountRegistration.validationLineTooLong)
		}
	}

	/** Every problem with `request`, in form order.

	 - Parameters:
	   - values: The server's rules, or `nil` before they are known.
	   - currentNickname: The nickname a `*` account stands for.
	   - casefold: The server's casemapping, to compare a typed account with
	     the nickname. */
	static func problems(
		in request: AccountRegistrationRequest,
		values: AccountRegistrationCapabilityValues?,
		refusesCustomAccountNames: Bool = false,
		currentNickname: String,
		casefold: (String) -> String
	) -> [AccountRegistrationValidation] {
		var problems: [AccountRegistrationValidation] = []

		if case let .named(name) = request.account {
			if isSingleToken(name) == false {
				problems.append(.accountNameInvalid)
			} else if values?.customAccountName == false || refusesCustomAccountNames,
			          casefold(name) != casefold(currentNickname)
			{
				problems.append(.accountMustMatchNickname)
			}
		}

		if let email = request.email {
			if isSingleToken(email) == false || isPlausibleEmail(email) == false {
				problems.append(.emailInvalid)
			}
		} else if values?.emailRequired == true {
			problems.append(.emailRequired)
		}

		if let problem = passwordProblem(request.password, values: values) {
			problems.append(problem)
		} else if lineBytes(for: request) > ProtocolLimits.maximumBodyLength + ProtocolLimits.lineTerminatorLength {
			problems.append(.lineTooLong)
		}

		return problems
	}

	/// The first problem with a password, or `nil` when it may be sent.
	static func passwordProblem(
		_ password: String,
		values: AccountRegistrationCapabilityValues?
	) -> AccountRegistrationValidation? {
		let bytes = password.utf8.count

		guard bytes > 0 else { return .passwordEmpty }

		guard password.unicodeScalars.contains(where: { $0 == "\0" || $0 == "\r" || $0 == "\n" }) == false else {
			return .passwordControlCharacters
		}

		let maximum = min(values?.maximumPasswordBytes ?? maximumPasswordBytes, maximumPasswordBytes)

		if bytes > maximum {
			return .passwordTooLong(maximumBytes: maximum)
		}

		if let minimum = values?.minimumPasswordBytes, bytes < minimum {
			return .passwordTooShort(minimumBytes: minimum)
		}

		return nil
	}

	/// The problem with a verification code, or `nil` when it may be sent.
	static func codeProblem(_ code: String) -> AccountRegistrationValidation? {
		isSingleToken(code) ? nil : .codeInvalid
	}

	/// A value that travels as one middle parameter: not empty, no spaces, no
	/// control characters and no leading colon.
	static func isSingleToken(_ value: String) -> Bool {
		value.isEmpty == false && value.hasPrefix(":") == false && value != "*"
			&& value.unicodeScalars.allSatisfy { scalar in
				scalar.properties.isWhitespace == false && scalar.properties.generalCategory != .control
			}
	}

	private static func isPlausibleEmail(_ email: String) -> Bool {
		let parts = email.split(separator: "@", omittingEmptySubsequences: false)

		return parts.count == 2 && parts[0].isEmpty == false && parts[1].isEmpty == false
	}

	/// The bytes `REGISTER` takes on the wire, with the trailing colon and CRLF.
	private static func lineBytes(for request: AccountRegistrationRequest) -> Int {
		"REGISTER \(request.wireAccount) \(request.wireEmail) :\(request.password)\r\n".utf8.count
	}
}
