// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
import SwiftUI

/** How one semantic row becomes the characters the transcript draws.

 Everything here reads the theme and produces attributed text; nothing here
 touches the document, the selection or the scroll position, which is what lets
 a theme change re-render the rows the adapter already holds. */
extension TranscriptView {
	/** One theme role, resolved for whatever this render is for.

	 Every colour below goes through here so that laying the transcript out for
	 paper has one thing to change: the printed copy is drawn against the
	 theme's light half, because paper is white. */
	func themeColor(_ role: AdaptiveTranscriptColor) -> NSColor {
		rendersForPrint
			? role.resolved(isDark: false)
			: AppServices.theme.resolved(role)
	}

	func render(_ line: TranscriptRow) -> NSAttributedString {
		let controller = AppServices.theme
		let header = line.header(using: controller.theme)
		let result = NSMutableAttributedString()
		for marker in line.markers {
			let start = result.length
			result.append(render(marker, lineNumber: line.lineNumber))
			result.addAttribute(.transcriptSelectionSegment, value: marker.selectionSegment,
			                    range: NSRange(location: start, length: result.length - start))
		}
		let theme = controller.theme
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineSpacing = theme.lineSpacing
		paragraph.paragraphSpacing = theme.messageSpacing
		paragraph.firstLineHeadIndent = theme.horizontalPadding
		paragraph.headIndent = theme.horizontalPadding
		paragraph.tailIndent = -theme.horizontalPadding

		let metadata = metadataAttributes(for: line, paragraph: paragraph)
		result.append(NSAttributedString(string: "\(header.timestamp)  ", attributes: metadata.merging([
			.transcriptSelectionSegment: "timestamp",
		]) { _, new in new }))
		if !header.nickname.isEmpty || theme.layout == .bubbles {
			let attributes = nicknameAttributes(for: line, paragraph: paragraph).merging([
				.transcriptSelectionSegment: "nickname",
			]) { _, new in new }
			/* The gap after the name, and the isolate the name is drawn in, carry
			 none of the name's click action: they are not the name, and the
			 popover is anchored to the name alone. */
			var separatorAttributes = attributes
			separatorAttributes.removeValue(forKey: .transcriptAction)
			TranscriptTextSanitizer.appendIsolated(
				NSAttributedString(string: header.nickname, attributes: attributes),
				to: result,
				isolateAttributes: separatorAttributes
			)
			result.append(NSAttributedString(
				string: theme.layout == .bubbles ? "\n" : "  ",
				attributes: separatorAttributes
			))
		}

		let bodyStart = result.length
		let body = NSMutableAttributedString()
		for run in line.body.runs {
			body.append(NSAttributedString(
				string: run.text,
				attributes: runAttributes(run, line: line, paragraph: paragraph)
			))
		}
		TranscriptTextSanitizer.appendIsolated(body, to: result, isolateAttributes: metadata)
		result.addAttribute(.transcriptSelectionSegment, value: "body",
		                    range: NSRange(location: bodyStart, length: result.length - bodyStart))
		let detailsStart = result.length
		appendDeliveryAndReactions(for: line, to: result, paragraph: paragraph)
		for image in document.inlineImages[line.lineNumber] ?? [] {
			append(image, to: result, paragraph: paragraph)
		}
		result.append(NSAttributedString(string: "\n", attributes: metadata))
		result.addAttribute(.transcriptSelectionSegment, value: "details",
		                    range: NSRange(location: detailsStart, length: result.length - detailsStart))
		return result
	}

	/** Appends wire text inside an isolate of its own.

	 The bidirectional algorithm reorders a paragraph as a whole, so text that
	 is not isolated can carry the name before it or the reactions after it
	 along with its own direction. The isolate's two characters are layout, and
	 carry the padding mark that keeps them off the pasteboard. */
	func metadataAttributes(
		for line: TranscriptRow,
		paragraph: NSParagraphStyle
	) -> [NSAttributedString.Key: Any] {
		let controller = AppServices.theme
		let palette = controller.theme.palette
		/* Digits of one width keep the column straight, and the theme's
		 timestamp role keeps the clock from competing with the name beside it. */
		var attributes = lineAttributes(for: line).merging([
			.font: NSFont.monospacedDigitSystemFont(
				ofSize: max(9, effectiveFont(controller).pointSize - 1),
				weight: .regular
			),
			.foregroundColor: themeColor(palette.timestampText),
			.paragraphStyle: paragraph,
		]) { _, new in new }
		if let background = bubbleBackground(for: line) {
			attributes[.backgroundColor] = background
		}
		return attributes
	}

