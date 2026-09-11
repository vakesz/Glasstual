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
	@Test("Both selection endpoints follow body text across markers, theme headers and prefix trimming")
	func selectionEndpointsSurviveRestylingAndTrim() throws {
		let themeController = SharedApplication.sharedThemeController()
		let previousTheme = themeController.theme
		let previousData = Preferences.Theme.transcriptTheme.value
		let copyOnSelect = Preferences.Messages.copyOnSelect.value
		defer {
			themeController.apply(previousTheme)
			Preferences.Theme.transcriptTheme.value = previousData
			Preferences.Messages.copyOnSelect.value = copyOnSelect
		}
		Preferences.Messages.copyOnSelect.value = false
		let view = makeLogView(bufferLimit: 3)
		view.appendLines([
			transcriptLine("before"),
			transcriptLine("first e\u{0301}"),
			transcriptLine("last \u{1F600}"),
		])
		let text = try textView(of: view)
		let start = (text.string as NSString).range(of: "first").location
		let end = NSMaxRange((text.string as NSString).range(of: "last \u{1F600}"))
		text.setSelectedRange(NSRange(location: start, length: end - start))
		view.setUnreadMarker(.line("first e\u{0301}"))
		var theme = previousTheme
		theme.timestampFormat = "%Y-%m-%d %H:%M:%S"
		theme.nicknameFormat = "[%n]"
		#expect(themeController.apply(theme))
		view.applyTheme()
		view.appendLines([transcriptLine("after")])
		let selection = (text.string as NSString).substring(with: text.selectedRange())
		#expect(selection.hasPrefix("first e\u{0301}"))
		#expect(selection.hasSuffix("last \u{1F600}"))
		#expect(!selection.contains("before"))
		#expect(!selection.contains("after"))
		#expect(selection.contains("[alice]"))
	}

	@Test("An edit batch preserves archived reactions and one selection through multiple row refreshes")
	func batchedRefreshKeepsSelectionAndReactionBase() throws {
		let copyOnSelect = Preferences.Messages.copyOnSelect.value
		defer { Preferences.Messages.copyOnSelect.value = copyOnSelect }
		Preferences.Messages.copyOnSelect.value = false
		let view = makeLogView()
		var first = transcriptLine("selected body")
		first.reactions = ["+1": ["alice"]]
		view.appendLines([first, transcriptLine("last")])
		let text = try textView(of: view)
		text.setSelectedRange((text.string as NSString).range(of: "selected body"))
		view.performEditingBatch {
			view.setUnreadMarker(.line(first.lineNumber))
			view.updateReactions(["+1": ["bob"]], messageIdentifier: "id-selected body")
			view.updateDelivery(TranscriptDeliveryUpdate(
				lineNumber: first.lineNumber, state: .delivered, messageIdentifier: nil, reason: nil
			))
		}
		#expect((text.string as NSString).substring(with: text.selectedRange()) == "selected body")
		#expect(view.displayedLines.first?.reactions == ["+1": ["alice", "bob"]])
	}

	@Test("Prepend reports only adjacent accepted rows and does not spend capacity on duplicates")
	func prependReportsAcceptedRows() {
		let view = makeLogView(bufferLimit: 1)
		let newest = transcriptLine("newest")
		view.appendLines([newest])
		let accepted = view.prependLines([transcriptLine("older"), newest])
		#expect(accepted == ["older"])
		#expect(view.displayedBounds.oldest == "older")
		#expect(view.displayedBounds.newest == "newest")
		#expect(view.displayedBounds.count == 2)
		#expect(view.prependLines([transcriptLine("older")]).isEmpty)
	}

	@Test("Capacity keeps only the adjacent part of a page without advancing past refused rows")
	func prependAtCapacityRetainsAdjacentRows() {
		let limit = LogViewBufferPolicy.validLimits.upperBound
		let view = makeLogView(bufferLimit: limit)
		view.view.removeFromSuperview()
		view.appendLines((0 ..< limit - 1).map(message))
		#expect(view.prependLines([transcriptLine("oldest"), transcriptLine("adjacent")]) == ["adjacent"])
		#expect(view.displayedBounds.remainingCapacity == 0)
		#expect(view.displayedBounds.oldest == "adjacent")
		#expect(view.displayedBounds.newest == "message \(limit - 2)")
		#expect(view.prependLines([transcriptLine("oldest")]).isEmpty)
		#expect(!view.jump(to: "oldest"))
	}

	@Test("Refreshing a line reuses its decoded image and attachment")
	func attachmentIsCachedAcrossRefreshes() throws {
		let view = makeLogView()
		view.appendLines([transcriptLine("image")])
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
			hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
		))
		let data = try #require(bitmap.representation(using: .png, properties: [:]))
		try view.addInlineImage(TranscriptInlineImage(
			lineNumber: "image", linkIdentifier: "link", sourceURL: #require(URL(string: "https://example.com/image")),
			imageData: data
		))
		let storage = try #require(textView(of: view).textStorage)
		func attachment() throws -> NSTextAttachment {
			var attachment: NSTextAttachment?
			storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
				if let value = value as? NSTextAttachment {
					attachment = value
				}
			}
			return try #require(attachment)
		}
		let original = try attachment()
		view.updateReactions(["+1": ["bob"]], messageIdentifier: "id-image")
		view.applyTheme()
		view.setUnreadMarker(.latest)
		#expect(try attachment() === original)
		#expect(try attachment().image === original.image)
	}

	/** The scrollback a reader pulled in gives way to new traffic.

	 Loading older lines raises the buffer's ceiling so history stays on screen,
	 but the ceiling used to stay raised for the session: a reader who scrolled
	 back once held tens of thousands of lines live for as long as the view
	 existed. */
	@Test("The ceiling scrollback raised comes back down as the lines it raised it for are trimmed")
	func scrollbackAllowanceDecaysWithTheLinesItHeld() {
		let logView = makeLogView(bufferLimit: 6)

		logView.appendLines((0 ..< 8).map(message))
		logView.prependLines((0 ..< 3).map { transcriptLine("older \($0)") })
		/* History on screen still widens the buffer while it is there. */
		#expect(logView.displayedLines.count == 9)

		logView.appendLines([transcriptLine("newest")])
		logView.appendLines([transcriptLine("newer still")])
		#expect(logView.displayedLines.contains { $0.lineNumber.hasPrefix("older") } == false)

		logView.appendLines([transcriptLine("newest of all")])
		#expect(logView.displayedLines.count == 6)
	}

	/** A reload that has to be retried re-sends lines the document already
	 shows. Prepending has always refused a line it already holds; appending
	 drew it a second time, so the reader read the same message twice. */
	@Test("Appending a line the document already holds changes nothing")
	func appendingRefusesLinesAlreadyOnScreen() throws {
		let logView = makeLogView(bufferLimit: 20)
		let lines = (0 ..< 4).map(message)

		logView.appendLines(lines)
		logView.appendLines(lines)
		logView.appendLines(Array(lines[2 ..< 4]) + [message(4)])

		#expect(logView.displayedLines.map(\.lineNumber) == (0 ..< 5).map { "message \($0)" })
		#expect(try document(of: logView) == rebuiltDocument(of: (0 ..< 5).map(message)))
	}

	@Test("A batch that repeats a line within itself draws it once")
	func appendingRefusesRepeatsWithinOneBatch() {
		let logView = makeLogView(bufferLimit: 20)
		logView.appendLines([message(0), message(1), message(0)])
		#expect(logView.displayedLines.map(\.lineNumber) == ["message 0", "message 1"])
	}

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

	/** The deferred scroll is performed by the view's layout pass, so the pass
	 has to be asked for. A hidden view that is never marked dirty never lays
	 out again, and the transcript stays parked where the reader left it. */
	@Test("A scroll to the end asked for while hidden marks the view for layout")
	func hiddenScrollToBottomRequestsLayout() throws {
		let logView = makeLogView()
		let native = try #require(logView.view as? NativeTranscriptView)
		logView.appendLines((1 ... 20).map(message))
		native.layoutSubtreeIfNeeded()
		native.isHidden = true
		native.layoutSubtreeIfNeeded()
		#expect(native.needsLayout == false)

		logView.scrollToBottom()

		#expect(native.needsLayout)
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

	@Test("Appending uses the storage end after UTF-16 edits, trimming and clearing")
	func appendAfterVariableLengthEditsMatchesRebuild() throws {
		let logView = makeLogView(bufferLimit: 3)
		let first = transcriptLine("first \u{1F600}")
		var changed = transcriptLine("changed e\u{0301}")
		let last = transcriptLine("last")
		logView.appendLines([first, changed])
		logView.updateDelivery(TranscriptDeliveryUpdate(
			lineNumber: changed.lineNumber, state: .failed, messageIdentifier: nil, reason: "longer reason"
		))
		changed.deliveryState = .failed
		changed.deliveryFailureReason = "longer reason"
		logView.prependLines([transcriptLine("older")])
		logView.appendLines([last, transcriptLine("newest")])
		#expect(try document(of: logView) == rebuiltDocument(of: [first, changed, last, transcriptLine("newest")]))

		logView.clearLines()
		logView.appendLines([last])
		#expect(try document(of: logView) == rebuiltDocument(of: [last]))
	}

	/// The two ways a reader moves off the end of the transcript.
	enum TranscriptNavigation: String, CustomTestStringConvertible {
		case usingJump
		case usingFind

		var testDescription: String {
			rawValue
		}
	}

	/** Both ways of navigating have to stop the transcript following the end,
	 or the next line to arrive takes the reader off what they navigated to.

	 Find used to leave the flag alone: `performFindAction(_:)` handed the
	 command to the text view's find bar and never said that the reader was no
	 longer at the end, so the first message to arrive scrolled the match out of
	 sight. */
	@Test(
		"Navigating away suspends bottom following until it is explicitly resumed",
		arguments: [TranscriptNavigation.usingJump, .usingFind]
	)
	func navigationSuspendsBottomFollowing(_ navigation: TranscriptNavigation) throws {
		let copyOnSelect = Preferences.Messages.copyOnSelect.value
		defer { Preferences.Messages.copyOnSelect.value = copyOnSelect }
		Preferences.Messages.copyOnSelect.value = false
		let logView = makeLogView()
		logView.appendLines((0 ..< 200).map(message))
		let textView = try textView(of: logView)
		let scrollView = try #require(textView.enclosingScrollView)
		switch navigation {
		case .usingJump:
			#expect(logView.jump(to: "message 0"))
		case .usingFind:
			/* The find bar is `NSTextFinder`'s and it has no search session in a
			 test process, so the transcript's own half of the command is what is
			 driven here: the command suspends following, and the scroll onto the
			 first line stands for the one the bar performs onto a match. */
			logView.performFindAction(.nextMatch)
			textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
		}
		// A pending first layout must not undo the navigation either.
		logView.view.layoutSubtreeIfNeeded()
		logView.appendLines((200 ..< 220).map(message))
		let layoutManager = try #require(textView.textLayoutManager)
		layoutManager.ensureLayout(for: layoutManager.documentRange)
		textView.sizeToFit()
		#expect(scrollView.contentView.bounds.maxY < textView.frame.maxY - 100)

		logView.scrollToBottom()
		logView.appendLines([message(220)])
		let visibleBottom = scrollView.contentView.bounds.maxY - scrollView.contentInsets.bottom
		#expect(abs(visibleBottom - textView.frame.maxY) < 2)
	}

	/** ⌘G and ⇧⌘G are pressed while the reader is typing in the find field or
	 in the message field, so stepping through matches must leave the keyboard
	 where it is. Every find command used to take it for the transcript. */
	@Test("Stepping through matches leaves the keyboard where it is")
	func steppingThroughMatchesKeepsFirstResponder() throws {
		let logView = makeLogView()
		logView.appendLines((0 ..< 20).map(message))
		let window = try #require(logView.view.window)
		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
		logView.view.addSubview(field)
		#expect(window.makeFirstResponder(field))
		let editor = window.firstResponder

		logView.performFindAction(.nextMatch)
		#expect(window.firstResponder === editor)
		logView.performFindAction(.previousMatch)
		#expect(window.firstResponder === editor)

		/* Opening the bar is the one command that does take the keyboard: it is
		 how the reader gets to the search field at all. */
		logView.performFindAction(.showFindInterface)
		#expect(window.firstResponder !== editor)
	}

	@Test("An unknown jump target leaves bottom following enabled")
	func failedJumpKeepsBottomFollowing() throws {
		let logView = makeLogView()
		logView.appendLines((0 ..< 200).map(message))
		logView.view.layoutSubtreeIfNeeded()
		#expect(logView.jump(to: "missing") == false)
		logView.appendLines([message(200)])
		let textView = try textView(of: logView)
		let scrollView = try #require(textView.enclosingScrollView)
		let visibleBottom = scrollView.contentView.bounds.maxY - scrollView.contentInsets.bottom
		#expect(abs(visibleBottom - textView.frame.maxY) < 2)
	}

	@Test("Bubble fills are fallback backgrounds, below IRC colors and highlights")
	func bubbleBackgroundPreservesExplicitAndHighlightColors() throws {
		let controller = SharedApplication.sharedThemeController()
		let previousTheme = controller.theme
		let previousData = Preferences.Theme.transcriptTheme.value
		defer {
			controller.apply(previousTheme)
			Preferences.Theme.transcriptTheme.value = previousData
		}
		#expect(controller.apply(.bubbles))
		let logView = makeLogView()
		var line = transcriptLine("plain colored highlighted")
		line.body.runs = [
			TranscriptTextRun(text: "plain "),
			TranscriptTextRun(text: "colored ", background: .palette(4)),
			TranscriptTextRun(text: "highlighted", traits: .highlighted, background: .palette(4)),
		]
		logView.appendLines([line])
		let storage = try #require(textView(of: logView).textStorage)
		for (text, expected) in [
			("plain", controller.resolved(controller.theme.palette.bubbleIncoming)),
			("colored", NSColor.formatterColors[4]),
			("highlighted", controller.resolved(controller.theme.palette.highlightBackground)),
		] {
			let range = (storage.string as NSString).range(of: text)
			#expect(storage
				.attribute(.backgroundColor, at: range.location, effectiveRange: nil) as? NSColor == expected)
		}
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
