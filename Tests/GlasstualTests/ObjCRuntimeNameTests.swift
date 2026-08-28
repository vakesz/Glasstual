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
import CocoaExtensions
@testable import Glasstual
import Testing

/// The few Objective-C names and protocol constants that something outside the
/// compiler depends on. `NibRuntimeNameTests` checks the other direction — that
/// every name a nib mentions resolves — so this suite only pins the Swift types
/// whose `@objc` name a nib binds, and the mIRC palette, whose indices are wire
/// format rather than a design choice.
///
/// Nothing else belongs here. A test that asserts a type conforms to a protocol,
/// responds to a selector it declares, or has the raw value written next to its
/// declaration restates the compiler and fails on every rename.
@Suite("Objective-C runtime names")
@MainActor
struct ObjCRuntimeNameTests {
	@Test(
		"A nib-bound class keeps the runtime name the nib holds",
		arguments: [
			(FileTransferDialog.self as AnyClass, "TDCFileTransferDialog"),
			(FileTransferDialogWindow.self as AnyClass, "TDCFileTransferDialogWindow"),
			(PreferencesController.self as AnyClass, "TDCPreferencesController"),
			(BasicTableView.self as AnyClass, "TVCBasicTableView"),
			(ValidatedTextField.self as AnyClass, "TVCValidatedTextField"),
			(ValidatedComboBox.self as AnyClass, "TVCValidatedComboBox"),
			(TextViewWithIRCFormatter.self as AnyClass, "TVCTextViewWithIRCFormatter"),
		]
	)
	func classKeepsItsRuntimeName(_ type: AnyClass, _ name: String) {
		#expect(NSStringFromClass(type) == name)
	}

	/// `TVCValidatedComboBox` sets this as its cell class from the nib; no Swift
	/// declaration references it by type.
	@Test("The validated combo box cell is reachable by name")
	func comboBoxCellResolves() {
		#expect(NSClassFromString("TVCValidatedComboBoxCell") != nil)
	}

	/// mIRC colour codes index this table, so the order is protocol, not
	/// presentation: colour 0 is white and colour 1 is black on every network.
	@Test("The mIRC palette keeps its 99 entries in wire order")
	func formatterPaletteIsPinned() {
		#expect(NSColor.formatterColors.count == 99)
		#expect(NSColor.formatterWhiteColor == NSColor.formatterColors[0])
		#expect(NSColor.formatterBlackColor == NSColor.formatterColors[1])
		#expect(NSColor.formatterLightGrayColor == NSColor.formatterColors[15])
	}
}
