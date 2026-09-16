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

struct PreferencesNotificationsSections: View {
	let model: PreferencesPaneModel

	private var onlySpeakForSelection: Bool {
		model.preferences[Preferences.Notifications.onlySpeakForSelection]
	}

	var body: some View {
		Section {
			NotificationConfigurationView(model: model.notificationConfiguration)
				.accessibilityLabel(Text(verbatim: PreferencesNotificationsStrings.headingAlerts))
		} header: {
			Text(verbatim: PreferencesNotificationsStrings.headingAlerts)
		}

		Section {
			PreferencesToggle(
				title: PreferencesNotificationsStrings.onlySpeakSelection,
				isOn: model.preferences.binding(for: Preferences.Notifications.onlySpeakForSelection)
			)
		} header: {
			Text(verbatim: PreferencesNotificationsStrings.headingSpeech)
		}

		Section {
			PreferencesToggle(
				title: PreferencesNotificationsStrings.speakChannelName,
				isEnabled: onlySpeakForSelection == false,
				isOn: model.preferences.binding(
					for: Preferences.Notifications.flag(.channelMessage, .speakChannelName)
				)
			)
			PreferencesToggle(
				title: PreferencesNotificationsStrings.speakNickname,
				isOn: model.preferences.binding(
					for: Preferences.Notifications.flag(.channelMessage, .speakNickname)
				)
			)
		} header: {
			Text(verbatim: PreferencesNotificationsStrings.headingSpeechInclude)
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
		} header: {
			Text(verbatim: PreferencesNotificationsStrings.headingDockIcon)
		}

		Section {
			PreferencesToggle(
				title: PreferencesNotificationsStrings.postWhileInFocus,
				isOn: model.preferences.binding(for: Preferences.Notifications.postWhileInFocus)
			)
		} header: {
			Text(verbatim: PreferencesNotificationsStrings.headingDelivery)
		}
	}
}

struct PreferencesHighlightsSections: View {
	let model: PreferencesPaneModel

	private var matchingMethod: NicknameHighlightMatchMode {
		model.preferences[Preferences.Highlights.matchingMethod]
	}

	private var usesRegularExpression: Bool {
		matchingMethod == .regularExpression
	}

	var body: some View {
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
				isEnabled: usesRegularExpression == false,
				isOn: model.preferences.binding(for: Preferences.Highlights.trackLocalNickname)
			)
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
	/** One identity per row, in the order of `keywords`.

	 Rows identified by their position hand focus and selection to whichever
	 row slides into the place of one that was removed, so a blank row dropped
	 when focus left it took the next row's focus with it. */
	@State private var rowIdentities = PreferencesKeywordRowIdentities()
	@State private var selection: UUID?
	@FocusState private var focusedKeyword: UUID?

