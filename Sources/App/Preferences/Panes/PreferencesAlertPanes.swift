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
	let model: PreferencesPaneModel

	private var onlySpeakForSelection: Bool {
		model.preferences[Preferences.Notifications.onlySpeakForSelection]
	}

	var body: some View {
		PreferencesPaneLayout {
			Section {
				NotificationConfigurationView(
					notifications: model.notificationItems,
					allowsInheritedState: false
				)
				.accessibilityLabel(Text(verbatim: PreferencesNotificationsStrings.headingAlerts))
			} header: {
				Text(verbatim: PreferencesNotificationsStrings.headingAlerts)
			}

			Section {
				PreferencesToggle(
					title: PreferencesNotificationsStrings.onlySpeakSelection,
					isOn: model.preferences.binding(for: Preferences.Notifications.onlySpeakForSelection)
				)
				/* Each switch is its own form row, so the system draws the
				 separators, spacing and label alignment instead of a hand-made
				 stack indented by eye. */
				Text(verbatim: PreferencesNotificationsStrings.speechIncludeLabel)
				PreferencesToggle(
					title: PreferencesNotificationsStrings.speakChannelName,
					isOn: model.preferences.gatedBinding(
						for: Preferences.Notifications.flag(.channelMessage, .speakChannelName),
						enabledWhen: { onlySpeakForSelection == false }
					)
				)
				.disabled(onlySpeakForSelection)
				PreferencesToggle(
					title: PreferencesNotificationsStrings.speakNickname,
					isOn: model.preferences.binding(
						for: Preferences.Notifications.flag(.channelMessage, .speakNickname)
					)
				)
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

	private var matchingMethod: NicknameHighlightMatchMode {
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
						.tag(NicknameHighlightMatchMode.partial)
					Text(verbatim: PreferencesHighlightsStrings.matchTypeExact)
						.tag(NicknameHighlightMatchMode.exact)
					Text(verbatim: PreferencesHighlightsStrings.matchTypeRegex)
						.tag(NicknameHighlightMatchMode.regularExpression)
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
						enabledWhen: { usesRegularExpression == false }
					)
				)
				.disabled(usesRegularExpression)
			}

			Section {
				PreferencesKeywordList(
					title: PreferencesHighlightsStrings.wordsLabel,
					addLabel: PreferencesHighlightsStrings.addKeyword,
					removeLabel: PreferencesHighlightsStrings.removeKeyword,
					keywords: model.preferences.binding(for: Preferences.Highlights.matchKeywords),
					usesRegularExpression: usesRegularExpression
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
	/// Whether these keywords are matched as regular expressions, which is what
	/// decides whether an unusable pattern is an error worth showing.
	var usesRegularExpression = false
	@State private var selection: Int?

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(verbatim: title)

			List(selection: $selection) {
				ForEach(keywords.indices, id: \.self) { index in
					HStack(spacing: 4) {
						TextField("", text: binding(at: index))
							.textFieldStyle(.plain)
							.accessibilityLabel(Text(verbatim: title))

						if let error = patternError(at: index) {
							Image(systemName: "exclamationmark.triangle.fill")
								.foregroundStyle(.orange)
								.help(Text(verbatim: error))
								.accessibilityLabel(Text(verbatim: error))
						}
					}
				}
			}
			.frame(height: Self.listHeight)
			.accessibilityLabel(Text(verbatim: title))

			HStack(spacing: 6) {
				Button(action: add) {
					Image(systemName: "plus")
				}
				.help(Text(verbatim: addLabel))
				.accessibilityLabel(Text(verbatim: addLabel))

				Button(role: .destructive, action: remove) {
					Image(systemName: "minus")
				}
				.help(Text(verbatim: removeLabel))
				.accessibilityLabel(Text(verbatim: removeLabel))
				.disabled(selection == nil)
			}
		}
	}

	/// The keyword at `index` is reported where it is typed, rather than
	/// failing silently in the renderer when the pattern will not compile.
	private func patternError(at index: Int) -> String? {
		guard keywords.indices.contains(index) else { return nil }
		let keyword = keywords[index].string.trimmingCharacters(in: .whitespacesAndNewlines)
		guard keyword.isEmpty == false else { return nil }

		return HighlightKeywordPattern.validationError(
			for: keyword,
			usesRegularExpression: usesRegularExpression
		)
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
			PreferencesIncomingDataSections(model: model)
		}
	}
}

