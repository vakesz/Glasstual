/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

nonisolated enum NicknameColorStrings { // nonisolated: value
	static var colorPickerAccessibilityHint: String {
		String(localized: .TDCNicknameColorSheet.colorPickerAccessibilityHint)
	}

	static var colorPickerLabel: String {
		String(localized: .TDCNicknameColorSheet.colorPickerLabel)
	}

	static var useDefaultColorAccessibilityHint: String {
		String(localized: .TDCNicknameColorSheet.useDefaultColorAccessibilityHint)
	}

	static var useDefaultColorTitle: String {
		String(localized: .TDCNicknameColorSheet.useDefaultColor)
	}
}
