// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript native keyboard commands", .serialized)
struct TranscriptNativeCommandTests {
	@Test("Focus Transcript makes the selectable text view the actual first responder")
	func focusTargetsTextView() throws {
		let window = makeWindow()
		defer { window.close() }
		let session = ServerSession(config: ServerConfig())
		let controller = window.transcriptControllers.controller(for: session)
		let transcript = controller.ensureBackingView()
		window.contentView = transcript
		window.selectedItem = session
		let event = try #require(NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: [.control, .command],
			timestamp: 0, windowNumber: window.windowNumber, context: nil,
			characters: "t", charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17
		))

		window.focusTranscript(event)

		#expect(window.firstResponder === transcript.textView)
		#expect(transcript.textView.isSelectable)
		#expect(transcript.textView.isEditable == false)
	}

	@Test("Keyboard and accessibility context menus use the selected message, not an earlier pointer target")
	func selectionMenuTargetsSelectedMessage() throws {
		try withTranscript { transcript in
			let range = (transcript.textView.string as NSString).range(of: "second body")
			try #require(range.location != NSNotFound)
			transcript.textView.setSelectedRange(range)
			transcript.contextMenuTarget.lineMessageIdentifier = "stale-pointer-message"
			let target = transcript.selectedContextTarget()
			#expect(target.lineMessageIdentifier == "message-second")
			#expect(target.lineNickname == "alice")
			let menu = try #require(transcript.textView.selectionContextMenu())
			#expect(menu.items.contains { $0.representedObject as? String == "message-second" })
			#expect(transcript.contextMenuTarget.lineMessageIdentifier == nil)
		}
	}

	@Test("A selected reaction chip keeps its owning message as the menu target")
	func selectionMenuTargetsReactionMessage() throws {
		try withTranscript { transcript in
			let storage = try #require(transcript.textView.textStorage)
			var chipRange: NSRange?
			storage.enumerateAttribute(.transcriptReaction, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
				if let reaction = value as? TranscriptReactionTarget, reaction.messageIdentifier == "message-second" {
					chipRange = range
					stop.pointee = true
				}
			}
			let range = try #require(chipRange)
			transcript.textView.setSelectedRange(range)
			#expect(transcript.selectedContextTarget().lineMessageIdentifier == "message-second")
			let menu = try #require(transcript.textView.selectionContextMenu())
			#expect(menu.items.contains { $0.representedObject as? String == "message-second" })
		}
	}

	@Test("A selection at the end of an empty document has no message actions")
	func emptySelectionHasNoMessageTarget() throws {
		try withTranscript { transcript in
			transcript.clearLines()
			#expect(transcript.selectedContextTarget().lineMessageIdentifier == nil)
			let items = try #require(transcript.textView.selectionContextMenu()).items
			#expect(items.contains { ($0.representedObject as? String)?.hasPrefix("message-") == true } == false)
		}
	}

	private func withTranscript(_ body: (TranscriptView) throws -> Void) throws {
		let window = makeWindow()
		defer { window.close() }
		let conversation = Conversation(config: ConversationConfig(name: "#selection"))
		var commands = TranscriptCommandSink()
		commands.messageReplyItems = { identifier, _, _ in
			let item = NSMenuItem(title: "Reply", action: nil, keyEquivalent: "")
			item.representedObject = identifier
			return [item]
		}
		let controller = TranscriptController(conversation: conversation, in: window, commands: commands)
		let transcript = controller.ensureBackingView()
		window.contentView = transcript
		transcript.appendLines([line("first"), line("second", reactions: ["👍": ["bob"]])])
		try withExtendedLifetime((controller, conversation)) {
			try body(transcript)
		}
	}

	private func makeWindow() -> MainWindow {
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless, backing: .buffered, defer: false
		)
		window.isReleasedWhenClosed = false
		return window
	}

	private func line(_ identifier: String, reactions: [String: [String]] = [:]) -> TranscriptRow {
		let text = "\(identifier) body"
		return TranscriptRow(
			lineNumber: identifier, receivedAt: Date(timeIntervalSince1970: 0),
			nickname: "alice", memberType: .normal, lineType: .privateMessage, command: "PRIVMSG",
			messageIdentifier: "message-\(identifier)", replyToMessageIdentifier: nil,
			deliveryState: .none, deliveryFailureReason: nil, reactions: reactions, markers: [],
			body: TranscriptBody(plainText: text, runs: [TranscriptTextRun(text: text)])
		)
	}
}
