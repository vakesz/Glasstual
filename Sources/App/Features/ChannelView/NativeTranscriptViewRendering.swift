/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Foundation
import SwiftUI

/** How one semantic row becomes the characters the transcript draws.

 Everything here reads the theme and produces attributed text; nothing here
 touches the document, the selection or the scroll position, which is what lets
 a theme change re-render the rows the adapter already holds. */
extension NativeTranscriptView {
	func render(_ line: TranscriptLine) -> NSAttributedString {
		let controller = SharedApplication.sharedThemeController()
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
			result.append(NSAttributedString(
				string: header.nickname + (theme.layout == .bubbles ? "\n" : "  "),
				attributes: nicknameAttributes(for: line, paragraph: paragraph).merging([
					.transcriptSelectionSegment: "nickname",
				]) { _, new in new }
			))
		}

		let bodyStart = result.length
		for run in line.body.runs {
			result.append(NSAttributedString(
				string: run.text,
				attributes: runAttributes(run, line: line, paragraph: paragraph)
			))
		}
		result.addAttribute(.transcriptSelectionSegment, value: "body",
		                    range: NSRange(location: bodyStart, length: result.length - bodyStart))
		let detailsStart = result.length
		appendDeliveryAndReactions(for: line, to: result, paragraph: paragraph)
		for image in inlineImages[line.lineNumber] ?? [] {
			append(image, to: result, paragraph: paragraph)
		}
		result.append(NSAttributedString(string: "\n", attributes: metadata))
		result.addAttribute(.transcriptSelectionSegment, value: "details",
		                    range: NSRange(location: detailsStart, length: result.length - detailsStart))
		return result
	}

	func metadataAttributes(
		for line: TranscriptLine,
		paragraph: NSParagraphStyle
	) -> [NSAttributedString.Key: Any] {
		let controller = SharedApplication.sharedThemeController()
		let palette = controller.theme.palette
		var attributes = lineAttributes(for: line).merging([
			.font: NSFont.systemFont(ofSize: max(9, effectiveFont(controller).pointSize - 1)),
			.foregroundColor: controller.resolved(palette.secondaryText),
			.paragraphStyle: paragraph,
		]) { _, new in new }
		if let background = bubbleBackground(for: line) {
			attributes[.backgroundColor] = background
		}
		return attributes
	}

	func nicknameAttributes(
		for line: TranscriptLine,
		paragraph: NSParagraphStyle
	) -> [NSAttributedString.Key: Any] {
		let controller = SharedApplication.sharedThemeController()
		let palette = controller.theme.palette
		let fallback = line.memberType == .localUser ? palette.localNickname : palette.remoteNickname
		let color = Preferences.Messages.disableNicknameColorHashing.value
			? controller.resolved(fallback)
			: nicknameColor(for: line.nickname ?? "")
		var attributes = lineAttributes(for: line).merging([
			.font: NSFontManager.shared.convert(effectiveFont(controller), toHaveTrait: .boldFontMask),
			.foregroundColor: color,
			.paragraphStyle: paragraph,
			.transcriptNickname: line.nickname ?? "",
			.transcriptAction: "nickname:\(line.nickname ?? "")",
		]) { _, new in new }
		if let background = bubbleBackground(for: line) {
			attributes[.backgroundColor] = background
		}
		return attributes
	}

	func runAttributes(
		_ run: TranscriptTextRun,
		line: TranscriptLine,
		paragraph: NSParagraphStyle
	) -> [NSAttributedString.Key: Any] {
		let controller = SharedApplication.sharedThemeController()
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
		attributes[.foregroundColor] = resolved(run.foreground) ?? controller.resolved(
			line.lineType == .privateMessage || line.lineType == .action ? palette.primaryText : palette.eventText
		)
		if let background = resolved(run.background) ?? bubbleBackground(for: line) {
			attributes[.backgroundColor] = background
		}
		if run.traits.contains(.highlighted) {
			attributes[.backgroundColor] = controller.resolved(palette.highlightBackground)
			attributes[.foregroundColor] = controller.resolved(palette.highlightText)
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
			attributes[.foregroundColor] = controller.resolved(palette.link)
		case let .channel(name):
			attributes[.transcriptAction] = "channel:\(name)"
			attributes[.foregroundColor] = controller.resolved(palette.link)
		case let .nickname(name):
			attributes[.transcriptAction] = "nickname:\(name)"
			attributes[.transcriptNickname] = name
			attributes[.foregroundColor] = nicknameColor(for: name)
		case nil:
			break
		}
		return attributes
	}

	/// A nickname's colour, remembered for the batch being rendered. Resolving
	/// one reads the pinned-colour dictionary out of the defaults store, and a
	/// batch of lines asks for the same few names repeatedly.
	func nicknameColor(for nickname: String) -> NSColor {
		if let cached = nicknameColors[nickname] {
			return cached
		}
		let color = UserNicknameColorStyleGenerator.color(for: nickname)
		nicknameColors[nickname] = color
		return color
	}

	func bubbleBackground(for line: TranscriptLine) -> NSColor? {
		let controller = SharedApplication.sharedThemeController()
		guard controller.theme.layout == .bubbles else { return nil }
		let palette = controller.theme.palette
		let pair = line.memberType == .localUser ? palette.bubbleOutgoing : palette.bubbleIncoming
		return controller.resolved(pair)
	}

	func lineAttributes(for line: TranscriptLine) -> [NSAttributedString.Key: Any] {
		[
			.transcriptLineNumber: line.lineNumber,
			.transcriptLineType: line.lineTypeString,
			.transcriptMessageIdentifier: line.messageIdentifier ?? "",
			.transcriptExcerpt: line.body.plainText,
		]
	}

	func appendDeliveryAndReactions(
		for line: TranscriptLine,
		to result: NSMutableAttributedString,
		paragraph: NSParagraphStyle
	) {
		let controller = SharedApplication.sharedThemeController()
		let palette = controller.theme.palette
		var details: [String] = []
		switch line.deliveryState {
		case .pending: details.append(TranscriptThemeStrings.pending)
		case .delivered: details.append(TranscriptThemeStrings.delivered)
		case .failed:
			details.append(
				TranscriptThemeStrings.failed + (line.deliveryFailureReason.map { ": \($0)" } ?? "")
			)
		case .none: break
		}
		for emoji in line.reactions.keys.sorted() {
			details.append("\(emoji) \(line.reactions[emoji]?.count ?? 0)")
		}
		guard details.isEmpty == false else { return }
		var attributes = lineAttributes(for: line)
		attributes[.font] = NSFont.systemFont(ofSize: max(9, effectiveFont(controller).pointSize - 1))
		attributes[.foregroundColor] = line.deliveryState == .failed
			? controller.resolved(palette.failure)
			: controller.resolved(palette.secondaryText)
		attributes[.paragraphStyle] = paragraph
		result.append(NSAttributedString(string: "  \(details.joined(separator: "  "))", attributes: attributes))
	}

	func append(
		_ inlineImage: CachedTranscriptImage,
		to result: NSMutableAttributedString,
		paragraph: NSParagraphStyle
	) {
		let image = inlineImage.image
		let maxSize = NSSize(
			width: min(480, max(120, textView.bounds.width - 40)),
			height: 320
		)
		let size = inlineImage.originalSize
		let scale = min(1, maxSize.width / size.width, maxSize.height / size.height)
		image.size = NSSize(width: size.width * scale, height: size.height * scale)
		let attachmentString = NSMutableAttributedString(string: "\n")
		attachmentString.append(NSAttributedString(attachment: inlineImage.attachment))
		attachmentString.addAttribute(.paragraphStyle, value: paragraph, range: attachmentString.fullRange)
		result.append(attachmentString)
	}

	func attributedTopic(_ topic: String) -> NSAttributedString {
		let controller = SharedApplication.sharedThemeController()
		let palette = controller.theme.palette
		let result = NSMutableAttributedString(string: topic, attributes: [
			.font: NSFont.preferredFont(forTextStyle: .body),
			.foregroundColor: controller.resolved(palette.primaryText),
		])
		for link in LinkParser.locateLinks(in: topic)
			where LogRenderer.isSafeLink(link.stringValue)
		{
			guard let url = URL(string: link.stringValue), NSMaxRange(link.range) <= result.length else {
				continue
			}
			result.addAttributes([
				.link: url,
				.foregroundColor: controller.resolved(palette.link),
				.underlineStyle: NSUnderlineStyle.single.rawValue,
			], range: link.range)
		}
		return result
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

extension NativeTranscriptView {
	func render(_ marker: TranscriptMarker, lineNumber: String) -> NSAttributedString {
		let controller = SharedApplication.sharedThemeController()
		let palette = controller.theme.palette
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = .center
		let text: String
		let color: NSColor
		let font: NSFont
		switch marker {
		case let .date(value):
			text = value
			color = controller.resolved(palette.secondaryText)
			font = NSFont.systemFont(
				ofSize: max(9, effectiveFont(controller).pointSize - 1),
				weight: .medium
			)
			paragraph.paragraphSpacing = 6
		case let .currentSession(value):
			text = value
			color = controller.resolved(palette.secondaryText)
			font = NSFont.systemFont(
				ofSize: max(9, effectiveFont(controller).pointSize - 1),
				weight: .medium
			)
			paragraph.paragraphSpacingBefore = 5
			paragraph.paragraphSpacing = 6
			paragraph.textBlocks = [separatorBlock(
				ruleColor: color.withAlphaComponent(0.22),
				topPadding: 5
			)]
		case .unread:
			// The previous Simplified theme used only a quiet accent hairline.
			// Keeping the caption out of the transcript prevents an unread
			// boundary from competing with actual messages.
			text = "\u{200B}"
			color = .clear
			font = NSFont.systemFont(ofSize: 1)
			paragraph.paragraphSpacingBefore = 5
			paragraph.paragraphSpacing = 5
			paragraph.textBlocks = [separatorBlock(
				ruleColor: controller.resolved(palette.unreadMarker).withAlphaComponent(0.6)
			)]
		}
		return NSAttributedString(string: "\(text)\n", attributes: [
			.font: font,
			.foregroundColor: color,
			.paragraphStyle: paragraph,
			.transcriptLineNumber: lineNumber,
		])
	}

	func separatorBlock(ruleColor: NSColor, topPadding: CGFloat = 0) -> NSTextBlock {
		let block = NSTextBlock()
		block.setContentWidth(100, type: .percentageValueType)
		block.setWidth(1, type: .absoluteValueType, for: .border, edge: .minY)
		block.setBorderColor(ruleColor, for: .minY)
		if topPadding > 0 {
			block.setWidth(topPadding, type: .absoluteValueType, for: .padding, edge: .minY)
		}
		return block
	}
}

extension NativeTranscriptView {
	/// The theme's font at this view's text scale. Every attribute run starts
	/// from it, so the scale is applied once, here.
	func effectiveFont(_ controller: ThemeController) -> NSFont {
		let font = controller.font
		return NSFont(name: font.fontName, size: font.pointSize * textScale)
			?? NSFont.systemFont(ofSize: font.pointSize * textScale)
	}
}

private extension NSAttributedString {
	var fullRange: NSRange {
		NSRange(location: 0, length: length)
	}
}
