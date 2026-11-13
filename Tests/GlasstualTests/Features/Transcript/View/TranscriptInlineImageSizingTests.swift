// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// An inline image is sized from the column the text view has when its line is
/// drawn, so it has to be drawn again when the column changes.
@MainActor
@Suite("Transcript inline image sizing")
struct TranscriptInlineImageSizingTests {
	@Test("A text view with no width yet gets the box's width, not a zero-size image")
	func unmeasuredWidthUsesTheBox() {
		#expect(TranscriptMetrics.inlineImageMaximumWidth(forTextViewWidth: 0) == TranscriptMetrics.inlineImageBox.width)
		#expect(TranscriptMetrics.inlineImageMaximumWidth(forTextViewWidth: -1) == TranscriptMetrics.inlineImageBox.width)
	}

	@Test("A wide column is capped at the box, a narrow one at what is left of it")
	func widthFollowsTheColumn() {
		let inset = TranscriptMetrics.inlineImageSideInset
		#expect(TranscriptMetrics.inlineImageMaximumWidth(forTextViewWidth: 2000) == 480)
		#expect(TranscriptMetrics.inlineImageMaximumWidth(forTextViewWidth: 300) == 300 - inset)
		#expect(TranscriptMetrics.inlineImageMaximumWidth(forTextViewWidth: 100) == 100 - inset)
		#expect(TranscriptMetrics.inlineImageMaximumWidth(forTextViewWidth: inset + 10) == 10)
	}

	@Test("Narrowing the transcript redraws its images smaller, and widening it restores them")
	func imagesFollowTheColumnWidth() throws {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(session: session, in: window)
		let view = controller.ensureBackingView()
		view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = view
		view.layoutSubtreeIfNeeded()
		view.appendLines([line("image")])
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 400, bitsPerSample: 8, samplesPerPixel: 4,
			hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
		))
		let data = try #require(bitmap.representation(using: .png, properties: [:]))
		try view.addInlineImage(TranscriptInlineImage(
			lineNumber: "image", linkIdentifier: "link", sourceURL: #require(URL(string: "https://example.com/image")),
			imageData: data
		))
		let storage = try #require(view.textView.textStorage)
		func drawnWidth() throws -> CGFloat {
			var width: CGFloat?
			storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
				if let attachment = value as? NSTextAttachment {
					width = attachment.image?.size.width
				}
			}
			return try #require(width)
		}
		let wide = try drawnWidth()
		#expect(wide <= TranscriptMetrics.inlineImageBox.width)

		view.frame = NSRect(x: 0, y: 0, width: 300, height: 600)
		view.layoutSubtreeIfNeeded()
		view.reflowInlineImages()
		let narrow = try drawnWidth()
		#expect(narrow < wide)
		#expect(narrow <= TranscriptMetrics.inlineImageMaximumWidth(forTextViewWidth: view.textView.bounds.width))

		view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		view.layoutSubtreeIfNeeded()
		view.reflowInlineImages()
		#expect(try drawnWidth() == wide)
	}

	private func line(_ text: String) -> TranscriptRow {
		TranscriptRow(
			lineNumber: text,
			receivedAt: Date(timeIntervalSince1970: 0),
			nickname: "alice",
			memberType: .normal,
			lineType: .privateMessage,
			command: "PRIVMSG",
			messageIdentifier: "id-\(text)",
			replyToMessageIdentifier: nil,
			deliveryState: .none,
			deliveryFailureReason: nil,
			reactions: [:],
			markers: [],
			body: TranscriptBody(plainText: text, runs: [TranscriptTextRun(text: text)])
		)
	}
}
