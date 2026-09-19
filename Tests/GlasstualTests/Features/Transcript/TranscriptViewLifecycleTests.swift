// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
@Suite("Transcript view lifecycle")
struct TranscriptViewLifecycleTests {
	private func descendants<View: NSView>(of type: View.Type, in root: NSView) -> [View] {
		root.subviews.flatMap { view in
			(view as? View).map { [$0] } ?? descendants(of: type, in: view)
		}
	}

	private func transcriptLine(_ text: String) -> TranscriptRow {
		TranscriptRow(
			lineNumber: UUID().uuidString,
			receivedAt: Date(),
			nickname: "alice",
			memberType: .normal,
			lineType: .privateMessage,
			command: "PRIVMSG",
			messageIdentifier: nil,
			replyToMessageIdentifier: nil,
			deliveryState: .none,
			deliveryFailureReason: nil,
			reactions: [:],
			markers: [],
			body: TranscriptBody(
				plainText: text,
				runs: [TranscriptTextRun(text: text)]
			)
		)
	}

	@Test("The view keeps only a weak controller reference")
	func controllerCanDeallocate() throws {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: .zero,
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		var controller: TranscriptController? = TranscriptController(session: session, in: window)
		let transcriptView = try #require(controller?.ensureBackingView())
		weak let weakController = controller

		controller = nil

		#expect(weakController == nil)
		#expect(transcriptView.viewController == nil)
	}

	@Test("A topic received while connecting is fixed above the transcript")
	func connectingTopicAppearsInHeader() throws {
		let fixture = ChatEnvironmentFixture()
		let session = fixture.chatSession.createSession(with: ServerConfig())
		let channel = fixture.chatSession.createConversation(
			with: ConversationConfig.seed(withName: "#swift"),
			on: session,
			add: true,
			adjust: false,
			reload: false
		)
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: [.titled, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		let controller = window.transcriptControllers.controller(for: channel)
		let transcriptView = controller.ensureBackingView()
		let host = NSHostingController(rootView: TranscriptViewRepresentable(transcriptView: transcriptView))
		host.preferredContentSize = NSSize(width: 800, height: 600)
		window.contentViewController = host
		window.setContentSize(NSSize(width: 800, height: 600))

		channel.topic = "Native AppKit discussion"
		window.contentView?.layoutSubtreeIfNeeded()
		host.view.layoutSubtreeIfNeeded()

		let topicField = try #require(
			descendants(of: NSTextField.self, in: transcriptView)
				.first { visibleTranscriptText($0.attributedStringValue) == "Native AppKit discussion" }
		)
		#expect(topicField.isHiddenOrHasHiddenAncestor == false)
		#expect(topicField.frame.height > 0)
		let topicFrame = topicField.convert(topicField.bounds, to: host.view)
		#expect(topicFrame.maxY <= host.view.safeAreaRect.maxY + 0.5)
	}

	/** SwiftUI asks the transcript for its minimum and ideal size when it lays
	 out the split view's detail column, and the column follows the answer. An
	 AppKit view answers with its Auto Layout fitting size by default, which for
	 the transcript is whatever its topic bar measures: nothing, or the width of
	 a long topic on one line. Either answer breaks the column. */
	@Test("The transcript's minimum width does not follow its topic bar", arguments: [
		nil,
		"Linux kernel discussion | BOOKS https://lwn.net/Kernel/LDD3 | BROWSER https://elixir.bootlin.com | PASTEBIN https://privatebin.net https://codepad.org | HOWTOASK https://goo.gl/zi5V | CONTRIBUTE https://goo.gl/1Fb2VG",
	])
	func transcriptMinimumWidthIgnoresTopic(topic: String?) {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(session: session, in: window)
		let transcriptView = controller.ensureBackingView()
		transcriptView.setTopic(topic)
		transcriptView.replaceLines([transcriptLine("hello there")])
		let hostingView = NSHostingView(rootView: TranscriptViewRepresentable(transcriptView: transcriptView))
		hostingView.sizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
		hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = hostingView
		hostingView.layoutSubtreeIfNeeded()

		let minimum = hostingView.fittingSize
		let ideal = hostingView.intrinsicContentSize
		let frame = transcriptView.convert(transcriptView.bounds, to: hostingView)
		let columnMinimum = MainWindowConstants.conversationMinimumWidth
		#expect(minimum.width <= columnMinimum, "minimum \(minimum) fitting \(transcriptView.fittingSize)")
		#expect(ideal.width >= columnMinimum, "ideal \(ideal) fitting \(transcriptView.fittingSize)")
		#expect(abs(frame.width - 800) < 1, "frame \(frame)")
	}

