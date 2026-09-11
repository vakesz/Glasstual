/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

/** What the capsule around the message field draws its focus ring from.

 The field is an AppKit view inside SwiftUI, so it reports its own
 first-responder transitions — and that alone was the ring's whole answer. A
 window keeps its first responder while it is inactive and sends no
 `resignFirstResponder` when it stops being key, so every background window in
 the space kept a lit ring around its message field. */
@Suite("Main window input focus ring")
@MainActor
struct MainWindowInputFocusTests {
	@Test("The ring needs the first responder and the key window, not either one")
	func ringNeedsBothHalves() {
		let model = MainWindowInputFocusModel()
		#expect(model.isFocused == false)

		model.isFirstResponder = true
		#expect(model.isFocused == false, "an inactive window's field draws no ring")

		model.windowIsKey = true
		#expect(model.isFocused)

		/* The regression: this is the transition that arrives with no
		 `resignFirstResponder` behind it. */
		model.windowIsKey = false
		#expect(model.isFocused == false)
	}

	@Test("A key window whose field does not hold the keyboard draws no ring")
	func keyWindowAloneIsNotFocus() {
		let model = MainWindowInputFocusModel()
		model.windowIsKey = true
		#expect(model.isFocused == false)

		model.isFirstResponder = true
		#expect(model.isFocused)

		model.isFirstResponder = false
		#expect(model.isFocused == false)
	}
}
