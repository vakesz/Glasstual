// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import SwiftUI

/// The transcript with an overlaid input bar.
struct MainWindowConversation: View {
	let columns: MainWindowColumnModel
	let inputContentView: InputFieldContentView

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.colorSchemeContrast) private var contrast

	/// AppKit measures the input bar and reserves its height in the transcript's
	/// bottom inset. Feeding SwiftUI geometry back into layout can cause a loop.
	var body: some View {
		VStack(spacing: 0) {
			TranscriptHistoryRecoveryView(controller: columns.transcript?.viewController)
			ZStack(alignment: .bottom) {
				// The native scroll view stays inside the toolbar safe area.
				// SwiftUI's scrollEdgeEffectStyle does not reach hosted NSScrollViews.
				TranscriptViewRepresentable(
					transcriptView: columns.transcript,
					inputField: inputContentView,
					accessoryHeight: InputBarLayout.accessoryHeight(
						for: inputContentView.textView.accessoryModel
					) + SlashCommandDiscoveryView.height(for: inputContentView.textView.commandDiscovery),
					isObscured: columns.isConversationObscured
				)

				inputBar
			}
		}
		.background(columns.conversationBackground)
	}

	/// The reply banner and input capsule share a glass backdrop.
	private var inputBar: some View {
		GlassEffectContainer(spacing: 0) {
			VStack(spacing: 0) {
				SlashCommandDiscoveryView(model: inputContentView.textView.commandDiscovery) { suggestion in
					inputContentView.textView.acceptSlashCommand(suggestion)
				}
				.padding(.horizontal, UISpacing.regular)

				InputAccessoryView(model: inputContentView.textView.accessoryModel) {
					inputContentView.textView.focus()
				}
				// Align the reply text with the field's text inset.
				.padding(.horizontal, UISpacing.loose)

				/* The field's own height constraint is the capsule's height. A
				 SwiftUI frame around it let a short column squeeze the capsule
				 below the field: the field overflowed the glass, and the
				 transcript's inset, measured from the field, missed the bar. */
				MainWindowInputRepresentable(contentView: inputContentView)
					.padding(.horizontal, UISpacing.regular)
					.padding(.vertical, InputBarLayout.fieldVerticalPadding)
					.glassEffect(.regular, in: .capsule)
					.overlay(focusRing)
					.padding(.horizontal, UISpacing.regular)
					.padding(.bottom, InputBarLayout.bottomPadding)
			}
		}
	}

	/// The capsule owns the field's focus ring and follows system contrast and motion settings.
	private var focusRing: some View {
		Capsule()
			.strokeBorder(
				Color(nsColor: .keyboardFocusIndicatorColor),
				lineWidth: contrast == .increased
					? MainWindowConstants.focusRingWidthIncreasedContrast
					: MainWindowConstants.focusRingWidth
			)
			.opacity(inputContentView.textView.focusModel.isFocused ? 1 : 0)
			.animation(
				reduceMotion ? nil : .easeOut(duration: 0.12),
				value: inputContentView.textView.focusModel.isFocused
			)
			.accessibilityHidden(true)
	}
}

private struct MainWindowInputRepresentable: NSViewRepresentable {
	let contentView: InputFieldContentView

	func makeNSView(context _: Context) -> InputFieldContentView {
		contentView.removeFromSuperview()
		return contentView
	}

	func updateNSView(_: InputFieldContentView, context _: Context) {}

	/// Accept SwiftUI's proposed width; derive height from the text field's constraints.
	func sizeThatFits(
		_ proposal: ProposedViewSize,
		nsView: InputFieldContentView,
		context _: Context
	) -> CGSize? {
		CGSize(
			width: proposal.width ?? MainWindowConstants.conversationMinimumWidth,
			height: nsView.fittingSize.height
		)
	}
}
