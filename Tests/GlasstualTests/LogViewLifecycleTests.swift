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
			timestamp: "12:00",
			nickname: "alice",
			formattedNickname: "alice",
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
	func connectingTopicAppearsInHeader() async throws {
		let fixture = GLTClientEnvironmentFixture()
		let client = fixture.world.createClient(with: ClientConfig(), reload: false)
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
		await Task.yield()
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

		let block = try #require(paragraph.textBlocks.first)
		#expect(block.contentWidth == 100)
		#expect(block.contentWidthValueType == .percentageValueType)
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
		let block = try #require(paragraph.textBlocks.first)
		#expect(block.contentWidth == 100)
		#expect(block.contentWidthValueType == .percentageValueType)
	}
}

private extension NSAttributedString {
	var fullRange: NSRange {
		NSRange(location: 0, length: length)
	}
}
