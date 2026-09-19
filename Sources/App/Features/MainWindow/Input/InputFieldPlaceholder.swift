// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

/** The prompt an empty message field draws.

 TextKit 2 paints the text through its layout fragments and does not redraw the
 view for every edit, so a placeholder painted in `draw(_:)` lingers under typed
 text. It is a click-transparent label instead, shown only while the string is
 empty.

 The field is handed in per call rather than held: this belongs to one field, the
 field builds it, and a stored reference back would be a cycle. It also keeps the
 string off the text view itself, where `placeholderAttributedString` is a
 private `NSTextView` accessor AppKit may call. */
@MainActor
final class InputFieldPlaceholder {
	private let label: PlaceholderLabel = {
		let label = PlaceholderLabel(labelWithString: "")
		label.lineBreakMode = .byTruncatingTail
		label.maximumNumberOfLines = 1
		label.isHidden = true
		return label
	}()

	/// The string the label draws, or `nil` until the field has built one.
	private(set) var attributedString: NSAttributedString?

	/// The placeholder as the reader sees it, or `nil` when nothing is drawn.
	var drawnText: String? {
		guard label.superview != nil, label.isHidden == false else { return nil }

		return label.stringValue
	}

	/** Builds the placeholder out of what the field knows now.

	 It used to be built only from the appearance pass, which reads the main
	 window's appearance objects and so needs the field to already be in that
	 window. The field is built before it joins one — SwiftUI hands it over from
	 `makeNSView`, after the window has run its appearance walk — so on a normal
	 launch nothing ever built the string, the label was never added as a
	 subview, and an empty field showed a caret and nothing else. */
	func update(in field: InputField) {
		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.baseWritingDirection = field.baseWritingDirection
		paragraphStyle.alignment = .natural
		paragraphStyle.lineBreakMode = .byTruncatingTail

		let placeholder = NSAttributedString(
			string: String(localized: .MainWindow.sendMessage),
			attributes: [
				.font: field.preferredFont,
				.foregroundColor: NSColor.placeholderTextColor,
				.paragraphStyle: paragraphStyle,
			]
		)

		attributedString = placeholder
		field.setAccessibilityPlaceholderValue(placeholder.string)
		if label.superview == nil {
			field.addSubview(label)
		}
		label.attributedStringValue = placeholder
		field.needsLayout = true
		layout(in: field)
		updateVisibility(in: field)
	}

	/// Sits the label on the first line fragment, so its text starts where the
	/// reader's would.
	func layout(in field: InputField) {
		guard let textContainer = field.textContainer else { return }

		let padding = textContainer.lineFragmentPadding
		let origin = field.textContainerOrigin
		label.frame = NSRect(
			x: origin.x + padding,
			y: origin.y,
			width: max(0, textContainer.size.width - (padding * 2)),
			height: field.defaultLineHeight
		)
	}

	func updateVisibility(in field: InputField) {
		label.isHidden = field.stringLength != 0 || attributedString == nil
	}
}

/// A label that never takes the click, so the caret still lands in the text view.
private final class PlaceholderLabel: NSTextField {
	override func hitTest(_: NSPoint) -> NSView? {
		nil
	}
}
