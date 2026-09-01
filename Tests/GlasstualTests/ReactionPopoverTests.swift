/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@Suite("Reaction popover")
struct ReactionPopoverTests {
	@Test("The picker sends one complete grapheme")
	func pickerUsesOneCompleteGrapheme() {
		#expect(ReactionInput.emoji(from: "  👨‍👩‍👧‍👦 trailing") == "👨‍👩‍👧‍👦")
	}

	@Test("Whitespace does not enable the send action")
	func whitespaceIsNotAReaction() {
		#expect(ReactionInput.emoji(from: " \n\t ") == nil)
	}
}
