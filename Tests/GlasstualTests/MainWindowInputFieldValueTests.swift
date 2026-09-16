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
	/// Exercise editing with the same window and first-responder ownership as
	/// the input bar. Its undo stack belongs to the editor.
	private func makeField() -> (window: NSWindow, field: IRCFormattedTextView) {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		let field = IRCFormattedTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 40))
		window.isReleasedWhenClosed = false
		field.prepareInitialState()
		field.allowsUndo = true
		window.contentView?.addSubview(field)
		window.makeFirstResponder(field)
		return (window, field)
	}

	private func typeAnUndoableEdit(into field: IRCFormattedTextView) throws {
		field.insertText("typed", replacementRange: field.selectedRange())
		#expect(try #require(field.undoManager).canUndo)
	}

	@Test("The plain setter replaces the value and drops the undo stack")
	func stringValueClearsUndo() throws {
		let (window, field) = makeField()
		defer { window.close() }
		try typeAnUndoableEdit(into: field)

		field.stringValue = "replaced"

		#expect(field.stringValue == "replaced")
		#expect(try #require(field.undoManager).canUndo == false)
	}

	@Test("The attributed setter behaves identically")
	func attributedStringValueClearsUndo() throws {
		let (window, field) = makeField()
		defer { window.close() }
		try typeAnUndoableEdit(into: field)

		field.attributedStringValue = NSAttributedString(string: "replaced")

		#expect(field.stringValue == "replaced")
		#expect(try #require(field.undoManager).canUndo == false)
	}

	@Test("Replacing one editor's value keeps another editor's undo history")
	func replacingTheValueKeepsOtherUndoActions() throws {
		let (window, field) = makeField()
		defer { window.close() }
		let other = IRCFormattedTextView(frame: NSRect(x: 0, y: 40, width: 320, height: 40))
		other.allowsUndo = true
		window.contentView?.addSubview(other)
		window.makeFirstResponder(other)
		let otherUndoManager = try #require(other.undoManager)
		otherUndoManager.groupsByEvent = false
		otherUndoManager.beginUndoGrouping()
		try typeAnUndoableEdit(into: other)
		otherUndoManager.endUndoGrouping()

		field.stringValue = "replaced"

		#expect(try #require(field.undoManager).canUndo == false)
		#expect(otherUndoManager.canUndo)
		otherUndoManager.undo()
		#expect(other.string.isEmpty)
		#expect(field.stringValue == "replaced")
	}

	/** A conversation switch refills the field through the value setters, and
	 the field reported that refill as typing. The new conversation got a
	 typing notice the user never started. */
	@Test("A value set from code is marked as not typed, and typing is not")
	func programmaticValuesAreNotTyping() {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		let field = TypingRecordingField(frame: NSRect(x: 0, y: 0, width: 320, height: 40))
		window.isReleasedWhenClosed = false
		defer { window.close() }
		field.prepareInitialState()
		window.contentView?.addSubview(field)
		window.makeFirstResponder(field)

		field.stringValue = "restored draft"
		field.attributedStringValue = NSAttributedString(string: "history entry")
		#expect(field.changesMarkedAsReplacement == [true, true])

		field.insertText("!", replacementRange: field.selectedRange())
		#expect(field.changesMarkedAsReplacement == [true, true, false])
		#expect(field.isReplacingEntireValue == false)
	}
}

/// Records, for every text change, whether the field called it a replacement.
private final class TypingRecordingField: IRCFormattedTextView {
	private(set) var changesMarkedAsReplacement: [Bool] = []

	override func textDidChange(_ notification: Notification) {
		super.textDidChange(notification)
		changesMarkedAsReplacement.append(isReplacingEntireValue)
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
