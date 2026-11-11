// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// A display name is drawn beside the nickname, never instead of it, and copy
/// yields the nickname as a log does.
@MainActor
@Suite("Transcript sender profiles", .serialized)
struct TranscriptSenderProfileTests {
	private func withTranscript(
		profiles: [String: TranscriptSenderProfile],
		_ body: (TranscriptView) throws -> Void
	) throws {
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless, backing: .buffered, defer: false
		)
		window.isReleasedWhenClosed = false
		defer { window.close() }
		let conversation = Conversation(config: ConversationConfig(name: "#swift"))
		let controller = TranscriptController(conversation: conversation, in: window)
		let transcript = controller.ensureBackingView()
		window.contentView = transcript
		transcript.senderProfile = { profiles[$0] }
		transcript.appendLines([line("alice", number: "1"), line("bob", number: "2")])
		try withExtendedLifetime((controller, conversation)) {
			try body(transcript)
		}
	}

	private func line(_ nickname: String, number: String) -> TranscriptRow {
		TranscriptRow(
			lineNumber: number, receivedAt: Date(timeIntervalSince1970: 0),
			nickname: nickname, memberType: .normal, lineType: .privateMessage, command: "PRIVMSG",
			messageIdentifier: "message-\(number)", replyToMessageIdentifier: nil,
			deliveryState: .none, deliveryFailureReason: nil, reactions: [:], markers: [],
			body: TranscriptBody(plainText: "hello", runs: [TranscriptTextRun(text: "hello")])
		)
	}

	@Test("The header holds the display name and the nickname, each isolated")
	func headerText() throws {
		try withTranscript(profiles: ["alice": TranscriptSenderProfile(displayName: "علي Alice")]) { transcript in
			let text = transcript.textView.string
			let isolatedName = "\(TranscriptIsolate.isolateStart)علي Alice\(TranscriptIsolate.isolateEnd)"
			let nameRange = try #require(text.range(of: isolatedName))

			#expect(text[nameRange.upperBound...].hasPrefix("\u{2009}\(TranscriptIsolate.isolateStart)"))
			#expect(text[nameRange.upperBound...].contains("alice"))
		}
	}

	@Test("Copying a line yields the nickname, not the display name")
	func copyYieldsNickname() throws {
		try withTranscript(profiles: ["alice": TranscriptSenderProfile(displayName: "Alice Liddell")]) { transcript in
			let textView = transcript.textView
			textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))
			let pasteboard = NSPasteboard(name: NSPasteboard.Name("transcript-sender-\(UUID().uuidString)"))
			defer { pasteboard.releaseGlobally() }

			#expect(textView.writeSelection(to: pasteboard, type: .string))
			let copied = try #require(pasteboard.string(forType: .string))
			#expect(copied.contains("alice"))
			#expect(copied.contains("Alice Liddell") == false)
		}
	}

	@Test("A screen reader hears the display name and the nickname together")
	func accessibilityText() throws {
		try withTranscript(profiles: ["alice": TranscriptSenderProfile(displayName: "Alice Liddell")]) { transcript in
			let storage = try #require(transcript.textView.textStorage)
			var spoken: [String] = []
			storage.enumerateAttribute(.accessibilityCustomText, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
				spoken += value as? [String] ?? []
			}

			#expect(spoken.contains(String(localized: .Transcript.senderWithDisplayName("Alice Liddell", "alice"))))
		}
	}

	@Test("Restyling redraws only the matching senders")
	func restyleMatchingRows() throws {
		var profiles: [String: TranscriptSenderProfile] = [:]
		try withTranscript(profiles: [:]) { transcript in
			transcript.senderProfile = { profiles[$0] }
			profiles["bob"] = TranscriptSenderProfile(displayName: "Robert")
			profiles["alice"] = TranscriptSenderProfile(displayName: "Alicia")

			transcript.restyleSenders(["bob"]) { $0.lowercased() }

			#expect(transcript.textView.string.contains("Robert"))
			#expect(transcript.textView.string.contains("Alicia") == false)
		}
	}
}
