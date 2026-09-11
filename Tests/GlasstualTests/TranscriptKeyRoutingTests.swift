/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

/** Which keys the transcript hands to the input field.

 Focusing the transcript is how a reader moves back through it, so every key
 that moves a document has to stay with the text view; only text the reader is
 starting to type belongs in the input field. */
@Suite("Transcript key routing")
struct TranscriptKeyRoutingTests {
	@Test("Typed text is sent to the input field")
	func typedTextGoesToTheInputField() {
		for characters in ["a", "Z", "7", "/", "\u{00E9}", "\u{1F600}"] {
			#expect(LogView.isTextInput(characters))
		}
	}

	@Test("The keys that move a document stay with the transcript")
	func navigationKeysStayWithTheTranscript() {
		let navigation: [String?] = [
			NSUpArrowFunctionKey, NSDownArrowFunctionKey, NSLeftArrowFunctionKey, NSRightArrowFunctionKey,
			NSPageUpFunctionKey, NSPageDownFunctionKey, NSHomeFunctionKey, NSEndFunctionKey,
		].compactMap { UnicodeScalar(UInt32($0)).map { String($0) } }
		for characters in navigation + [" ", "", nil] {
			#expect(LogView.isTextInput(characters) == false)
		}
	}
}
