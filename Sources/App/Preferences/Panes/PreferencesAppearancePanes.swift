/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import SwiftUI

struct PreferencesInterfacePane: View {
	let model: PreferencesPaneModel

	var body: some View {
		PreferencesPaneLayout {
			Section {
				PreferencesToggle(
					title: PreferencesInterfaceStrings.rightToLeftText,
					isOn: model.preferences.binding(for: Preferences.Messages.rightToLeftFormatting) { _ in
						TextualPreferences.performReloadAction([.style, .textDirection])
					}
				)
				appearancePicker
				PreferencesToggle(
					title: PreferencesInterfaceStrings.noModeSymbol,
					isOn: model.preferences.binding(for: Preferences.Appearance.memberListNoModeSymbol) { _ in
						TextualPreferences.performReloadAction([.memberListUserBadges, .memberList])
					}
				)
				PreferencesToggle(
					title: PreferencesInterfaceStrings.staffAtTop,
					isOn: model.preferences.binding(
						for: Preferences.Appearance.memberListSortFavorsServerStaff
					) { _ in TextualPreferences.performReloadAction(.memberListSortOrder) }
				)
				PreferencesToggle(
					title: PreferencesInterfaceStrings.popoverUpdatesOnScroll,
					isOn: model.preferences.binding(for: Preferences.Appearance.memberListUpdatesPopoverOnScroll)
				)
			} header: {
				Text(verbatim: PreferencesSectionStrings.general)
			}

			Section {
				serverListBadgeColor
			} header: {
				Text(verbatim: PreferencesInterfaceStrings.headingServerListColors)
			}

			Section {
				PreferencesNote(PreferencesInterfaceStrings.userListColorsNote)
				ForEach(UserListModeBadge.allCases, id: \.self) { badge in
					ColorPicker(
						selection: model.preferences.colorBinding(for: badge.preferenceKey) {
							TextualPreferences.performReloadAction(
								.memberListUserBadges,
								forKey: badge.preferenceKey.name
							)
						},
						supportsOpacity: false
					) {
						Text(verbatim: Self.title(for: badge))
					}
				}
				Button(PreferencesInterfaceStrings.resetToDefaults, role: .destructive) {
					confirmResetUserListColors()
				}
				.accessibilityLabel(Text(verbatim: PreferencesInterfaceStrings.resetUserListColors))
			} header: {
				Text(verbatim: PreferencesInterfaceStrings.headingUserListColors)
			}
		}
	}

	private var appearancePicker: some View {
		Picker(selection: model.preferences.binding(for: Preferences.Appearance.preferredAppearance) { _ in
			TextualPreferences.performReloadAction(.appearance)
		}) {
			/* From `allCases`, so the picker offers every appearance the type
			 declares: three rows spelled out here is three rows that go on
			 saying three when a fourth is added. */
			ForEach(PreferredAppearance.allCases, id: \.self) { appearance in
				Text(verbatim: Self.title(for: appearance)).tag(appearance)
			}
		} label: {
			Text(verbatim: PreferencesInterfaceStrings.appearanceLabel)
		}
	}

	private static func title(for appearance: PreferredAppearance) -> String {
		switch appearance {
		case .inherited: PreferencesInterfaceStrings.appearanceSystem
		case .light: PreferencesInterfaceStrings.appearanceLight
		case .dark: PreferencesInterfaceStrings.appearanceDark
		}
	}

	private var serverListBadgeColor: some View {
		HStack {
			ColorPicker(
				selection: model.preferences.storedColorBinding(
					for: Preferences.Badges.serverListUnreadHighlight
				) { TextualPreferences.performReloadAction(.serverListUnreadBadges) },
				supportsOpacity: false
			) {
				Text(verbatim: PreferencesInterfaceStrings.unreadHighlightColorLabel)
			}
			Spacer()
			Button(PreferencesInterfaceStrings.reset) {
				model.preferences.reset(Preferences.Badges.serverListUnreadHighlight)
				TextualPreferences.performReloadAction(.serverListUnreadBadges)
			}
			.accessibilityLabel(Text(verbatim: PreferencesInterfaceStrings.resetUnreadHighlightColor))
		}
	}

	/// Colours the user picked are gone for good, so a reset that would throw
	/// any away asks first. With nothing customised there is nothing to lose.
	private func confirmResetUserListColors() {
		guard hasCustomUserListColors else {
			resetUserListColors()
			return
		}

		Alerts.alert(
			withMessage: PreferencesInterfaceStrings.resetColorsConfirmationBody,
			title: PreferencesInterfaceStrings.resetColorsConfirmationTitle,
			defaultButton: PreferencesInterfaceStrings.resetToDefaults,
			alternateButton: PromptStrings.Action.cancel,
			destructiveButton: .default
		) { outcome in
			guard outcome.response == .default else { return }
			resetUserListColors()
		}
	}

