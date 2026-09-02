/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
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
}
