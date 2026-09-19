// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
@Suite("Nickname color sheet", .serialized)
struct NicknameColorFeatureTests {
	/** The sheet was untitled, never said whose colour it was changing, and
	 offered "Save" for a choice that changes a colour rather than writing a
	 document. */
	@Test("Every string the sheet shows comes from the catalog, and names what it does")
	func sheetCopyNamesTheNicknameAndTheVerb() {
		#expect(String(localized: .MemberList.windowTitle("alice")) == "Color for “alice”")
		#expect(String(localized: .MemberList.colorPickerLabel) == "Color")
		#expect(String(localized: .MemberList.useDefaultColor) == "Use default color")
		#expect(String(localized: .MemberList.changeColor) == "Change Color")
		#expect(
			String(localized: .MemberList.previewAccessibilityLabel("alice"))
				== "Preview of alice in the chosen color"
		)
	}

	/** The sheet shows the nickname in the colour being chosen. Asked for the
	 default, the preview is the colour the nickname hashes to — not whatever
	 override is still stored, which is what the transcript would stop using. */
	@Test("The preview is what the transcript would draw")
	func previewFollowsTheChoice() {
		let nickname = "nickname-color-preview-\(UUID().uuidString)"
		let customColor = NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
		let model = NicknameColorModel(nickname: nickname, overrideColor: customColor)

		expectColorsEqual(model.previewColor, customColor)

		model.setUsesDefaultColor(true)
		expectColorsEqual(
			model.previewColor,
			NicknameColors.generatedColor(for: nickname)
		)
	}

	@Test("Choosing the default color withholds a color from persistence without forgetting the old one")
	func modelPreservesDefaultAndCustomColorSemantics() {
		let customColor = NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
		let replacementColor = NSColor(calibratedRed: 0.7, green: 0.3, blue: 0.1, alpha: 1)
		let defaultModel = NicknameColorModel(nickname: "alice", overrideColor: nil)

		#expect(defaultModel.usesDefaultColor)
		#expect(defaultModel.colorForPersistence == nil)
		expectColorsEqual(defaultModel.selectedColor, NicknameColorModel.initialPickerColor)

		let customModel = NicknameColorModel(nickname: "bob", overrideColor: customColor)
		#expect(customModel.usesDefaultColor == false)
		expectColorsEqual(customModel.colorForPersistence, customColor)

		customModel.setUsesDefaultColor(true)
		#expect(customModel.colorForPersistence == nil)

		customModel.setUsesDefaultColor(false)
		expectColorsEqual(customModel.colorForPersistence, customColor)

		customModel.selectColor(replacementColor)
		#expect(customModel.usesDefaultColor == false)
		expectColorsEqual(customModel.colorForPersistence, replacementColor)
	}

	@Test("Accepting writes the chosen color, and the default color clears it again")
	func sheetPersistsSelectionAndReportsTheChange() throws {
		let nickname = "Nickname-Color-Feature-\(UUID().uuidString)"
		let customColor = NSColor(calibratedRed: 0.15, green: 0.35, blue: 0.75, alpha: 0.9)
		var changeCount = 0

		NicknameColors.setOverride(nil, for: nickname)
		defer {
			NicknameColors.setOverride(nil, for: nickname)
		}

		let sheet = NicknameColorSheet(nickname: nickname) { changeCount += 1 }
		sheet.model.selectColor(customColor)
		sheet.submit()

		/* The store folds case, so the colour a sheet opened on one spelling
		 pins is the colour every other spelling of the name is drawn in. */
		let persistedColor = try #require(
			NicknameColors.pinnedColor(for: nickname.lowercased())
		)
		expectColorsEqual(persistedColor, customColor)
		#expect(changeCount == 1)

		sheet.model.setUsesDefaultColor(true)
		sheet.submit()
		#expect(NicknameColors.pinnedColor(for: nickname) == nil)
		#expect(changeCount == 2)
	}

	private func expectColorsEqual(
		_ first: NSColor?,
		_ second: NSColor?,
		sourceLocation: SourceLocation = #_sourceLocation
	) {
		guard
			let first = first?.usingColorSpace(.extendedSRGB),
			let second = second?.usingColorSpace(.extendedSRGB)
		else {
			#expect((first == nil) == (second == nil), sourceLocation: sourceLocation)
			return
		}

		let tolerance = 0.000_1
		#expect(abs(first.redComponent - second.redComponent) < tolerance, sourceLocation: sourceLocation)
		#expect(abs(first.greenComponent - second.greenComponent) < tolerance, sourceLocation: sourceLocation)
		#expect(abs(first.blueComponent - second.blueComponent) < tolerance, sourceLocation: sourceLocation)
		#expect(abs(first.alphaComponent - second.alphaComponent) < tolerance, sourceLocation: sourceLocation)
	}
}