	private var hasCustomUserListColors: Bool {
		UserListModeBadge.allCases.contains { model.preferences[stored: $0.preferenceKey] != nil }
	}

	private func resetUserListColors() {
		for badge in UserListModeBadge.allCases {
			model.preferences.reset(badge.preferenceKey)
		}
		TextualPreferences.performReloadAction([.memberListUserBadges, .memberList])
	}

	private static func title(for badge: UserListModeBadge) -> String {
		switch badge {
		case .ircOperator: PreferencesInterfaceStrings.modeServerStaff
		case .channelOwner: PreferencesInterfaceStrings.modeChannelOwner
		case .superOperator: PreferencesInterfaceStrings.modeChannelAdministrator
		case .normalOperator: PreferencesInterfaceStrings.modeChannelOperator
		case .halfOperator: PreferencesInterfaceStrings.modeChannelHalfOperator
		case .voiced: PreferencesInterfaceStrings.modeVoicedUser
		}
	}
}

private struct TranscriptThemeColorRole: Identifiable {
	let id: String
	let title: String
	let keyPath: WritableKeyPath<TranscriptThemePalette, AdaptiveTranscriptColor>

	static let all = [
		Self(id: "background", title: TranscriptThemeStrings.background, keyPath: \.background),
		Self(id: "primaryText", title: TranscriptThemeStrings.primaryText, keyPath: \.primaryText),
		Self(id: "secondaryText", title: TranscriptThemeStrings.secondaryText, keyPath: \.secondaryText),
		Self(id: "timestampText", title: TranscriptThemeStrings.timestampText, keyPath: \.timestampText),
		Self(id: "eventText", title: TranscriptThemeStrings.eventText, keyPath: \.eventText),
		Self(id: "link", title: TranscriptThemeStrings.links, keyPath: \.link),
		Self(id: "localNickname", title: TranscriptThemeStrings.yourNickname, keyPath: \.localNickname),
		Self(id: "remoteNickname", title: TranscriptThemeStrings.otherNicknames, keyPath: \.remoteNickname),
		Self(
			id: "highlightBackground",
			title: TranscriptThemeStrings.highlightBackground,
			keyPath: \.highlightBackground
		),
		Self(id: "highlightText", title: TranscriptThemeStrings.highlightText, keyPath: \.highlightText),
		Self(id: "bubbleIncoming", title: TranscriptThemeStrings.incomingBubble, keyPath: \.bubbleIncoming),
		Self(id: "bubbleOutgoing", title: TranscriptThemeStrings.outgoingBubble, keyPath: \.bubbleOutgoing),
		Self(id: "unreadMarker", title: TranscriptThemeStrings.unreadMarker, keyPath: \.unreadMarker),
		Self(id: "failure", title: TranscriptThemeStrings.failure, keyPath: \.failure),
	]
}

struct PreferencesStylePane: View {
	private static let scrollbackPresets = [
		"1000", "2000", "3000", "4000", "5000", "10000", "20000", "30000", "40000", "50000",
	]
	/** The default first: a preset list whose first entry is not what the app
	 ships with reads as though the shipped format were a custom one. */
	private static let nicknamePresets = [
		"%@%n:", "%@%n", "%n: ", "%@%n: ", "(%n) ", "<%n> ", "<%@%n> ", "<%@%-9n>",
	]
	/// The default first, for the reason above: what the app ships with is
	/// `%H:%M:%S`, and a list that started with a bracketed format made the
	/// shipped one look like something the person had typed themselves.
	private static let timestampPresets = [
		"%H:%M:%S", "[%H:%M]", "[%H:%M:%S]", "[%I:%M:%S %p]", "[%m/%d/%Y -:- %I:%M:%S %p]",
	]

	let model: PreferencesPaneModel

	/// The name being typed, held here until it is committed. A theme with an
	/// empty name is rejected, so writing every keystroke through made the
	/// field snap back as soon as the last character was deleted.
	@State private var themeNameDraft: String?
	@FocusState private var themeNameIsFocused: Bool

