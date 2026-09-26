// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Main window text view")
struct MainWindowTextViewAppearanceTests {
	@Test("Native appearance changes refresh plain text and preserve IRC colors and selection",
	      arguments: [NSAppearance.Name.aqua, .darkAqua])
	func nativeAppearanceChangesPreserveEditingState(appearanceName: NSAppearance.Name) throws {
		let host = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
			styleMask: .borderless, backing: .buffered, defer: false
		)
		host.appearance = NSAppearance(named: appearanceName == .aqua ? .darkAqua : .aqua)
		let textView = InputField(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
		host.contentView?.addSubview(textView)
		textView.preferredFontColor = .systemRed
		let formatterKey = NSAttributedString.Key(TextFormatterAttributeName.foregroundColorAttributeName.rawValue)
		let text = NSMutableAttributedString(string: "plain colored", attributes: [.foregroundColor: NSColor.systemRed])
		text.addAttributes([.foregroundColor: NSColor.systemBlue, formatterKey: 4], range: NSRange(location: 6, length: 7))
		textView.attributedStringValue = text
		let selection = NSRange(location: 2, length: 8)
		textView.setSelectedRange(selection)

		host.appearance = NSAppearance(named: appearanceName)

		let storage = try #require(textView.textStorage)
		#expect(textView.preferredFontColor == .labelColor)
		#expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .labelColor)
		#expect(storage.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor == .systemBlue)
		#expect(textView.selectedRange() == selection)
		#expect(textView.string == "plain colored")
	}

	@Test("Text with no IRC colour of its own is drawn in the preferred colour")
	func attributedValueUsesPreferredColorForUnformattedText() {
		let textView = InputField(frame: .zero)
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
		let textView = InputField(frame: .zero)
		textView.preferredFontColor = .systemRed
		let formatterKey = NSAttributedString.Key(
			TextFormatterAttributeName.foregroundColorAttributeName.rawValue
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
		let textView = InputField(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
		host.contentView?.addSubview(textView)

		#expect(textView.drawnPlaceholderText == String(localized: .MainWindow.sendMessage))

		textView.insertText("h", replacementRange: textView.selectedRange())

		#expect(textView.drawnPlaceholderText == nil)
	}

	@Test("The content view stays transparent and refuses vibrancy")
	func contentViewRemainsTransparentAndNonVibrant() {
		let contentView = InputFieldContentView(frame: .zero)

		#expect(contentView.isOpaque == false)
		#expect(contentView.allowsVibrancy == false)
	}
}
