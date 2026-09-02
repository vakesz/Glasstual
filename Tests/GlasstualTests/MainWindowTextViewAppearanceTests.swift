/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Main window text view")
struct MainWindowTextViewAppearanceTests {
	@Test("Text with no IRC colour of its own is drawn in the preferred colour")
	func attributedValueUsesPreferredColorForUnformattedText() {
		let textView = MainWindowTextView(frame: .zero)
		textView.preferredFontColor = .systemRed
		textView.attributedStringValue = NSAttributedString(
			string: "plain",
			attributes: [.foregroundColor: NSColor.systemBlue]
		)

		let color = textView.attributedStringValue.attribute(
			.foregroundColor,
			at: 0,
			effectiveRange: nil
		) as? NSColor

		#expect(color == .systemRed)
	}

	@Test("An explicit IRC colour survives the preferred colour pass")
	func attributedValuePreservesExplicitIRCColor() {
		let textView = MainWindowTextView(frame: .zero)
		textView.preferredFontColor = .systemRed
		let formatterKey = NSAttributedString.Key(
			IRCTextFormatterAttributeName.foregroundColorAttributeName.rawValue
		)

		textView.attributedStringValue = NSAttributedString(
			string: "formatted",
			attributes: [
				.foregroundColor: NSColor.systemBlue,
				formatterKey: 4,
			]
		)

		let color = textView.attributedStringValue.attribute(
			.foregroundColor,
			at: 0,
			effectiveRange: nil
		) as? NSColor

		#expect(color == .systemBlue)
	}

	/** The placeholder used to be built only by the appearance pass, which reads
	 the main window's appearance objects and so needs the field to already be in
	 that window. The field joins one after the window has run its appearance
	 walk, so nothing built the string, the label was never added as a subview,
	 and an empty field drew a caret and nothing else. */
	@Test("An empty input field draws its placeholder, and typing hides it")
	func emptyInputFieldDrawsItsPlaceholder() {
		let host = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let textView = MainWindowTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
		host.contentView?.addSubview(textView)

		#expect(textView.drawnPlaceholderText == MainWindowStrings.Conversation.inputPlaceholder)

		textView.insertText("h", replacementRange: textView.selectedRange())

		#expect(textView.drawnPlaceholderText == nil)
	}

	@Test("The content view stays transparent and refuses vibrancy")
	func contentViewRemainsTransparentAndNonVibrant() {
		let contentView = MainWindowTextViewContentView(frame: .zero)

		#expect(contentView.isOpaque == false)
		#expect(contentView.allowsVibrancy == false)
	}
}
