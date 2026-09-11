/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@Suite("Menu commands that follow the responder")
@MainActor
struct MenuCommandValidationResponderTests {
	/** Paste used to validate against the chat input whenever the main window
	 was key, so it read as enabled while the caret was in the toolbar's search
	 field or a sheet's field -- and then pasted into the wrong one. The
	 responder is the only thing the answer may depend on. */
	@Test("Paste follows the first responder, not the window")
	func pasteFollowsTheResponder() {
		#expect(MenuResponderCommandPolicy.canPaste(
			pasteboardHasText: true,
			responderIsEditableText: true,
			responderIsInInputBar: false,
			hasInputField: false
		))
		#expect(MenuResponderCommandPolicy.canPaste(
			pasteboardHasText: true,
			responderIsEditableText: false,
			responderIsInInputBar: false,
			hasInputField: false
		) == false)
	}

	/** The item and the action used to disagree: validation asked only whether
	 the responder was editable text, while the action falls back to the message
	 field. ⌘V read as unavailable -- and so did nothing at all -- while the
	 reader was in the transcript, which is exactly where the fallback is for. */
	@Test("Paste stays available while the message field is the fallback")
	func pasteIsAvailableWhereverTheActionHasSomewhereToPut() {
		#expect(MenuResponderCommandPolicy.canPaste(
			pasteboardHasText: true,
			responderIsEditableText: false,
			responderIsInInputBar: false,
			hasInputField: true
		))
		#expect(MenuResponderCommandPolicy.pasteTarget(
			responderIsEditableText: false,
			responderIsInInputBar: false,
			hasInputField: true
		) == .inputField)
	}

	@Test("A responder that cannot take text and no field to fall back on refuses the paste")
	func nonTextRespondersRefusePaste() {
		#expect(MenuResponderCommandPolicy.canPaste(
			pasteboardHasText: true,
			responderIsEditableText: false,
			responderIsInInputBar: false,
			hasInputField: false
		) == false)
	}

	@Test("An empty pasteboard refuses the paste whatever has the keyboard")
	func emptyPasteboardRefusesPaste() {
		#expect(MenuResponderCommandPolicy.canPaste(
			pasteboardHasText: false,
			responderIsEditableText: true,
			responderIsInInputBar: false,
			hasInputField: true
		) == false)
	}

	/// Validation and the action read the same three inputs, so no combination
	/// of them may enable an item the action would do nothing for.
	@Test("Validation and the paste target never disagree")
	func validationMatchesThePasteTarget() {
		for editable in [true, false] {
			for inInputBar in [true, false] {
				for hasField in [true, false] {
					let target = MenuResponderCommandPolicy.pasteTarget(
						responderIsEditableText: editable,
						responderIsInInputBar: inInputBar,
						hasInputField: hasField
					)
					#expect(MenuResponderCommandPolicy.canPaste(
						pasteboardHasText: true,
						responderIsEditableText: editable,
						responderIsInInputBar: inInputBar,
						hasInputField: hasField
					) == (target != .none))
				}
			}
		}
	}

	/** The action side of the same rule. Pasting used to focus the chat input
	 whenever the main window was key, so the text landed in the conversation
	 while the caret was in the toolbar's search field. */
	@Test("Paste is delivered to the responder that holds the keyboard")
	func pasteTargetsTheResponder() {
		#expect(MenuResponderCommandPolicy.pasteTarget(
			responderIsEditableText: true,
			responderIsInInputBar: false,
			hasInputField: true
		) == .firstResponder)
	}

	@Test("A responder inside the input bar is served by the input field")
	func pasteTargetsTheInputBarField() {
		#expect(MenuResponderCommandPolicy.pasteTarget(
			responderIsEditableText: true,
			responderIsInInputBar: true,
			hasInputField: true
		) == .inputField)
	}

	@Test("With nothing editable focused the chat input takes the paste")
	func pasteFallsBackToTheInputField() {
		#expect(MenuResponderCommandPolicy.pasteTarget(
			responderIsEditableText: false,
			responderIsInInputBar: false,
			hasInputField: true
		) == .inputField)
	}

	/// A window that is not the main one has no chat input to fall back to.
	@Test("Without an input field the paste goes nowhere it cannot go")
	func pasteWithoutAnInputFieldFollowsTheResponderOrStops() {
		#expect(MenuResponderCommandPolicy.pasteTarget(
			responderIsEditableText: true,
			responderIsInInputBar: false,
			hasInputField: false
		) == .firstResponder)
		#expect(MenuResponderCommandPolicy.pasteTarget(
			responderIsEditableText: false,
			responderIsInInputBar: false,
			hasInputField: false
		) == .none)
	}

	/** Change Nickname validated on `isConnected` while the action it enables
	 guards on `isLoggedIn` -- and calls `closePresentedSheet()` first, so
	 choosing it during registration dismissed an unrelated sheet and then did
	 nothing at all. */
	@Test("Change Nickname needs a registered connection, not merely a socket")
	func changeNicknameNeedsLogin() {
		#expect(MenuResponderCommandPolicy.canChangeNickname(clientIsLoggedIn: true))
		#expect(MenuResponderCommandPolicy.canChangeNickname(clientIsLoggedIn: false) == false)
	}
}
