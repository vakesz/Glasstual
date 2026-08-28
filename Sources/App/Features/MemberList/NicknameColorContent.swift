/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

struct NicknameColorContent: Equatable, Sendable {
	let colorPickerLabel: String
	let colorPickerAccessibilityHint: String
	let useDefaultColorTitle: String
	let useDefaultColorAccessibilityHint: String
	let saveButtonTitle: String
	let cancelButtonTitle: String
	let windowTitle: String

	static var current: Self {
		Self(
			colorPickerLabel: NicknameColorStrings.colorPickerLabel,
			colorPickerAccessibilityHint: NicknameColorStrings.colorPickerAccessibilityHint,
			useDefaultColorTitle: NicknameColorStrings.useDefaultColorTitle,
			useDefaultColorAccessibilityHint: NicknameColorStrings.useDefaultColorAccessibilityHint,
			saveButtonTitle: PromptStrings.Action.save,
			cancelButtonTitle: PromptStrings.Action.cancel,
			windowTitle: NicknameColorStrings.windowTitle
		)
	}
}
