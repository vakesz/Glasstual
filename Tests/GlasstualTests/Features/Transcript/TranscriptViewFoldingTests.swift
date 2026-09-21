// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript view folding")
struct TranscriptViewFoldingTests {
	@Test("Collapsed events retain their source rows while native storage contains only the summary")
	func appendMergesCollapsedEvents() throws {
		try withTranscript { view, _ in
			view.appendLines([line("first", kind: .join), line("second", kind: .part)])
			#expect(view.textView.string == String(localized: .Transcript.expandGeneralEvents(2)) + "\n")
			#expect(view.range(ofLine: "second")?.length == 0)
			view.appendLines([line("third", kind: .quit)])
			#expect(view.textView.string == String(localized: .Transcript.expandGeneralEvents(3)) + "\n")
			#expect(view.displayedLines.map(\.body.plainText) == ["first body", "second body", "third body"])
			#expect(view.containsLine(identifier: "second"))
			view.appendLines([line("visible")])
			let range = try #require(view.range(ofLine: "visible"))
			#expect(view.lineIndex(containing: range.location) == 3)
			#expect(view.textView.string.contains("visible body"))
			#expect(view.textView.string.contains("second body") == false)
		}
	}

	@Test("Native links expand a summary and its context menu collapses it without exposing hidden excerpts")
	func nativeLinkAndContextMenuToggle() throws {
		try withTranscript { view, _ in
			view.appendLines([line("first", kind: .join), line("second", kind: .part)])
			let storage = try #require(view.textView.textStorage)
			let link = try #require(storage.attribute(.link, at: 0, effectiveRange: nil) as? URL)
			#expect(storage.attribute(.transcriptFoldLineNumber, at: 0, effectiveRange: nil) as? String == "first")
			select(NSRange(location: 0, length: 0), in: view)
			let collapsedTarget = view.selectedContextTarget()
			#expect(collapsedTarget.foldLineNumber == "first")
			#expect(collapsedTarget.lineExcerpt == nil)
			#expect(collapsedTarget.lineMessageIdentifier == nil)

			#expect(view.textView(view.textView, clickedOnLink: link, at: 0))
			#expect(view.textView.string.contains("first body"))
			#expect(view.textView.string.contains("second body"))
			select(NSRange(location: 0, length: 0), in: view)
			view.contextMenuTarget = view.selectedContextTarget()
			let menu = view.contextMenu(defaultItems: [])
			let item = try #require(menu.items.first)
			#expect(item.title == String(localized: .Transcript.collapseMessages))
			let action = try #require(item.action)
			#expect(NSApp.sendAction(action, to: item.target, from: item))
			#expect(view.textView.string.contains("first body") == false)
			#expect(view.textView.string.contains("second body") == false)
		}
	}

	@Test("Return and Space activate a focused summary without redirecting typing")
	func keyboardActivatesFocusedSummary() throws {
		try withTranscript { view, _ in
			view.appendLines([line("event", kind: .join)])
			select(NSRange(location: 0, length: 0), in: view)
			let enter = try keyEvent("\r", keyCode: 0x24, in: view)
			#expect(view.keyDown(enter, in: view.textView))
			#expect(view.textView.string.contains("event body"))
			#expect(view.followsBottom == false)
			select(NSRange(location: 0, length: 0), in: view)
			let space = try keyEvent(" ", keyCode: 0x31, in: view)
			#expect(view.keyDown(space, in: view.textView))
			#expect(view.textView.string.contains("event body") == false)
			select(NSRange(location: 0, length: 1), in: view)
			#expect(view.activateSelectedFold() == false)
		}
	}

	@Test("Muting existing messages hides their bodies and updates stay hidden until a jump or unmute")
	func mutingRetainsMessagesAndTheirUpdates() throws {
		try withTranscript { view, session in
			var own = line("own")
			own.memberType = .localUser
			view.appendLines([line("first"), line("second", kind: .action), own])
			#expect(view.textView.string.contains("first body"))
			session.setUserMuted(true, nickname: "alice")
			view.reloadFolding()
			#expect(view.textView.string.contains("first body") == false)
			#expect(view.textView.string.contains("second body") == false)
			#expect(view.textView.string.contains("own body"))
			#expect(view.displayedLines.count == 3)

			view.updateReactions(["👍": ["bob"]], messageIdentifier: "message-second")
			view.updateDelivery(TranscriptDeliveryUpdate(
				lineNumber: "second", state: .delivered, messageIdentifier: nil, reason: nil
			))
			#expect(view.textView.string.contains("second body") == false)
			#expect(view.textView.string.contains("👍") == false)
			#expect(view.displayedLines[1].deliveryState == .delivered)
			#expect(view.jump(to: "second"))
			#expect(view.textView.string.contains("first body"))
			#expect(view.textView.string.contains("second body"))
			#expect(view.textView.string.contains("👍"))

			view.toggleFoldedGroup("first")
			session.setUserMuted(false, nickname: "alice")
			view.reloadFolding()
			#expect(view.textView.string.contains("first body"))
			#expect(view.textView.string.contains("second body"))
			#expect(view.document.folding.presentations.isEmpty)
		}
	}

