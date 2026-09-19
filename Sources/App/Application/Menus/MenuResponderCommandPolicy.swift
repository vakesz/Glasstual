// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Where a Paste command puts what it is carrying.
nonisolated enum MenuPasteTarget: Sendable {
	/// Whatever holds the keyboard.
	case firstResponder
	/// The chat input, which is where the main window sends a paste that has no
	/// editable responder of its own to go to.
	case inputField
	/// Nowhere: nothing editable holds the keyboard and there is no input field.
	case none
}

/** The menu rule that was asking the wrong thing.

 Paste asked whether the main window was key and then validated against the
 chat input, so it read as enabled while the caret was in the toolbar's search
 field or a sheet's field. */
@MainActor
enum MenuResponderCommandPolicy {
	/** Paste is a property of the responder that will receive it.

	 The menu item and the action ask the same question of the same three
	 inputs: the item was enabled only for an editable responder while the
	 action fell back to the message field, so ⌘V read as unavailable while the
	 reader was in the transcript -- and the shortcut, which AppKit validates
	 through the item, did nothing at all. */
	static func canPaste(
		pasteboardHasText: Bool,
		responderIsEditableText: Bool,
		responderIsInInputBar: Bool,
		hasInputField: Bool
	) -> Bool {
		guard pasteboardHasText else { return false }
		return pasteTarget(
			responderIsEditableText: responderIsEditableText,
			responderIsInInputBar: responderIsInInputBar,
			hasInputField: hasInputField
		) != .none
	}

	/** Which of the two the paste is aimed at.

	 The same question ``canPaste(pasteboardHasText:responderIsEditableText:responderIsInInputBar:hasInputField:)``
	 answers, asked for the action rather than the menu item: the responder holding
	 the keyboard is the destination, and the chat input is only a fallback. Sending
	 every paste to the input field pulled the focus out of the toolbar's search
	 field or a sheet's field and dropped the text into the conversation
	 instead, so the field is chosen only when the responder belongs to the
	 input bar already, or when nothing editable has the keyboard at all. */
	static func pasteTarget(
		responderIsEditableText: Bool,
		responderIsInInputBar: Bool,
		hasInputField: Bool
	) -> MenuPasteTarget {
		if responderIsEditableText, responderIsInInputBar == false {
			return .firstResponder
		}
		if hasInputField {
			return .inputField
		}
		return responderIsEditableText ? .firstResponder : .none
	}
}
