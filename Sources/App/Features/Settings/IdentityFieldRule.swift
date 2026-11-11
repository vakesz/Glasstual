// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What an entry in a Default Identity field is worth.

 A new connection and onboarding both start from these values and refuse a
 nickname that is not one or a real name that is empty, so a value stored here
 that they would refuse only fails later, once per connection. The rules are
 theirs, asked here when the entry is made. */
enum IdentityFieldRule {
	/// A nickname a connection needs, so an empty entry restores the default.
	case nickname
	/// A nickname that may be empty, such as the one used while away.
	case optionalNickname
	case username
	case realName

	enum Outcome: Equatable {
		/// Restore the key's declared default.
		case reset
		case store(String)
		/// Leave the stored value alone.
		case reject
	}

	/// What to do with `text`, which is trimmed first.
	func outcome(for text: String) -> Outcome {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmed.isEmpty == false else {
			return self == .optionalNickname ? .store("") : .reset
		}

		switch self {
		case .nickname, .optionalNickname:
			return trimmed.isHostmaskNickname ? .store(trimmed) : .reject
		case .username:
			return .store(trimmed)
		case .realName:
			return ServerPropertiesValidation.isRealName(trimmed) ? .store(trimmed) : .reject
		}
	}
}
