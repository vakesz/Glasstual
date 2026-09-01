/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

@Suite("Input history scope")
@MainActor
struct InputHistoryScopeTests {
	private static let channelSpecificKey = "SaveInputHistoryPerSelection"

	private func makeWindow() -> MainWindow {
		MainWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
	}

	/// The tests run against the scheme's scratch defaults suite, so the
	/// original value is restored rather than left behind.
	private func withChannelSpecificHistory(_ enabled: Bool, _ body: () -> Void) {
		let defaults = TextualUserDefaults.container
		let original = defaults.persistentDomain(forName: ApplicationGroup.identifier)?[Self.channelSpecificKey]
		defer {
			if let original {
				defaults.set(original, forKey: Self.channelSpecificKey)
			} else {
				defaults.removeObject(forKey: Self.channelSpecificKey)
			}
		}

		defaults.set(enabled, forKey: Self.channelSpecificKey)
		body()
	}

	/// The global buffer used to live under the literal key
	/// "TLOInputHistoryDefaultObject" in the same dictionary as the per-item
	/// buffers, so a tree item whose identifier happened to be that string
	/// would have shared the global history.
	@Test("The global scope cannot collide with a tree item's")
	func globalScopeIsNotAnIdentifier() {
		#expect(InputHistoryScope.global != .item("TLOInputHistoryDefaultObject"))
		#expect(InputHistoryScope.item("a") != .item("b"))
		#expect(InputHistoryScope.item("a") == .item("a"))
	}

	@Test("Scopes are distinct dictionary keys")
	func scopesAreDistinctKeys() {
		var buffers: [InputHistoryScope: Int] = [:]
		buffers[.global] = 1
		buffers[.item("TLOInputHistoryDefaultObject")] = 2
		buffers[.item("channel")] = 3

		#expect(buffers.count == 3)
		#expect(buffers[.global] == 1)
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
}
