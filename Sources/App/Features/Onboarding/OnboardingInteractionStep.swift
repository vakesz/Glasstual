// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/** The step that asks how Glasstual asks: questions as dialogs, or in the
 conversation answered by a click or a typed command.

 Two previews side by side, drawn with the same semantic colours the window
 uses and in the appearance chosen on the step before, so the choice is made
 by looking rather than by reading a description of it. */
struct OnboardingInteractionView: View {
	@Bindable var settings: OnboardingSettings
	/// The height the window gives a step, between the heading and the buttons.
	var availableHeight: CGFloat = 0
	@State private var systemAppearance = SystemAppearanceSnapshot()
	@Environment(\.colorSchemeContrast) private var contrast

	private var previewColorScheme: ColorScheme {
		switch settings.appearance.previewMode(systemMode: systemAppearance.mode) {
		case .light: .light
		case .dark: .dark
		}
	}

	var body: some View {
		let palette = OnboardingPreviewPalette(
			theme: settings.appearance.transcriptStyle.theme,
			fontSize: settings.appearance.textSize.fontSize,
			isDark: previewColorScheme == .dark,
			increasesContrast: contrast == .increased
		)
		VStack(spacing: UISpacing.spacious) {
			HStack(spacing: UISpacing.spacious) {
				ForEach(InteractionStyle.allCases, id: \.self) { style in
					OnboardingPreviewCard(
						title: style.displayName,
						caption: style.onboardingCaption,
						isSelected: settings.interaction == style,
						colorScheme: previewColorScheme,
						background: palette.background,
						previewHeight: Self.previewHeight(forAvailableHeight: availableHeight),
						select: { settings.interaction = style },
						preview: { OnboardingInteractionPreview(style: style, palette: palette) }
					)
					.accessibilityIdentifier(style.onboardingIdentifier)
				}
			}
			.accessibilityElement(children: .contain)
			.accessibilityLabel(Text(.Onboarding.howGlasstualAsks))

			Text(.Onboarding.interactionChangeLater)
				.font(.callout)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.frame(maxWidth: 440)
		}
		/* The two previews are all this step has, so they take the room the
		 window offers and what is left is shared above and below them, rather
		 than left empty under a step that stops halfway down. */
		.frame(maxWidth: .infinity, minHeight: availableHeight, alignment: .center)
	}

	/** How tall a preview is drawn for the room a step has.

	 A preview is a miniature of a conversation, so it grows with the window
	 up to the proportions of one and never shrinks below the size the
	 appearance step draws its own at. */
	static func previewHeight(forAvailableHeight height: CGFloat) -> CGFloat {
		min(maximumPreviewHeight, max(OnboardingPreviewMetrics.minimumHeight, (height * previewShare).rounded()))
	}

	private static let maximumPreviewHeight: CGFloat = 280
	/// The part of a step's height its previews take; the rest is their
	/// names, their captions and the note beneath.
	private static let previewShare: CGFloat = 0.6
}

extension InteractionStyle {
	/// The line under a preview, saying what choosing it means.
	var onboardingCaption: LocalizedStringResource {
		switch self {
		case .dialogs: .Onboarding.interactionDialogsCaption
		case .conversation: .Onboarding.interactionConversationCaption
		}
	}

	var onboardingIdentifier: String {
		switch self {
		case .dialogs: AccessibilityIdentifier.onboardingInteractionDialogs
		case .conversation: AccessibilityIdentifier.onboardingInteractionConversation
		}
	}
}

/** A miniature of the conversation with the same question asked each way,
 drawn from the transcript the reader chose and with real controls, so the
 alert and the card look as they will. */
private struct OnboardingInteractionPreview: View {
	let style: InteractionStyle
	let palette: OnboardingPreviewPalette

	/// The miniature alert's and question card's corners, scaled down with them.
	private static let alertCornerRadius: CGFloat = 10
	private static let questionCornerRadius: CGFloat = 8

	var body: some View {
		switch style {
		case .dialogs: dialogPreview
		case .conversation: conversationPreview
		}
	}

	private var transcript: some View {
		VStack(alignment: .leading, spacing: UISpacing.tight) {
			line(.Onboarding.stepLookAndFeelAlice, .Onboarding.goodMorningEveryone)
			line(.Onboarding.stepLookAndFeelBob, .Onboarding.morningAnyoneTriedTheNewBuild)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private func line(_ nickname: LocalizedStringResource, _ message: LocalizedStringResource) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: UISpacing.tight) {
			Text(nickname)
				.font(palette.smallFont.weight(.semibold))
				.foregroundStyle(palette.remoteNickname)
			Text(message)
				.font(palette.smallFont)
				.foregroundStyle(palette.text)
				.lineLimit(1)
		}
	}

	/// The two answers, as the real buttons at their smallest size.
	private var answers: some View {
		HStack(spacing: UISpacing.snug) {
			Button(.Onboarding.interactionPreviewCancel) {}
			Button(.Onboarding.interactionPreviewSend) {}
				.buttonStyle(.borderedProminent)
		}
		.controlSize(.mini)
		.allowsHitTesting(false)
	}

	/// A miniature alert over the conversation.
	private var dialogPreview: some View {
		ZStack {
			VStack(alignment: .leading, spacing: UISpacing.tight) {
				transcript
				Spacer(minLength: 0)
			}
			.opacity(0.35)

			VStack(spacing: UISpacing.snug) {
				Image(nsImage: NSApp.applicationIconImage)
					.resizable()
					.frame(width: 24, height: 24)
				Text(.Onboarding.interactionPreviewQuestion)
					.font(.caption.weight(.semibold))
					.multilineTextAlignment(.center)
				answers
			}
			.padding(UISpacing.comfortable)
			.frame(width: 150)
			.background(.regularMaterial, in: .rect(cornerRadius: Self.alertCornerRadius))
			.shadow(radius: UISpacing.snug, y: 2)
		}
	}

	/// The same question as a card above the message field, answered by a
	/// click or by typing.
	private var conversationPreview: some View {
		VStack(alignment: .leading, spacing: UISpacing.snug) {
			transcript
			Spacer(minLength: 0)
			VStack(alignment: .leading, spacing: UISpacing.tight) {
				Label(.Onboarding.interactionPreviewQuestion, systemImage: "questionmark.bubble")
					.font(.caption.weight(.semibold))
				HStack {
					Spacer(minLength: 0)
					answers
				}
			}
			.padding(UISpacing.snug)
			.background(.regularMaterial, in: .rect(cornerRadius: Self.questionCornerRadius))
			Text(verbatim: "/yes")
				.font(palette.smallFont)
				.foregroundStyle(palette.text)
				.padding(.horizontal, UISpacing.regular)
				.padding(.vertical, UISpacing.tight)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(.quaternary, in: .capsule)
		}
	}
}
