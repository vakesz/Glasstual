/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import Foundation
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
private final class NicknameColorDelegateSpy: NSObject, NicknameColorSheetDelegate {
	private(set) var didAccept = false
	private(set) var didClose = false

	@objc(nicknameColorSheetOnOk:)
	func nicknameColorSheetOnOk(_: NicknameColorSheet) {
		didAccept = true
	}

	@objc(nicknameColorSheetWillClose:)
	func nicknameColorSheetWillClose(_: NicknameColorSheet) {
		didClose = true
	}
}

@MainActor
@Suite("Nickname color sheet", .serialized)
struct NicknameColorFeatureTests {
	@Test("Every string the sheet shows comes from the catalog")
	func contentUsesKeyedLocalizedCopy() {
		let content = NicknameColorContent.current

		#expect(content.colorPickerLabel == "Change nickname color to:")
		#expect(content.useDefaultColorTitle == "Use default color")
		#expect(content.saveButtonTitle == "Save")
		#expect(content.cancelButtonTitle == "Cancel")
		#expect(content.windowTitle == "Nickname Color")
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

	@Test("The sheet hosts its model in a fixed, non-resizable window it built itself")
	func sheetWindowIsBuiltAroundTheModelWithoutANib() throws {
		let adapter = NicknameColorSheet(nickname: "alice")
		let hostingView = try #require(adapter.sheet.contentView as? NSHostingView<NicknameColorView>)

		#expect(hostingView.rootView.model === adapter.model)
		#expect(adapter.sheet.delegate === adapter)
		#expect(adapter.sheet.styleMask.contains(.resizable) == false)
		#expect(adapter.sheet.isReleasedWhenClosed == false)
		#expect(adapter.sheet.isRestorable == false)
		#expect(adapter.sheet.tabbingMode == .disallowed)
		#expect(adapter.sheet.contentMinSize == NSSize(width: 390, height: 112))
		#expect(adapter.sheet.contentMaxSize == NSSize(width: 390, height: 112))
	}

	@Test("Accepting writes the chosen color, and the default color clears it again")
	func adapterPersistsSelectionAndPreservesDelegateCallbacks() throws {
		let nickname = "nickname-color-feature-\(UUID().uuidString)"
		// The generator looks overrides up by lowercased nickname, so that is
		// the key the sheet has to have written under.
		let overrideKey = nickname.lowercased()
		let customColor = NSColor(calibratedRed: 0.15, green: 0.35, blue: 0.75, alpha: 0.9)
		let delegate = NicknameColorDelegateSpy()

		UserNicknameColorStyleGenerator.setNicknameColorStyleOverride(nil, forKey: overrideKey)
		defer {
			UserNicknameColorStyleGenerator.setNicknameColorStyleOverride(nil, forKey: overrideKey)
		}

		let adapter = NicknameColorSheet(nickname: nickname)
		adapter.delegate = delegate
		adapter.nicknameColorChanged(customColor)
		adapter.ok(nil)

		let persistedColor = try #require(
			UserNicknameColorStyleGenerator.nicknameColorStyleOverride(forKey: overrideKey)
		)
		expectColorsEqual(persistedColor, customColor)
		#expect(delegate.didAccept)

		let defaultColorButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
		defaultColorButton.state = .on
		adapter.useDefaultColorToggled(defaultColorButton)
		adapter.ok(nil)
		#expect(UserNicknameColorStyleGenerator.nicknameColorStyleOverride(forKey: overrideKey) == nil)

		adapter.windowWillClose(Notification(name: NSWindow.willCloseNotification))
		#expect(delegate.didClose)
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
