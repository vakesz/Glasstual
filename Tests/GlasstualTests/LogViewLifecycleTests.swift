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
struct LogViewLifecycleTests {
	private func descendants<View: NSView>(of type: View.Type, in root: NSView) -> [View] {
		root.subviews.flatMap { view in
			(view as? View).map { [$0] } ?? descendants(of: type, in: view)
		}
	}

	private func transcriptLine(_ text: String) -> TranscriptLine {
		TranscriptLine(
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

	@Test("The transcript is a native AppKit view")
	func transcriptUsesAppKit() {
		let client = IRCClient(config: ClientConfig())
		let window = MainWindow(
			contentRect: .zero,
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = LogController(client: client, in: window)
		let logView = controller.ensureBackingView()

		#expect(logView.view.subviews.isEmpty == false)
		#expect(logView.view.window == nil)
	}

	@Test("The view keeps only a weak controller reference")
	func controllerCanDeallocate() throws {
		let client = IRCClient(config: ClientConfig())
		let window = MainWindow(
			contentRect: .zero,
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		var controller: LogController? = LogController(client: client, in: window)
		let logView = try #require(controller?.ensureBackingView())
		weak let weakController = controller

		controller = nil

		#expect(weakController == nil)
		#expect(logView.viewController == nil)
	}

	@Test("A topic received while connecting is fixed above the transcript")
	func connectingTopicAppearsInHeader() throws {
		let fixture = GLTClientEnvironmentFixture()
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
		let host = NSHostingController(rootView: MainWindowTranscriptRepresentable(logView: logView))
		host.preferredContentSize = NSSize(width: 800, height: 600)
		window.contentViewController = host
		window.setContentSize(NSSize(width: 800, height: 600))

		channel.topic = "Native AppKit discussion"
		window.contentView?.layoutSubtreeIfNeeded()
		host.view.layoutSubtreeIfNeeded()

		let topicField = try #require(
			descendants(of: NSTextField.self, in: logView.view)
				.first { $0.stringValue == "Native AppKit discussion" }
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
		let client = IRCClient(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = LogController(client: client, in: window)
		let logView = controller.ensureBackingView()
		logView.setTopic(topic)
		logView.replaceLines([transcriptLine("hello there")])
		let hostingView = NSHostingView(rootView: MainWindowTranscriptRepresentable(logView: logView))
		hostingView.sizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
		hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = hostingView
		hostingView.layoutSubtreeIfNeeded()

		let minimum = hostingView.fittingSize
		let ideal = hostingView.intrinsicContentSize
		let frame = logView.view.convert(logView.view.bounds, to: hostingView)
		let columnMinimum = MainWindowConstants.conversationMinimumWidth
		#expect(minimum.width <= columnMinimum, "minimum \(minimum) fitting \(logView.view.fittingSize)")
		#expect(ideal.width >= columnMinimum, "ideal \(ideal) fitting \(logView.view.fittingSize)")
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
		let fixture = GLTClientEnvironmentFixture()
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
		window.presentationModel.isMemberListAvailable = false
		logView.setTopic("Native AppKit discussion")
		logView.replaceLines([transcriptLine("hello there")])
		window.contentView?.layoutSubtreeIfNeeded()
		let frameAlone = logView.view.convert(logView.view.bounds, to: host.view)

		window.presentationModel.isMemberListAvailable = true
		window.presentationModel.isMemberListVisible = true
		window.contentView?.layoutSubtreeIfNeeded()
		host.view.layoutSubtreeIfNeeded()

		let rootFrame = host.view.frame
		let transcriptFrame = logView.view.convert(logView.view.bounds, to: host.view)
		#expect(transcriptFrame.minX >= 0, "transcript \(transcriptFrame) root \(rootFrame)")
		#expect(transcriptFrame.maxX <= rootFrame.width + 0.5, "transcript \(transcriptFrame) root \(rootFrame)")
		#expect(transcriptFrame.width >= MainWindowConstants.conversationMinimumWidth, "transcript \(transcriptFrame)")
		#expect(
			rootFrame.width - transcriptFrame.maxX >= MainWindowConstants.memberListMinimumWidth,
			"transcript \(transcriptFrame) leaves no room in \(rootFrame)"
		)

		/* The bar floats over the transcript, and the inset is what keeps the
		 last line out from under it. */
		let scrollView = try #require(descendants(of: NSScrollView.self, in: logView.view).first)
		let field = window.inputContentView.frame
		let barHeight = field.height + MainWindowInputBarLayout.fieldVerticalPadding * 2
			+ MainWindowInputBarLayout.bottomPadding
		let inset = scrollView.contentInsets.bottom
		#expect(abs(inset - barHeight) < 1, "inset \(inset) bar \(barHeight)")

		window.presentationModel.isMemberListVisible = false
		window.contentView?.layoutSubtreeIfNeeded()
		host.view.layoutSubtreeIfNeeded()
		let frameAgain = logView.view.convert(logView.view.bounds, to: host.view)
		#expect(abs(frameAgain.width - frameAlone.width) < 1, "alone \(frameAlone) again \(frameAgain)")
	}

	@Test("Links in the topic are native clickable links")
	func topicLinksAreClickable() throws {
		let client = IRCClient(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = LogController(client: client, in: window)
		let logView = controller.ensureBackingView()
		let topic = "Project https://example.com and docs.example.org/guide"

		logView.setTopic(topic)

		let topicField = try #require(
			descendants(of: NSTextField.self, in: logView.view)
				.first { $0.stringValue == topic }
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
		let client = IRCClient(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = LogController(client: client, in: window)
		let logView = controller.ensureBackingView()
		logView.view.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = logView.view
		logView.view.layoutSubtreeIfNeeded()

		let scrollView = try #require(descendants(of: NSScrollView.self, in: logView.view).first)
		let allTopicFieldsHidden = descendants(of: NSTextField.self, in: logView.view).allSatisfy(\.isHidden)
		#expect(scrollView.frame.maxY == logView.view.bounds.maxY)
		#expect(allTopicFieldsHidden)
	}

	@Test("A short transcript starts at the bottom and grows upward")
	func shortTranscriptIsBottomAnchored() throws {
		let client = IRCClient(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = LogController(client: client, in: window)
		let logView = controller.ensureBackingView()
		logView.view.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = logView.view
		logView.replaceLines([transcriptLine("hello")])
		logView.view.layoutSubtreeIfNeeded()

		let scrollView = try #require(descendants(of: NSScrollView.self, in: logView.view).first)
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
	private func ruleIsDrawn(for location: Int, in logView: LogView, textView: NSTextView) throws -> Bool {
		let window = try #require(logView.view.window ?? {
			let window = MainWindow(
				contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
				styleMask: .borderless,
				backing: .buffered,
				defer: false
			)
			logView.view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
			window.contentView = logView.view
			return window
		}())
		_ = window
		logView.view.layoutSubtreeIfNeeded()
		logView.view.displayIfNeeded()
		let layoutManager = try #require(textView.textLayoutManager)
		let storage = try #require(textView.textStorage)
		let inset = try #require(
			storage.attribute(.transcriptRuleInset, at: location, effectiveRange: nil) as? NSNumber
		)
		let start = try #require(layoutManager.location(layoutManager.documentRange.location, offsetBy: location))
		let fragment = try #require(layoutManager.textLayoutFragment(for: start))
		let origin = textView.textContainerOrigin
		let ruleY = fragment.layoutFragmentFrame.minY + origin.y + CGFloat(inset.doubleValue)
		let view = logView.view
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
		logView.replaceLines([transcriptLine("hello"), transcriptLine("there")])
		logView.view.layoutSubtreeIfNeeded()
		logView.view.displayIfNeeded()

		let firstRow = try #require(firstDrawnRowFraction(in: logView.view))
		#expect(firstRow > 0.6, "first drawn row at \(firstRow) of the height")
	}

	/** A query opens with lines already in it: the identification exchange is
	 printed before the view is ever shown. Those lines belong at the foot too,
	 once the view lands in the window. */
	@Test("Lines received before the view is shown still draw at the foot")
	func hiddenTranscriptDrawsAtTheBottomOnceShown() throws {
		let client = IRCClient(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = LogController(client: client, in: window)
		let logView = controller.ensureBackingView()
		logView.appendLines([transcriptLine("hello")])
		logView.appendLines([transcriptLine("there")])

		logView.view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = logView.view
		logView.view.layoutSubtreeIfNeeded()
		logView.view.displayIfNeeded()

		let firstRow = try #require(firstDrawnRowFraction(in: logView.view))
		#expect(firstRow > 0.6, "first drawn row at \(firstRow) of the height")
	}

	/** A query that opened while another view was selected carries the unread
	 hairline above its first line. The marker's block spans the container's
	 width, and it must not make the short transcript read as taller than the
	 viewport. */
	@Test("A short transcript with an unread marker still draws at the foot")
	func shortTranscriptWithUnreadMarkerDrawsAtTheBottom() throws {
		let client = IRCClient(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = LogController(client: client, in: window)
		let logView = controller.ensureBackingView()
		logView.appendLines([transcriptLine("hello"), transcriptLine("there")])
		/* An identifier the transcript does not hold marks its first line,
		 which is where a query that opened unseen carries the marker. */
		logView.setUnreadMarker(.line("missing"))

		logView.view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = logView.view
		logView.view.layoutSubtreeIfNeeded()
		logView.view.displayIfNeeded()

		let scrollView = try #require(descendants(of: NSScrollView.self, in: logView.view).first)
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
		let firstRow = try #require(firstDrawnRowFraction(in: logView.view))
		#expect(firstRow > 0.6, "first drawn row at \(firstRow) of the height")
	}

	@Test("A long transcript uses ordinary top-aligned scrolling")
	func longTranscriptUsesNormalScrolling() throws {
		let client = IRCClient(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = LogController(client: client, in: window)
		let logView = controller.ensureBackingView()
		logView.view.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = logView.view
		logView.replaceLines((0 ..< 100).map { transcriptLine("message \($0)") })
		logView.view.layoutSubtreeIfNeeded()

		let scrollView = try #require(descendants(of: NSScrollView.self, in: logView.view).first)
		let textView = try #require(scrollView.documentView as? NSTextView)
		let layoutManager = try #require(textView.textLayoutManager)
		layoutManager.ensureLayout(for: layoutManager.documentRange)

		#expect(textView.textContainerOrigin.y == textView.textContainerInset.height)
	}

	@Test("The current-session marker draws a full-width native separator")
	func currentSessionMarkerHasFullWidthSeparator() throws {
		let client = IRCClient(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = LogController(client: client, in: window)
		let logView = controller.ensureBackingView()
		var liveLine = transcriptLine("live")
		liveLine.markers = [.currentSession("Current Session")]

		logView.replaceLines([transcriptLine("history"), liveLine])

		let scrollView = try #require(descendants(of: NSScrollView.self, in: logView.view).first)
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
		let client = IRCClient(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = LogController(client: client, in: window)
		let logView = controller.ensureBackingView()
		var unreadLine = transcriptLine("unread")
		unreadLine.markers = [.unread("Unread messages")]

		logView.replaceLines([transcriptLine("read"), unreadLine])

		let scrollView = try #require(descendants(of: NSScrollView.self, in: logView.view).first)
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
	func oneLineTopicHasNoChevron(scale: CGFloat) throws {
		let transcript = try makeTranscript(width: 800)
		transcript.logView.setTopic("Short topic")
		transcript.logView.setTextScale(scale)
		transcript.window.contentView?.layoutSubtreeIfNeeded()

		#expect(transcript.view.topicField.isHidden == false)
		#expect(transcript.view.topicDisclosure.isHidden)
	}

	/// A topic too long for the column keeps its chevron, whatever the scale:
	/// the fix must not have turned the disclosure off altogether.
	@Test("A topic that does not fit keeps its chevron", arguments: [1.0, 2.0] as [CGFloat])
	func wrappingTopicKeepsItsChevron(scale: CGFloat) throws {
		let transcript = try makeTranscript(width: 400)
		transcript.logView.setTopic(String(repeating: "a long topic that cannot fit on one line ", count: 6))
		transcript.logView.setTextScale(scale)
		transcript.window.contentView?.layoutSubtreeIfNeeded()

		#expect(transcript.view.topicDisclosure.isHidden == false)
	}

	/** The popover a single click asks for is anchored to characters, so any
	 edit that can move them has to call the click off.

	 It used to be cancelled only by another click: a line arriving during the
	 double-click interval left the popover to open a quarter of a second later
	 against whatever text had taken that range. */
	@Test("An edit during the double-click wait calls off the profile popover")
	func appendingCancelsThePendingProfileClick() throws {
		let transcript = try makeTranscript(width: 800)
		transcript.logView.replaceLines([transcriptLine("hello there")])
		transcript.window.contentView?.layoutSubtreeIfNeeded()

		try clickNickname(in: transcript)
		#expect(transcript.view.hasPendingNicknameClick)

		transcript.logView.appendLines([transcriptLine("and another line")])
		#expect(transcript.view.hasPendingNicknameClick == false)
	}

	/// Clearing and trimming reach the same characters, and the batch every
	/// edit runs inside is where the click is called off.
	@Test("Clearing the transcript calls off the pending profile popover")
	func clearingCancelsThePendingProfileClick() throws {
		let transcript = try makeTranscript(width: 800)
		transcript.logView.replaceLines([transcriptLine("hello there")])
		transcript.window.contentView?.layoutSubtreeIfNeeded()

		try clickNickname(in: transcript)
		#expect(transcript.view.hasPendingNicknameClick)

		transcript.logView.clearLines()
		#expect(transcript.view.hasPendingNicknameClick == false)
	}

	/// A transcript that leaves its window has nothing to anchor a popover to.
	@Test("Leaving the window calls off the pending profile popover")
	func leavingTheWindowCancelsThePendingProfileClick() throws {
		let transcript = try makeTranscript(width: 800)
		transcript.logView.replaceLines([transcriptLine("hello there")])
		transcript.window.contentView?.layoutSubtreeIfNeeded()

		try clickNickname(in: transcript)
		#expect(transcript.view.hasPendingNicknameClick)

		transcript.view.removeFromSuperview()
		#expect(transcript.view.hasPendingNicknameClick == false)
	}

	private struct Transcript {
		let window: MainWindow
		let logView: LogView
		let view: NativeTranscriptView
	}

	private func makeTranscript(width: CGFloat) throws -> Transcript {
		let client = IRCClient(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = LogController(client: client, in: window)
		let logView = controller.ensureBackingView()
		let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 600))
		container.addSubview(logView.view)
		NSLayoutConstraint.activate([
			logView.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			logView.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			logView.view.topAnchor.constraint(equalTo: container.topAnchor),
			logView.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
		])
		window.contentView = container
		container.layoutSubtreeIfNeeded()
		return try Transcript(
			window: window,
			logView: logView,
			view: #require(logView.view as? NativeTranscriptView)
		)
	}

	/// Clicks the middle of the first nickname the transcript drew, the way the
	/// text view reports a click of its own.
	private func clickNickname(in transcript: Transcript) throws {
		let textView = transcript.view.textView
		let storage = try #require(textView.textStorage)
		var nicknameRange: NSRange?
		storage.enumerateAttribute(
			.transcriptAction,
			in: NSRange(location: 0, length: storage.length)
		) { value, range, stop in
			if case .nickname = TranscriptAction(attributeValue: value) {
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