	func nicknameAttributes(
		for line: TranscriptRow,
		paragraph: NSParagraphStyle
	) -> [NSAttributedString.Key: Any] {
		let controller = AppServices.theme
		let palette = controller.theme.palette
		let fallback = line.memberType == .localUser ? palette.localNickname : palette.remoteNickname
		let color = SettingsKeys.Messages.disableNicknameColorHashing.value
			? themeColor(fallback)
			: nicknameColor(for: line.nickname ?? "")
		var attributes = lineAttributes(for: line).merging([
			.font: NSFontManager.shared.convert(effectiveFont(controller), toHaveTrait: .boldFontMask),
			.foregroundColor: color,
			.paragraphStyle: paragraph,
			.transcriptNickname: line.nickname ?? "",
			.transcriptAction: TranscriptAction.nickname(line.nickname ?? ""),
		]) { _, new in new }
		if let background = bubbleBackground(for: line) {
			attributes[.backgroundColor] = background
		}
		return attributes
	}

	func runAttributes(
		_ run: TranscriptTextRun,
		line: TranscriptRow,
		paragraph: NSParagraphStyle
	) -> [NSAttributedString.Key: Any] {
		let controller = AppServices.theme
		let palette = controller.theme.palette
		var attributes = lineAttributes(for: line)
		var font = effectiveFont(controller)
		if run.traits
			.contains(.monospace)
		{
			font = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
		}
		if run.traits.contains(.bold) {
			font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
		}
		if run.traits.contains(.italic) {
			font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
		}
		attributes[.font] = font
		attributes[.paragraphStyle] = paragraph
		attributes[.foregroundColor] = resolved(run.foreground) ?? themeColor(
			line.lineType == .privateMessage || line.lineType == .action ? palette.primaryText : palette.eventText
		)
		if let background = resolved(run.background) ?? bubbleBackground(for: line) {
			attributes[.backgroundColor] = background
		}
		if run.traits.contains(.highlighted) {
			attributes[.backgroundColor] = themeColor(palette.highlightBackground)
			attributes[.foregroundColor] = themeColor(palette.highlightText)
		}
		if run.traits.contains(.strikethrough) {
			attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
		}
		if run.traits.contains(.underline) {
			attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
		}
		switch run.action {
		case let .link(url):
			attributes[.link] = url
			attributes[.foregroundColor] = themeColor(palette.link)
		case let .channel(name):
			attributes[.transcriptAction] = TranscriptAction.channel(name)
			attributes[.foregroundColor] = themeColor(palette.link)
		case let .nickname(name):
			attributes[.transcriptAction] = TranscriptAction.nickname(name)
			attributes[.transcriptNickname] = name
			attributes[.foregroundColor] = nicknameColor(for: name)
		case nil:
			break
		}
		return attributes
	}

	/// A nickname's colour, remembered for the batch being rendered. Resolving
	/// one reads the pinned-colour dictionary out of the defaults store, and a
	/// batch of lines asks for the same few names repeatedly -- so the table is
	/// read on the first name the cache misses and reused for every one after.
	func nicknameColor(for nickname: String) -> NSColor {
		if let cached = nicknameColors[nickname] {
			return cached
		}
		let overrides = nicknameColorOverrides ?? NicknameColors.overridesSnapshot()
		nicknameColorOverrides = overrides
		/* A printed copy asks for the light appearance's names for the reason
		 every other colour does: the pale ones a dark theme uses disappear. */
		let color = rendersForPrint
			? NicknameColors.color(for: nickname, isDark: false, overrides: overrides)
			: NicknameColors.color(for: nickname, overrides: overrides)
		nicknameColors[nickname] = color
		return color
	}

