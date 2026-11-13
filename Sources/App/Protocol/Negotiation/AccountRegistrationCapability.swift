// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What a network says about creating an account through
 `draft/account-registration`.

 The server lists its rules in the capability's value, as in
 `draft/account-registration=before-connect,email-required`. Each key appears
 at most once and the first one wins; a key this client does not know is
 ignored with its value, and so is a length that is not a positive number. */
nonisolated struct AccountRegistrationCapabilityValues: Sendable, Equatable {
	static let capabilityName = "draft/account-registration"

	/// `before-connect`: `REGISTER` may go out before registration completes.
	var beforeConnect = false
	/// `custom-account-name`: the account may be named something other than
	/// the current nickname.
	var customAccountName = false
	/// `email-required`: `REGISTER` has to carry an email address.
	var emailRequired = false
	/// `min-password-length`, in bytes.
	var minimumPasswordBytes: Int?
	/// `max-password-length`, in bytes.
	var maximumPasswordBytes: Int?

	init() {}

	/** The rules a capability value states.

	 - Parameter values: The capability value split at its commas, the way the
	   registry keeps what `CAP LS` offered. */
	init(capabilityValues values: [String]) {
		var seen: Set<Substring> = []

		for value in values {
			let parts = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
			let key = parts[0]

			guard seen.insert(key).inserted else { continue }

			switch key {
			case "before-connect": beforeConnect = true
			case "custom-account-name": customAccountName = true
			case "email-required": emailRequired = true
			case "min-password-length": minimumPasswordBytes = Self.positiveNumber(in: parts)
			case "max-password-length": maximumPasswordBytes = Self.positiveNumber(in: parts)
			default: continue
			}
		}
	}

	private static func positiveNumber(in parts: [Substring]) -> Int? {
		guard parts.count == 2, let number = Int(parts[1]), number > 0 else { return nil }

		return number
	}
}
