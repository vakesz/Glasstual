// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import SwiftUI

/// The transcript, with the input bar floating over its foot.
struct MainWindowConversation: View {
	let columns: MainWindowColumnModel
	let inputContentView: InputFieldContentView

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.colorSchemeContrast) private var contrast

	/** The transcript fills the column and the input bar floats over its foot.
	 The transcript keeps the bar's height clear as its scroll view's bottom
	 content inset, and it measures that in AppKit: the field's frame plus the
	 capsule padding above it, and the accessory strip's height from what the
	 strip is showing. Nothing here reads SwiftUI's layout back into state. An
	 `onGeometryChange` on the bar did, and a size read during layout that then
	 changes the view tree sends the split view back to measure the column; it
	 lays the bar out at its probe sizes on the way, those are reported too, and
	 the loop never settles: the columns were drawn at whatever width it was
	 passing through, and AppKit threw after three hundred passes. A
	 `safeAreaInset` is the same loop through a different door. */
	var body: some View {
		VStack(spacing: 0) {
			TranscriptHistoryRecoveryView(controller: columns.transcript?.viewController)
			ZStack(alignment: .bottom) {
				/* No `.scrollEdgeEffectStyle` beside the member list's, and it is
				 not an oversight. The transcript is an AppKit `NSScrollView`
				 that this view only hosts, and the modifier is SwiftUI's: it
				 reaches SwiftUI's own scrollable content, not a scroll view
				 inside an `NSViewRepresentable`. AppKit has no equivalent -- the
				 macOS 26 SDK declares `NSScrollEdgeEffectStyle` but the only
				 public properties that take one are on
				 `NSTitlebarAccessoryViewController` and
				 `NSSplitViewItemAccessoryViewController`, and `NSScrollView`
				 exposes nothing at all -- so the transcript cannot ask for the
				 soft treatment the lists get. It also has nothing to soften: the
				 representable is laid out inside the safe area, so the
				 conversation starts below the toolbar rather than scrolling
				 under it, and the list -- whose own scroll view runs the full
				 height and insets its rows by the titlebar instead -- starts its
				 first row on the same line. `MainWindowColumnAlignmentTests`
				 measures both. Insetting this column by hand to close the
				 remaining difference is what the comment above rules out: it
				 makes the column's insets depend on the column's own layout. */
				TranscriptViewRepresentable(
					transcriptView: columns.transcript,
					inputField: inputContentView,
					accessoryHeight: InputBarLayout.accessoryHeight(
						for: inputContentView.textView.accessoryModel
					) + SlashCommandDiscoveryView.height(for: inputContentView.textView.commandDiscovery),
					isObscured: columns.isConversationObscured
				)
				.id(columns.appearanceRevision)

				inputBar
			}
		}
		.background(columns.conversationBackground)
	}

	/** The reply banner and the field are two glass shapes over the same ground,
	 so they share one container and sample one backdrop. The zero spacing keeps
	 them from merging: they carry different shapes and insets, and a blend
	 between the two reads as a smear rather than as one control. */
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
				/* The banner's text starts where the field's does: the capsule's
				 own inset plus the inset that holds the capsule off the column's
				 edge. */
				.padding(.horizontal, UISpacing.loose)

				MainWindowInputRepresentable(contentView: inputContentView)
					.frame(
						minHeight: InputBarLayout.minimumHostHeight,
						idealHeight: InputBarLayout.idealHostHeight
					)
					.padding(.horizontal, UISpacing.regular)
					.padding(.vertical, InputBarLayout.fieldVerticalPadding)
					.glassEffect(.regular, in: .capsule)
					.overlay(focusRing)
					.padding(.horizontal, UISpacing.regular)
					.padding(.bottom, InputBarLayout.bottomPadding)
			}
		}
	}

	/** What says the keyboard is in the message field.

	 Glass draws no focus ring of its own and the field's own ring is turned
	 off, so nothing marked the field as the place typing would land. The
	 capsule takes the system's own focus-ring colour while the field holds the
	 keyboard -- which tracks both the accent setting and Increase Contrast --
	 drawn thicker where the system asks for increased contrast. */
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

	/** Width from SwiftUI, height from the field.

	 The field's height is a constraint its text view moves as the text grows,
	 and that is what the column should follow. Its width, left to SwiftUI's
	 default measurement of an AppKit view, comes back as whatever it was last
	 laid out at, and the split view reads that as the column's minimum: the
	 column could then never shrink to make room for the member list, and the
	 columns spilled past the window's edges. */
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