	var body: some View {
		PreferencesPaneLayout {
			Section {
				LabeledContent(TranscriptThemeStrings.themeName) { themeNameField }
				Picker(TranscriptThemeStrings.layout, selection: themeLayout) {
					Text(verbatim: TranscriptThemeStrings.lines).tag(TranscriptThemeLayout.lines)
					Text(verbatim: TranscriptThemeStrings.bubbles).tag(TranscriptThemeLayout.bubbles)
				}
				fontRow
				HStack {
					Button(TranscriptThemeStrings.importTheme) { model.importTranscriptTheme() }
					Button(TranscriptThemeStrings.exportTheme) { model.exportTranscriptTheme() }
					Spacer()
					Button(PreferencesInterfaceStrings.resetToDefaults, role: .destructive) {
						confirmResetTranscriptTheme()
					}
				}
			} header: {
				Text(verbatim: TranscriptThemeStrings.transcriptTheme)
			}

			Section {
				ForEach(TranscriptThemeColorRole.all) { role in
					HStack {
						Text(role.title)
						Spacer()
						ColorPicker(
							TranscriptThemeStrings.light,
							selection: color(role, dark: false),
							supportsOpacity: true
						)
						.labelsHidden()
						ColorPicker(
							TranscriptThemeStrings.dark,
							selection: color(role, dark: true),
							supportsOpacity: true
						)
						.labelsHidden()
					}
					.accessibilityElement(children: .contain)
				}
				PreferencesNote(TranscriptThemeStrings.roleColorNote)
			} header: {
				HStack {
					Text(verbatim: TranscriptThemeStrings.colors)
					Spacer()
					Text(verbatim: "\(TranscriptThemeStrings.light)   \(TranscriptThemeStrings.dark)")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}

			Section {
				formatFields
				Stepper(
					"\(TranscriptThemeStrings.lineSpacing): \(model.transcriptTheme.lineSpacing.formatted())",
					value: lineSpacing,
					in: 0 ... 16
				)
				Stepper(
					"\(TranscriptThemeStrings.messageSpacing): \(model.transcriptTheme.messageSpacing.formatted())",
					value: messageSpacing,
					in: 0 ... 32
				)
				Stepper(
					"\(TranscriptThemeStrings.horizontalPadding): \(model.transcriptTheme.horizontalPadding.formatted())",
					value: horizontalPadding,
					in: 0 ... 48
				)
			} header: {
				Text(verbatim: PreferencesSectionStrings.advanced)
			}

			Section {
				PreferencesToggle(
					title: PreferencesStyleStrings.autoScrollbackMarker,
					isOn: model.preferences.binding(for: Preferences.Messages.autoAddScrollbackMark)
				)
				PreferencesToggle(
					title: PreferencesStyleStrings.showDateChanges,
					isOn: model.preferences.binding(for: Preferences.Messages.showDateChanges)
				)
				PreferencesToggle(
					title: PreferencesStyleStrings.showJoinLeave,
					isOn: model.preferences.binding(for: Preferences.Messages.showJoinLeave)
				)
				PreferencesToggle(
					title: TranscriptThemeStrings.showInlineImages,
					isOn: model.preferences.binding(for: Preferences.Messages.showInlineMedia)
				)
				PreferencesToggle(
					title: PreferencesStyleStrings.disableNicknameColors,
					isOn: model.preferences.binding(for: Preferences.Messages.disableNicknameColorHashing)
				)
				PreferencesToggle(
					title: PreferencesStyleStrings.showMotd,
					isOn: model.preferences.binding(for: Preferences.Connection.displayServerMOTD)
				)
			} header: {
				Text(verbatim: PreferencesSectionStrings.general)
			}

			Section {
				LabeledContent {
					PreferencesComboField(
						title: PreferencesStyleStrings.scrollbackSaveLimit,
						presets: Self.scrollbackPresets,
						commitsOnEndEditing: true,
						text: model.preferences.numberFieldBinding(
							for: Preferences.Logging.scrollbackSaveLimit
						) { TextualPreferences.performReloadAction(.scrollbackSaveLimit) }
					)
				} label: {
					Text(verbatim: PreferencesStyleStrings.scrollbackSaveLimit)
				}
				PreferencesNote(PreferencesStyleStrings.scrollbackSaveLimitNote)
			} header: {
				Text(verbatim: PreferencesStyleStrings.headingScrollback)
			}
		}
	}

	private var fontRow: some View {
		LabeledContent {
			HStack {
				Text(verbatim: PreferencesStyleStrings.fontDescription(
					name: model.channelViewFontName,
					size: Double(model.channelViewFontSize).formatted(.number.precision(.fractionLength(0 ... 1)))
				))
				Spacer()
				Button(PreferencesStyleStrings.fontChange) { model.selectChannelViewFont() }
			}
		} label: {
			Text(verbatim: PreferencesStyleStrings.fontLabel)
		}
	}

	/// Each format field is its own form row, with its note attached to it: one
	/// stack holding both fields collapsed into a single row, so the system's
	/// separators and label alignment applied to the stack rather than to the
	/// settings inside it.
	@ViewBuilder
	private var formatFields: some View {
		VStack(alignment: .leading, spacing: PreferencesMetrics.spacingSmall) {
			LabeledContent {
				PreferencesComboField(
					title: PreferencesStyleStrings.nicknameFormatLabel,
					presets: Self.nicknamePresets,
					text: nicknameFormat
				)
			} label: {
				Text(verbatim: PreferencesStyleStrings.nicknameFormatLabel)
			}
			PreferencesNote(
				"\(PreferencesStyleStrings.formatSymbolsLabel) %@ = "
					+ "\(PreferencesStyleStrings.nicknameFormatSymbolMode); "
					+ "%n = \(PreferencesStyleStrings.nicknameFormatSymbolNickname)"
			)
		}

		VStack(alignment: .leading, spacing: PreferencesMetrics.spacingSmall) {
			LabeledContent {
				PreferencesComboField(
					title: PreferencesStyleStrings.timestampFormatLabel,
					presets: Self.timestampPresets,
					text: timestampFormat
				)
			} label: {
				Text(verbatim: PreferencesStyleStrings.timestampFormatLabel)
			}
			PreferencesNote(PreferencesStyleStrings.timestampFormatNote)
		}
	}

	/// A customised theme cannot be brought back once it is replaced, so the
	/// reset asks first; a theme still at its defaults has nothing to lose.
	private func confirmResetTranscriptTheme() {
		guard hasCustomTranscriptTheme else {
			model.resetTranscriptTheme()
			return
		}

		Alerts.alert(
			withMessage: PreferencesInterfaceStrings.resetThemeConfirmationBody,
			title: PreferencesInterfaceStrings.resetThemeConfirmationTitle,
			defaultButton: PreferencesInterfaceStrings.resetToDefaults,
			alternateButton: PromptStrings.Action.cancel,
			destructiveButton: .default
		) { outcome in
			guard outcome.response == .default else { return }
			model.resetTranscriptTheme()
		}
	}

	private var hasCustomTranscriptTheme: Bool {
		let theme = model.transcriptTheme
		return theme != (theme.layout == .bubbles ? .bubbles : .lines)
	}

	private var themeNameField: some View {
		TextField("", text: Binding(
			get: { themeNameDraft ?? model.transcriptTheme.name },
			set: { themeNameDraft = $0 }
		))
		.focused($themeNameIsFocused)
		.onSubmit { commitThemeName() }
		.onChange(of: themeNameIsFocused) { _, isFocused in
			if isFocused == false {
				commitThemeName()
			}
		}
	}

	/// Commits the typed name, or drops it and restores the stored one when it
	/// is blank.
	private func commitThemeName() {
		guard let draft = themeNameDraft else { return }

		themeNameDraft = nil

		let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)

		guard name.isEmpty == false, name != model.transcriptTheme.name else { return }

		model.updateTheme { $0.name = name }
	}

