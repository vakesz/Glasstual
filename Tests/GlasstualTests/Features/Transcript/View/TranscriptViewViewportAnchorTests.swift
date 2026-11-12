// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// A reader who is not following the end keeps the text they are looking at
/// where it is, whatever goes in above it.
@MainActor
@Suite("Transcript view viewport anchor")
struct TranscriptViewViewportAnchorTests {
	@Test("A viewport that begins above the text is anchored to the first line, not the last")
	func viewportAboveTheTextNamesTheFirstLine() throws {
		let view = makeTranscriptView()
		view.appendLines((0 ..< 200).map { line($0) })
		view.layoutSubtreeIfNeeded()
		view.followsBottom = false
		_ = view.jump(to: "line 0")
		view.scrollView.contentView.scroll(to: .zero)
		view.scrollView.reflectScrolledClipView(view.scrollView.contentView)
		view.layoutSubtreeIfNeeded()
		view.textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
		#expect(view.textView.textContainerOrigin.y > 0)

		#expect(try #require(view.viewportAnchor()).endpoint.lineNumber == "line 0")
	}

	@Test("The reader's line stays put however many older lines go in above it", arguments: [1, 5, 40, 150])
	func olderLinesDoNotMoveTheReader(count: Int) throws {
		let view = makeTranscriptView()
		view.appendLines((0 ..< 200).map { line($0) })
		view.layoutSubtreeIfNeeded()
		view.followsBottom = false
		_ = view.jump(to: "line 6")
		view.layoutSubtreeIfNeeded()
		let before = try #require(viewportOffset(of: "line 6 body", in: view))

		view.prependLines((0 ..< count).map { line($0 - count) })

		let after = try #require(viewportOffset(of: "line 6 body", in: view))
		#expect(abs(after - before) < 1)
	}

	/// How far below the top of the viewport `text` is drawn.
	private func viewportOffset(of text: String, in view: TranscriptView) -> CGFloat? {
		let index = (view.textView.string as NSString).range(of: text).location
		guard index != NSNotFound, let layoutManager = view.textView.textLayoutManager,
		      let contentManager = layoutManager.textContentManager,
		      let location = contentManager.location(contentManager.documentRange.location, offsetBy: index)
		else { return nil }
		layoutManager.textViewportLayoutController.layoutViewport()
		let range = NSTextRange(location: location)
		layoutManager.ensureLayout(for: range)
		var top: CGFloat?
		layoutManager.enumerateTextSegments(in: range, type: .standard, options: [.rangeNotRequired]) { _, frame, _, _ in
			top = frame.minY
			return false
		}
		return top.map { $0 + view.textView.textContainerOrigin.y - view.scrollView.contentView.bounds.minY }
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
			body: TranscriptBody(plainText: "\(text) body", runs: [TranscriptTextRun(text: "\(text) body")])
		)
	}
}
