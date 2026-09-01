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

	@Test("The content view stays transparent and refuses vibrancy")
	func contentViewRemainsTransparentAndNonVibrant() {
		let contentView = MainWindowTextViewContentView(frame: .zero)

		#expect(contentView.isOpaque == false)
		#expect(contentView.allowsVibrancy == false)
	}
}
