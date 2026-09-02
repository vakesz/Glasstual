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

import AppKit
import Observation

@MainActor
@Observable
final class NicknameColorModel {
	static let initialPickerColor = NSColor(
		calibratedRed: 0.058_130_498_98,
		green: 0.055_541_899_06,
		blue: 1,
		alpha: 1
	)

	let nickname: String
	private(set) var selectedColor: NSColor
	private(set) var usesDefaultColor: Bool

	init(nickname: String, overrideColor: NSColor?) {
		self.nickname = nickname
		selectedColor = overrideColor ?? Self.initialPickerColor
		usesDefaultColor = overrideColor == nil
	}

	var colorForPersistence: NSColor? {
		usesDefaultColor ? nil : selectedColor
	}

	func setUsesDefaultColor(_ usesDefaultColor: Bool) {
		self.usesDefaultColor = usesDefaultColor
	}

	func selectColor(_ color: NSColor) {
		selectedColor = color
		usesDefaultColor = false
	}
}
