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
			: themeStore.resolved(role)
	}

	func render(_ line: TranscriptRow) -> NSAttributedString {
		let controller = themeStore
		let header = line.header(using: controller.theme)
		let result = NSMutableAttributedString()
		for marker in line.markers {
			let start = result.length
			result.append(render(marker, lineNumber: line.lineNumber))
			result.addAttribute(.transcriptSelectionSegment, value: marker.selectionSegment,
			                    range: NSRange(location: start, length: result.length - start))
		}
		let theme = controller.theme
		let paragraph = TranscriptMetrics.transcriptParagraph(
			lineSpacing: theme.lineSpacing,
			messageSpacing: theme.messageSpacing,
			horizontalPadding: theme.horizontalPadding
		)

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
			TranscriptIsolate.appendIsolated(
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
		if line.body.isHighlight, body.length > 0 {
			/* A highlight is drawn in colour, so the word is what a screen reader
			 hears first; whatever the first run already says follows it. */
			let existing = body.attribute(.accessibilityCustomText, at: 0, effectiveRange: nil) as? [String] ?? []
			body.addAttribute(
				.accessibilityCustomText,
				value: TranscriptHighlightCue.spokenText(
					prefix: String(localized: .Transcript.highlightAccessibility),
					existing: existing
				),
				range: (body.string as NSString).rangeOfComposedCharacterSequence(at: 0)
			)
		}
		if line.lineType == .redacted, body.length > 0 {
			/* The placeholder is italic text, which says nothing to a screen
			 reader about why the message is gone; the word is spoken first. */
			body.addAttribute(
				.accessibilityCustomText,
				value: [String(localized: .Transcript.messageDeletedAccessibility)],
				range: (body.string as NSString).rangeOfComposedCharacterSequence(at: 0)
			)
		}
		TranscriptIsolate.appendIsolated(body, to: result, isolateAttributes: metadata)
		result.addAttribute(.transcriptSelectionSegment, value: "body",
		                    range: NSRange(location: bodyStart, length: result.length - bodyStart))
		let detailsStart = result.length
		appendDeliveryAndReactions(for: line, to: result, paragraph: paragraph)
		for media in document.inlineMedia[line.lineNumber] ?? [] {
			switch media {
			case let .image(image): append(image, to: result, paragraph: paragraph)
			case let .placeholder(placeholder): append(placeholder, to: result, paragraph: paragraph)
			}
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
		let controller = themeStore
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
		let controller = themeStore
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
		let controller = themeStore
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
		let bubble = bubbleBackground(for: line)
		let colors = TranscriptReverseColors.resolve(
			foreground: resolved(run.foreground) ?? themeColor(
				line.lineType == .privateMessage || line.lineType == .action ? palette.primaryText : palette.eventText
			),
			background: resolved(run.background) ?? bubble,
			isReversed: run.traits.contains(.reverse),
			fallbackBackground: bubble ?? themeColor(palette.background)
		)
		attributes[.foregroundColor] = colors.foreground
		if let background = colors.background {
			attributes[.backgroundColor] = background
		}
		if run.traits.contains(.highlighted) {
			attributes[.backgroundColor] = themeColor(palette.highlightBackground)
			attributes[.foregroundColor] = themeColor(palette.highlightText)
			/* The colours are the whole of the cue otherwise, so a reader who has
			 asked to be told things without colour gets a line under the run. */
			if TranscriptHighlightCue.underlinesRun(
				isHighlighted: true,
				differentiatesWithoutColor: NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor,
				action: run.action
			) {
				attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
				attributes[.underlineColor] = themeColor(palette.highlightText)
			}
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
		let controller = themeStore
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

	func append(
		_ inlineImage: CachedTranscriptImage,
		to result: NSMutableAttributedString,
		paragraph: NSParagraphStyle
	) {
		let image = inlineImage.image
		let maximumWidth = TranscriptMetrics.inlineImageMaximumWidth(forTextViewWidth: textView.bounds.width)
		renderedInlineImageWidth = maximumWidth
		let maxSize = NSSize(width: maximumWidth, height: TranscriptMetrics.inlineImageBox.height)
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
	/// The theme's font at this view's text scale. Every attribute run starts
	/// from it, so the scale is applied once, here.
	func effectiveFont(_ controller: ThemeStore) -> NSFont {
		controller.scaledFont(scale: textScale)
	}
}
