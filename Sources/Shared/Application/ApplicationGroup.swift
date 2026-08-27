/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

enum ApplicationGroup {
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
