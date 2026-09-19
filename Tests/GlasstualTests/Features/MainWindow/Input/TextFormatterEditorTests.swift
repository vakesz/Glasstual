// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/** The formatting menu's edit half, exercised against a bare formatting field.

 The pipeline used to be private to the menu class, reachable only through an
 `@objc` item action on a menu the window had installed, so none of it was
 measured: not that a spoiler carries both of its colours, not that clearing one
 takes all three attributes with it, and not the rainbow walk's one rule -- one
 colour per composed character sequence, so a surrogate pair or a combining
 sequence is never split across two codes. */
@MainActor
@Suite("Text formatter editor")
struct TextFormatterEditorTests {
	private func makeEditor(over text: String) -> TextFormatterEditor {
		let field = FormattedTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 40))
		field.isEditable = true
		field.string = text
		field.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
		return TextFormatterEditor(field: field)
	}

	private func fullRange(of editor: TextFormatterEditor) -> NSRange {
		NSRange(location: 0, length: editor.field.attributedString().length)
	}

	@Test("A spoiler carries the two colours that hide the text with it")
	func spoilerCarriesBothColours() {
		let editor = makeEditor(over: "hidden")

		editor.setEffect(.spoiler, enabled: true)

		let stored = editor.field.attributedString()
		let range = fullRange(of: editor)
		#expect(stored.ircFormatterAttributeSet(inRange: .spoiler, range: range))
		#expect(stored.ircFormatterAttributeSet(inRange: .foregroundColor, range: range))
		#expect(stored.ircFormatterAttributeSet(inRange: .backgroundColor, range: range))
		#expect(editor.isSet(.spoiler))

		let foreground = stored.attribute(
			formatterKey(.foregroundColorAttributeName),
			at: 0,
			effectiveRange: nil
		) as? Int
		let background = stored.attribute(
			formatterKey(.backgroundColorAttributeName),
			at: 0,
			effectiveRange: nil
		) as? Int
		#expect(foreground == background)
	}

	@Test("Clearing the spoiler takes both of its colours with it")
	func clearingTheSpoilerClearsItsColours() {
		let editor = makeEditor(over: "hidden")
		editor.setEffect(.spoiler, enabled: true)

		editor.setEffect(.spoiler, enabled: false)

		let stored = editor.field.attributedString()
		let range = fullRange(of: editor)
		#expect(stored.ircFormatterAttributeSet(inRange: .spoiler, range: range) == false)
		#expect(stored.ircFormatterAttributeSet(inRange: .foregroundColor, range: range) == false)
		#expect(stored.ircFormatterAttributeSet(inRange: .backgroundColor, range: range) == false)
	}

	/** The regression the walk is written for: colouring by UTF-16 unit split a
	 surrogate pair or a combining sequence across two colour codes, which broke
	 the character it was colouring. */
	@Test("The rainbow colours one composed character sequence at a time")
	func rainbowColoursWholeCharacters() {
		let family = "👩‍👩‍👦"
		let editor = makeEditor(over: "a\(family)b")

		editor.applyRainbow(asForegroundColor: true)

		var runs: [(range: NSRange, code: Int)] = []
		editor.field.attributedString().enumerateAttribute(
			formatterKey(.foregroundColorAttributeName),
			in: fullRange(of: editor),
			options: []
		) { value, range, _ in
			if let code = value as? Int {
				runs.append((range, code))
			}
		}

		#expect(runs.count == 3, "runs \(runs)")
		#expect(runs.map(\.range.length) == [1, (family as NSString).length, 1])
		#expect(Set(runs.map(\.code)).count == 3, "each character takes the next code")
	}

	@Test("An unformatted selection reports no effects")
	func unformattedSelectionReportsNothing() {
		let editor = makeEditor(over: "plain")

		#expect(editor.isSet(.spoiler) == false)
		#expect(editor.isSet(.foregroundColor) == false)
		#expect(editor.isSet(.underline) == false)
	}

	@Test("Underline applies across the selection and is taken off again")
	func underlineTogglesAcrossTheSelection() {
		let editor = makeEditor(over: "marked")

		editor.setEffect(.underline, enabled: true)
		#expect(editor.isSet(.underline))

		editor.setEffect(.underline, enabled: false)
		#expect(editor.isSet(.underline) == false)
	}
}
