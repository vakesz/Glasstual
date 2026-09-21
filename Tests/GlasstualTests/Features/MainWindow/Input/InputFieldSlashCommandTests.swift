// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Slash commands in the native editor")
struct InputFieldSlashCommandTests {
	private func makeWindow() -> MainWindow {
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		let inputBar = window.inputContentView!
		inputBar.frame = NSRect(x: 0, y: 0, width: 400, height: 40)
		window.contentView?.addSubview(inputBar)
		window.makeFirstResponder(window.inputTextField)
		// Supply the key-window half of the adapter's focus state without
		// bringing a test window in front of the running application.
		window.inputTextField.focusModel.windowIsKey = true
		return window
	}

	private func setDraft(_ text: String, caret: Int, in field: InputField) {
		field.stringValue = text
		field.setSelectedRange(NSRange(location: caret, length: 0))
		field.refreshSlashCommands()
	}

	@Test("Completing a command preserves its arguments and remains one undoable edit")
	func completionPreservesArgumentsAndUndo() throws {
		let window = makeWindow()
		defer { window.close() }
		let field = try #require(window.inputTextField)
		let original = "/jo  #swift 🦉"
		setDraft(original, caret: 3, in: field)
		let suggestion = try #require(field.commandDiscovery.suggestions.first { $0.name == "join" })
		let undoManager = try #require(field.undoManager)
		undoManager.groupsByEvent = false
		undoManager.beginUndoGrouping()

		#expect(field.acceptSlashCommand(suggestion))
		undoManager.endUndoGrouping()

		#expect(field.string == "/join  #swift 🦉")
		#expect(field.selectedRange() == NSRange(location: 5, length: 0))
		#expect(undoManager.canUndo)
		undoManager.undo()
		#expect(field.string == original)
	}

	@Test("Return completes an unfinished name and leaves exact commands ready to send")
	func returnCompletesOnlyUnfinishedNames() throws {
		let window = makeWindow()
		defer { window.close() }
		let field = try #require(window.inputTextField)
		setDraft("/jo", caret: 3, in: field)

		#expect(field.acceptIncompleteSlashCommand())
		#expect(field.string == "/join ")
		#expect(field.selectedRange() == NSRange(location: 6, length: 0))
		#expect(field.acceptIncompleteSlashCommand() == false)

		setDraft("/join", caret: 5, in: field)
		#expect(field.acceptIncompleteSlashCommand() == false)
		#expect(field.string == "/join")
	}

	@Test("A delayed suggestion cannot replace an unrelated draft")
	func staleSuggestionDoesNotChangeDraft() throws {
		let window = makeWindow()
		defer { window.close() }
		let field = try #require(window.inputTextField)
		setDraft("/jo", caret: 3, in: field)
		let suggestion = try #require(field.commandDiscovery.selectedSuggestion)
		setDraft("/topic new topic", caret: 16, in: field)

		#expect(field.acceptSlashCommand(suggestion) == false)
		#expect(field.string == "/topic new topic")
	}

	@Test("Escape dismisses discovery before canceling a reply and editing opens it again")
	func escapeKeepsReplyAndDismissesUntilEditing() throws {
		let window = makeWindow()
		defer { window.close() }
		let field = try #require(window.inputTextField)
		field.beginReply(toMessageIdentifier: "reply-id", nickname: "Alice", excerpt: "Hello")
		setDraft("/j", caret: 2, in: field)

		#expect(field.textView(field, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
		#expect(field.commandDiscovery.isVisible == false)
		#expect(field.replyMessageIdentifier == "reply-id")
		field.setSelectedRange(NSRange(location: 1, length: 0))
		field.setSelectedRange(NSRange(location: 2, length: 0))
		field.refreshSlashCommands()
		#expect(field.commandDiscovery.isVisible == false)

		field.insertText("o", replacementRange: field.selectedRange())
		#expect(field.commandDiscovery.isVisible)
		#expect(field.commandDiscovery.selectedSuggestion?.name == "join")
	}

	@Test("A delayed mouse selection cannot reclaim focus after the editor resigns")
	func staleMouseSelectionDoesNotReclaimFocus() throws {
		let window = makeWindow()
		defer { window.close() }
		let field = try #require(window.inputTextField)
		setDraft("/jo", caret: 3, in: field)
		let suggestion = try #require(field.commandDiscovery.selectedSuggestion)

		#expect(window.makeFirstResponder(nil))
		#expect(field.focusModel.isFirstResponder == false)
		#expect(field.acceptSlashCommand(suggestion) == false)
		#expect(field.string == "/jo")
		#expect(window.firstResponder !== field)
	}

	@Test("Marked text owns its keys and suppresses command discovery")
	func markedTextSuppressesSuggestions() throws {
		let window = makeWindow()
		defer { window.close() }
		let field = try #require(window.inputTextField)
		setDraft("/j", caret: 2, in: field)
		#expect(field.commandDiscovery.isVisible)

		field.setMarkedText("o", selectedRange: NSRange(location: 1, length: 0), replacementRange: field.selectedRange())
		#expect(field.hasMarkedText())
		#expect(field.commandDiscovery.isVisible == false)
		#expect(field.acceptSlashCommand() == false)
		#expect(field.textView(field, doCommandBy: #selector(NSResponder.insertNewline(_:))) == false)

		field.unmarkText()
		#expect(field.hasMarkedText() == false)
		#expect(field.commandDiscovery.isVisible)
	}

	@Test("Plain arrows select suggestions while Option arrows retain input history")
	func suggestionNavigationPreservesHistoryModifiers() throws {
		let previous = SettingsKeys.Input.historyIsPerSelection.storedValue
		defer { SettingsKeys.Input.historyIsPerSelection.storedValue = previous }
		SettingsKeys.Input.historyIsPerSelection.value = false
		let window = makeWindow()
		defer { window.close() }
		let field = try #require(window.inputTextField)
		window.inputHistory.add(NSAttributedString(string: "previous message"))
		setDraft("/j", caret: 2, in: field)
		let initial = field.commandDiscovery.selectedSuggestion?.name
		let arrow = try #require(keyEvent(.downArrow))
		window.inputHistoryDownWithScrollCheck(arrow)
		#expect(field.commandDiscovery.selectedSuggestion?.name != initial)
		#expect(field.string == "/j")

		let optionArrow = try #require(keyEvent(.upArrow, modifiers: .option))
		window.inputHistoryUpWithScrollCheck(optionArrow)
		#expect(field.string == "previous message")
	}

	@Test("Tab respects the configured action before accepting a suggestion")
	func tabRespectsInputPreference() throws {
		let previous = SettingsKeys.Input.tabKeyAction.storedValue
		defer { SettingsKeys.Input.tabKeyAction.storedValue = previous }
		let window = makeWindow()
		defer { window.close() }
		let field = try #require(window.inputTextField)
		setDraft("/jo", caret: 3, in: field)
		let tab = try #require(keyEvent(.tab))

		SettingsKeys.Input.tabKeyAction.value = .none
		#expect(window.tab(tab) == false)
		#expect(field.string == "/jo")

		SettingsKeys.Input.tabKeyAction.value = .nicknameComplete
		#expect(window.tab(tab))
		#expect(field.string == "/join ")
	}

	private func keyEvent(_ key: KeyCode, modifiers: NSEvent.ModifierFlags = []) -> NSEvent? {
		NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: modifiers,
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			characters: "",
			charactersIgnoringModifiers: "",
			isARepeat: false,
			keyCode: key.rawValue
		)
	}
}