/// The pane as one form section, for the Advanced group that gathers it with
/// its neighbours.
struct PreferencesIncomingDataSections: View {
	let model: PreferencesPaneModel

	var body: some View {
		Section {
			PreferencesToggle(
				title: PreferencesIncomingDataStrings.replyCtcp,
				isOn: model.preferences.binding(for: Preferences.Messages.replyToCTCPRequests)
			)
			PreferencesToggle(
				title: PreferencesIncomingDataStrings.highlightSpam,
				note: PreferencesIncomingDataStrings.highlightSpamNote,
				isOn: model.preferences.binding(for: Preferences.Messages.detectHighlightSpam)
			)
			PreferencesToggle(
				title: PreferencesIncomingDataStrings.removeFormatting,
				note: PreferencesIncomingDataStrings.removeFormattingNote,
				isOn: model.preferences.binding(for: Preferences.Messages.removeAllFormatting)
			)
			PreferencesToggle(
				title: PreferencesIncomingDataStrings.unicodeSpam,
				note: PreferencesIncomingDataStrings.unicodeSpamNote,
				isOn: model.preferences.binding(for: Preferences.Messages.filterUnicodeTextSpam)
			)
		} header: {
			Text(verbatim: PreferencesStrings.paneTitle(.incomingData))
		}
	}
}

struct PreferencesFloodControlPane: View {
	let model: PreferencesPaneModel

	var body: some View {
		PreferencesPaneLayout {
			PreferencesFloodControlSections(model: model)
		}
	}
}

/// The pane as one form section, for the Advanced group that gathers it with
/// its neighbours.
struct PreferencesFloodControlSections: View {
	/* The nib's sliders only stopped on tick marks; the step keeps that. */
	private static let delayStep = 0.5
	private static let channelSizeStep = 40.0
	private static let channelSizeMaximum = 2000.0

	let model: PreferencesPaneModel

	var body: some View {
		Section {
			delaySlider(
				label: PreferencesFloodControlStrings.identifyDelayLabel,
				note: PreferencesFloodControlStrings.identifyDelayNote,
				value: model.preferences.sliderBinding(
					for: Preferences.Connection.autojoinDelayAfterIdentification
				),
				range: 0.0 ... 10.0
			)
			PreferencesNote(PreferencesFloodControlStrings.note)
			channelSizeSlider
		} header: {
			Text(verbatim: PreferencesStrings.paneTitle(.floodControl))
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
			Text(verbatim: PreferencesFloodControlStrings.countValue(value: Self.countText(value.wrappedValue)))
				.font(.callout)
				.foregroundStyle(.secondary)
			HStack(spacing: 8) {
				Text(verbatim: PreferencesFloodControlStrings.disabledMarker)
					.font(.callout)
					.foregroundStyle(.secondary)
				Slider(value: value, in: 0 ... Self.channelSizeMaximum, step: Self.channelSizeStep)
					.accessibilityLabel(Text(verbatim: PreferencesFloodControlStrings.whoLimitLabel))
				Text(verbatim: Self.countText(Self.channelSizeMaximum))
					.font(.callout)
					.foregroundStyle(.secondary)
			}
		}
	}

	private func secondsText(_ value: Double) -> String {
		value.formatted(.number.precision(.fractionLength(1)))
	}

	/** The value comes from a stored count that a hand-edited defaults file can
	 put anywhere in `UInt`, so the conversion has to be total: `Int(_:)` traps
	 on a `Double` outside `Int`, and this label is not worth a crash. */
	static func countText(_ value: Double) -> String {
		let count = Int(exactly: value.rounded()) ?? (value < 0 ? Int.min : Int.max)
		return count.formatted(.number)
	}
}
