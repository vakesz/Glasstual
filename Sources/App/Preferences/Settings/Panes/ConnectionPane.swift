// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// The Connection row: how much the client asks of a server at once, and what
/// it does with what arrives.
struct ConnectionPane: View {
	/* The steps keep the tick marks the sliders have always stopped on. */
	private static let delayStep = 0.5
	private static let delayRange = 0.0 ... 10.0
	private static let channelSizeStep = 40.0
	private static let channelSizeRange = 0.0 ... 2000.0

	let model: SettingsModel

	var body: some View {
		Section {
			delayRow
			SettingsNote(.Settings.floodControlIdentifyDelayNote)
			channelSizeRow
			SettingsNote(.Settings.floodControlWhoLimitNote)
			SettingsNote(.Settings.floodControlNote)
		} header: {
			Text(SettingsPane.floodControl.title)
		}

		Section {
			SettingsToggle(
				title: .Settings.incomingDataReplyCtcp,
				isOn: model.preferences.binding(for: Preferences.Messages.replyToCTCPRequests)
			)
			SettingsToggle(
				title: .Settings.incomingDataHighlightSpam,
				note: .Settings.incomingDataHighlightSpamNote,
				isOn: model.preferences.binding(for: Preferences.Messages.detectHighlightSpam)
			)
			SettingsToggle(
				title: .Settings.incomingDataRemoveFormatting,
				note: .Settings.incomingDataRemoveFormattingNote,
				isOn: model.preferences.binding(for: Preferences.Messages.removeAllFormatting)
			)
			SettingsToggle(
				title: .Settings.incomingDataUnicodeSpam,
				note: .Settings.incomingDataUnicodeSpamNote,
				isOn: model.preferences.binding(for: Preferences.Messages.filterUnicodeTextSpam)
			)
		} header: {
			Text(SettingsPane.incomingData.title)
		}
	}

	private var delayRow: some View {
		let value = model.preferences.binding(
			for: Preferences.Connection.autojoinDelayAfterIdentification
		)
		return SettingsSliderRow(
			label: .Settings.floodControlIdentifyDelayLabel,
			valueText: .Settings.floodControlSecondsValue(Self.secondsText(value.wrappedValue)),
			range: Self.delayRange,
			step: Self.delayStep,
			minimumLabel: Self.secondsText(Self.delayRange.lowerBound),
			maximumLabel: Self.secondsText(Self.delayRange.upperBound),
			value: value
		)
	}

	private var channelSizeRow: some View {
		let value = model.preferences.sliderBinding(
			for: Preferences.Appearance.trackUserAwayStatusMaximumChannelSize
		)
		return SettingsSliderRow(
			label: .Settings.floodControlWhoLimitLabel,
			valueText: .Settings.floodControlCountValue(Self.countText(value.wrappedValue)),
			range: Self.channelSizeRange,
			step: Self.channelSizeStep,
			minimumLabel: String(localized: .Settings.floodControlDisabledMarker),
			maximumLabel: Self.countText(Self.channelSizeRange.upperBound),
			value: value
		)
	}

	private static func secondsText(_ value: Double) -> String {
		value.formatted(.number.precision(.fractionLength(1)))
	}

	/** Formatted as a `Double`, because the stored count a hand-edited defaults
	 file can leave here is not always one an `Int` can hold, and a label is not
	 worth a trap. */
	private static func countText(_ value: Double) -> String {
		value.rounded().formatted(.number.precision(.fractionLength(0)))
	}
}

/// One slider row: the setting's name and current value on the left, the
/// slider between the ends of its range on the right.
private struct SettingsSliderRow: View {
	let label: LocalizedStringResource
	let valueText: LocalizedStringResource
	let range: ClosedRange<Double>
	let step: Double
	/// The ends of the range, already formatted: a count and a duration are
	/// numbers rather than sentences.
	let minimumLabel: String
	let maximumLabel: String
	@Binding var value: Double

	var body: some View {
		Slider(value: $value, in: range, step: step) {
			VStack(alignment: .leading, spacing: 2) {
				Text(label)
				Text(valueText)
					.font(.callout)
					.foregroundStyle(.secondary)
			}
		} minimumValueLabel: {
			endLabel(minimumLabel)
		} maximumValueLabel: {
			endLabel(maximumLabel)
		}
		.accessibilityLabel(Text(label))
		.accessibilityValue(Text(valueText))
	}

	private func endLabel(_ text: String) -> some View {
		Text(verbatim: text)
			.font(.callout)
			.foregroundStyle(.secondary)
	}
}
