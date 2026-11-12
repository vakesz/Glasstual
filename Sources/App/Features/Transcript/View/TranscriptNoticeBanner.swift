// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/** The one banner the transcript draws above its text.

 The history upgrade, a history that could not be loaded, and a window of
 stored history that is not the end of the conversation are three states with
 the same shape: a glyph, a line saying what happened, sometimes a second line
 or a progress bar, and one thing to do about it. They used to be three
 differently sized banners in `.headline`, stacked when more than one applied;
 this is the shape once, in `.subheadline`, so a notice reads as a notice and
 not as a second toolbar. */
struct TranscriptNoticeBanner: View {
	struct Action {
		let title: String
		let identifier: String
		var isEnabled = true
		let perform: () -> Void
	}

	let symbol: String?
	/// The glyph's tint, or `nil` for the symbol's own colours, which is how
	/// the system draws a warning: the multicolour yellow triangle.
	var symbolTint: Color? = .secondary
	var symbolLabel: String?
	let title: String
	var detail: String?
	/// The progress of work the notice is waiting on, or `nil` for none.
	var progress: Double?
	var isBusy = false
	/// The one thing to do about the notice, shown prominently.
	var primaryAction: Action?
	/// A second, quieter thing to do, for the notice that has two ways out.
	var secondaryAction: Action?
	let identifier: String

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: UISpacing.regular) {
			if let symbol {
				Image(systemName: symbol)
					.symbolRenderingMode(symbolTint == nil ? .multicolor : .monochrome)
					.foregroundStyle(symbolTint ?? .primary)
					.accessibilityLabel(symbolLabel ?? "")
					.accessibilityHidden(symbolLabel == nil)
			}
			VStack(alignment: .leading, spacing: UISpacing.tight) {
				Text(verbatim: title)
					.font(.subheadline.weight(.medium))
				if let detail {
					Text(verbatim: detail)
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.textSelection(.enabled)
				}
				if let progress {
					ProgressView(value: progress)
						.accessibilityLabel(Text(verbatim: title))
				}
			}
			Spacer(minLength: UISpacing.regular)
			if isBusy {
				ProgressView().controlSize(.small)
			}
			if let secondaryAction {
				button(for: secondaryAction)
			}
			if let primaryAction {
				button(for: primaryAction)
					.buttonStyle(.borderedProminent)
			}
		}
		.controlSize(.small)
		.padding(.horizontal, UISpacing.wide)
		.padding(.vertical, UISpacing.regular)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(.bar)
		.accessibilityElement(children: .contain)
		.accessibilityIdentifier(identifier)
	}

	private func button(for action: Action) -> some View {
		Button(action.title, action: action.perform)
			.disabled(action.isEnabled == false)
			.accessibilityIdentifier(action.identifier)
	}
}
