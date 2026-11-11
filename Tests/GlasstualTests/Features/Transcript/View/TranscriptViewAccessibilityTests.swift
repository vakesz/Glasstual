// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// Channel names and nicknames in the transcript are activated with a double
/// click, which a screen reader moving the text cursor cannot make. The text
/// view offers the same commands as custom actions on the selection.
@MainActor
@Suite("Transcript name accessibility actions", .serialized)
struct TranscriptViewAccessibilityTests {
	private final class Recorder {
		var joined: [String] = []
		var opened: [String] = []
	}

	private func actionNames(of transcript: TranscriptView) -> [String] {
		(transcript.textView.accessibilityCustomActions() ?? []).map(\.name)
	}

	private func select(_ text: String, in transcript: TranscriptView) throws {
		let range = (transcript.textView.string as NSString).range(of: text)
		try #require(range.location != NSNotFound)
		transcript.textView.setSelectedRange(range)
	}

	@Test("A selected channel name offers to join it")
	func channelOffersJoin() throws {
		try withTranscript { transcript, _ in
			try select("#swift", in: transcript)
			let names = actionNames(of: transcript)
			#expect(names == [String(localized: .Transcript.joinChannelAction("#swift"))])
		}
	}

	@Test("A selected nickname offers the configured double-click action")
	func nicknameOffersTheConfiguredAction() throws {
		let setting = SettingsKeys.Input.userDoubleClickAction
		let saved = setting.value
		defer { setting.value = saved }
		try withTranscript { transcript, _ in
			try select("bob", in: transcript)
			setting.value = .startDirectConversation
			#expect(actionNames(of: transcript).contains(String(localized: .Transcript.openConversationNicknameAction("bob"))))
			setting.value = .whois
			#expect(actionNames(of: transcript).contains(String(localized: .Transcript.whoisNicknameAction("bob"))))
			setting.value = .insertTextField
			#expect(actionNames(of: transcript).contains(String(localized: .Transcript.insertNicknameAction("bob"))))
		}
	}

	@Test("Plain text offers neither action")
	func plainTextOffersNeither() throws {
		try withTranscript { transcript, _ in
			try select("see ", in: transcript)
			let names = actionNames(of: transcript)
			#expect(names.contains(String(localized: .Transcript.joinChannelAction("#swift"))) == false)
			#expect(names.contains { $0.contains("bob") } == false)
		}
	}

	@Test("Performing the actions raises the commands a double click raises")
	func performingRaisesTheCommands() throws {
		try withTranscript { transcript, recorder in
			try select("#swift", in: transcript)
			let join = try #require(transcript.textView.accessibilityCustomActions()?.first {
				$0.name == String(localized: .Transcript.joinChannelAction("#swift"))
			})
			#expect(join.handler?() == true)
			#expect(recorder.joined == ["#swift"])

			try select("bob", in: transcript)
			let open = try #require(transcript.textView.accessibilityCustomActions()?.first { $0.name.contains("bob") })
			#expect(open.handler?() == true)
			#expect(recorder.opened == ["bob"])
		}
	}

	private func withTranscript(_ body: (TranscriptView, Recorder) throws -> Void) throws {
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless, backing: .buffered, defer: false
		)
		window.isReleasedWhenClosed = false
		defer { window.close() }
		let recorder = Recorder()
		var commands = TranscriptCommandSink()
		commands.joinChannel = { recorder.joined.append($0) }
		commands.openConversation = { recorder.opened.append($0) }
		let conversation = Conversation(config: ConversationConfig(name: "#swift"))
		let controller = TranscriptController(conversation: conversation, in: window, commands: commands)
		let transcript = controller.ensureBackingView()
		window.contentView = transcript
		transcript.appendLines([line()])
		try withExtendedLifetime((controller, conversation)) {
			try body(transcript, recorder)
		}
	}

	private func line() -> TranscriptRow {
		let runs = [
			TranscriptTextRun(text: "see "),
			TranscriptTextRun(text: "#swift", action: .channel("#swift")),
			TranscriptTextRun(text: " and "),
			TranscriptTextRun(text: "bob", action: .nickname("bob")),
		]
		return TranscriptRow(
			lineNumber: "line", receivedAt: Date(timeIntervalSince1970: 0),
			nickname: "alice", memberType: .normal, lineType: .privateMessage, command: "PRIVMSG",
			messageIdentifier: "message-line", replyToMessageIdentifier: nil,
			deliveryState: .none, deliveryFailureReason: nil, reactions: [:], markers: [],
			body: TranscriptBody(plainText: "see #swift and bob", runs: runs)
		)
	}
}
