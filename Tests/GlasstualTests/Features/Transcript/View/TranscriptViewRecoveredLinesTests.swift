// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/** Lines recovered from the server go between the lines they fall between,
 and the reader stays where they were: at the end, or on the line they had
 scrolled to. What the lines around them carry is left alone. */
@MainActor
@Suite("Transcript view recovered lines")
struct TranscriptViewRecoveredLinesTests {
	@Test("Recovered lines are drawn between the lines they fall between, and the text is in the same order")
	func recoveredLinesAreDrawnInOrder() {
		let view = makeTranscriptView()
		view.appendLines([line(1), line(2), line(7), line(8)])

		let placed = view.insertRecoveredLines([line(5), line(4), line(0), line(9)])

		#expect(placed.accepted == ["line 4", "line 5", "line 9"])
		#expect(placed.heldBack == ["line 0"])
		#expect(view.displayedLines.map(\.lineNumber) == ["line 1", "line 2", "line 4", "line 5", "line 7", "line 8", "line 9"])
		let text = view.textView.string as NSString
		let positions = [1, 2, 4, 5, 7, 8, 9].map { text.range(of: "line \($0)").location }
		#expect(positions == positions.sorted())
		#expect(positions.contains(NSNotFound) == false)
		#expect(text.range(of: "line 0").location == NSNotFound)
		#expect(view.jump(to: "line 8"))
	}

	@Test("A message the transcript already draws is not drawn again, by line or by message identifier")
	func drawnMessagesAreNotRepeated() {
		let view = makeTranscriptView()
		view.appendLines([line(1), line(3)])
		var sameMessage = line(2)
		sameMessage.messageIdentifier = "id-line 3"

		let placed = view.insertRecoveredLines([line(1), sameMessage])

		#expect(placed.accepted.isEmpty)
		#expect(view.displayedLines.map(\.lineNumber) == ["line 1", "line 3"])
	}

	@Test("A reader at the end stays at the end")
	func readerAtTheEndStaysThere() {
		let view = makeTranscriptView()
		view.appendLines((0 ..< 200).map { line($0 * 10) })
		view.layoutSubtreeIfNeeded()
		view.scrollToBottom()
		#expect(view.isNearBottom)

		view.insertRecoveredLines((0 ..< 60).map { line(505 + $0 * 10) })

		#expect(view.followsBottom)
		#expect(view.isNearBottom)
		#expect(view.displayedBounds.newest == "line 1990")
	}

	@Test("A reader who scrolled up keeps the line at the top of the viewport where it was",
	      arguments: [505, 1505])
	func scrolledUpReaderKeepsTheirLine(firstRecovered: Int) throws {
		let view = makeTranscriptView()
		view.appendLines((0 ..< 200).map { line($0 * 10) })
		view.layoutSubtreeIfNeeded()
		view.followsBottom = false
		_ = view.jump(to: "line 1000")
		view.layoutSubtreeIfNeeded()
		let before = try #require(view.viewportAnchor())

		view.insertRecoveredLines((0 ..< 30).map { line(firstRecovered + $0 * 10) })

		let after = try #require(view.viewportAnchor())
		#expect(view.followsBottom == false)
		#expect(after.endpoint.lineNumber == before.endpoint.lineNumber)
		#expect(abs(after.offset - before.offset) < 1)
		#expect(view.lastVisibleTop == view.scrollView.contentView.bounds.minY)
	}

	@Test("Reactions, the unread marker, a redaction, an inline image and the selection survive")
	func surroundingStateSurvives() throws {
		let copyOnSelect = SettingsKeys.Messages.copyOnSelect.value
		defer { SettingsKeys.Messages.copyOnSelect.value = copyOnSelect }
		SettingsKeys.Messages.copyOnSelect.value = false
		let view = makeTranscriptView()
		view.appendLines([line(1), line(2), line(7), line(8)])
		view.updateReactions(["+1": ["bob"]], messageIdentifier: "id-line 2")
		view.setUnreadMarker(.line("line 7"))
		view.redactMessage(withIdentifier: "id-line 8", placeholder: "deleted")
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
			hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
		))
		let data = try #require(bitmap.representation(using: .png, properties: [:]))
		try #expect(view.addInlineImage(TranscriptInlineImage(
			lineNumber: "line 7", linkIdentifier: "link", sourceURL: #require(URL(string: "https://example.com/image")),
			imageData: data
		)))
		let text = view.textView
		let start = (text.string as NSString).range(of: "line 2").location
		let end = NSMaxRange((text.string as NSString).range(of: "line 7"))
		text.setSelectedRange(NSRange(location: start, length: end - start))

		view.insertRecoveredLines([line(4), line(5)])

		let rows = Dictionary(uniqueKeysWithValues: view.displayedLines.map { ($0.lineNumber, $0) })
		#expect(rows["line 2"]?.reactions == ["+1": ["bob"]])
		#expect(rows["line 7"]?.markers.contains(where: \.isUnread) == true)
		#expect(view.displayedLines.filter { $0.markers.contains(where: \.isUnread) }.count == 1)
		#expect(rows["line 8"]?.lineType == .redacted)
		#expect(view.document.inlineMedia["line 7"]?.count == 1)
		var attachments = 0
		let storage = try #require(text.textStorage)
		storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
			attachments += value is NSTextAttachment ? 1 : 0
		}
		#expect(attachments == 1)
		let selection = (text.string as NSString).substring(with: text.selectedRange())
		#expect(selection.hasPrefix("line 2"))
		#expect(selection.hasSuffix("line 7"))
		#expect(selection.contains("line 4"))
	}

	private func makeTranscriptView() -> TranscriptView {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(session: session, in: window)
		let transcriptView = controller.ensureBackingView()
		transcriptView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = transcriptView
		transcriptView.setBufferLimit(1000)
		return transcriptView
	}

	/// A line whose number is also the second it was received at.
	private func line(_ second: Int) -> TranscriptRow {
		let text = "line \(second)"
		return TranscriptRow(
			lineNumber: text,
			receivedAt: Date(timeIntervalSince1970: 1_000_000 + Double(second)),
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
