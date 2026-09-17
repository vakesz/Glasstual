// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated enum CommonValidationStrings {
	static var invalidInternetPort: String {
		String(localized: .CommonErrors.internetPortInvalid)
	}

	static func maximumLength(_ maximumLength: Int) -> String {
		String(localized: .CommonErrors.maximumLength(maximumLength))
	}

	static var invalidRealName: String {
		String(localized: .CommonErrors.realNameInvalid)
	}

	static var invalidNickname: String {
		String(localized: .CommonErrors.nicknameInvalid)
	}

	static var invalidServerAddress: String {
		String(localized: .CommonErrors.serverAddressInvalid)
	}

	static var singleLineRequired: String {
		String(localized: .CommonErrors.singleLineRequired)
	}
}
