// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

private let inputHistoryMaximumCount = 100

/// Which history buffer the input field is typing into. The global buffer is a
/// case of its own rather than a reserved key in the per-item dictionary, which
/// a sidebar item could have collided with.
enum InputHistoryScope: Hashable, Sendable {
	case global
	case item(String)
}

/// One buffer of entries and the cursor walking it. A value, so forking the
/// global buffer into a selection's own is a copy.
private struct InputHistoryObject {
	private var historyBuffer: [NSAttributedString] = []
	private var historyBufferPosition = 0
	var lastHistoryItem: NSAttributedString?

	mutating func add(_ string: NSAttributedString) {
		guard string.length > 0 else {
			return
		}

		if historyBuffer.last?.string != string.string {
			addToBuffer(string)
		}

		historyBufferPosition = historyBuffer.count
	}

	mutating func up(_ string: NSAttributedString) -> NSAttributedString? {
		if string.length > 0, entryAtBufferPosition()?.string != string.string {
			addToBuffer(string)
		}

		historyBufferPosition -= 1

		if historyBufferPosition < 0 {
			historyBufferPosition = 0
		} else if historyBuffer.indices.contains(historyBufferPosition) {
			return historyBuffer[historyBufferPosition]
		}

		return nil
	}

	mutating func down(_ string: NSAttributedString) -> NSAttributedString? {
		guard string.length > 0 else {
			historyBufferPosition = historyBuffer.count

			return nil
		}

		if entryAtBufferPosition()?.string != string.string {
			addToBuffer(string)

			return NSAttributedString(string: "")
		}

		historyBufferPosition += 1

		return entryAtBufferPosition() ?? NSAttributedString(string: "")
	}

	/// A line that carries a password or a code never enters the buffer, as
	/// an entry or as the draft Up and Down keep.
	private mutating func addToBuffer(_ string: NSAttributedString) {
		guard LocalCommand.inputCarriesSecret(string.string) == false else {
			return
		}

		historyBuffer.append(NSAttributedString(attributedString: string))

		guard historyBuffer.count > inputHistoryMaximumCount else {
			return
		}

		historyBuffer.removeFirst()
		/* Dropping the oldest entry shifts every index down by one, and the
		 cursor is an index. Left where it was, the first press of Up at a full
		 buffer returned the draft that had just been stashed and every entry
		 after it was off by one. */
		historyBufferPosition = max(0, historyBufferPosition - 1)
	}

	private func entryAtBufferPosition() -> NSAttributedString? {
		guard historyBuffer.indices.contains(historyBufferPosition) else {
			return nil
		}

		return historyBuffer[historyBufferPosition]
	}
}

/** The input history follows the focused view, so it lives where the text field
 does: on the main actor. That is what makes the plain stored state safe. */
@MainActor
final class InputHistory {
	private weak var window: MainWindow?
	private var historyObjects: [InputHistoryScope: InputHistoryObject] = [:]
	private var currentSidebarItem: String?

	init(window: MainWindow) {
		self.window = window
	}

	func destroy(_ sidebarItem: ChatItem) {
		guard SettingsKeys.Input.historyIsPerSelection.value else {
			return
		}

		if let session = sidebarItem as? ServerSession {
			for conversation in session.conversationList {
				destroy(conversation)
			}
		}

		let itemIdentifier = sidebarItem.uniqueIdentifier
		historyObjects.removeValue(forKey: .item(itemIdentifier))

		if currentSidebarItem == itemIdentifier {
			currentSidebarItem = nil
		}
	}

	func moveFocus(to sidebarItem: ChatItem) {
		guard SettingsKeys.Input.historyIsPerSelection.value,
		      let textView = window?.inputTextField
		else {
			return
		}

		let draft = NSAttributedString(attributedString: textView.attributedStringValue)
		withCurrentObject { $0.lastHistoryItem = draft }

		currentSidebarItem = sidebarItem.uniqueIdentifier

		if let scope = currentScope, let lastHistoryItem = historyObjects[scope]?.lastHistoryItem {
			textView.attributedStringValue = lastHistoryItem
		} else {
			textView.stringValue = ""
		}
	}

	func noteInputHistoryObjectScopeDidChange() {
		if SettingsKeys.Input.historyIsPerSelection.value {
			forkGlobalHistory(into: AppServices.chatSession.sessions.flatMap { session in
				[session.uniqueIdentifier] + session.conversationList.map(\.uniqueIdentifier)
			})
		} else {
			historyObjects.removeAll()
			currentSidebarItem = nil
		}
	}

	/// Gives each item its own copy of the global buffer and retires the global
	/// one, so what was typed before the switch is still there to walk back
	/// through, and what is typed after it stays with one item.
	func forkGlobalHistory(into itemIdentifiers: [String]) {
		for identifier in itemIdentifiers {
			applyGlobalHistory(to: identifier)
		}

		historyObjects.removeValue(forKey: .global)
	}

	func add(_ string: NSAttributedString) {
		withCurrentObject { $0.add(string) }
	}

	func up(_ string: NSAttributedString) -> NSAttributedString? {
		withCurrentObject { $0.up(string) } ?? nil
	}

	func down(_ string: NSAttributedString) -> NSAttributedString? {
		withCurrentObject { $0.down(string) } ?? nil
	}

	private func applyGlobalHistory(to itemIdentifier: String) {
		guard let globalObject = historyObjects[.global] else {
			return
		}

		var forked = globalObject
		forked.lastHistoryItem = nil
		historyObjects[.item(itemIdentifier)] = forked
	}

	/// `nil` when history is kept per selection and nothing is focused.
	var currentScope: InputHistoryScope? {
		guard SettingsKeys.Input.historyIsPerSelection.value else {
			return .global
		}

		return currentSidebarItem.map(InputHistoryScope.item)
	}

	/// Runs `body` on the focused scope's buffer, in place, creating it on first
	/// use. `nil` when history is kept per selection and nothing is focused.
	@discardableResult
	private func withCurrentObject<Result>(_ body: (inout InputHistoryObject) -> Result) -> Result? {
		guard let scope = currentScope else {
			return nil
		}

		return body(&historyObjects[scope, default: InputHistoryObject()])
	}
}
