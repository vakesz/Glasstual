// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// The codes `FAIL REGISTER`, `FAIL VERIFY` and `FAIL * ACCOUNT_REQUIRED`
/// carry under `draft/account-registration`.
nonisolated enum AccountRegistrationReplyCode: String, Sendable, CaseIterable {
	case accountExists = "ACCOUNT_EXISTS"
	case badAccountName = "BAD_ACCOUNT_NAME"
	case accountNameMustBeNickname = "ACCOUNT_NAME_MUST_BE_NICK"
	case needNickname = "NEED_NICK"
	case alreadyAuthenticated = "ALREADY_AUTHENTICATED"
	case weakPassword = "WEAK_PASSWORD"
	case unacceptablePassword = "UNACCEPTABLE_PASSWORD"
	case invalidEmail = "INVALID_EMAIL"
	case unacceptableEmail = "UNACCEPTABLE_EMAIL"
	case completeConnectionRequired = "COMPLETE_CONNECTION_REQUIRED"
	case invalidCode = "INVALID_CODE"
	case temporarilyUnavailable = "TEMPORARILY_UNAVAILABLE"
	case accountRequired = "ACCOUNT_REQUIRED"
}

/// The codes `FAIL METADATA` carries under `draft/metadata-2`.
nonisolated enum MetadataReplyCode: Sendable, Equatable, CaseIterable {
	case invalidTarget
	case keyInvalid
	case subcommandInvalid
	case keyNoPermission
	case keyNotSet
	case limitReached
	case rateLimited
	case tooManySubscriptions
	case valueInvalid

	/// The specification's table says `INVALID_TARGET` and its own example
	/// says `TARGET_INVALID`; both are read as the same code.
	init?(rawValue: String) {
		switch rawValue {
		case "INVALID_TARGET", "TARGET_INVALID": self = .invalidTarget
		case "KEY_INVALID": self = .keyInvalid
		case "SUBCOMMAND_INVALID": self = .subcommandInvalid
		case "KEY_NO_PERMISSION": self = .keyNoPermission
		case "KEY_NOT_SET": self = .keyNotSet
		case "LIMIT_REACHED": self = .limitReached
		case "RATE_LIMITED": self = .rateLimited
		case "TOO_MANY_SUBS": self = .tooManySubscriptions
		case "VALUE_INVALID": self = .valueInvalid
		default: return nil
		}
	}
}
