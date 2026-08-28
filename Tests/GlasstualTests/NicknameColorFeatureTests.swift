/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import SwiftUI
import XCTest

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
final class NicknameColorFeatureTests: XCTestCase {
	func testContentUsesKeyedLocalizedCopy() {
		let content = NicknameColorContent.current

		XCTAssertEqual(content.colorPickerLabel, "Change nickname color to:")
		XCTAssertEqual(content.useDefaultColorTitle, "Use default color")
		XCTAssertEqual(content.saveButtonTitle, "Save")
		XCTAssertEqual(content.cancelButtonTitle, "Cancel")
		XCTAssertEqual(content.windowTitle, "Nickname Color")
	}

	func testModelPreservesDefaultAndCustomColorSemantics() {
		let customColor = NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
		let replacementColor = NSColor(calibratedRed: 0.7, green: 0.3, blue: 0.1, alpha: 1)
		let defaultModel = NicknameColorModel(nickname: "alice", overrideColor: nil)

		XCTAssertTrue(defaultModel.usesDefaultColor)
		XCTAssertNil(defaultModel.colorForPersistence)
		assertColorsEqual(defaultModel.selectedColor, NicknameColorModel.initialPickerColor)

		let customModel = NicknameColorModel(nickname: "bob", overrideColor: customColor)
		XCTAssertFalse(customModel.usesDefaultColor)
		assertColorsEqual(customModel.colorForPersistence, customColor)

		customModel.setUsesDefaultColor(true)
		XCTAssertNil(customModel.colorForPersistence)

		customModel.setUsesDefaultColor(false)
		assertColorsEqual(customModel.colorForPersistence, customColor)

		customModel.selectColor(replacementColor)
		XCTAssertFalse(customModel.usesDefaultColor)
		assertColorsEqual(customModel.colorForPersistence, replacementColor)
	}

	func testRuntimeSheetContractSurvivesWithoutANib() throws {
		let adapter = NicknameColorSheet(nickname: "alice")
		let hostingView = try XCTUnwrap(adapter.sheet.contentView as? NSHostingView<NicknameColorView>)

		XCTAssertEqual(NSStringFromClass(NicknameColorSheet.self), "TDCNicknameColorSheet")
		XCTAssertEqual(
			NSStringFromProtocol(NicknameColorSheetDelegate.self),
			"TDCNicknameColorSheetDelegate"
		)
		XCTAssertNotNil(NSProtocolFromString("TDCNicknameColorSheetDelegate"))
		XCTAssertNil(Bundle.main.path(forResource: "TDCNicknameColorSheet", ofType: "nib"))

		for selectorName in [
			"initWithNickname:",
			"start",
			"ok:",
			"cancel:",
			"useDefaultColorToggled:",
			"nicknameColorChanged:",
			"windowWillClose:",
		] {
			XCTAssertTrue(
				NicknameColorSheet.instancesRespond(to: NSSelectorFromString(selectorName)),
				selectorName
			)
		}

		XCTAssertIdentical(hostingView.rootView.model, adapter.model)
		XCTAssertTrue(adapter.sheet.delegate === adapter)
		XCTAssertFalse(adapter.sheet.styleMask.contains(.resizable))
		XCTAssertFalse(adapter.sheet.isReleasedWhenClosed)
		XCTAssertFalse(adapter.sheet.isRestorable)
		XCTAssertEqual(adapter.sheet.tabbingMode, .disallowed)
		XCTAssertEqual(adapter.sheet.contentMinSize, NSSize(width: 390, height: 112))
		XCTAssertEqual(adapter.sheet.contentMaxSize, NSSize(width: 390, height: 112))
	}

	func testAdapterPersistsSelectionAndPreservesDelegateCallbacks() throws {
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

		let persistedColor = try XCTUnwrap(
			UserNicknameColorStyleGenerator.nicknameColorStyleOverride(forKey: overrideKey)
		)
		assertColorsEqual(persistedColor, customColor)
		XCTAssertTrue(delegate.didAccept)

		let defaultColorButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
		defaultColorButton.state = .on
		adapter.useDefaultColorToggled(defaultColorButton)
		adapter.ok(nil)
		XCTAssertNil(UserNicknameColorStyleGenerator.nicknameColorStyleOverride(forKey: overrideKey))

		adapter.windowWillClose(Notification(name: NSWindow.willCloseNotification))
		XCTAssertTrue(delegate.didClose)
	}

	private func assertColorsEqual(
		_ first: NSColor?,
		_ second: NSColor?,
		file: StaticString = #filePath,
		line: UInt = #line
	) {
		guard
			let first = first?.usingColorSpace(.extendedSRGB),
			let second = second?.usingColorSpace(.extendedSRGB)
		else {
			XCTAssertEqual(first == nil, second == nil, file: file, line: line)
			return
		}

		XCTAssertEqual(first.redComponent, second.redComponent, accuracy: 0.000_1, file: file, line: line)
		XCTAssertEqual(first.greenComponent, second.greenComponent, accuracy: 0.000_1, file: file, line: line)
		XCTAssertEqual(first.blueComponent, second.blueComponent, accuracy: 0.000_1, file: file, line: line)
		XCTAssertEqual(first.alphaComponent, second.alphaComponent, accuracy: 0.000_1, file: file, line: line)
	}
}
