// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation

extension TranscriptView {
	func render(_ marker: TranscriptMarker, lineNumber: String) -> NSAttributedString {
		let controller = themeStore
		let palette = controller.theme.palette
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = .center
		let text: String
		let color: NSColor
		let font: NSFont
		/* The separators are hairlines the paragraph's layout fragment draws,
		 `inset` points below the paragraph's top, not `NSTextBlock` borders: a
		 text block in the storage moves the whole view back to TextKit 1. */
		var rule: (color: NSColor, inset: CGFloat)?
		// What an assistive reader is told the marker says, where the drawing
		// itself carries no words.
		var spokenText: String?
		switch marker {
		case let .date(value):
			text = value
			/* A date and a session boundary are clock-like text, the same as the
			 timestamp column, and share its role. */
			color = themeColor(palette.timestampText)
			font = NSFont.systemFont(
				ofSize: max(9, effectiveFont(controller).pointSize - 1),
				weight: .medium
			)
			paragraph.paragraphSpacing = 6
		case let .currentSession(value):
			text = value
			color = themeColor(palette.timestampText)
			font = NSFont.systemFont(
				ofSize: max(9, effectiveFont(controller).pointSize - 1),
				weight: .medium
			)
			paragraph.paragraphSpacingBefore = 10
			paragraph.paragraphSpacing = 6
			rule = (color.withAlphaComponent(0.22), 5)
		case let .unread(value):
			/* A quiet accent hairline keeps the boundary from competing with the
			 messages around it, but a hairline is a colour and nothing else: a
			 reader who has asked to be told things without colour, and a reader
			 who is not looking at all, both need the words. */
			let differentiates = NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor
			text = differentiates ? value : "\u{200B}"
			spokenText = value
			color = differentiates ? themeColor(palette.unreadMarker) : .clear
			font = NSFont.systemFont(
				ofSize: differentiates ? max(9, effectiveFont(controller).pointSize - 1) : 1,
				weight: .medium
			)
			paragraph.paragraphSpacingBefore = 5
			paragraph.paragraphSpacing = 5
			rule = (themeColor(palette.unreadMarker).withAlphaComponent(0.6), 5)
		}
		var attributes: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: color,
			.paragraphStyle: paragraph,
			.transcriptLineNumber: lineNumber,
		]
		if marker.isUnread, text == "\u{200B}" {
			/* The zero-width space is only something for the rule to stand on. */
			attributes[.transcriptPadding] = true
		}
		if let spokenText {
			attributes[.accessibilityCustomText] = [spokenText]
			attributes[.toolTip] = spokenText
		}
		if let rule {
			attributes[.transcriptRuleColor] = rule.color
			attributes[.transcriptRuleInset] = NSNumber(value: Double(rule.inset))
		}
		return NSAttributedString(string: "\(text)\n", attributes: attributes)
	}
}
