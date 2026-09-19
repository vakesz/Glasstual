// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
@Suite("Main window sheets")
struct MainWindowSheetModelTests {
	/** Sheets raised on top of sheets are a chain, not an array the window
	 indexes into: SwiftUI presents a sheet from the view it is attached to, so
	 the second is presented by the first. Taking one down takes everything it
	 raised with it, innermost owner first. */
	@Test("A sheet raised over a sheet is dismissed with it, innermost first")
	func nestedSheetsAreDismissedTogether() {
		let model = MainWindowSheetModel()
		let firstOwner = NSObject()
		let secondOwner = NSObject()
		var finished: [String] = []

		model.presentSheet(MainWindowSheet(owner: firstOwner, content: EmptyView()) {
			finished.append("first")
		})
		model.presentSheet(MainWindowSheet(owner: secondOwner, content: EmptyView()) {
			finished.append("second")
		})

		#expect(model.presentedSheet?.owner === firstOwner)
		#expect(model.presentedSheet?.child?.owner === secondOwner)
		#expect(model.presentedSheet?.chain.count == 2)

		model.dismissSheet(ownedBy: firstOwner)

		#expect(finished == ["second", "first"])
		#expect(model.presentedSheet == nil)
	}

	@Test("Dismissing the inner sheet leaves the one that raised it")
	func dismissingTheInnerSheetLeavesItsParent() {
		let model = MainWindowSheetModel()
		let firstOwner = NSObject()
		let secondOwner = NSObject()
		var finished: [String] = []

		model.presentSheet(MainWindowSheet(owner: firstOwner, content: EmptyView()) {
			finished.append("first")
		})
		model.presentSheet(MainWindowSheet(owner: secondOwner, content: EmptyView()) {
			finished.append("second")
		})

		model.dismissSheet(ownedBy: secondOwner)

		#expect(finished == ["second"])
		#expect(model.presentedSheet?.owner === firstOwner)
		#expect(model.presentedSheet?.child == nil)
	}
}
