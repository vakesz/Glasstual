// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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
		let defaults = GlasstualUserDefaults.container
		let original = defaults.persistedObject(forKey: Self.channelSpecificKey)
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
