/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

/** What the transcript keeps, and where.

 The view splices lines into the text storage instead of rewriting it, so the
 record of where each line's characters are has to survive an append, a trim and
 a prepend. These tests read that record through what it produces: the document
 an edited view holds, checked against the one a full rebuild of the same lines
 produces, and the ranges `jump(to:)` resolves against it. */
@MainActor
@Suite("Native transcript buffer")
struct LogViewTranscriptBufferTests {
	private func makeLogView(bufferLimit: Int = 1000) -> LogView {
		let client = IRCClient(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = LogController(client: client, in: window)
		let logView = controller.ensureBackingView()
		logView.view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = logView.view
		logView.setBufferLimit(bufferLimit)
		return logView
	}

	private func transcriptLine(_ text: String) -> TranscriptLine {
		TranscriptLine(
			lineNumber: text,
			receivedAt: Date(),
			timestamp: "12:00",
			nickname: "alice",
			formattedNickname: "alice",
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

	private func message(_ index: Int) -> TranscriptLine {
		transcriptLine("message \(index)")
	}

	private func textView(of logView: LogView) throws -> NSTextView {
		func descendants(in root: NSView) -> [NSTextView] {
			root.subviews.flatMap { view in
				(view as? NSTextView).map { [$0] } ?? descendants(in: view)
			}
		}
		return try #require(descendants(in: logView.view).first)
	}

	/** The view is hidden while a channel is not selected, and lines keep
	 arriving. Opening the channel has to show those lines: a reader who was at
	 the end when they left the channel comes back to the end. */
	@Test("A transcript that was following the end scrolls to it when shown again")
	func hiddenTranscriptFollowingTheEndScrollsToItWhenShown() throws {
		let client = IRCClient(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 200),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = LogController(client: client, in: window)
		let logView = controller.ensureBackingView()
		logView.view.frame = NSRect(x: 0, y: 0, width: 800, height: 200)

		/* Detached, as a channel that is not selected is: nothing on screen. */
		logView.appendLines((1 ... 200).map(message))

		window.contentView = logView.view
		logView.view.layoutSubtreeIfNeeded()

		let textView = try textView(of: logView)
		let scrollView = try #require(textView.enclosingScrollView)
		let clip = scrollView.contentView
		/* The document settles its height a turn or two after landing in the
		 window, and the view follows it through notifications delivered on a
		 later main-actor turn, so the run loop is spun until it has. */
		var visibleBottom = clip.bounds.maxY - scrollView.contentInsets.bottom
		for _ in 0 ..< 200 where abs(visibleBottom - textView.frame.maxY) >= 2 {
			RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
			visibleBottom = clip.bounds.maxY - scrollView.contentInsets.bottom
		}

		/* Taller than the viewport, or the scroll would prove nothing. */
		#expect(textView.frame.maxY > clip.bounds.height)
		#expect(abs(visibleBottom - textView.frame.maxY) < 2)
	}

	private func document(of logView: LogView) throws -> String {
		try textView(of: logView).string
	}

	/// The document a view holding exactly `lines` would draw, rendered in one
	/// pass rather than spliced together.
	private func rebuiltDocument(of lines: [TranscriptLine]) throws -> String {
		let reference = makeLogView()
		reference.replaceLines(lines)
		return try document(of: reference)
	}

	@Test("Appending in batches leaves the document a full rebuild would leave")
	func appendingMatchesARebuild() throws {
		let lines = (0 ..< 12).map(message)
		let logView = makeLogView()

		logView.appendLines(Array(lines[0 ..< 4]))
		logView.appendLines(Array(lines[4 ..< 5]))
		logView.appendLines(Array(lines[5 ..< 12]))

		#expect(try document(of: logView) == rebuiltDocument(of: lines))
	}

	@Test("Trimming drops the oldest lines and keeps the newest addressable")
	func trimmingDropsOnlyTheOldest() throws {
		let logView = makeLogView(bufferLimit: 5)

		logView.appendLines((0 ..< 8).map(message))

		#expect(try document(of: logView) == rebuiltDocument(of: (3 ..< 8).map(message)))
		#expect(logView.jump(to: "message 7"))
		#expect(logView.jump(to: "message 3"))
		#expect(logView.jump(to: "message 2") == false)
	}

	@Test("Loading older history never drops the newest lines")
	func prependingKeepsTheNewestLines() throws {
		let logView = makeLogView(bufferLimit: 5)

		logView.appendLines((5 ..< 10).map(message))
		logView.prependLines((0 ..< 5).map(message))

		#expect(try document(of: logView) == rebuiltDocument(of: (0 ..< 10).map(message)))
		#expect(logView.jump(to: "message 9"))
		#expect(logView.jump(to: "message 0"))
	}

	@Test("A line's characters follow it through an append, a trim and a prepend")
	func theDocumentSurvivesEveryKindOfEdit() throws {
		let logView = makeLogView(bufferLimit: 6)

		logView.appendLines((0 ..< 8).map(message))
		logView.prependLines((0 ..< 3).map { transcriptLine("older \($0)") })
		logView.appendLines([transcriptLine("newest")])

		/* Six live lines, widened by the three older ones, then slid by one when
		 the newest arrived: the oldest of the prepended block is what goes. */
		let expected = [transcriptLine("older 1"), transcriptLine("older 2")]
			+ (2 ..< 8).map(message)
			+ [transcriptLine("newest")]
		#expect(try document(of: logView) == rebuiltDocument(of: expected))
		#expect(logView.jump(to: "newest"))
		#expect(logView.jump(to: "older 1"))
		#expect(logView.jump(to: "older 0") == false)
	}

	/// A range that no longer matched its line would scroll to the wrong place;
	/// the order the targets appear in is what says the ranges still line up.
	@Test("Jump targets stay in document order after the buffer has been edited")
	func jumpTargetsStayInDocumentOrder() throws {
		let logView = makeLogView(bufferLimit: 120)
		logView.appendLines((0 ..< 100).map(message))
		logView.prependLines((0 ..< 10).map { transcriptLine("older \($0)") })
		logView.view.layoutSubtreeIfNeeded()

		func scrollOffset(after lineNumber: String) throws -> CGFloat {
			#expect(logView.jump(to: lineNumber))
			let scrollView = try #require(textView(of: logView).enclosingScrollView)
			return scrollView.contentView.bounds.origin.y
		}

		let top = try scrollOffset(after: "older 0")
		let bottom = try scrollOffset(after: "message 99")
		let middle = try scrollOffset(after: "message 50")

		#expect(top < middle)
		#expect(middle < bottom)
	}

	@Test("A delivery receipt redraws its own line and leaves the rest alone")
	func aDeliveryReceiptTouchesOneLineOnly() throws {
		let logView = makeLogView()
		logView.appendLines((0 ..< 4).map(message))

		logView.updateDelivery(TranscriptDeliveryUpdate(
			lineNumber: "message 1",
			state: .failed,
			messageIdentifier: nil,
			reason: "no such nick"
		))

		var expected = (0 ..< 4).map(message)
		expected[1].deliveryState = .failed
		expected[1].deliveryFailureReason = "no such nick"
		#expect(try document(of: logView) == rebuiltDocument(of: expected))
	}

	@Test("A reaction is drawn on the line it names and nowhere else")
	func aReactionIsDrawnOnItsOwnLine() throws {
		let logView = makeLogView()
		logView.appendLines((0 ..< 3).map(message))

		logView.updateReactions(["👍": ["bob", "carol"]], messageIdentifier: "id-message 2")

		var expected = (0 ..< 3).map(message)
		expected[2].reactions = ["👍": ["bob", "carol"]]
		#expect(try document(of: logView) == rebuiltDocument(of: expected))
		#expect(try document(of: logView).contains("👍 2"))
	}

	/// An image whose line has already been trimmed has nothing to be drawn on,
	/// and keeping its bytes would hold a whole download alive for nothing.
	@Test("An image that arrives after its line was trimmed is dropped")
	func aLateInlineImageIsDropped() throws {
		let logView = makeLogView(bufferLimit: 2)
		logView.appendLines((0 ..< 4).map(message))
		let before = try document(of: logView)

		let url = try #require(URL(string: "https://example.com/cat.png"))
		logView.addInlineImage(TranscriptInlineImage(
			lineNumber: "message 0",
			linkIdentifier: "link-1",
			sourceURL: url,
			imageData: Data([0x00])
		))

		#expect(try document(of: logView) == before)
		#expect(try document(of: logView) == rebuiltDocument(of: (2 ..< 4).map(message)))
	}
}
