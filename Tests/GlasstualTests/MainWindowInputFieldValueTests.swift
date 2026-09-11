/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

/** Replacing the field's whole value is not an edit the user can undo: the
 ranges the undo stack recorded describe text that has been thrown away. Only
 `attributedStringValue` cleared the stack, so which of the two setters a
 caller happened to reach for decided whether ⌘Z after a channel switch
 replayed the previous channel's ranges. */
@Suite("Main window input field values")
@MainActor
struct MainWindowInputFieldValueTests {
	/// An undo manager reaches a text view through the responder chain, so the
	/// field has to be in a window and hold the keyboard for there to be a stack
	/// to talk about.
	private func makeField() -> (window: NSWindow, field: TextViewWithIRCFormatter) {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		let field = TextViewWithIRCFormatter(frame: NSRect(x: 0, y: 0, width: 320, height: 40))
		field.prepareInitialState()
		field.allowsUndo = true
		window.contentView?.addSubview(field)
		window.makeFirstResponder(field)
		return (window, field)
	}

	private func typeAnUndoableEdit(into field: TextViewWithIRCFormatter) throws {
		field.insertText("typed", replacementRange: field.selectedRange())
		#expect(try #require(field.undoManager).canUndo)
	}

	@Test("The plain setter replaces the value and drops the undo stack")
	func stringValueClearsUndo() throws {
		let (_, field) = makeField()
		try typeAnUndoableEdit(into: field)

		field.stringValue = "replaced"

		#expect(field.stringValue == "replaced")
		#expect(try #require(field.undoManager).canUndo == false)
	}

	@Test("The attributed setter behaves identically")
	func attributedStringValueClearsUndo() throws {
		let (_, field) = makeField()
		try typeAnUndoableEdit(into: field)

		field.attributedStringValue = NSAttributedString(string: "replaced")

		#expect(field.stringValue == "replaced")
		#expect(try #require(field.undoManager).canUndo == false)
	}

	@Test("Both setters replace the whole value rather than appending")
	func settersReplaceTheWholeValue() {
		let (_, field) = makeField()

		field.stringValue = "first"
		field.attributedStringValue = NSAttributedString(string: "second")
		#expect(field.stringValue == "second")

		field.stringValue = ""
		#expect(field.stringValue.isEmpty)
	}
}

/** A range measured before a replacement describes storage the replacement
 shrank. Selecting eleven characters and inserting a shorter nickname then
 recoloured a range past the end of the field and threw. */
@Suite("Menu insertion ranges")
struct MenuInsertionRangePolicyTests {
	@Test("The inserted range covers what was inserted, at the replaced location")
	func insertedRangeCoversTheInsertion() {
		let replaced = NSRange(location: 4, length: 11)

		let inserted = MenuInsertionRangePolicy.insertedRange(replacing: replaced, with: "bob, ")

		#expect(inserted == NSRange(location: 4, length: 5))
	}

	/// The length is in UTF-16 units, which is what `NSTextStorage` counts in.
	@Test("Astral characters count as the storage counts them")
	func lengthIsMeasuredInUTF16() {
		let inserted = MenuInsertionRangePolicy.insertedRange(
			replacing: NSRange(location: 0, length: 3),
			with: "🙂"
		)

		#expect(inserted == NSRange(location: 0, length: 2))
	}

	@Test("An empty insertion collapses the range")
	func emptyInsertionCollapses() {
		let inserted = MenuInsertionRangePolicy.insertedRange(
			replacing: NSRange(location: 7, length: 4),
			with: ""
		)

		#expect(inserted == NSRange(location: 7, length: 0))
	}
}
