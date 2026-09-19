// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
struct TranscriptViewSelectionTests {
	@Test("Clearing selected text clears the transcript's cached selection")
	func clearingRemovesSelection() throws {
		try withSelectedTranscript { view in
			view.clearLines()
			#expect(view.textView.selectedRange().length == 0)
			#expect(view.hasSelection == false)
			#expect(view.selection == nil)
		}
	}

	@Test("Trimming one selected endpoint does not select the surviving remainder")
	func trimmingSelectedEndpointClearsSelection() throws {
		try withSelectedTranscript { view in
			let text = view.textView.string as NSString
			let start = text.range(of: "first body").location
			let end = NSMaxRange(text.range(of: "second body"))
			view.textView.setSelectedRange(NSRange(location: start, length: end - start))
			view.appendLines([line("third body")])
			#expect(view.displayedLines.map(\.lineNumber) == ["second body", "third body"])
			#expect(view.textView.selectedRange().length == 0)
			#expect(view.hasSelection == false)
		}
	}

	@Test("Removing a selected unread marker does not move selection into the message header")
	func removingSelectedSegmentClearsSelection() throws {
		try withSelectedTranscript { view in
			view.setUnreadMarker(.line("first body"))
			let marker = (view.textView.string as NSString).range(of: String(localized: .Transcript.unreadMessages))
			try #require(marker.location != NSNotFound)
			view.textView.setSelectedRange(marker)
			view.setUnreadMarker(.none)
			#expect(view.textView.selectedRange().length == 0)
			#expect(view.hasSelection == false)
		}
	}

	private func withSelectedTranscript(_ body: (TranscriptView) throws -> Void) throws {
		let copyOnSelect = SettingsKeys.Messages.copyOnSelect.value
		defer { SettingsKeys.Messages.copyOnSelect.value = copyOnSelect }
		SettingsKeys.Messages.copyOnSelect.value = false
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
		let controller = TranscriptController(session: session, in: window)
		let view = controller.ensureBackingView()
		view.setBufferLimit(2)
		view.appendLines([line("first body"), line("second body")])
		view.textView.setSelectedRange((view.textView.string as NSString).range(of: "first body"))
		view.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
		try #require(view.hasSelection)
		try body(view)
	}

	private func line(_ text: String) -> TranscriptRow {
		TranscriptRow(
			lineNumber: text,
			receivedAt: Date(timeIntervalSince1970: 0),
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
			body: TranscriptBody(plainText: text, runs: [TranscriptTextRun(text: text)])
		)
	}
}
