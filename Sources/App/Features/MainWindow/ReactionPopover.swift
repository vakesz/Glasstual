/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import SwiftUI

nonisolated enum ReactionInput { // nonisolated: value
	static func emoji(from input: String) -> String? { // nonisolated: pure
		let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
		guard value.isEmpty == false else { return nil }

		let first = value.rangeOfComposedCharacterSequence(at: value.startIndex)
		return String(value[first])
	}
}

private struct ReactionPopoverView: View {
	let send: (String) -> Void

	@State private var input = ""
	@FocusState private var inputIsFocused: Bool

	private var emoji: String? {
		ReactionInput.emoji(from: input)
	}

	var body: some View {
		HStack(spacing: 8) {
			TextField(MessageMenuStrings.emojiPlaceholder, text: $input)
				.textFieldStyle(.roundedBorder)
				.multilineTextAlignment(.center)
				.focused($inputIsFocused)
				.onSubmit(submit)

			Button(MessageMenuStrings.sendReaction, action: submit)
				.disabled(emoji == nil)
				.keyboardShortcut(.defaultAction)
		}
		.padding(12)
		.frame(width: 220)
		.task {
			inputIsFocused = true
		}
	}

	private func submit() {
		guard let emoji else { return }
		send(emoji)
	}
}

/// AppKit presentation shell for the SwiftUI reaction picker.
@MainActor
public final class ReactionPopover: NSObject, NSPopoverDelegate {
	public let messageIdentifier: String
	public var completion: ((String, String) -> Void)?

	private var popover: NSPopover?

	public init(messageIdentifier: String) {
		self.messageIdentifier = messageIdentifier
	}

	public func present(relativeTo rect: NSRect, of view: NSView) {
		let popover = NSPopover()
		popover.behavior = .transient
		popover.delegate = self
		popover.contentViewController = NSHostingController(
			rootView: ReactionPopoverView { [weak self] emoji in
				self?.submit(emoji)
			}
		)

		self.popover = popover
		popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
	}

	public func close() {
		popover?.close()
	}

	public func popoverDidClose(_: Notification) {
		popover = nil
	}

	private func submit(_ emoji: String) {
		completion?(emoji, messageIdentifier)
		close()
	}
}