	private var themeLayout: Binding<TranscriptThemeLayout> {
		themeBinding(\.layout)
	}

	private var nicknameFormat: Binding<String> {
		themeBinding(\.nicknameFormat)
	}

	private var timestampFormat: Binding<String> {
		themeBinding(\.timestampFormat)
	}

	private var lineSpacing: Binding<Double> {
		themeBinding(\.lineSpacing)
	}

	private var messageSpacing: Binding<Double> {
		themeBinding(\.messageSpacing)
	}

	private var horizontalPadding: Binding<Double> {
		themeBinding(\.horizontalPadding)
	}

	private func themeBinding<Value>(_ keyPath: WritableKeyPath<TranscriptTheme, Value>) -> Binding<Value> {
		Binding(
			get: { model.transcriptTheme[keyPath: keyPath] },
			set: { value in model.updateTheme { $0[keyPath: keyPath] = value } }
		)
	}

	private func color(_ role: TranscriptThemeColorRole, dark: Bool) -> Binding<Color> {
		Binding(
			get: {
				let pair = model.transcriptTheme.palette[keyPath: role.keyPath]
				return Color(nsColor: (dark ? pair.dark : pair.light).color)
			},
			set: { value in
				guard let components = TranscriptThemeColor(NSColor(value)) else { return }
				model.updateTheme {
					if dark {
						$0.palette[keyPath: role.keyPath].dark = components
					} else {
						$0.palette[keyPath: role.keyPath].light = components
					}
				}
			}
		)
	}
}
