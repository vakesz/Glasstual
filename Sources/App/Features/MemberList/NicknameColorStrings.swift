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
		String(localized: .MemberList.colorPickerAccessibilityHint)
	}

	static var colorPickerLabel: String {
		String(localized: .MemberList.colorPickerLabel)
	}

	static var useDefaultColorAccessibilityHint: String {
		String(localized: .MemberList.useDefaultColorAccessibilityHint)
	}

	static var useDefaultColorTitle: String {
		String(localized: .MemberList.useDefaultColor)
	}

	static func windowTitle(nickname: String) -> String {
		String(localized: .MemberList.windowTitle(nickname))
	}

	static var changeColor: String {
		String(localized: .MemberList.changeColor)
	}

	static func previewAccessibilityLabel(nickname: String) -> String {
		String(localized: .MemberList.previewAccessibilityLabel(nickname))
	}
}
