// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// What the transcript shows and hands back, as opposed to how it stores it:
/// the topic bar, the unread boundary, the highlight count and what a copy
/// puts on the pasteboard.
@MainActor
@Suite("Transcript presentation")
struct TranscriptPresentationTests {
	/** The topic arrives in the same wire form a message does. It used to be
	 drawn as it arrived, so a coloured topic put its control codes in the bar,
	 in the tooltip and on the pasteboard. */
	@Test("The topic bar draws IRC formatting rather than the codes that carry it")
	func topicBarRendersIRCFormatting() throws {
		let transcriptView = makeTranscriptView()
		transcriptView.setTopic("\u{02}bold\u{02} and \u{03}04red\u{03} plain")

		let topic = transcriptView.topicField.attributedStringValue
		#expect(visibleTranscriptText(topic) == "bold and red plain")
		#expect(transcriptView.topicField.toolTip == "bold and red plain")

		let boldRange = (topic.string as NSString).range(of: "bold")
		let boldFont = try #require(topic.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont)
		#expect(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))
	}

	/// A link in a topic is located in the text as drawn; a scan of the wire
	/// form counts the control codes too, and lands the range on the wrong
	/// characters.
	@Test("A link in a formatted topic is attached to the words that spell it")
	func topicLinkRangeFollowsTheRenderedText() throws {
		let transcriptView = makeTranscriptView()
		transcriptView.setTopic("\u{02}rules\u{02} at https://example.com/rules")

		let topic = transcriptView.topicField.attributedStringValue
		let visibleURL = (topic.string as NSString).range(of: "https://example.com/rules")
		try #require(visibleURL.location != NSNotFound)
		var linkRange = NSRange(location: NSNotFound, length: 0)
		let url = topic.attribute(.link, at: visibleURL.location, effectiveRange: &linkRange) as? URL
		#expect(url?.absoluteString == "https://example.com/rules")
		#expect((topic.string as NSString).substring(with: linkRange) == "https://example.com/rules")
		#expect(topic.attribute(.link, at: topic.length - 1, effectiveRange: nil) == nil)
	}

	/** The boundary is a claim about where the reader stopped reading, and the
	 buffer only ever trims its oldest lines: a marked line it no longer holds
	 is older than everything on screen, so the boundary belongs above all of
	 it rather than nowhere. */
	@Test("An unread boundary lands on its line, or above the whole buffer when that line is gone")
	func unreadMarkerFallsBackToTheOldestLine() {
		let transcriptView = makeTranscriptView()
		transcriptView.replaceLines([line("one"), line("two")])

		transcriptView.setUnreadMarker(.line("two"))
		#expect(transcriptView.displayedLines.last?.markers.contains(where: \.isUnread) == true)

		transcriptView.setUnreadMarker(.line("trimmed-away"))
		#expect(transcriptView.displayedLines.first?.markers.contains(where: \.isUnread) == true)
		#expect(transcriptView.displayedLines.last?.markers.contains(where: \.isUnread) == false)
	}

	/// The menu asks on every validation pass, so the transcript counts as it
	/// is edited instead of walking the whole scrollback for an answer.
	@Test("The highlight count follows what the document holds")
	func highlightCountFollowsTheDocument() {
		let transcriptView = makeTranscriptView(bufferLimit: 2)
		#expect(transcriptView.hasHighlightedLines == false)

		transcriptView.appendLines([line("plain"), line("shouted", isHighlight: true)])
		#expect(transcriptView.hasHighlightedLines)

		// The highlight is the older of the two once the buffer trims.
		transcriptView.appendLines([line("after"), line("later")])
		#expect(transcriptView.hasHighlightedLines == false)

		transcriptView.clearLines()
		#expect(transcriptView.hasHighlightedLines == false)
	}

	/// A restored row answers to the history row it came back from as well as
	/// to the line number it was printed with, so a message the reader has
	/// already seen is not drawn again beside its restored self.
	@Test("A restored row is found under both identifiers it answers to")
	func restoredRowsAnswerToBothIdentifiers() {
		let transcriptView = makeTranscriptView()
		var restored = line("row-uri")
		restored.historyCursor = ScrollbackRowCursor(
			timestamp: 0,
			insertionIdentifier: 1,
			lineIdentifier: "printed-line",
			rowURI: "row-uri"
		)
		transcriptView.replaceLines([restored])

		#expect(transcriptView.containsLine(identifier: "row-uri"))
		#expect(transcriptView.containsLine(identifier: "printed-line"))
		#expect(transcriptView.containsLine(identifier: "something-else") == false)

		transcriptView.clearLines()
		#expect(transcriptView.containsLine(identifier: "printed-line") == false)
	}

	/** The window subtitle no longer carries the channel's modes, so the topic
	 bar does. It is a caption rather than part of the topic: nobody set it, so
	 neither the tooltip nor Copy Topic answers with it. */
	@Test("The topic bar captions the topic with the channel's modes, and copies only the topic")
	func topicBarCaptionsChannelModes() throws {
		let client = Client(config: ClientConfig())
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		/* Built here rather than asked of the client: `findChannelOrCreate` goes
		 through the world, which a client made for one test does not have. */
		let channel = Channel(config: ChannelConfig(channelName: "#modes"))
		channel.associatedClient = client
		channel.activate()
		_ = try #require(channel.modeInfo).updateModes("+ntk secret")

		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		/* The view holds its controller weakly, so the controller has to outlive
		 the assertions for the bar to have a channel to read modes from. */
		let controller = TranscriptController(channel: channel, in: window)
		let transcriptView = controller.ensureBackingView()
		transcriptView.setTopic("House rules")

		let drawn = visibleTranscriptText(transcriptView.topicField.attributedStringValue)
		#expect(drawn.hasPrefix("House rules"))
		#expect(drawn.hasSuffix("+knt ******"))
		/* The key never reaches the bar, only the mask. */
		#expect(drawn.contains("secret") == false)
		#expect(transcriptView.topicField.toolTip == "House rules")
		#expect(transcriptView.copyableTopic == "House rules")
	}

	/// A channel whose modes are not known yet draws the topic and nothing else.
	@Test("A view with no modes captions nothing")
	func topicBarWithoutModesDrawsTheTopicAlone() {
		let transcriptView = makeTranscriptView()
		transcriptView.setTopic("House rules")

		#expect(visibleTranscriptText(transcriptView.topicField.attributedStringValue) == "House rules")
	}

	private func makeTranscriptView(bufferLimit: Int = 1000) -> TranscriptView {
		let client = Client(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(client: client, in: window)
		let transcriptView = controller.ensureBackingView()
		transcriptView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = transcriptView
		transcriptView.setBufferLimit(bufferLimit)
		return transcriptView
	}

	private func line(_ text: String, isHighlight: Bool = false) -> TranscriptRow {
		TranscriptRow(
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
			body: TranscriptBody(
				plainText: text,
				runs: [TranscriptTextRun(text: text)],
				isHighlight: isHighlight
			)
		)
	}
}
