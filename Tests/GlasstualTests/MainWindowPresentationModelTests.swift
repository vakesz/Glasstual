/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
@Suite("Main window presentation model")
struct MainWindowPresentationModelTests {
	/// The sidebar filter lives in the window toolbar, and the root view binds
	/// this flag to the field's focus. Raising it is the whole of what the
	/// Search Channels command does.
	@Test("Focusing the search field raises the flag the toolbar field is bound to")
	func focusingTheSearchFieldRaisesItsFlag() {
		let model = MainWindowPresentationModel()

		#expect(model.isSearchFieldFocused == false)

		model.focusSearchField()

		#expect(model.isSearchFieldFocused)
	}

	/** Sheets raised on top of sheets are a chain, not an array the window
	 indexes into: SwiftUI presents a sheet from the view it is attached to, so
	 the second is presented by the first. Taking one down takes everything it
	 raised with it, innermost owner first. */
	@Test("A sheet raised over a sheet is dismissed with it, innermost first")
	func nestedSheetsAreDismissedTogether() {
		let model = MainWindowPresentationModel()
		let firstOwner = NSObject()
		let secondOwner = NSObject()
		var finished: [String] = []

		model.presentSheet(PresentedSheet(owner: firstOwner, content: EmptyView()) {
			finished.append("first")
		})
		model.presentSheet(PresentedSheet(owner: secondOwner, content: EmptyView()) {
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
		let model = MainWindowPresentationModel()
		let firstOwner = NSObject()
		let secondOwner = NSObject()
		var finished: [String] = []

		model.presentSheet(PresentedSheet(owner: firstOwner, content: EmptyView()) {
			finished.append("first")
		})
		model.presentSheet(PresentedSheet(owner: secondOwner, content: EmptyView()) {
			finished.append("second")
		})

		model.dismissSheet(ownedBy: secondOwner)

		#expect(finished == ["second"])
		#expect(model.presentedSheet?.owner === firstOwner)
		#expect(model.presentedSheet?.child == nil)
	}
}