	var body: some View {
		VStack(alignment: .leading, spacing: PreferencesMetrics.spacingMedium) {
			Text(verbatim: title)

			List(selection: $selection) {
				ForEach(Array(rowIdentities.identities.enumerated()), id: \.element) { index, identity in
					HStack(spacing: PreferencesMetrics.spacingSmall) {
						TextField(
							text: binding(for: identity),
							prompt: Text(verbatim: PreferencesHighlightsStrings.newKeyword)
						) {
							Text(verbatim: title)
						}
						.labelsHidden()
						.textFieldStyle(.plain)
						.focused($focusedKeyword, equals: identity)
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
			.onChange(of: keywords.count, initial: true) { _, count in
				rowIdentities.match(count: count)
			}
			/* A row that was added and then left blank is one nobody asked for:
			 dropping it here is what keeps a placeholder keyword out of the
			 stored list, which is where the renderer reads it from. */
			.onChange(of: focusedKeyword) { previous, _ in
				guard let previous, let index = index(of: previous), isBlank(at: index) else { return }
				removeRow(at: index)
			}

			HStack(spacing: PreferencesMetrics.spacingMedium) {
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

	private func isBlank(at index: Int) -> Bool {
		guard keywords.indices.contains(index) else { return false }
		return keywords[index].string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	private func index(of identity: UUID) -> Int? {
		guard let index = rowIdentities.identities.firstIndex(of: identity), keywords.indices.contains(index) else {
			return nil
		}
		return index
	}

	private func binding(for identity: UUID) -> Binding<String> {
		Binding(
			get: { index(of: identity).map { keywords[$0].string } ?? "" },
			set: { newValue in
				guard let index = index(of: identity) else { return }
				keywords[index].string = newValue
			}
		)
	}

	private func add() {
		rowIdentities.match(count: keywords.count)
		let identity = rowIdentities.append()
		keywords.append(HighlightKeyword(string: ""))
		selection = identity
		focusedKeyword = identity
	}

	private func remove() {
		guard let selection, let index = index(of: selection) else { return }
		removeRow(at: index)
	}

	private func removeRow(at index: Int) {
		let identity = rowIdentities.remove(at: index)
		keywords.remove(at: index)
		if selection == identity {
			selection = nil
		}
	}
}

/** The identities of a keyword list's rows.

 The stored list has no identity of its own — a keyword is its text, and two
 rows can hold the same text — so the rows get one here. A list that changed
 length without going through this, an import say, is given fresh identities. */
struct PreferencesKeywordRowIdentities {
	private(set) var identities: [UUID] = []

	/// Gives every row of a list with `count` rows an identity, keeping the
	/// ones it has while the count still agrees.
	mutating func match(count: Int) {
		guard identities.count != count else { return }
		identities = (0 ..< count).map { _ in UUID() }
	}

	/// Records a row appended to the end of the list.
	mutating func append() -> UUID {
		let identity = UUID()
		identities.append(identity)
		return identity
	}

	/// Forgets the row at `index`, returning its identity.
	mutating func remove(at index: Int) -> UUID {
		identities.remove(at: index)
	}
}

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
			Text(verbatim: PreferencesPane.incomingData.title)
		}
	}
}

struct PreferencesFloodControlSections: View {
	/* The steps keep the tick marks the sliders have always stopped on. */
	private static let delayStep = 0.5
	private static let delayRange = 0.0 ... 10.0
	private static let channelSizeStep = 40.0
	private static let channelSizeRange = 0.0 ... 2000.0

	let model: PreferencesPaneModel

	var body: some View {
		Section {
			delayRow
			PreferencesNote(PreferencesFloodControlStrings.identifyDelayNote)
			channelSizeRow
			PreferencesNote(PreferencesFloodControlStrings.whoLimitNote)
			PreferencesNote(PreferencesFloodControlStrings.note)
		} header: {
			Text(verbatim: PreferencesPane.floodControl.title)
		}
	}

	private var delayRow: some View {
		let value = model.preferences.binding(
			for: Preferences.Connection.autojoinDelayAfterIdentification
		)
		return PreferencesSliderRow(
			label: PreferencesFloodControlStrings.identifyDelayLabel,
			valueText: PreferencesFloodControlStrings.secondsValue(
				value: Self.secondsText(value.wrappedValue)
			),
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
		return PreferencesSliderRow(
			label: PreferencesFloodControlStrings.whoLimitLabel,
			valueText: PreferencesFloodControlStrings.countValue(
				value: Self.countText(value.wrappedValue)
			),
			range: Self.channelSizeRange,
			step: Self.channelSizeStep,
			minimumLabel: PreferencesFloodControlStrings.disabledMarker,
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
private struct PreferencesSliderRow: View {
	let label: String
	let valueText: String
	let range: ClosedRange<Double>
	let step: Double
	let minimumLabel: String
	let maximumLabel: String
	@Binding var value: Double

	var body: some View {
		Slider(value: $value, in: range, step: step) {
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: label)
				Text(verbatim: valueText)
					.font(.callout)
					.foregroundStyle(.secondary)
			}
		} minimumValueLabel: {
			endLabel(minimumLabel)
		} maximumValueLabel: {
			endLabel(maximumLabel)
		}
		.accessibilityLabel(Text(verbatim: label))
		.accessibilityValue(Text(verbatim: valueText))
	}

	private func endLabel(_ text: String) -> some View {
		Text(verbatim: text)
			.font(.callout)
			.foregroundStyle(.secondary)
	}
}
