// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

struct OnboardingAppearanceView: View {
	@Bindable var settings: OnboardingSettings

	var body: some View {
		VStack(spacing: 18) {
			HStack(spacing: 18) {
				ForEach(OnboardingTranscriptStyle.allCases) { style in
					OnboardingStylePreview(
						style: style,
						fontSize: settings.appearance.textSize.fontSize,
						isSelected: settings.appearance.transcriptStyle == style
					) { settings.appearance.transcriptStyle = style }
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

/// One line of the mock transcript the appearance step previews.
private struct OnboardingAppearancePreviewMessage {
	let nickname: LocalizedStringResource
	let message: LocalizedStringResource
}

private struct OnboardingStylePreview: View {
	let style: OnboardingTranscriptStyle
	let fontSize: CGFloat
	let isSelected: Bool
	let select: () -> Void

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

	private var usesBubbles: Bool {
		style == .bubbles
	}

	var body: some View {
		let messages = Array(Self.previewMessages.enumerated())

		Button(action: select) {
			VStack(spacing: UISpacing.regular) {
				ZStack(alignment: .topTrailing) {
					VStack(spacing: 6) {
						ForEach(messages, id: \.offset) { index, message in
							previewRow(message, outgoing: index == 2)
						}
					}
					.padding(UISpacing.wide)
					.frame(maxWidth: .infinity, minHeight: 150, alignment: .top)
					.background(.background, in: RoundedRectangle(cornerRadius: 10))
					.overlay {
						RoundedRectangle(cornerRadius: 10)
							.stroke(
								isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
								lineWidth: isSelected ? 2 : 1
							)
					}

					if isSelected {
						Image(systemName: "checkmark.circle.fill")
							.foregroundStyle(.tint)
							.padding(UISpacing.regular)
					}
				}

				Text(style.title).font(.headline)
				Text(style.summary)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.buttonStyle(.plain)
		.frame(maxWidth: .infinity)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(Text(style.title))
		.accessibilityAddTraits(isSelected ? [.isSelected] : [])
	}

	@ViewBuilder
	private func previewRow(_ message: OnboardingAppearancePreviewMessage, outgoing: Bool) -> some View {
		if usesBubbles {
			HStack {
				if outgoing {
					Spacer(minLength: 30)
				}
				VStack(alignment: .leading, spacing: 1) {
					if outgoing == false {
						Text(message.nickname)
							.font(.system(size: max(9, fontSize - 2), weight: .semibold))
							.foregroundStyle(.secondary)
					}
					Text(message.message)
						.font(.system(size: fontSize))
						.foregroundStyle(outgoing ? Color.white : Color.primary)
				}
				.padding(.horizontal, 9)
				.padding(.vertical, 5)
				.background(outgoing ? Color.accentColor : Color.secondary.opacity(0.16))
				.clipShape(RoundedRectangle(cornerRadius: 11))
				if outgoing == false {
					Spacer(minLength: 30)
				}
			}
		} else {
			HStack(alignment: .firstTextBaseline, spacing: 5) {
				Text(.Onboarding.stepLookAndFeel)
					.font(.system(size: max(9, fontSize - 2), design: .monospaced))
					.foregroundStyle(.tertiary)
				/* The angle brackets are how the lines style marks a nickname,
				 so they are punctuation around the name rather than copy. */
				Text(verbatim: "<\(String(localized: message.nickname))>")
					.font(.system(size: fontSize, weight: .semibold))
					.foregroundStyle(outgoing ? Color.accentColor : Color.primary)
				Text(message.message)
					.font(.system(size: fontSize))
					.lineLimit(1)
				Spacer(minLength: 0)
			}
		}
	}
}
