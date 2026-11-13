// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated enum ApplicationGroup {
	private static let infoKey = "GlasstualApplicationGroupIdentifier"

	static let identifier: String = {
		guard let identifier = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
		      !identifier.isEmpty
		else {
			preconditionFailure("The generated Info.plist is missing \(infoKey)")
		}

		return identifier
	}()
}
