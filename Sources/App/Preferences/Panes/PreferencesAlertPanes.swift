/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import SwiftUI

struct PreferencesNotificationsPane: View {
	/// The alert table's own height, taken from the view it loads from its nib.
	private static let alertTableHeight = 220.0

	let model: PreferencesPaneModel

	private var onlySpeakForSelection: Bool {
		model.preferences[Preferences.Notifications.onlySpeakForSelection]
	}

	var body: some View {
		PreferencesPaneLayout {
			Section {
				PreferencesHostedView(view: model.notificationHostView, height: Self.alertTableHeight)
					.accessibilityLabel(Text(verbatim: PreferencesNotificationsStrings.headingAlerts))
			} header: {
				Text(verbatim: PreferencesNotificationsStrings.headingAlerts)
			}

			Section {
				PreferencesToggle(
					title: PreferencesNotificationsStrings.onlySpeakSelection,
					isOn: model.preferences.binding(for: Preferences.Notifications.onlySpeakForSelection)
				)
				VStack(alignment: .leading, spacing: 6) {
					Text(verbatim: PreferencesNotificationsStrings.speechIncludeLabel)
					PreferencesToggle(
						title: PreferencesNotificationsStrings.speakChannelName,
						isOn: model.preferences.gatedBinding(
							for: Preferences.Notifications.flag(.channelMessage, .speakChannelName),
							enabledWhen: { self.onlySpeakForSelection == false }
						)
					)
					.disabled(onlySpeakForSelection)
					PreferencesToggle(
						title: PreferencesNotificationsStrings.speakNickname,
						isOn: model.preferences.binding(
							for: Preferences.Notifications.flag(.channelMessage, .speakNickname)
						)
					)
				}
				.padding(.leading, 16)
			} header: {
				Text(verbatim: PreferencesNotificationsStrings.headingSpeech)
			}

			Section {
				PreferencesToggle(
					title: PreferencesNotificationsStrings.dockBadgePrivate,
					isOn: model.preferences.binding(for: Preferences.Notifications.displayDockBadge)
				)
				PreferencesToggle(
					title: PreferencesNotificationsStrings.dockBadgePublic,
					isOn: model.preferences.binding(
						for: Preferences.Notifications.publicMessageCountOnDockBadge
					)
				)
				PreferencesToggle(
					title: PreferencesNotificationsStrings.postWhileInFocus,
					isOn: model.preferences.binding(for: Preferences.Notifications.postWhileInFocus)
				)
			} header: {
				Text(verbatim: PreferencesSectionStrings.advanced)
			}
		}
	}
}

struct PreferencesHighlightsPane: View {
	let model: PreferencesPaneModel

	private var matchingMethod: TXNicknameHighlightMatchType {
		model.preferences[Preferences.Highlights.matchingMethod]
	}

	private var usesRegularExpression: Bool {
		matchingMethod == .regularExpression
	}

	var body: some View {
		PreferencesPaneLayout {
			Section {
				Picker(selection: model.preferences.binding(for: Preferences.Highlights.matchingMethod)) {
					Text(verbatim: PreferencesHighlightsStrings.matchTypePartial)
						.tag(TXNicknameHighlightMatchType.partial)
					Text(verbatim: PreferencesHighlightsStrings.matchTypeExact)
						.tag(TXNicknameHighlightMatchType.exact)
					Text(verbatim: PreferencesHighlightsStrings.matchTypeRegex)
						.tag(TXNicknameHighlightMatchType.regularExpression)
				} label: {
					Text(verbatim: PreferencesHighlightsStrings.matchTypeLabel)
				}
				.labelsHidden()
				.accessibilityLabel(Text(verbatim: PreferencesHighlightsStrings.matchTypeLabel))

				PreferencesToggle(
					title: PreferencesHighlightsStrings.logToWindow,
					isOn: model.preferences.binding(for: Preferences.Logging.logHighlights) { _ in
						TextualPreferences.performReloadAction(.highlightLogging)
					}
				)
				PreferencesToggle(
					title: PreferencesHighlightsStrings.trackLocalNickname,
					isOn: model.preferences.gatedBinding(
						for: Preferences.Highlights.trackLocalNickname,
						enabledWhen: { self.usesRegularExpression == false }
					)
				)
				.disabled(usesRegularExpression)
			}

			Section {
				PreferencesKeywordList(
					title: PreferencesHighlightsStrings.wordsLabel,
					addLabel: PreferencesHighlightsStrings.addKeyword,
					removeLabel: PreferencesHighlightsStrings.removeKeyword,
					keywords: model.preferences.binding(for: Preferences.Highlights.matchKeywords)
				)
				PreferencesKeywordList(
					title: PreferencesHighlightsStrings.excludeWordsLabel,
					addLabel: PreferencesHighlightsStrings.addExcluded,
					removeLabel: PreferencesHighlightsStrings.removeExcluded,
					keywords: model.preferences.binding(for: Preferences.Highlights.excludeKeywords)
				)
				.disabled(usesRegularExpression)
			}
		}
	}
}

/// One of the two keyword tables in the Highlights pane, with its add and
/// remove buttons.
struct PreferencesKeywordList: View {
	private static let listHeight = 140.0

	let title: String
	let addLabel: String
	let removeLabel: String
	@Binding var keywords: [HighlightKeyword]
	@State private var selection: Int?

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(verbatim: title)

			List(selection: $selection) {
				ForEach(keywords.indices, id: \.self) { index in
					TextField("", text: binding(at: index))
						.textFieldStyle(.plain)
						.accessibilityLabel(Text(verbatim: title))
				}
			}
			.frame(height: Self.listHeight)
			.accessibilityLabel(Text(verbatim: title))

