// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@Suite("Input history scope")
@MainActor
struct InputHistoryScopeTests {
	private static let perSelectionKey = SettingsKeys.Input.historyIsPerSelection.name

	private func makeWindow() -> MainWindow {
		let window = MainWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
		/* Closed by the tests that focus items, and a window that releases
		 itself on close is released twice. */
		window.isReleasedWhenClosed = false
		return window
	}

	/// The tests run against the scheme's scratch defaults suite, so the
	/// original value is restored rather than left behind.
	private func withChannelSpecificHistory(_ enabled: Bool, _ body: () -> Void) {
		let defaults = GlasstualUserDefaults.container
		let original = defaults.persistedObject(forKey: Self.perSelectionKey)
		defer {
			if let original {
				defaults.set(original, forKey: Self.perSelectionKey)
			} else {
				defaults.removeObject(forKey: Self.perSelectionKey)
			}
		}

		defaults.set(enabled, forKey: Self.perSelectionKey)
		body()
	}

	@Test("A shared history uses the global scope whatever is focused")
	func sharedHistoryUsesGlobalScope() {
		withChannelSpecificHistory(false) {
			#expect(InputHistory(window: makeWindow()).currentScope == .global)
		}
	}

	/// With per-channel history and nothing focused there is no buffer to
	/// write into, which is what the optional scope says.
	@Test("A channel-specific history has no scope until a view is focused")
	func channelSpecificHistoryNeedsAFocusedView() {
		withChannelSpecificHistory(true) {
			#expect(InputHistory(window: makeWindow()).currentScope == nil)
		}
	}

	/// A buffer is a value: forking the global one hands each item a copy, so
	/// typing into one item's history changes no other's.
	@Test("Switching to per-selection history gives every item an independent copy of the shared buffer")
	func forkedHistoriesAreIndependent() {
		let setting = SettingsKeys.Input.historyIsPerSelection
		let previous = setting.storedValue
		defer { setting.storedValue = previous }
		setting.value = false
		let window = makeWindow()
		defer { window.close() }
		let history = InputHistory(window: window)
		history.add(NSAttributedString(string: "shared"))

		setting.value = true
		let first = ServerSession(config: ServerConfig())
		let second = ServerSession(config: ServerConfig())
		history.forkGlobalHistory(into: [first.uniqueIdentifier, second.uniqueIdentifier])
		history.moveFocus(to: first)
		history.add(NSAttributedString(string: "only in the first"))
		history.moveFocus(to: second)

		#expect(history.up(NSAttributedString(string: ""))?.string == "shared")
		#expect(history.up(NSAttributedString(string: "shared"))?.string == nil)
		history.moveFocus(to: first)
		#expect(history.up(NSAttributedString(string: ""))?.string == "only in the first")
		#expect(history.up(NSAttributedString(string: "only in the first"))?.string == "shared")
	}

	@Test("A draft left in one item's field comes back when the item is focused again, and not in another")
	func draftsFollowTheirItem() throws {
		let setting = SettingsKeys.Input.historyIsPerSelection
		let previous = setting.storedValue
		defer { setting.storedValue = previous }
		setting.value = true
		let window = makeWindow()
		defer { window.close() }
		let field = try #require(window.inputTextField)
		let history = InputHistory(window: window)
		let first = ServerSession(config: ServerConfig())
		let second = ServerSession(config: ServerConfig())

		history.moveFocus(to: first)
		field.stringValue = "half-typed"
		history.moveFocus(to: second)
		#expect(field.stringValue.isEmpty)
		history.moveFocus(to: first)
		#expect(field.stringValue == "half-typed")
	}
}
