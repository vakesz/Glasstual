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
import SwiftUI

nonisolated enum ReactionInput { // nonisolated: value
	static func emoji(from input: String) -> String? {
		let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
		guard value.isEmpty == false else { return nil }

		let first = value.rangeOfComposedCharacterSequence(at: value.startIndex)
		return String(value[first])
	}
}

/** Which reactions the picker offers, and in which order.

 A reaction is a one-tap gesture everywhere else, so the row is the control and
 the character palette is the way out for anything that is not on it. What the
 reader reaches for stays at the front of the row, and the common set fills what
 is left so the row never changes length. */
nonisolated enum RecentReactions { // nonisolated: value
	/// The reactions offered before the user has picked anything.
	static let common = ["👍", "❤️", "😂", "😮", "😢", "🎉"]
	/// How many of the user's own choices are remembered.
	static let maximumRememberedCount = 6
	/// How many buttons the row shows, whatever the mix.
	static let rowLength = 6

	/// The row to draw: the user's own choices first, the common set filling the
	/// rest, no repeats.
	static func row(recent: [String]) -> [String] {
		var result: [String] = []
		for emoji in recent + common where result.contains(emoji) == false {
			result.append(emoji)
			if result.count == rowLength {
				break
			}
		}
		return result
	}

	/// What to store once `emoji` has been used: it moves to the front, and the
	/// list stays bounded.
	static func recording(_ emoji: String, in recent: [String]) -> [String] {
		guard let emoji = ReactionInput.emoji(from: emoji) else {
			return recent
		}
		return Array(([emoji] + recent.filter { $0 != emoji }).prefix(maximumRememberedCount))
	}
}

private struct ReactionPopoverView: View {
	let send: (String) -> Void

	@State private var recent = Preferences.Reactions.recent.value
	@State private var input = ""
	@FocusState private var inputIsFocused: Bool
	/// The row's hit targets, scaled with the reader's text size so the emoji
	/// drawn in them are never clipped.
	@ScaledMetric private var buttonSize: CGFloat = 30

	var body: some View {
		HStack(spacing: UISpacing.tight) {
			ForEach(RecentReactions.row(recent: recent), id: \.self) { emoji in
				Button {
					submit(emoji)
				} label: {
					Text(emoji)
						.font(.title2)
						.frame(width: buttonSize, height: buttonSize)
				}
				.buttonStyle(.accessoryBar)
				.help(MainWindowStrings.Reaction.reactWith(emoji))
				.accessibilityLabel(MainWindowStrings.Reaction.reactWith(emoji))
			}

			Divider()
				.frame(height: buttonSize * 0.75)

			/* The palette inserts into whatever holds the keyboard, so the field
			 stays: it is where the palette's choice lands, and
			 `ReactionInput.emoji(from:)` still decides what counts. It also takes
			 a pasted emoji, which is what the old field was for. */
			TextField(MainWindowStrings.Reaction.custom, text: $input)
				.labelsHidden()
				.textFieldStyle(.roundedBorder)
				.multilineTextAlignment(.center)
				.frame(width: 44)
				.focused($inputIsFocused)
				/* One submission, on the change: the palette and a paste both
				 write the field without pressing Return, so the change is what
				 has to act -- and `onSubmit` beside it sent the same emoji a
				 second time when the reader did press Return. The field is
				 cleared on the way out, so the next character typed into a
				 popover that is still open is a reaction of its own rather
				 than the second character of the last one. */
				.onChange(of: input) { _, newValue in
					guard newValue.isEmpty == false else { return }
					input = ""
					submit(newValue)
				}
				.help(MainWindowStrings.Reaction.custom)

			Button(MainWindowStrings.Reaction.moreEmoji, systemImage: "face.smiling") {
				presentCharacterPalette()
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.accessoryBar)
			.help(MainWindowStrings.Reaction.moreEmoji)
		}
		.padding(UISpacing.regular)
	}

	/** The palette is a system panel that types into the first responder, so
	 the field takes the keyboard first. The panel is ordered front on the next
	 turn: asking for it in the same one races the focus change and the panel
	 opens pointed at whatever had the keyboard before. */
	private func presentCharacterPalette() {
		inputIsFocused = true
		Task { @MainActor in
			NSApp.orderFrontCharacterPalette(nil)
		}
	}

	private func submit(_ candidate: String) {
		guard let emoji = ReactionInput.emoji(from: candidate) else { return }
		recent = RecentReactions.recording(emoji, in: recent)
		Preferences.Reactions.recent.value = recent
		send(emoji)
	}
}

/// AppKit presentation shell for the SwiftUI reaction picker.
@MainActor
final class ReactionPopover: NSObject, NSPopoverDelegate {
	let messageIdentifier: String
	var completion: ((String, String) -> Void)?

	private var popover: NSPopover?

	init(messageIdentifier: String) {
		self.messageIdentifier = messageIdentifier
	}

	func present(relativeTo rect: NSRect, of view: NSView) {
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

	func close() {
		popover?.close()
	}

	func popoverDidClose(_: Notification) {
		popover = nil
	}

	private func submit(_ emoji: String) {
		completion?(emoji, messageIdentifier)
		close()
	}
}