	/** With the member list open the three columns have to share the window.
	 A conversation column whose minimum width is whatever it measured last
	 cannot give anything up, and the columns spill past the window instead;
	 and a column that grows when the list appears never comes back when it
	 goes. The window is the narrowest one the app allows, so the room the
	 list needs is exactly what the transcript has to give up. */
	@Test("The transcript makes room for the member list and takes it back")
	func transcriptMakesRoomForMemberList() throws {
		let fixture = ChatEnvironmentFixture()
		let session = fixture.chatSession.createSession(with: ServerConfig())
		let channel = fixture.chatSession.createConversation(
			with: ConversationConfig.seed(withName: "#swift"),
			on: session,
			add: true,
			adjust: false,
			reload: false
		)
		let size = MainWindowConstants.minimumContentSize
		let window = MainWindow(
			contentRect: NSRect(origin: .zero, size: size),
			styleMask: [.titled, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		let transcriptView = window.transcriptControllers.controller(for: channel).ensureBackingView()
		let host = NSHostingController(rootView: MainWindowRootView(
			columns: window.columnModel,
			sheets: window.sheetModel,
			chrome: window.chrome,
			loadingScreen: window.loadingScreen,
			sidebar: window.sidebar,
			memberList: window.memberList,
			inputContentView: window.inputContentView,
			commands: AppServices.delegate.menuController
		))
		host.sizingOptions = []
		window.contentViewController = host
		window.setContentSize(size)
		window.columnModel.transcript = transcriptView
		window.columnModel.applyMemberListAvailability(false)
		transcriptView.setTopic("Native AppKit discussion")
		transcriptView.replaceLines([transcriptLine("hello there")])
		window.contentView?.layoutSubtreeIfNeeded()
		let frameAlone = transcriptView.convert(transcriptView.bounds, to: host.view)

		window.columnModel.applyMemberListAvailability(true)
		window.contentView?.layoutSubtreeIfNeeded()
		host.view.layoutSubtreeIfNeeded()

		let rootFrame = host.view.frame
		let transcriptFrame = transcriptView.convert(transcriptView.bounds, to: host.view)
		#expect(transcriptFrame.minX >= 0, "transcript \(transcriptFrame) root \(rootFrame)")
		#expect(transcriptFrame.maxX <= rootFrame.width + 0.5, "transcript \(transcriptFrame) root \(rootFrame)")
		#expect(transcriptFrame.width >= MainWindowConstants.conversationMinimumWidth, "transcript \(transcriptFrame)")
		#expect(
			rootFrame.width - transcriptFrame.maxX >= MemberListLayout.minimumWidth,
			"transcript \(transcriptFrame) leaves no room in \(rootFrame)"
		)

		/* The bar floats over the transcript, and the inset is what keeps the
		 last line out from under it. */
		let scrollView = try #require(descendants(of: NSScrollView.self, in: transcriptView).first)
		let field = window.inputContentView.frame
		let barHeight = field.height + InputBarLayout.fieldVerticalPadding * 2
			+ InputBarLayout.bottomPadding
		let inset = scrollView.contentInsets.bottom
		#expect(abs(inset - barHeight) < 1, "inset \(inset) bar \(barHeight)")

		window.columnModel.toggleMemberList()
		window.contentView?.layoutSubtreeIfNeeded()
		host.view.layoutSubtreeIfNeeded()
		let frameAgain = transcriptView.convert(transcriptView.bounds, to: host.view)
		#expect(abs(frameAgain.width - frameAlone.width) < 1, "alone \(frameAlone) again \(frameAgain)")
	}

	@Test("Links in the topic are native clickable links")
	func topicLinksAreClickable() throws {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(session: session, in: window)
		let transcriptView = controller.ensureBackingView()
		let topic = "Project https://example.com and docs.example.org/guide"

		transcriptView.setTopic(topic)

		let topicField = try #require(
			descendants(of: NSTextField.self, in: transcriptView)
				.first { visibleTranscriptText($0.attributedStringValue) == topic }
		)
		let attributedTopic = topicField.attributedStringValue
		var links: [URL] = []
		attributedTopic.enumerateAttribute(.link, in: attributedTopic.fullRange) { value, _, _ in
			if let url = value as? URL {
				links.append(url)
			}
		}

		#expect(topicField.isSelectable)
		#expect(topicField.allowsEditingTextAttributes)
		#expect(try links == [
			#require(URL(string: "https://example.com")),
			#require(URL(string: "http://docs.example.org/guide")),
		])
	}

	@Test("A server view with no topic reserves no topic bar")
	func serverViewHasNoEmptyTopicBar() throws {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(session: session, in: window)
		let transcriptView = controller.ensureBackingView()
		transcriptView.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = transcriptView
		transcriptView.layoutSubtreeIfNeeded()

		let scrollView = try #require(descendants(of: NSScrollView.self, in: transcriptView).first)
		/* The bar hides itself rather than its label, so a field inside a hidden
		 bar is still `isHidden == false`: what must be true is that none of them
		 is on screen. */
		let noTopicFieldIsVisible = descendants(of: NSTextField.self, in: transcriptView)
			.allSatisfy { field in field.isHiddenOrHasHiddenAncestor }
		#expect(scrollView.frame.maxY == transcriptView.bounds.maxY)
		#expect(transcriptView.topicBar.isHidden)
		#expect(noTopicFieldIsVisible)
	}

	@Test("A short transcript starts at the bottom and grows upward")
	func shortTranscriptIsBottomAnchored() throws {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(session: session, in: window)
		let transcriptView = controller.ensureBackingView()
		transcriptView.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = transcriptView
		transcriptView.replaceLines([transcriptLine("hello")])
		transcriptView.layoutSubtreeIfNeeded()

		let scrollView = try #require(descendants(of: NSScrollView.self, in: transcriptView).first)
		let textView = try #require(scrollView.documentView as? NSTextView)
		let layoutManager = try #require(textView.textLayoutManager)
		layoutManager.ensureLayout(for: layoutManager.documentRange)

		#expect(textView.textContainerOrigin.y > scrollView.contentView.bounds.midY)
	}

	/// The topmost row of the drawn transcript whose pixels differ from the
	/// background, as a fraction of the view's height, or nil when nothing drew.
	private func firstDrawnRowFraction(in view: NSView) -> CGFloat? {
		guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
		view.cacheDisplay(in: view.bounds, to: bitmap)
		guard let background = bitmap.colorAt(x: bitmap.pixelsWide - 2, y: bitmap.pixelsHigh / 2)?
			.usingColorSpace(.deviceRGB)
		else { return nil }
		for y in 0 ..< bitmap.pixelsHigh {
			for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
				guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
				let differs = abs(color.redComponent - background.redComponent) > 0.2
					|| abs(color.greenComponent - background.greenComponent) > 0.2
					|| abs(color.blueComponent - background.blueComponent) > 0.2
				if differs {
					return CGFloat(y) / CGFloat(bitmap.pixelsHigh)
				}
			}
		}
		return nil
	}

	/** Whether the hairline for the marker paragraph at `location` is on the
	 pixels: the row `transcriptRuleInset` below the paragraph's top holds
	 something other than the background, and the row just above it does not.
	 The view is drawn into an 800 by 600 window for the check. */
	private func ruleIsDrawn(for location: Int, in transcriptView: TranscriptView, textView: NSTextView) throws -> Bool {
		let window = try #require(transcriptView.window ?? {
			let window = MainWindow(
				contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
				styleMask: .borderless,
				backing: .buffered,
				defer: false
			)
			transcriptView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
			window.contentView = transcriptView
			return window
		}())
		_ = window
		transcriptView.layoutSubtreeIfNeeded()
		transcriptView.displayIfNeeded()
		let layoutManager = try #require(textView.textLayoutManager)
		let storage = try #require(textView.textStorage)
		let inset = try #require(
			storage.attribute(.transcriptRuleInset, at: location, effectiveRange: nil) as? NSNumber
		)
		let start = try #require(layoutManager.location(layoutManager.documentRange.location, offsetBy: location))
		let fragment = try #require(layoutManager.textLayoutFragment(for: start))
		let origin = textView.textContainerOrigin
		let ruleY = fragment.layoutFragmentFrame.minY + origin.y + CGFloat(inset.doubleValue)
		let view = transcriptView
		let ruleInView = textView.convert(NSPoint(x: textView.bounds.midX, y: ruleY), to: view)
		let aboveInView = textView.convert(NSPoint(x: textView.bounds.midX, y: ruleY - 3), to: view)
		guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
		view.cacheDisplay(in: view.bounds, to: bitmap)
		let background = try #require(bitmap.colorAt(x: bitmap.pixelsWide - 2, y: bitmap.pixelsHigh / 2)?
			.usingColorSpace(.deviceRGB))
		/* `colorAt(x:y:)` is in pixels and the rule's position is in points, so
		 the backing scale is part of the conversion: on a Retina display the
		 probe used to read a row half way up the view from the one it meant, and
		 found the background there whatever the rule did. */
		let scale = CGFloat(bitmap.pixelsHigh) / view.bounds.height
		func rowDiffers(_ pointInView: NSPoint) -> Bool {
			let offset = view.isFlipped ? pointInView.y : view.bounds.height - pointInView.y
			let row = Int(offset * scale)
			let radius = Int(scale.rounded(.up))
			for probe in (row - radius) ... (row + radius) where probe >= 0 && probe < bitmap.pixelsHigh {
				for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
					guard let color = bitmap.colorAt(x: x, y: probe)?.usingColorSpace(.deviceRGB) else { continue }
					if abs(color.redComponent - background.redComponent) > 0.05
						|| abs(color.greenComponent - background.greenComponent) > 0.05
						|| abs(color.blueComponent - background.blueComponent) > 0.05
					{
						return true
					}
				}
			}
			return false
		}
		return rowDiffers(ruleInView) && rowDiffers(aboveInView) == false
	}

	/** The property says where the text container is meant to sit; this draws
	 the view and checks where the first line actually lands. A short
	 conversation belongs beside the input bar, at the foot of the view. */
	@Test("A short transcript draws its lines at the foot of the view")
	func shortTranscriptDrawsAtTheBottom() throws {
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
		transcriptView.replaceLines([transcriptLine("hello"), transcriptLine("there")])
		transcriptView.layoutSubtreeIfNeeded()
		transcriptView.displayIfNeeded()

		let firstRow = try #require(firstDrawnRowFraction(in: transcriptView))
		#expect(firstRow > 0.6, "first drawn row at \(firstRow) of the height")
	}

	/** A query opens with lines already in it: the identification exchange is
	 printed before the view is ever shown. Those lines belong at the foot too,
	 once the view lands in the window. */
	@Test("Lines received before the view is shown still draw at the foot")
	func hiddenTranscriptDrawsAtTheBottomOnceShown() throws {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(session: session, in: window)
		let transcriptView = controller.ensureBackingView()
		transcriptView.appendLines([transcriptLine("hello")])
		transcriptView.appendLines([transcriptLine("there")])

		transcriptView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = transcriptView
		transcriptView.layoutSubtreeIfNeeded()
		transcriptView.displayIfNeeded()

		let firstRow = try #require(firstDrawnRowFraction(in: transcriptView))
		#expect(firstRow > 0.6, "first drawn row at \(firstRow) of the height")
	}

	/** A query that opened while another view was selected carries the unread
	 hairline above its first line. The marker's block spans the container's
	 width, and it must not make the short transcript read as taller than the
	 viewport. */
	@Test("A short transcript with an unread marker still draws at the foot")
	func shortTranscriptWithUnreadMarkerDrawsAtTheBottom() throws {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(session: session, in: window)
		let transcriptView = controller.ensureBackingView()
		transcriptView.appendLines([transcriptLine("hello"), transcriptLine("there")])
		/* An identifier the transcript does not hold marks its first line,
		 which is where a query that opened unseen carries the marker. */
		transcriptView.setUnreadMarker(.line("missing"))

		transcriptView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = transcriptView
		transcriptView.layoutSubtreeIfNeeded()
		transcriptView.displayIfNeeded()

		let scrollView = try #require(descendants(of: NSScrollView.self, in: transcriptView).first)
		let textView = try #require(scrollView.documentView as? NSTextView)
		/* The marker must not have moved the view back to TextKit 1; the
		 alignment below only exists on TextKit 2. */
		#expect(textView.textLayoutManager != nil)
		let markerRange = (textView.string as NSString).range(of: "\u{200B}")
		#expect(markerRange.location != NSNotFound)
		let ruleColor = textView.textStorage?.attribute(
			.transcriptRuleColor, at: markerRange.location, effectiveRange: nil
		)
		#expect(ruleColor != nil)
		let firstRow = try #require(firstDrawnRowFraction(in: transcriptView))
		#expect(firstRow > 0.6, "first drawn row at \(firstRow) of the height")
	}

	@Test("A long transcript uses ordinary top-aligned scrolling")
	func longTranscriptUsesNormalScrolling() throws {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(session: session, in: window)
		let transcriptView = controller.ensureBackingView()
		transcriptView.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = transcriptView
		transcriptView.replaceLines((0 ..< 100).map { transcriptLine("message \($0)") })
		transcriptView.layoutSubtreeIfNeeded()

		let scrollView = try #require(descendants(of: NSScrollView.self, in: transcriptView).first)
		let textView = try #require(scrollView.documentView as? NSTextView)
		let layoutManager = try #require(textView.textLayoutManager)
		layoutManager.ensureLayout(for: layoutManager.documentRange)

		#expect(textView.textContainerOrigin.y == textView.textContainerInset.height)
	}

	@Test("The current-session marker draws a full-width native separator")
	func currentSessionMarkerHasFullWidthSeparator() throws {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(session: session, in: window)
		let transcriptView = controller.ensureBackingView()
		var liveLine = transcriptLine("live")
		liveLine.markers = [.currentSession("Current Session")]

		transcriptView.replaceLines([transcriptLine("history"), liveLine])

		let scrollView = try #require(descendants(of: NSScrollView.self, in: transcriptView).first)
		let textView = try #require(scrollView.documentView as? NSTextView)
		let markerRange = (textView.string as NSString).range(of: "Current Session")
		let paragraph = try #require(
			textView.textStorage?.attribute(.paragraphStyle, at: markerRange.location, effectiveRange: nil)
				as? NSParagraphStyle
		)
		let rule = textView.textStorage?.attribute(.transcriptRuleColor, at: markerRange.location, effectiveRange: nil)

		/* A text block would give the rule for free, and take TextKit 2 away
		 from the whole view with it. */
		#expect(paragraph.textBlocks.isEmpty)
		#expect(rule is NSColor)
		#expect(textView.textLayoutManager != nil)
		#expect(try ruleIsDrawn(for: markerRange.location, in: transcriptView, textView: textView))
		#expect(try layoutFragment(for: markerRange.location, in: textView) is TranscriptRuleLayoutFragment)
	}

	/// The TextKit 2 fragment laying out the paragraph at `location`.
	private func layoutFragment(for location: Int, in textView: NSTextView) throws -> NSTextLayoutFragment {
		let layoutManager = try #require(textView.textLayoutManager)
		let start = try #require(layoutManager.location(layoutManager.documentRange.location, offsetBy: location))
		layoutManager.ensureLayout(for: NSTextRange(location: start))
		return try #require(layoutManager.textLayoutFragment(for: start))
	}

	@Test("The unread marker is a quiet hairline without a caption")
	func unreadMarkerHasNoCaption() throws {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(session: session, in: window)
		let transcriptView = controller.ensureBackingView()
		var unreadLine = transcriptLine("unread")
		unreadLine.markers = [.unread("Unread messages")]

		transcriptView.replaceLines([transcriptLine("read"), unreadLine])

		let scrollView = try #require(descendants(of: NSScrollView.self, in: transcriptView).first)
		let textView = try #require(scrollView.documentView as? NSTextView)
		#expect(textView.string.contains("Unread messages") == false)
		let markerRange = (textView.string as NSString).range(of: "\u{200B}")
		let paragraph = try #require(
			textView.textStorage?.attribute(.paragraphStyle, at: markerRange.location, effectiveRange: nil)
				as? NSParagraphStyle
		)
		let rule = textView.textStorage?.attribute(.transcriptRuleColor, at: markerRange.location, effectiveRange: nil)
		#expect(paragraph.textBlocks.isEmpty)
		#expect(rule is NSColor)
		#expect(textView.textLayoutManager != nil)
		#expect(try ruleIsDrawn(for: markerRange.location, in: transcriptView, textView: textView))
		#expect(try layoutFragment(for: markerRange.location, in: textView) is TranscriptRuleLayoutFragment)
	}

	/** The chevron says the topic has more to show, so a topic that fits on one
	 line must not offer one at any text size.

	 The threshold used to be a line of the field's own font while the string
	 measured against it carried the scaled font `attributedTopic(_:)` writes,
	 so at ⌘= every one-line topic measured as an overflow and got a chevron
	 that unfolded onto nothing. */
	@Test("A one-line topic offers no chevron at any text scale", arguments: [1.0, 2.0] as [CGFloat])
	func oneLineTopicHasNoChevron(scale: CGFloat) {
		let transcript = makeTranscript(width: 800)
		transcript.transcriptView.setTopic("Short topic")
		transcript.transcriptView.setTextScale(scale)
		transcript.window.contentView?.layoutSubtreeIfNeeded()

		#expect(transcript.transcriptView.topicBar.isHidden == false)
		#expect(transcript.transcriptView.topicBar.disclosure.isHidden)
	}

	/// A topic too long for the column keeps its chevron, whatever the scale:
	/// the fix must not have turned the disclosure off altogether.
	@Test("A topic that does not fit keeps its chevron", arguments: [1.0, 2.0] as [CGFloat])
	func wrappingTopicKeepsItsChevron(scale: CGFloat) {
		let transcript = makeTranscript(width: 400)
		transcript.transcriptView.setTopic(String(repeating: "a long topic that cannot fit on one line ", count: 6))
		transcript.transcriptView.setTextScale(scale)
		transcript.window.contentView?.layoutSubtreeIfNeeded()

		#expect(transcript.transcriptView.topicBar.disclosure.isHidden == false)
	}

	/** The profile used to wait out the double-click interval before opening,
	 which follows the reader's Double-click speed and can be seconds. It
	 opens on the click now; the double click that opens a conversation takes
	 it down. */
	@Test("A click on a name opens the profile at once")
	func clickingANameOpensTheProfileAtOnce() throws {
		let transcript = makeTranscript(width: 800, withMember: "alice")
		transcript.transcriptView.replaceLines([transcriptLine("hello there")])
		transcript.window.contentView?.layoutSubtreeIfNeeded()

		try clickNickname(in: transcript)
		#expect(transcript.transcriptView.memberInformationPopover != nil)
	}

	/// Clearing and trimming remove the characters the popover is anchored
	/// to, so they take it down rather than leave it pointing at other text.
	@Test("Clearing the transcript closes the profile popover")
	func clearingClosesTheProfilePopover() throws {
		let transcript = makeTranscript(width: 800, withMember: "alice")
		transcript.transcriptView.replaceLines([transcriptLine("hello there")])
		transcript.window.contentView?.layoutSubtreeIfNeeded()

		try clickNickname(in: transcript)
		#expect(transcript.transcriptView.memberInformationPopover != nil)

		transcript.transcriptView.clearLines()
		#expect(transcript.transcriptView.memberInformationPopover == nil)
	}

	/// A transcript that leaves its window has nothing to anchor a popover to.
	@Test("Leaving the window closes the profile popover")
	func leavingTheWindowClosesTheProfilePopover() throws {
		let transcript = makeTranscript(width: 800, withMember: "alice")
		transcript.transcriptView.replaceLines([transcriptLine("hello there")])
		transcript.window.contentView?.layoutSubtreeIfNeeded()

		try clickNickname(in: transcript)
		#expect(transcript.transcriptView.memberInformationPopover != nil)

		transcript.transcriptView.removeFromSuperview()
		#expect(transcript.transcriptView.memberInformationPopover == nil)
	}

	private struct Transcript {
		let window: MainWindow
		let transcriptView: TranscriptView
		/// Held here because the view, the controller and the channel hold
		/// the controller, the channel and the session weakly.
		let controller: TranscriptController
		let session: ServerSession
		let channel: Conversation?
	}

	/// A transcript over a channel when `member` is given, so a click on that
	/// name has a profile to show; over the connection alone otherwise.
	private func makeTranscript(width: CGFloat, withMember member: String? = nil) -> Transcript {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller: TranscriptController
		var channel: Conversation?
		if let member {
			let profileChannel = Conversation(config: ConversationConfig(name: "#profile"))
			profileChannel.associatedSession = session
			profileChannel.activate()
			profileChannel.addMember(
				Member(user: session.findUserOrCreate(member), prefixes: session.currentUserPrefixes)
			)
			controller = TranscriptController(conversation: profileChannel, in: window)
			channel = profileChannel
		} else {
			controller = TranscriptController(session: session, in: window)
		}
		let transcriptView = controller.ensureBackingView()
		let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 600))
		container.addSubview(transcriptView)
		NSLayoutConstraint.activate([
			transcriptView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			transcriptView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			transcriptView.topAnchor.constraint(equalTo: container.topAnchor),
			transcriptView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
		])
		window.contentView = container
		container.layoutSubtreeIfNeeded()
		return Transcript(window: window, transcriptView: transcriptView, controller: controller, session: session, channel: channel)
	}

	/// Clicks the middle of the first nickname the transcript drew, the way the
	/// text view reports a click of its own.
	private func clickNickname(in transcript: Transcript) throws {
		let textView = transcript.transcriptView.textView
		let storage = try #require(textView.textStorage)
		var nicknameRange: NSRange?
		storage.enumerateAttribute(
			.transcriptAction,
			in: NSRange(location: 0, length: storage.length)
		) { value, range, stop in
			if case .nickname = value as? TranscriptAction {
				nicknameRange = range
				stop.pointee = true
			}
		}
		let range = try #require(nicknameRange)
		let screenRect = textView.firstRect(forCharacterRange: range, actualRange: nil)
		let windowRect = try #require(transcript.window.convertFromScreen(screenRect) as NSRect?)
		let rect = textView.convert(windowRect, from: nil)
		textView.onClick?(TranscriptClick(
			point: NSPoint(x: rect.midX, y: rect.midY),
			clickCount: 1,
			modifiers: [],
			dragged: false
		))
	}
}

private extension NSAttributedString {
	var fullRange: NSRange {
		NSRange(location: 0, length: length)
	}
}
