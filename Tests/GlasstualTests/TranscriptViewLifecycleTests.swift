/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
@Suite("Native log view lifecycle")
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
		let client = Client(config: ClientConfig())
		let window = MainWindow(
			contentRect: .zero,
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		var controller: TranscriptController? = TranscriptController(client: client, in: window)
		let logView = try #require(controller?.ensureBackingView())
		weak let weakController = controller

		controller = nil

		#expect(weakController == nil)
		#expect(logView.viewController == nil)
	}

	@Test("A topic received while connecting is fixed above the transcript")
	func connectingTopicAppearsInHeader() throws {
		let fixture = ClientEnvironmentFixture()
		let client = fixture.world.createClient(with: ClientConfig())
		let channel = fixture.world.createChannel(
			with: ChannelConfig.seed(withName: "#swift"),
			on: client,
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
		let controller = window.logControllers.controller(for: channel)
		let logView = controller.ensureBackingView()
		let host = NSHostingController(rootView: TranscriptViewRepresentable(logView: logView))
		host.preferredContentSize = NSSize(width: 800, height: 600)
		window.contentViewController = host
		window.setContentSize(NSSize(width: 800, height: 600))

		channel.topic = "Native AppKit discussion"
		window.contentView?.layoutSubtreeIfNeeded()
		host.view.layoutSubtreeIfNeeded()

		let topicField = try #require(
			descendants(of: NSTextField.self, in: logView)
				.first { visibleTranscriptText($0.attributedStringValue) == "Native AppKit discussion" }
		)
		#expect(topicField.isHidden == false)
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
		let client = Client(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(client: client, in: window)
		let logView = controller.ensureBackingView()
		logView.setTopic(topic)
		logView.replaceLines([transcriptLine("hello there")])
		let hostingView = NSHostingView(rootView: TranscriptViewRepresentable(logView: logView))
		hostingView.sizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
		hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = hostingView
		hostingView.layoutSubtreeIfNeeded()

		let minimum = hostingView.fittingSize
		let ideal = hostingView.intrinsicContentSize
		let frame = logView.convert(logView.bounds, to: hostingView)
		let columnMinimum = MainWindowConstants.conversationMinimumWidth
		#expect(minimum.width <= columnMinimum, "minimum \(minimum) fitting \(logView.fittingSize)")
		#expect(ideal.width >= columnMinimum, "ideal \(ideal) fitting \(logView.fittingSize)")
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
		let fixture = ClientEnvironmentFixture()
		let client = fixture.world.createClient(with: ClientConfig())
		let channel = fixture.world.createChannel(
			with: ChannelConfig.seed(withName: "#swift"),
			on: client,
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
		let logView = window.logControllers.controller(for: channel).ensureBackingView()
		let host = NSHostingController(rootView: MainWindowRootView(
			model: window.presentationModel,
			loadingScreen: window.loadingScreen,
			serverList: window.serverList,
			memberList: window.memberList,
			inputContentView: window.inputContentView
		))
		host.sizingOptions = []
		window.contentViewController = host
		window.setContentSize(size)
		window.presentationModel.transcript = logView
		window.presentationModel.applyMemberListAvailability(false)
		logView.setTopic("Native AppKit discussion")
		logView.replaceLines([transcriptLine("hello there")])
		window.contentView?.layoutSubtreeIfNeeded()
		let frameAlone = logView.convert(logView.bounds, to: host.view)

		window.presentationModel.applyMemberListAvailability(true)
		window.contentView?.layoutSubtreeIfNeeded()
		host.view.layoutSubtreeIfNeeded()

		let rootFrame = host.view.frame
		let transcriptFrame = logView.convert(logView.bounds, to: host.view)
		#expect(transcriptFrame.minX >= 0, "transcript \(transcriptFrame) root \(rootFrame)")
		#expect(transcriptFrame.maxX <= rootFrame.width + 0.5, "transcript \(transcriptFrame) root \(rootFrame)")
		#expect(transcriptFrame.width >= MainWindowConstants.conversationMinimumWidth, "transcript \(transcriptFrame)")
		#expect(
			rootFrame.width - transcriptFrame.maxX >= MainWindowConstants.memberListMinimumWidth,
			"transcript \(transcriptFrame) leaves no room in \(rootFrame)"
		)

		/* The bar floats over the transcript, and the inset is what keeps the
		 last line out from under it. */
		let scrollView = try #require(descendants(of: NSScrollView.self, in: logView).first)
		let field = window.inputContentView.frame
		let barHeight = field.height + MainWindowInputBarLayout.fieldVerticalPadding * 2
			+ MainWindowInputBarLayout.bottomPadding
		let inset = scrollView.contentInsets.bottom
		#expect(abs(inset - barHeight) < 1, "inset \(inset) bar \(barHeight)")

		window.presentationModel.toggleMemberList()
		window.contentView?.layoutSubtreeIfNeeded()
		host.view.layoutSubtreeIfNeeded()
		let frameAgain = logView.convert(logView.bounds, to: host.view)
		#expect(abs(frameAgain.width - frameAlone.width) < 1, "alone \(frameAlone) again \(frameAgain)")
	}

	@Test("Links in the topic are native clickable links")
	func topicLinksAreClickable() throws {
		let client = Client(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(client: client, in: window)
		let logView = controller.ensureBackingView()
		let topic = "Project https://example.com and docs.example.org/guide"

		logView.setTopic(topic)

		let topicField = try #require(
			descendants(of: NSTextField.self, in: logView)
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
		let client = Client(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(client: client, in: window)
		let logView = controller.ensureBackingView()
		logView.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = logView
		logView.layoutSubtreeIfNeeded()

		let scrollView = try #require(descendants(of: NSScrollView.self, in: logView).first)
		let allTopicFieldsHidden = descendants(of: NSTextField.self, in: logView).allSatisfy(\.isHidden)
		#expect(scrollView.frame.maxY == logView.bounds.maxY)
		#expect(allTopicFieldsHidden)
	}

	@Test("A short transcript starts at the bottom and grows upward")
	func shortTranscriptIsBottomAnchored() throws {
		let client = Client(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(client: client, in: window)
		let logView = controller.ensureBackingView()
		logView.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = logView
		logView.replaceLines([transcriptLine("hello")])
		logView.layoutSubtreeIfNeeded()

		let scrollView = try #require(descendants(of: NSScrollView.self, in: logView).first)
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
	private func ruleIsDrawn(for location: Int, in logView: TranscriptView, textView: NSTextView) throws -> Bool {
		let window = try #require(logView.window ?? {
			let window = MainWindow(
				contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
				styleMask: .borderless,
				backing: .buffered,
				defer: false
			)
			logView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
			window.contentView = logView
			return window
		}())
		_ = window
		logView.layoutSubtreeIfNeeded()
		logView.displayIfNeeded()
		let layoutManager = try #require(textView.textLayoutManager)
		let storage = try #require(textView.textStorage)
		let inset = try #require(
			storage.attribute(.transcriptRuleInset, at: location, effectiveRange: nil) as? NSNumber
		)
		let start = try #require(layoutManager.location(layoutManager.documentRange.location, offsetBy: location))
		let fragment = try #require(layoutManager.textLayoutFragment(for: start))
		let origin = textView.textContainerOrigin
		let ruleY = fragment.layoutFragmentFrame.minY + origin.y + CGFloat(inset.doubleValue)
		let view = logView
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
		let client = Client(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(client: client, in: window)
		let logView = controller.ensureBackingView()
		logView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = logView
		logView.replaceLines([transcriptLine("hello"), transcriptLine("there")])
		logView.layoutSubtreeIfNeeded()
		logView.displayIfNeeded()

		let firstRow = try #require(firstDrawnRowFraction(in: logView))
		#expect(firstRow > 0.6, "first drawn row at \(firstRow) of the height")
	}

	/** A query opens with lines already in it: the identification exchange is
	 printed before the view is ever shown. Those lines belong at the foot too,
	 once the view lands in the window. */
	@Test("Lines received before the view is shown still draw at the foot")
	func hiddenTranscriptDrawsAtTheBottomOnceShown() throws {
		let client = Client(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(client: client, in: window)
		let logView = controller.ensureBackingView()
		logView.appendLines([transcriptLine("hello")])
		logView.appendLines([transcriptLine("there")])

		logView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = logView
		logView.layoutSubtreeIfNeeded()
		logView.displayIfNeeded()

		let firstRow = try #require(firstDrawnRowFraction(in: logView))
		#expect(firstRow > 0.6, "first drawn row at \(firstRow) of the height")
	}

	/** A query that opened while another view was selected carries the unread
	 hairline above its first line. The marker's block spans the container's
	 width, and it must not make the short transcript read as taller than the
	 viewport. */
	@Test("A short transcript with an unread marker still draws at the foot")
	func shortTranscriptWithUnreadMarkerDrawsAtTheBottom() throws {
		let client = Client(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(client: client, in: window)
		let logView = controller.ensureBackingView()
		logView.appendLines([transcriptLine("hello"), transcriptLine("there")])
		/* An identifier the transcript does not hold marks its first line,
		 which is where a query that opened unseen carries the marker. */
		logView.setUnreadMarker(.line("missing"))

		logView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = logView
		logView.layoutSubtreeIfNeeded()
		logView.displayIfNeeded()

		let scrollView = try #require(descendants(of: NSScrollView.self, in: logView).first)
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
		let firstRow = try #require(firstDrawnRowFraction(in: logView))
		#expect(firstRow > 0.6, "first drawn row at \(firstRow) of the height")
	}

	@Test("A long transcript uses ordinary top-aligned scrolling")
	func longTranscriptUsesNormalScrolling() throws {
		let client = Client(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(client: client, in: window)
		let logView = controller.ensureBackingView()
		logView.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = logView
		logView.replaceLines((0 ..< 100).map { transcriptLine("message \($0)") })
		logView.layoutSubtreeIfNeeded()

		let scrollView = try #require(descendants(of: NSScrollView.self, in: logView).first)
		let textView = try #require(scrollView.documentView as? NSTextView)
		let layoutManager = try #require(textView.textLayoutManager)
		layoutManager.ensureLayout(for: layoutManager.documentRange)

		#expect(textView.textContainerOrigin.y == textView.textContainerInset.height)
	}

	@Test("The current-session marker draws a full-width native separator")
	func currentSessionMarkerHasFullWidthSeparator() throws {
		let client = Client(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(client: client, in: window)
		let logView = controller.ensureBackingView()
		var liveLine = transcriptLine("live")
		liveLine.markers = [.currentSession("Current Session")]

		logView.replaceLines([transcriptLine("history"), liveLine])

		let scrollView = try #require(descendants(of: NSScrollView.self, in: logView).first)
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
		#expect(try ruleIsDrawn(for: markerRange.location, in: logView, textView: textView))
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
		let client = Client(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(client: client, in: window)
		let logView = controller.ensureBackingView()
		var unreadLine = transcriptLine("unread")
		unreadLine.markers = [.unread("Unread messages")]

		logView.replaceLines([transcriptLine("read"), unreadLine])

		let scrollView = try #require(descendants(of: NSScrollView.self, in: logView).first)
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
		#expect(try ruleIsDrawn(for: markerRange.location, in: logView, textView: textView))
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
		transcript.logView.setTopic("Short topic")
		transcript.logView.setTextScale(scale)
		transcript.window.contentView?.layoutSubtreeIfNeeded()

		#expect(transcript.logView.topicField.isHidden == false)
		#expect(transcript.logView.topicDisclosure.isHidden)
	}

	/// A topic too long for the column keeps its chevron, whatever the scale:
	/// the fix must not have turned the disclosure off altogether.
	@Test("A topic that does not fit keeps its chevron", arguments: [1.0, 2.0] as [CGFloat])
	func wrappingTopicKeepsItsChevron(scale: CGFloat) {
		let transcript = makeTranscript(width: 400)
		transcript.logView.setTopic(String(repeating: "a long topic that cannot fit on one line ", count: 6))
		transcript.logView.setTextScale(scale)
		transcript.window.contentView?.layoutSubtreeIfNeeded()

		#expect(transcript.logView.topicDisclosure.isHidden == false)
	}

	/** The profile used to wait out the double-click interval before opening,
	 which follows the reader's Double-click speed and can be seconds. It
	 opens on the click now; the double click that opens a conversation takes
	 it down. */
	@Test("A click on a name opens the profile at once")
	func clickingANameOpensTheProfileAtOnce() throws {
		let transcript = makeTranscript(width: 800, withMember: "alice")
		transcript.logView.replaceLines([transcriptLine("hello there")])
		transcript.window.contentView?.layoutSubtreeIfNeeded()

		try clickNickname(in: transcript)
		#expect(transcript.logView.memberInformationPopover != nil)
	}

	/// Clearing and trimming remove the characters the popover is anchored
	/// to, so they take it down rather than leave it pointing at other text.
	@Test("Clearing the transcript closes the profile popover")
	func clearingClosesTheProfilePopover() throws {
		let transcript = makeTranscript(width: 800, withMember: "alice")
		transcript.logView.replaceLines([transcriptLine("hello there")])
		transcript.window.contentView?.layoutSubtreeIfNeeded()

		try clickNickname(in: transcript)
		#expect(transcript.logView.memberInformationPopover != nil)

		transcript.logView.clearLines()
		#expect(transcript.logView.memberInformationPopover == nil)
	}

	/// A transcript that leaves its window has nothing to anchor a popover to.
	@Test("Leaving the window closes the profile popover")
	func leavingTheWindowClosesTheProfilePopover() throws {
		let transcript = makeTranscript(width: 800, withMember: "alice")
		transcript.logView.replaceLines([transcriptLine("hello there")])
		transcript.window.contentView?.layoutSubtreeIfNeeded()

		try clickNickname(in: transcript)
		#expect(transcript.logView.memberInformationPopover != nil)

		transcript.logView.removeFromSuperview()
		#expect(transcript.logView.memberInformationPopover == nil)
	}

	private struct Transcript {
		let window: MainWindow
		let logView: TranscriptView
		/// Held here because the view, the controller and the channel hold
		/// the controller, the channel and the client weakly.
		let controller: TranscriptController
		let client: Client
		let channel: Channel?
	}

	/// A transcript over a channel when `member` is given, so a click on that
	/// name has a profile to show; over the connection alone otherwise.
	private func makeTranscript(width: CGFloat, withMember member: String? = nil) -> Transcript {
		let client = Client(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller: TranscriptController
		var channel: Channel?
		if let member {
			let profileChannel = Channel(config: ChannelConfig(channelName: "#profile"))
			profileChannel.associatedClient = client
			profileChannel.activate()
			profileChannel.addMember(
				ChannelUser(user: client.findUserOrCreate(member), prefixes: client.currentUserPrefixes)
			)
			controller = TranscriptController(channel: profileChannel, in: window)
			channel = profileChannel
		} else {
			controller = TranscriptController(client: client, in: window)
		}
		let logView = controller.ensureBackingView()
		let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 600))
		container.addSubview(logView)
		NSLayoutConstraint.activate([
			logView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			logView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			logView.topAnchor.constraint(equalTo: container.topAnchor),
			logView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
		])
		window.contentView = container
		container.layoutSubtreeIfNeeded()
		return Transcript(window: window, logView: logView, controller: controller, client: client, channel: channel)
	}

	/// Clicks the middle of the first nickname the transcript drew, the way the
	/// text view reports a click of its own.
	private func clickNickname(in transcript: Transcript) throws {
		let textView = transcript.logView.textView
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
