// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

struct OnboardingAppearanceView: View {
	@Bindable var settings: OnboardingSettings
	@State private var systemAppearance = SystemAppearanceSnapshot()
	@Environment(\.colorSchemeContrast) private var contrast

	private var previewColorScheme: ColorScheme {
		switch settings.appearance.previewMode(systemMode: systemAppearance.mode) {
		case .light: .light
		case .dark: .dark
		}
	}

	var body: some View {
		VStack(spacing: UISpacing.spacious) {
			HStack(spacing: UISpacing.spacious) {
				ForEach(OnboardingTranscriptStyle.allCases) { style in
					let palette = OnboardingPreviewPalette(
						theme: style.theme,
						fontSize: settings.appearance.textSize.fontSize,
						isDark: previewColorScheme == .dark,
						increasesContrast: contrast == .increased
					)
					OnboardingPreviewCard(
						title: style.title,
						caption: style.summary,
						isSelected: settings.appearance.transcriptStyle == style,
						colorScheme: previewColorScheme,
						background: palette.background,
						select: { settings.appearance.transcriptStyle = style },
						preview: { OnboardingStylePreview(style: style, palette: palette, isDark: previewColorScheme == .dark) }
					)
				}
			}
			.accessibilityElement(children: .contain)
			.accessibilityLabel(Text(.Onboarding.chatStyle))

			Form {
				Picker(.Onboarding.textSize, selection: $settings.appearance.textSize) {
					ForEach(OnboardingTextSize.allCases) { size in
						Text(size.title).tag(size)
					}
				}
				.pickerStyle(.segmented)

				Picker(.Onboarding.stepLookAndFeelAppearance, selection: $settings.appearance.preferredAppearance) {
					ForEach(PreferredAppearance.allCases, id: \.self) { appearance in
						Text(appearance.onboardingTitle).tag(appearance)
					}
				}
				.pickerStyle(.segmented)
			}
			.formStyle(.columns)
			.frame(maxWidth: 360)
		}
		.frame(maxWidth: .infinity, alignment: .center)
	}
}

extension OnboardingAppearance {
	func previewMode(systemMode: AppearanceMode) -> AppearanceMode {
		switch preferredAppearance {
		case .inherited: systemMode
		case .light: .light
		case .dark: .dark
		}
	}
}

/// One line of the mock transcript the appearance step previews.
private struct OnboardingAppearancePreviewMessage {
	let nickname: LocalizedStringResource
	let message: LocalizedStringResource
}

/// The same short exchange under each style, drawn as the transcript draws
/// it: the theme's font, its palette roles and the nickname colours.
private struct OnboardingStylePreview: View {
	let style: OnboardingTranscriptStyle
	let palette: OnboardingPreviewPalette
	let isDark: Bool

	/// The same short exchange under both styles, so the preview shows the
	/// layout rather than a difference in what was said.
	static let previewMessages: [OnboardingAppearancePreviewMessage] = [
		OnboardingAppearancePreviewMessage(
			nickname: .Onboarding.stepLookAndFeelAlice,
			message: .Onboarding.goodMorningEveryone
		),
		OnboardingAppearancePreviewMessage(
			nickname: .Onboarding.stepLookAndFeelBob,
			message: .Onboarding.morningAnyoneTriedTheNewBuild
		),
		OnboardingAppearancePreviewMessage(
			nickname: .Onboarding.stepLookAndFeelYou,
			message: .Onboarding.yesItWorksWellSoFar
		),
	]

	/// A miniature bubble's corners, rounded as far as its short height allows.
	private static let bubbleCornerRadius: CGFloat = 10

	var body: some View {
		VStack(spacing: UISpacing.snug) {
			ForEach(Array(Self.previewMessages.enumerated()), id: \.offset) { index, message in
				row(message, outgoing: index == Self.previewMessages.count - 1)
			}
		}
	}

	private func nicknameColor(_ message: OnboardingAppearancePreviewMessage, outgoing: Bool) -> Color {
		outgoing
			? palette.localNickname
			: Color(nsColor: NicknameColors.color(for: String(localized: message.nickname), isDark: isDark))
	}

	@ViewBuilder
	private func row(_ message: OnboardingAppearancePreviewMessage, outgoing: Bool) -> some View {
		switch style {
		case .bubbles:
			HStack {
				if outgoing {
					Spacer(minLength: UISpacing.spacious)
				}
				VStack(alignment: .leading, spacing: 1) {
					if outgoing == false {
						Text(message.nickname)
							.font(palette.smallFont.weight(.semibold))
							.foregroundStyle(nicknameColor(message, outgoing: outgoing))
					}
					Text(message.message)
						.font(palette.font)
						.foregroundStyle(palette.text)
				}
				.padding(.horizontal, UISpacing.regular)
				.padding(.vertical, UISpacing.tight)
				.background(
					outgoing ? palette.bubbleOutgoing : palette.bubbleIncoming,
					in: .rect(cornerRadius: Self.bubbleCornerRadius)
				)
				if outgoing == false {
					Spacer(minLength: UISpacing.spacious)
				}
			}
		case .lines:
			HStack(alignment: .firstTextBaseline, spacing: UISpacing.tight) {
				Text(.Onboarding.stepLookAndFeel)
					.font(palette.smallFont.monospacedDigit())
					.foregroundStyle(palette.timestamp)
				/* The angle brackets are how the lines style marks a nickname,
				 so they are punctuation around the name rather than copy. */
				Text(verbatim: "<\(String(localized: message.nickname))>")
					.font(palette.font.weight(.semibold))
					.foregroundStyle(nicknameColor(message, outgoing: outgoing))
				Text(message.message)
					.font(palette.font)
					.foregroundStyle(palette.text)
					.lineLimit(1)
				Spacer(minLength: 0)
			}
		}
	}
}