			HStack(spacing: 6) {
				Button(action: add) {
					Image(systemName: "plus")
				}
				.accessibilityLabel(Text(verbatim: addLabel))

				Button(action: remove) {
					Image(systemName: "minus")
				}
				.accessibilityLabel(Text(verbatim: removeLabel))
				.disabled(selection == nil)
			}
		}
	}

	private func binding(at index: Int) -> Binding<String> {
		Binding(
			get: { keywords.indices.contains(index) ? keywords[index].string : "" },
			set: { newValue in
				guard keywords.indices.contains(index) else { return }
				keywords[index].string = newValue
			}
		)
	}

	private func add() {
		keywords.append(HighlightKeyword(string: PreferencesHighlightsStrings.newKeyword))
		selection = keywords.count - 1
	}

	private func remove() {
		guard let selection, keywords.indices.contains(selection) else { return }
		keywords.remove(at: selection)
		self.selection = nil
	}
}

struct PreferencesIncomingDataPane: View {
	let model: PreferencesPaneModel

	var body: some View {
		PreferencesPaneLayout {
			Section {
				PreferencesToggle(
					title: PreferencesIncomingDataStrings.replyCtcp,
					isOn: model.preferences.binding(for: Preferences.Messages.replyToCTCPRequests)
				)
				VStack(alignment: .leading, spacing: 4) {
					PreferencesToggle(
						title: PreferencesIncomingDataStrings.highlightSpam,
						isOn: model.preferences.binding(for: Preferences.Messages.detectHighlightSpam)
					)
					PreferencesNote(PreferencesIncomingDataStrings.highlightSpamNote)
				}
				VStack(alignment: .leading, spacing: 4) {
					PreferencesToggle(
						title: PreferencesIncomingDataStrings.removeFormatting,
						isOn: model.preferences.binding(for: Preferences.Messages.removeAllFormatting)
					)
					PreferencesNote(PreferencesIncomingDataStrings.removeFormattingNote)
				}
				VStack(alignment: .leading, spacing: 4) {
					PreferencesToggle(
						title: PreferencesIncomingDataStrings.unicodeSpam,
						isOn: model.preferences.binding(for: Preferences.Messages.filterUnicodeTextSpam)
					)
					PreferencesNote(PreferencesIncomingDataStrings.unicodeSpamNote)
				}
			}
		}
	}
}

struct PreferencesFloodControlPane: View {
	let model: PreferencesPaneModel

	/* The nib's sliders only stopped on tick marks; the step keeps that. */
	private static let delayStep = 0.5
	private static let channelSizeStep = 40.0
	private static let channelSizeMaximum = 2000.0

	var body: some View {
		PreferencesPaneLayout {
			Section {
				delaySlider(
					label: PreferencesFloodControlStrings.joinDelayLabel,
					note: PreferencesFloodControlStrings.joinDelayNote,
					value: model.preferences.sliderBinding(
						for: Preferences.Connection.autojoinDelayBetweenChannelJoins
					),
					range: 0.5 ... 10.0
				)
				delaySlider(
					label: PreferencesFloodControlStrings.identifyDelayLabel,
					note: PreferencesFloodControlStrings.identifyDelayNote,
					value: model.preferences.sliderBinding(
						for: Preferences.Connection.autojoinDelayAfterIdentification
					),
					range: 0.0 ... 10.0
				)
				PreferencesNote(PreferencesFloodControlStrings.note)
			}

			Section {
				channelSizeSlider
			}
		}
	}

	private func delaySlider(
		label: String,
		note: String,
		value: Binding<Double>,
		range: ClosedRange<Double>
	) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(verbatim: label)
			PreferencesNote(note)
			Text(verbatim: PreferencesFloodControlStrings.secondsValue(value: secondsText(value.wrappedValue)))
				.font(.callout)
				.foregroundStyle(.secondary)
			HStack(spacing: 8) {
				Text(verbatim: secondsText(range.lowerBound))
					.font(.callout)
					.foregroundStyle(.secondary)
				Slider(value: value, in: range, step: Self.delayStep)
					.accessibilityLabel(Text(verbatim: label))
				Text(verbatim: secondsText(range.upperBound))
					.font(.callout)
					.foregroundStyle(.secondary)
			}
		}
	}

	private var channelSizeSlider: some View {
		let value = model.preferences.sliderBinding(
			for: Preferences.Appearance.trackUserAwayStatusMaximumChannelSize
		)
		return VStack(alignment: .leading, spacing: 4) {
			Text(verbatim: PreferencesFloodControlStrings.whoLimitLabel)
			PreferencesNote(PreferencesFloodControlStrings.whoLimitNote)
			Text(verbatim: PreferencesFloodControlStrings.countValue(value: countText(value.wrappedValue)))
				.font(.callout)
				.foregroundStyle(.secondary)
			HStack(spacing: 8) {
				Text(verbatim: PreferencesFloodControlStrings.disabledMarker)
					.font(.callout)
					.foregroundStyle(.secondary)
				Slider(value: value, in: 0 ... Self.channelSizeMaximum, step: Self.channelSizeStep)
					.accessibilityLabel(Text(verbatim: PreferencesFloodControlStrings.whoLimitLabel))
				Text(verbatim: countText(Self.channelSizeMaximum))
					.font(.callout)
					.foregroundStyle(.secondary)
			}
		}
	}

	private func secondsText(_ value: Double) -> String {
		value.formatted(.number.precision(.fractionLength(1)))
	}

	private func countText(_ value: Double) -> String {
		Int(value).formatted(.number)
	}
}
