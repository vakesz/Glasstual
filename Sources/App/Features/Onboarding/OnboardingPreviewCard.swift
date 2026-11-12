// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

/** The transcript colours and font an onboarding preview draws with.

 Read from the theme the choice would install, in the appearance chosen on
 the appearance step, so a preview is the transcript the reader will get
 rather than an illustration of it. */
struct OnboardingPreviewPalette {
	let background: Color
	let text: Color
	let timestamp: Color
	let localNickname: Color
	let remoteNickname: Color
	let bubbleIncoming: Color
	let bubbleOutgoing: Color
	let font: Font
	let smallFont: Font

	init(theme: TranscriptTheme, fontSize: CGFloat, isDark: Bool, increasesContrast: Bool) {
		let system = TranscriptSystemColors.current(isDark: isDark, increasesContrast: increasesContrast)
		func color(_ role: KeyPath<TranscriptThemePalette, AdaptiveTranscriptColor>) -> Color {
			Color(nsColor: theme.palette[keyPath: role].resolved(
				isDark: isDark,
				increasesContrast: increasesContrast,
				systemColors: system
			))
		}
		background = color(\.background)
		text = color(\.primaryText)
		timestamp = color(\.timestampText)
		localNickname = color(\.localNickname)
		remoteNickname = color(\.remoteNickname)
		bubbleIncoming = color(\.bubbleIncoming)
		bubbleOutgoing = color(\.bubbleOutgoing)
		font = Font(Self.font(named: theme.fontName, size: fontSize))
		smallFont = Font(Self.font(named: theme.fontName, size: Self.secondarySize(for: fontSize)))
	}

	/// The theme's font, or the system font where the named one is missing,
	/// as the transcript resolves it.
	static func font(named name: String, size: CGFloat) -> NSFont {
		NSFont(name: name, size: size) ?? .systemFont(ofSize: size)
	}

	/// A nickname or a time above a message: two points smaller, never below
	/// the smallest size a theme may use.
	static func secondarySize(for size: CGFloat) -> CGFloat {
		max(TranscriptTheme.fontSizeRange.lowerBound, size - 2)
	}
}

enum OnboardingPreviewMetrics {
	/// The least height a preview is drawn at.
	static let minimumHeight: CGFloat = 150
}

/// One choice of an onboarding step: a preview the reader picks by clicking,
/// with its name and what it means beneath.
struct OnboardingPreviewCard<Preview: View>: View {
	let title: LocalizedStringResource
	let caption: LocalizedStringResource
	let isSelected: Bool
	let colorScheme: ColorScheme
	let background: Color
	/// The height the preview is drawn at, where the step decides it. Without
	/// one the preview is as tall as its content, and never less than the
	/// minimum.
	var previewHeight: CGFloat?
	let select: () -> Void
	@ViewBuilder let preview: Preview

	/// The smallest radius the card keeps where the window offers no corner
	/// to be concentric with.
	private static var minimumCornerRadius: CGFloat {
		10
	}

	private var shape: ConcentricRectangle {
		ConcentricRectangle(corners: .concentric(minimum: .fixed(Self.minimumCornerRadius)), isUniform: true)
	}

	var body: some View {
		Button(action: select) {
			VStack(spacing: UISpacing.regular) {
				preview
					.padding(UISpacing.wide)
					.frame(
						maxWidth: .infinity,
						minHeight: previewHeight ?? OnboardingPreviewMetrics.minimumHeight,
						maxHeight: previewHeight,
						alignment: .top
					)
					.background(background, in: shape)
					.overlay {
						shape.stroke(
							isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(nsColor: .separatorColor)),
							lineWidth: isSelected ? 2 : 1
						)
					}
					.overlay(alignment: .topTrailing) {
						if isSelected {
							Image(systemName: "checkmark.circle.fill")
								.foregroundStyle(.tint)
								.padding(UISpacing.regular)
						}
					}
					.environment(\.colorScheme, colorScheme)
					.accessibilityHidden(true)

				Text(title).font(.headline)
				Text(caption)
					.font(.caption)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
			}
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.frame(maxWidth: .infinity)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(Text(.Onboarding.appearanceStyleAccessibilityLabel(
			String(localized: title),
			String(localized: caption)
		)))
		.accessibilityAddTraits(.isButton)
		.accessibilityAddTraits(isSelected ? [.isSelected] : [])
		/* The element stands in for the button, so it needs the button's
		 action: without it, VoiceOver's press chose nothing. */
		.accessibilityAction { select() }
	}
}