	@Test("An unread marker divides a collapsed group and remains visible after expansion")
	func unreadBoundaryRemainsVisible() throws {
		try withTranscript { view, _ in
			view.appendLines([line("first", kind: .join), line("second", kind: .part), line("third", kind: .quit)])
			view.setUnreadMarker(.line("second"))
			try expectUnreadMarker(in: view, lineNumber: "second")
			#expect(view.textView.string.contains(String(localized: .Transcript.expandGeneralEvents(1))))
			#expect(view.textView.string.contains(String(localized: .Transcript.expandGeneralEvents(2))))
			view.toggleFoldedGroup("second")
			#expect(view.textView.string.contains("first body") == false)
			#expect(view.textView.string.contains("second body"))
			#expect(view.textView.string.contains("third body"))
			try expectUnreadMarker(in: view, lineNumber: "second")
			view.setUnreadMarker(.none)
			#expect(unreadMarkerRanges(in: view).isEmpty)
			#expect(view.textView.string.contains("first body"))
		}
	}

	@Test("Expansion survives a native rebuild, older history, and removal of the original summary")
	func expansionSurvivesRebuildPrependAndTrim() throws {
		try withTranscript { view, _ in
			view.document.bufferLimit = 3
			view.appendLines([line("first", kind: .join), line("second", kind: .part)])
			view.toggleFoldedGroup("first")
			view.rebuild()
			#expect(view.textView.string.contains("first body"))
			#expect(view.textView.string.contains("second body"))
			#expect(view.prependLines([line("older", kind: .nick)]) == ["older"])
			#expect(view.textView.string.contains("older body"))
			#expect(view.textView.string.contains(String(localized: .Transcript.collapseGeneralEvents(3))))
			view.followsBottom = true
			view.appendLines([line("newest", kind: .quit), line("last", kind: .mode)])
			#expect(view.displayedLines.map(\.lineNumber) == ["second", "newest", "last"])
			#expect(view.textView.string.contains("second body"))
			#expect(view.textView.string.contains("newest body"))
			#expect(view.textView.string.contains("last body"))
			view.toggleFoldedGroup("second")
			#expect(view.textView.string == String(localized: .Transcript.expandGeneralEvents(3)) + "\n")
		}
	}

	@Test("Selections after zero-length hidden rows survive folds and row refreshes")
	func visibleSelectionSurvivesChangingFoldLengths() throws {
		try withTranscript { view, _ in
			view.appendLines([
				line("first", kind: .join), line("second", kind: .part), line("selected"),
			])
			let selection = (view.textView.string as NSString).range(of: "selected body")
			try #require(selection.location != NSNotFound)
			select(selection, in: view)
			view.toggleFoldedGroup("first")
			#expect(selectedText(in: view) == "selected body")
			view.toggleFoldedGroup("first")
			#expect(selectedText(in: view) == "selected body")
			view.prependLines([line("older", kind: .nick)])
			#expect(selectedText(in: view) == "selected body")
			view.updateReactions(["👍": ["bob"]], messageIdentifier: "message-second")
			#expect(selectedText(in: view) == "selected body")
			view.rebuild()
			#expect(selectedText(in: view) == "selected body")
			#expect(view.document.lineStarts.last == view.textView.textStorage?.length)
		}
	}

	@Test("Collapsing selected message text clears the selection instead of selecting unrelated text")
	func hidingSelectedBodyClearsSelection() throws {
		try withTranscript { view, _ in
			view.appendLines([line("first", kind: .join), line("second", kind: .part), line("visible")])
			view.toggleFoldedGroup("first")
			let range = (view.textView.string as NSString).range(of: "second body")
			try #require(range.location != NSNotFound)
			select(range, in: view)
			view.toggleFoldedGroup("first")
			#expect(view.textView.selectedRange().length == 0)
			#expect(view.selection == nil)
			#expect(view.textView.string.contains("visible body"))
		}
	}

	@Test("Changing Collapse to Hide conceals retained events and preserves their markers until Show restores their bodies")
	func displayChangesPreserveMarkers() throws {
		try withTranscript { view, _ in
			var first = line("first", kind: .join)
			first.markers = [.date("Date boundary")]
			view.appendLines([first, line("second", kind: .part), line("visible")])
			view.setUnreadMarker(.line("second"))
			let conversation = try #require(view.viewController?.associatedConversation)
			var config = conversation.config
			config.generalEventMessageDisplay = .hide
			conversation.updateConfig(config, fireChangedNotification: false, updateStoredConversationList: false)
			view.reloadFolding()
			#expect(view.textView.string.contains("first body") == false)
			#expect(view.textView.string.contains("second body") == false)
			#expect(view.textView.string.contains("Date boundary"))
			try expectUnreadMarker(in: view, lineNumber: "second")
			#expect(view.textView.string.contains(String(localized: .Transcript.expandGeneralEvents(1))) == false)
			#expect(view.textView.string.contains("visible body"))
			config.generalEventMessageDisplay = .show
			conversation.updateConfig(config, fireChangedNotification: false, updateStoredConversationList: false)
			view.reloadFolding()
			#expect(view.textView.string.contains("first body"))
			#expect(view.textView.string.contains("second body"))
			#expect(view.textView.string.components(separatedBy: "Date boundary").count == 2)
			try expectUnreadMarker(in: view, lineNumber: "second")
		}
	}

