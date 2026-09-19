// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/** Which keys the transcript hands to the input field.

 Focusing the transcript is how a reader moves back through it, so every key
 that moves a document has to stay with the text view; only text the reader is
 starting to type belongs in the input field. */
@Suite("Transcript view key routing")
struct TranscriptViewKeyRoutingTests {
	@MainActor
	@Test("Paging away from the newest message stops incoming messages from scrolling back")
	func keyboardPagingStopsBottomFollowing() throws {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(session: session, in: window)
		let view = controller.ensureBackingView()
		view.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
		window.contentView = view
		let rows = (0 ..< 80).map { index in
			TranscriptRow(
				lineNumber: String(index), receivedAt: Date(timeIntervalSince1970: 0), nickname: "alice",
				memberType: .normal, lineType: .privateMessage, command: "PRIVMSG", messageIdentifier: nil,
				replyToMessageIdentifier: nil, deliveryState: .none, deliveryFailureReason: nil,
				reactions: [:], markers: [],
				body: TranscriptBody(plainText: "message \(index)", runs: [TranscriptTextRun(text: "message \(index)")])
			)
		}
		view.appendLines(Array(rows.dropLast()))
		view.layoutSubtreeIfNeeded()
		let layoutManager = try #require(view.textView.textLayoutManager)
		layoutManager.ensureLayout(for: layoutManager.documentRange)
		view.textView.sizeToFit()
		view.scrollToBottom()
		let previousTop = view.scrollView.contentView.bounds.minY
		let pageUp = try #require(NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
			context: nil, characters: "\u{f72c}", charactersIgnoringModifiers: "\u{f72c}", isARepeat: false,
			keyCode: 0x74
		))

		view.textView.keyDown(with: pageUp)

		try #require(view.scrollView.contentView.bounds.minY < previousTop)
		#expect(view.followsBottom == false)
		#expect(view.scrollsToBottomOnLayout == false)
		view.appendLines([try #require(rows.last)])
		#expect(view.isNearBottom == false)
	}

	@Test("Typed text is sent to the input field")
	func typedTextGoesToTheInputField() {
		for characters in ["a", "Z", "7", "/", "\u{00E9}", "\u{1F600}"] {
			#expect(TranscriptView.isTextInput(characters))
		}
	}

	@Test("The keys that move a document stay with the transcript")
	func navigationKeysStayWithTheTranscript() {
		let navigation: [String?] = [
			NSUpArrowFunctionKey, NSDownArrowFunctionKey, NSLeftArrowFunctionKey, NSRightArrowFunctionKey,
			NSPageUpFunctionKey, NSPageDownFunctionKey, NSHomeFunctionKey, NSEndFunctionKey,
		].compactMap { UnicodeScalar(UInt32($0)).map { String($0) } }
		for characters in navigation + [" ", "", nil] {
			#expect(TranscriptView.isTextInput(characters) == false)
		}
	}
}
