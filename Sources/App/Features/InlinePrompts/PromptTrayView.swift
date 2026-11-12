// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/** The questions waiting in the conversation on screen, above the message field.

 Oldest first, so they read in the order they were asked; past a few, the rest
 wait behind a count rather than pushing the conversation off the window.
 Questions waiting in other conversations are a single line with a way there.
 The tray holds no state of its own: the registry is the questions, and a
 card disappears the moment its question is answered or withdrawn. */
struct PromptTrayView: View {
	let registry: PendingPromptRegistry
	/// The chat item whose conversation is on screen.
	let itemID: String?
	/// What the last typed answering command had to say, if anything.
	let feedback: String?
	/// Brings the conversation with the oldest waiting question on screen.
	let showItem: (String) -> Void
	let answered: (PendingPrompt, PromptAnswerResult) -> Void

	/// The most cards shown at once.
	static let visibleLimit = 3

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private var here: [PendingPrompt] {
		guard let itemID else { return [] }
		return registry.inlinePrompts(inItem: itemID)
	}

	private var elsewhere: [PendingPrompt] {
		registry.pending.filter { prompt in
			guard let anchor = prompt.route.itemID else { return false }
			return anchor != itemID
		}
	}

	var body: some View {
		let here = here
		let shown = Array(here.prefix(Self.visibleLimit))
		let generation = shown.map(\.number).reduce(into: Hasher()) { $0.combine($1) }.finalize()
		VStack(alignment: .leading, spacing: UISpacing.tight) {
			if let feedback {
				Label {
					Text(verbatim: feedback)
				} icon: {
					Image(systemName: "info.circle")
				}
				.font(.caption)
				.foregroundStyle(.secondary)
				.padding(.horizontal, UISpacing.wide)
				.accessibilityIdentifier("prompt-feedback")
			}
			ForEach(shown) { prompt in
				PromptCardView(prompt: prompt, registry: registry, layoutGeneration: generation) { result in
					answered(prompt, result)
				}
				.transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
			}
			if here.count > shown.count {
				Text(.InlinePrompts.moreHere(here.count - shown.count))
					.font(.caption)
					.foregroundStyle(.secondary)
					.padding(.horizontal, UISpacing.wide)
					.accessibilityIdentifier("prompt-more-here")
			}
			if let first = elsewhere.first, let anchor = first.route.itemID {
				HStack(spacing: UISpacing.regular) {
					Image(systemName: "questionmark.bubble")
						.foregroundStyle(.secondary)
						.accessibilityHidden(true)
					Text(.InlinePrompts.waitingElsewhere(elsewhere.count))
						.font(.subheadline)
						.foregroundStyle(.secondary)
					Spacer(minLength: UISpacing.regular)
					Button(String(localized: .InlinePrompts.show)) {
						showItem(anchor)
					}
					.controlSize(.small)
					.accessibilityIdentifier("prompt-elsewhere-show")
				}
				.padding(.horizontal, UISpacing.wide)
				.frame(minHeight: InputBarLayout.replyBannerHeight)
				.background(.regularMaterial, in: .rect(cornerRadius: InputBarLayout.accessoryCornerRadius))
				.accessibilityElement(children: .contain)
				.accessibilityIdentifier("prompt-elsewhere")
			}
		}
		.animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: shown.map(\.number))
		.accessibilityElement(children: .contain)
		.accessibilityLabel(Text(.InlinePrompts.trayLabel))
		.accessibilityIdentifier("prompt-tray")
	}
}