	@Test("A returned transcript Mute menu item retains the author's nickname after native copying")
	func copiedMuteMenuRetainsNickname() throws {
		let memberMenu = NSMenu()
		let mute = NSMenuItem(title: "Mute", action: nil, keyEquivalent: "")
		mute.command = .muteUser
		memberMenu.addItem(mute)
		var commands = TranscriptCommandSink()
		commands.memberMenu = { memberMenu }
		try withTranscript(commands: commands) { view, _ in
			view.appendLines([line("message")])
			let range = (view.textView.string as NSString).range(of: "message body")
			try #require(range.location != NSNotFound)
			select(NSRange(location: range.location, length: 0), in: view)
			view.contextMenuTarget = view.selectedContextTarget()
			let menu = view.contextMenu(defaultItems: [])
			let item = try #require(menu.items.first { $0.command == .muteUser })
			#expect(item.userInfoString == "alice")
		}
	}

	private func withTranscript(
		commands: TranscriptCommandSink = TranscriptCommandSink(),
		_ body: (TranscriptView, ServerSession) throws -> Void
	) throws {
		let session = ServerSession(config: ServerConfig())
		var config = ConversationConfig(name: "#folding")
		config.generalEventMessageDisplay = .collapse
		let conversation = Conversation(config: config)
		conversation.associatedSession = session
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless, backing: .buffered, defer: false
		)
		window.isReleasedWhenClosed = false
		let controller = TranscriptController(conversation: conversation, in: window, commands: commands)
		defer {
			controller.tearDown(.preservingRemoval)
			window.close()
		}
		let view = controller.ensureBackingView()
		window.contentView = view
		try withExtendedLifetime((session, conversation, controller)) {
			try body(view, session)
		}
	}

	private func select(_ range: NSRange, in view: TranscriptView) {
		view.isAdjustingSelection = true
		view.textView.setSelectedRange(range)
		view.isAdjustingSelection = false
	}

	private func selectedText(in view: TranscriptView) -> String {
		(view.textView.string as NSString).substring(with: view.textView.selectedRange())
	}

	private func unreadMarkerRanges(in view: TranscriptView) -> [NSRange] {
		guard let storage = view.textView.textStorage else { return [] }
		var ranges: [NSRange] = []
		storage.enumerateAttribute(.transcriptSelectionSegment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
			if value as? String == "marker-unread" {
				ranges.append(range)
			}
		}
		return ranges
	}

	private func expectUnreadMarker(
		in view: TranscriptView,
		lineNumber: String,
		sourceLocation: SourceLocation = #_sourceLocation
	) throws {
		let ranges = unreadMarkerRanges(in: view)
		#expect(ranges.count == 1, sourceLocation: sourceLocation)
		let range = try #require(ranges.first, sourceLocation: sourceLocation)
		let storage = try #require(view.textView.textStorage, sourceLocation: sourceLocation)
		#expect(
			storage.attribute(.accessibilityCustomText, at: range.location, effectiveRange: nil) as? [String]
				== [String(localized: .Transcript.unreadMessages)],
			sourceLocation: sourceLocation
		)
		#expect(
			storage.attribute(.transcriptRuleColor, at: range.location, effectiveRange: nil) is NSColor,
			sourceLocation: sourceLocation
		)
		#expect(
			storage.attribute(.transcriptLineNumber, at: range.location, effectiveRange: nil) as? String == lineNumber,
			sourceLocation: sourceLocation
		)
	}

	private func keyEvent(_ characters: String, keyCode: UInt16, in view: TranscriptView) throws -> NSEvent {
		try #require(NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
			windowNumber: view.window?.windowNumber ?? 0, context: nil,
			characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
		))
	}

	private func line(_ identifier: String, kind: ChatLineKind = .privateMessage) -> TranscriptRow {
		let text = "\(identifier) body"
		return TranscriptRow(
			lineNumber: identifier, receivedAt: Date(timeIntervalSince1970: 0), nickname: "alice",
			memberType: .normal, lineType: kind, command: "", messageIdentifier: "message-\(identifier)",
			replyToMessageIdentifier: nil, deliveryState: .none, deliveryFailureReason: nil,
			reactions: [:], markers: [], body: TranscriptBody(plainText: text, runs: [TranscriptTextRun(text: text)])
		)
	}
}