	func bubbleBackground(for line: TranscriptRow) -> NSColor? {
		let controller = AppServices.theme
		guard controller.theme.layout == .bubbles else { return nil }
		let palette = controller.theme.palette
		let pair = line.memberType == .localUser ? palette.bubbleOutgoing : palette.bubbleIncoming
		return themeColor(pair)
	}

	func lineAttributes(for line: TranscriptRow) -> [NSAttributedString.Key: Any] {
		var attributes: [NSAttributedString.Key: Any] = [
			.transcriptLineNumber: line.lineNumber,
			.transcriptLineType: line.lineTypeString,
			.transcriptMessageIdentifier: line.messageIdentifier ?? "",
			.transcriptExcerpt: line.body.plainText,
		]
		/* Carried by every run of the line, so a right-click anywhere in a
		 message — its timestamp, its body, a reaction — can name its author. */
		if let nickname = line.nickname, nickname.isEmpty == false {
			attributes[.transcriptLineNickname] = nickname
		}
		return attributes
	}

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
		let controller = AppServices.theme
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
		let controller = AppServices.theme
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
			TranscriptTextSanitizer.appendIsolated(
				NSAttributedString(string: TranscriptTextSanitizer.singleLine(reason), attributes: attributes),
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
		let controller = AppServices.theme
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
			TranscriptTextSanitizer.appendIsolated(
				NSAttributedString(string: TranscriptTextSanitizer.singleLine(emoji), attributes: attributes),
				to: result,
				isolateAttributes: attributes
			)
			result.append(NSAttributedString(string: " \(count)", attributes: attributes))
			result.append(NSAttributedString(string: "\u{2009}", attributes: padding))
		}
	}

	func append(
		_ inlineImage: CachedTranscriptImage,
		to result: NSMutableAttributedString,
		paragraph: NSParagraphStyle
	) {
		let image = inlineImage.image
		let maxSize = NSSize(
			width: min(
				TranscriptMetrics.inlineImageBox.width,
				max(120, textView.bounds.width - TranscriptMetrics.inlineImageSideInset)
			),
			height: TranscriptMetrics.inlineImageBox.height
		)
		let size = inlineImage.originalSize
		let scale = min(1, maxSize.width / size.width, maxSize.height / size.height)
		image.size = NSSize(width: size.width * scale, height: size.height * scale)
		/* An image with no description is a blank to anyone who cannot see it;
		 the address it came from is the one thing always known about it. */
		let description = String(localized: .Transcript.imageAccessibility(inlineImage.sourceURL.absoluteString))
		image.accessibilityDescription = description
		let attachmentString = NSMutableAttributedString(string: "\n")
		attachmentString.append(NSAttributedString(attachment: inlineImage.attachment))
		attachmentString.addAttributes([
			.paragraphStyle: paragraph,
			.accessibilityCustomText: [description],
			.toolTip: inlineImage.sourceURL.absoluteString,
			.transcriptInlineImage: inlineImage.sourceURL.absoluteString,
		], range: NSRange(location: 0, length: attachmentString.length))
		result.append(attachmentString)
	}

	func resolved(_ color: TranscriptRunColor?) -> NSColor? {
		switch color {
		case let .palette(index):
			guard NSColor.formatterColors.indices.contains(index) else { return nil }
			return NSColor.formatterColors[index]
		case let .rgb(components):
			return components.color
		case nil:
			return nil
		}
	}
}

extension TranscriptView {
	func render(_ marker: TranscriptMarker, lineNumber: String) -> NSAttributedString {
		let controller = AppServices.theme
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

extension TranscriptView {
	/// The theme's font at this view's text scale. Every attribute run starts
	/// from it, so the scale is applied once, here.
	func effectiveFont(_ controller: ThemeStore) -> NSFont {
		let font = controller.font
		return NSFont(name: font.fontName, size: font.pointSize * textScale)
			?? NSFont.systemFont(ofSize: font.pointSize * textScale)
	}
}
