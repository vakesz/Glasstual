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
	@State private var systemAppearance = SystemAppearanceSnapshot()

	private var previewColorScheme: ColorScheme {
		switch settings.appearance.previewMode(systemMode: systemAppearance.mode) {
		case .light: .light
		case .dark: .dark
		}
	}

	var body: some View {
		VStack(spacing: 18) {
			HStack(spacing: 18) {
				ForEach(InteractionStyle.allCases, id: \.self) { style in
					OnboardingInteractionPreview(
						style: style,
						colorScheme: previewColorScheme,
						isSelected: settings.interaction == style
					) { settings.interaction = style }
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
		.frame(maxWidth: .infinity, alignment: .center)
	}
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

private struct OnboardingInteractionPreview: View {
	let style: InteractionStyle
	let colorScheme: ColorScheme
	let isSelected: Bool
	let select: () -> Void

	@Environment(\.colorSchemeContrast) private var contrast

	var body: some View {
		Button(action: select) {
			VStack(spacing: UISpacing.regular) {
				ZStack(alignment: .topTrailing) {
					preview
						.padding(UISpacing.wide)
						.frame(maxWidth: .infinity, minHeight: 170, alignment: .top)
						.background(.background, in: RoundedRectangle(cornerRadius: 10))
						.overlay {
							RoundedRectangle(cornerRadius: 10)
								.stroke(
									isSelected ? Color.accentColor : Color.secondary.opacity(contrast == .increased ? 1 : 0.3),
									lineWidth: isSelected ? 2 : 1
								)
						}
					if isSelected {
						Image(systemName: "checkmark.circle.fill")
							.foregroundStyle(.tint)
							.padding(UISpacing.regular)
					}
				}
				.environment(\.colorScheme, colorScheme)
				.accessibilityHidden(true)

				Text(style.displayName).font(.headline)
				Text(style.onboardingCaption)
					.font(.caption)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.buttonStyle(.plain)
		.frame(maxWidth: .infinity)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(Text(.Onboarding.appearanceStyleAccessibilityLabel(
			String(localized: style.displayName),
			String(localized: style.onboardingCaption)
		)))
		.accessibilityAddTraits(.isButton)
		.accessibilityAddTraits(isSelected ? [.isSelected] : [])
		.accessibilityIdentifier(style.onboardingIdentifier)
	}

	@ViewBuilder
	private var preview: some View {
		switch style {
		case .dialogs: dialogPreview
		case .conversation: conversationPreview
		}
	}

	private var transcript: some View {
		VStack(alignment: .leading, spacing: 5) {
			line(.Onboarding.stepLookAndFeelAlice, .Onboarding.goodMorningEveryone)
			line(.Onboarding.stepLookAndFeelBob, .Onboarding.morningAnyoneTriedTheNewBuild)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private func line(_ nickname: LocalizedStringResource, _ message: LocalizedStringResource) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 4) {
			Text(nickname).font(.system(size: 10, weight: .semibold))
			Text(message).font(.system(size: 10)).lineLimit(1)
		}
	}

	/// A miniature alert over a dimmed conversation.
	private var dialogPreview: some View {
		ZStack {
			VStack(alignment: .leading, spacing: 5) {
				transcript
				Spacer(minLength: 0)
			}
			.opacity(0.35)

			VStack(spacing: 6) {
				Image(systemName: "app.badge.fill")
					.font(.system(size: 18))
					.foregroundStyle(.tint)
				Text(.Onboarding.interactionPreviewQuestion)
					.font(.system(size: 10, weight: .semibold))
					.multilineTextAlignment(.center)
				HStack(spacing: 6) {
					miniButton(.Onboarding.interactionPreviewCancel, prominent: false)
					miniButton(.Onboarding.interactionPreviewSend, prominent: true)
				}
			}
			.padding(10)
			.frame(width: 150)
			.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
			.shadow(color: .black.opacity(0.18), radius: 6, y: 2)
		}
	}

	/// The same question as a card above the message field, answered by typing.
	private var conversationPreview: some View {
		VStack(alignment: .leading, spacing: 6) {
			transcript
			Spacer(minLength: 0)
			HStack(alignment: .firstTextBaseline, spacing: 5) {
				Image(systemName: "questionmark.bubble")
					.font(.system(size: 10))
					.foregroundStyle(.tint)
				VStack(alignment: .leading, spacing: 4) {
					Text(.Onboarding.interactionPreviewQuestion)
						.font(.system(size: 10, weight: .semibold))
					HStack(spacing: 6) {
						Spacer(minLength: 0)
						miniButton(.Onboarding.interactionPreviewCancel, prominent: false)
						miniButton(.Onboarding.interactionPreviewSend, prominent: true)
					}
				}
			}
			.padding(6)
			.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
			Text(verbatim: "/yes")
				.font(.system(size: 10, design: .monospaced))
				.padding(.horizontal, 8)
				.padding(.vertical, 4)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(Color.secondary.opacity(0.12), in: Capsule())
		}
	}

	private func miniButton(_ title: LocalizedStringResource, prominent: Bool) -> some View {
		Text(title)
			.font(.system(size: 9, weight: .medium))
			.foregroundStyle(prominent ? Color.white : Color.primary)
			.padding(.horizontal, 8)
			.padding(.vertical, 3)
			.background(prominent ? Color.accentColor : Color.secondary.opacity(0.18), in: Capsule())
	}
}
