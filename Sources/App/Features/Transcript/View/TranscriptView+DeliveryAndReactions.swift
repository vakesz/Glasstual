// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation

extension TranscriptView {
	func appendDeliveryAndReactions(
		for line: TranscriptRow,
		to result: NSMutableAttributedString,
		paragraph: NSParagraphStyle
	) {
		appendDeliveryState(for: line, to: result, paragraph: paragraph)
		appendReactions(for: line, to: result, paragraph: paragraph)
	}

	/// How one delivery state is drawn. The symbol is what carries the meaning;
	/// the colour only reinforces it, so a reader who cannot tell the colours
	/// apart still can.
	private struct DeliveryPresentation {
		let symbol: String
		let label: String
		let color: NSColor
	}

	private func deliveryPresentation(for line: TranscriptRow) -> DeliveryPresentation? {
		let controller = themeStore
		let palette = controller.theme.palette
		let clock = themeColor(palette.timestampText)
		return switch line.deliveryState {
		case .pending:
			DeliveryPresentation(symbol: "clock", label: String(localized: .Transcript.pending), color: clock)
		case .delivered:
			DeliveryPresentation(symbol: "checkmark", label: String(localized: .Transcript.delivered), color: clock)
		case .failed:
			DeliveryPresentation(
				symbol: "exclamationmark.triangle.fill",
				label: String(localized: .Transcript.failed),
				color: themeColor(palette.failure)
			)
		case .none:
			nil
		}
	}

	private func appendDeliveryState(
		for line: TranscriptRow,
		to result: NSMutableAttributedString,
		paragraph: NSParagraphStyle
	) {
		guard let presentation = deliveryPresentation(for: line) else { return }
		let controller = themeStore
		let font = NSFont.systemFont(ofSize: max(9, effectiveFont(controller).pointSize - 1))
		var attributes = lineAttributes(for: line)
		attributes[.font] = font
		attributes[.paragraphStyle] = paragraph
		attributes[.foregroundColor] = presentation.color
		attributes[.toolTip] = presentation.label
		/* The glyph is the whole of the state for a sighted reader, so the words
		 have to be somewhere an assistive reader can still reach them. */
		attributes[.accessibilityCustomText] = [presentation.label]

		let piece = NSMutableAttributedString(string: "  ")
		let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
			.applying(NSImage.SymbolConfiguration(paletteColors: [presentation.color]))
		if let symbol = NSImage(systemSymbolName: presentation.symbol, accessibilityDescription: presentation.label)?
			.withSymbolConfiguration(configuration)
		{
			let attachment = NSTextAttachment()
			attachment.image = symbol
			piece.append(NSAttributedString(attachment: attachment))
		} else {
			piece.append(NSAttributedString(string: presentation.label))
		}
		piece.addAttributes(attributes, range: NSRange(location: 0, length: piece.length))
		if line.deliveryState == .failed, let reason = line.deliveryFailureReason, reason.isEmpty == false {
			piece.append(NSAttributedString(string: " ", attributes: attributes))
			TranscriptIsolate.appendIsolated(
				NSAttributedString(string: ControlCharacterDisposition.singleLine(reason), attributes: attributes),
				to: piece,
				isolateAttributes: attributes
			)
		}
		result.append(piece)
	}

	/** Draws each reaction as a chip: one run, tinted, carrying the message and
	 the emoji it stands for so a click on it reacts with that emoji.

	 A chip is a run rather than an attachment cell on purpose — attachment
	 cells are a TextKit 1 feature, and a storage that holds one moves the whole
	 transcript back to TextKit 1, where its bottom alignment does not exist. */
	private func appendReactions(
		for line: TranscriptRow,
		to result: NSMutableAttributedString,
		paragraph: NSParagraphStyle
	) {
		guard line.reactions.isEmpty == false else { return }
		let controller = themeStore
		let palette = controller.theme.palette
		let font = NSFont.systemFont(ofSize: max(9, effectiveFont(controller).pointSize - 1))
		let identifier = line.messageIdentifier ?? ""
		for emoji in line.reactions.keys.sorted() {
			let count = line.reactions[emoji]?.count ?? 0
			guard count > 0 else { continue }
			var attributes = lineAttributes(for: line)
			attributes[.font] = font
			attributes[.paragraphStyle] = paragraph
			attributes[.foregroundColor] = themeColor(palette.primaryText)
			attributes[.backgroundColor] = themeColor(palette.secondaryText).withAlphaComponent(0.14)
			attributes[.accessibilityCustomText] = [
				String(localized: .Transcript.reactionAccessibility(emoji, arg2: count)),
			]
			if identifier.isEmpty == false {
				attributes[.transcriptReaction] = TranscriptReactionTarget(
					messageIdentifier: identifier, emoji: emoji
				)
				attributes[.cursor] = NSCursor.pointingHand
			}
			result.append(NSAttributedString(string: "  ", attributes: [.paragraphStyle: paragraph, .font: font]))
			/* Thin spaces stand in for the padding a run cannot have. They are
			 marked as padding, and so is nothing the reaction itself spells. */
			var padding = attributes
			padding[.transcriptPadding] = true
			result.append(NSAttributedString(string: "\u{2009}", attributes: padding))
			TranscriptIsolate.appendIsolated(
				NSAttributedString(string: ControlCharacterDisposition.singleLine(emoji), attributes: attributes),
				to: result,
				isolateAttributes: attributes
			)
			result.append(NSAttributedString(string: " \(count)", attributes: attributes))
			result.append(NSAttributedString(string: "\u{2009}", attributes: padding))
		}
	}
}
