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
	/// The height the waiting questions take above the input bar, reserved in
	/// the transcript's inset so the newest line is never hidden behind them.
	/// The tray's height depends only on its width, so measuring it does not
	/// feed back into its own layout.
	@State private var promptTrayHeight: CGFloat = 0
	/// The height of the notices over the top of the transcript, which the
	/// transcript keeps its topic and first line below. The banners' height
	/// depends only on their width and content, as the tray's does.
	@State private var noticeHeight: CGFloat = 0

	/// AppKit measures the input bar and reserves its height in the transcript's
	/// bottom inset. Feeding SwiftUI geometry back into layout can cause a loop.
	var body: some View {
		ZStack(alignment: .top) {
			ZStack(alignment: .bottom) {
				/* The transcript runs under the toolbar, so its text scrolls
				 beneath the Liquid Glass and its scroll edge effect; the
				 transcript keeps its topic and first line clear of the toolbar
				 through its own safe area, and of the notices through the height
				 reported for them. */
				TranscriptViewRepresentable(
					transcriptView: columns.transcript,
					inputField: inputContentView,
					accessoryHeight: InputBarLayout.accessoryHeight(
						for: inputContentView.textView.accessoryModel
					) + SlashCommandDiscoveryView.height(for: inputContentView.textView.commandDiscovery) + promptTrayHeight,
					topAccessoryHeight: noticeHeight,
					isObscured: columns.isConversationObscured
				)
				.ignoresSafeArea(.container, edges: .top)

				inputBar
			}

			/* Notices sit under the toolbar on the bar material, over the text,
			 the way Mail's banners do. */
			VStack(spacing: 0) {
				ScrollbackMigrationBanner(recovery: Scrollback.shared.recovery)
				TranscriptHistoryRecoveryView(controller: columns.transcript?.viewController)
			}
			.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
				noticeHeight = height
			}
		}
		.background(columns.conversationBackground)
	}

	/// The input capsule is the only glass surface; the reply banner, the
	/// questions and the command list above it are flat material, so no glass
	/// sits on glass.
	private var inputBar: some View {
		VStack(spacing: 0) {
			promptTray
				.padding(.horizontal, UISpacing.regular)
				.padding(.bottom, AppServices.promptRegistry.pending.isEmpty ? 0 : UISpacing.tight)
				.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
					promptTrayHeight = height
				}

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

	/// The questions waiting in the conversation on screen, and elsewhere.
	private var promptTray: some View {
		let registry = AppServices.promptRegistry
		let itemID = columns.transcript?.viewController?.associatedItem?.uniqueIdentifier
		let feedback = registry.feedback.flatMap { $0.itemID == itemID ? $0.text : nil }
		return PromptTrayView(registry: registry, itemID: itemID, feedback: feedback) { anchor in
			columns.window?.showPromptAnchor(anchor)
		} answered: { prompt, result in
			columns.window?.promptWasAnswered(prompt, result: result)
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
