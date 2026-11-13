// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
@Suite("Channel search focus")
struct ChannelSpotlightFocusTests {
	@Test("Opening ignores inactive states until search has acquired the keyboard")
	func openingDoesNotDismiss() {
		var activation = ChannelSpotlightActivation()
		let states: [ControlActiveState] = [.inactive, .active, .inactive, .key, .key]
		let dismissals = states.map { activation.shouldDismiss(after: $0) }
		#expect(dismissals == [false, false, false, false, false])
	}

	@Test("Losing acquired keyboard focus dismisses once", arguments: [ControlActiveState.active, .inactive])
	func resignationDismisses(_ state: ControlActiveState) {
		var activation = ChannelSpotlightActivation()
		let dismissals = [ControlActiveState.key, state, state].map { activation.shouldDismiss(after: $0) }
		#expect(dismissals == [false, true, false])
	}

	@Test("Typing into the native search field updates search results")
	func typingStaysInSearch() async throws {
		let conversation = Conversation(config: ConversationConfig.seed(withName: "#swift"))
		let model = ChannelSpotlightModel(
			conversations: { [conversation] }, selectedSessionID: { nil }, selectConversation: { _ in }
		)
		let root = ChannelSpotlightView(model: model, select: { _ in }, close: {})
		let host = NSHostingView(rootView: root)
		// This matches the hidden-title scene's titled native window contract.
		// A borderless window returns false from canBecomeKey.
		let window = NSWindow(
			contentRect: NSRect(x: -4000, y: -4000, width: 600, height: 100),
			styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false
		)
		window.isReleasedWhenClosed = false
		defer { window.close() }
		window.contentView = host
		window.order(.below, relativeTo: 0)
		host.layoutSubtreeIfNeeded()
		#expect(window.canBecomeKey)
		let field = try #require(textField(in: host))
		#expect(window.makeFirstResponder(field))
		let editor = try #require(field.currentEditor() as? NSTextView)
		editor.insertText("swift", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
		await Task.yield()
		#expect(model.searchText == "swift")
		#expect(model.displayedResults.map(\.id) == [conversation.uniqueIdentifier])
		#expect(window.firstResponder === editor)
	}

	private func textField(in view: NSView) -> NSTextField? {
		if let field = view as? NSTextField, field.isEditable {
			return field
		}
		return view.subviews.lazy.compactMap { textField(in: $0) }.first
	}
}
