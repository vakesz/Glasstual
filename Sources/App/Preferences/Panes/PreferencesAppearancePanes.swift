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
				.disabled(model.isReloadingTheme)

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
					) { _ in
						TextualPreferences.performReloadAction(.memberListSortOrder)
					}
				)
				PreferencesToggle(
					title: PreferencesInterfaceStrings.popoverUpdatesOnScroll,
					isOn: model.preferences.binding(
						for: Preferences.Appearance.memberListUpdatesPopoverOnScroll
					)
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
				Button {
					resetUserListColors()
				} label: {
					Text(verbatim: PreferencesInterfaceStrings.resetToDefaults)
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
			Text(verbatim: PreferencesInterfaceStrings.appearanceSystem)
				.tag(TXPreferredAppearance.inherited)
			Text(verbatim: PreferencesInterfaceStrings.appearanceLight)
				.tag(TXPreferredAppearance.light)
			Text(verbatim: PreferencesInterfaceStrings.appearanceDark)
				.tag(TXPreferredAppearance.dark)
		} label: {
			Text(verbatim: PreferencesInterfaceStrings.appearanceLabel)
		}
	}

	private var serverListBadgeColor: some View {
		HStack {
			ColorPicker(
				selection: model.preferences.storedColorBinding(
					for: Preferences.Badges.serverListUnreadHighlight
				) {
					TextualPreferences.performReloadAction(.serverListUnreadBadges)
				},
				supportsOpacity: false
			) {
				Text(verbatim: PreferencesInterfaceStrings.unreadHighlightColorLabel)
			}
			Spacer()
			Button {
				model.preferences.reset(Preferences.Badges.serverListUnreadHighlight)
				TextualPreferences.performReloadAction(.serverListUnreadBadges)
			} label: {
				Text(verbatim: PreferencesInterfaceStrings.reset)
			}
			.accessibilityLabel(Text(verbatim: PreferencesInterfaceStrings.resetUnreadHighlightColor))
		}
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

struct PreferencesStylePane: View {
	/** The values the nib's combo boxes offered. */
	private static let scrollbackPresets = [
		"1000", "2000", "3000", "4000", "5000", "10000", "20000", "30000", "40000", "50000",
	]
	private static let nicknamePresets = ["%n: ", "%@%n: ", "(%n) ", "<%n> ", "<%@%n> ", "<%@%-9n>"]
	private static let timestampPresets = [
		"[%H:%M]", "[%H:%M:%S]", "[%I:%M:%S %p]", "[%m/%d/%Y -:- %I:%M:%S %p]",
	]

	let model: PreferencesPaneModel

	var body: some View {
		PreferencesPaneLayout {
			Section {
				stylePicker
				fontRow
				messageToggles
			} header: {
				Text(verbatim: PreferencesSectionStrings.general)
			}

			Section {
				VStack(alignment: .leading, spacing: 4) {
					PreferencesToggle(
						title: PreferencesStyleStrings.reloadCustomStyles,
						isOn: model.preferences.binding(for: Preferences.Theme.reloadCustomThemesOnChange)
					)
					PreferencesNote(PreferencesStyleStrings.reloadCustomStylesNote)
				}
				Button {
					model.actions?.editUserStyleSheetRules()
				} label: {
					Text(verbatim: PreferencesStyleStrings.modifyStyleSheet)
				}
			} header: {
				Text(verbatim: PreferencesStyleStrings.headingDevelopers)
			}

			Section {
				LabeledContent {
					PreferencesComboField(
						title: PreferencesStyleStrings.scrollbackSaveLimit,
						presets: Self.scrollbackPresets,
						text: model.preferences.numberFieldBinding(
							for: Preferences.Logging.scrollbackSaveLimit,
							range: PreferencesValueValidation.scrollbackSaveRange
						) {
							TextualPreferences.performReloadAction(.scrollbackSaveLimit)
						}
					)
				} label: {
					Text(verbatim: PreferencesStyleStrings.scrollbackSaveLimit)
				}
				PreferencesNote(PreferencesStyleStrings.scrollbackSaveLimitNote)
			} header: {
				Text(verbatim: PreferencesStyleStrings.headingScrollback)
			}

			Section {
				formatFields
				advancedToggles
			} header: {
				Text(verbatim: PreferencesSectionStrings.advanced)
			}
		}
	}

	private var stylePicker: some View {
		HStack {
			Picker(selection: themeSelection) {
				ForEach(model.themes) { theme in
					Text(verbatim: theme.title).tag(Optional(theme))
				}
			} label: {
				Text(verbatim: PreferencesStyleStrings.label)
			}
			.disabled(model.isReloadingTheme || model.themes.isEmpty)

			Button {
				model.actions?.browseStyleFiles()
			} label: {
				Text(verbatim: PreferencesStyleStrings.browseFiles)
			}
			.disabled(model.isReloadingTheme)
			.accessibilityLabel(Text(verbatim: PreferencesStyleStrings.browseFilesHelp))
		}
	}

	private var themeSelection: Binding<PreferencesThemeChoice?> {
		Binding(
			get: { model.selectedTheme },
			set: { newValue in
				guard let newValue else { return }
				model.actions?.selectTheme(newValue)
			}
		)
	}

	private var fontRow: some View {
		LabeledContent {
			HStack {
				Text(verbatim: PreferencesStyleStrings.fontDescription(
					name: model.channelViewFontName,
					size: Double(model.channelViewFontSize)
						.formatted(.number.precision(.fractionLength(0 ... 1)))
				))
				.accessibilityLabel(Text(verbatim: PreferencesStyleStrings.fontCurrent))
				Spacer()
				Button {
					model.actions?.selectChannelViewFont()
				} label: {
					Text(verbatim: PreferencesStyleStrings.fontChange)
				}
				.accessibilityLabel(Text(verbatim: PreferencesStyleStrings.fontChangeHelp))
				.disabled(model.isReloadingTheme || fontIsUserConfigurable == false)
			}
		} label: {
			Text(verbatim: PreferencesStyleStrings.fontLabel)
		}
	}

	private var fontIsUserConfigurable: Bool {
		model.preferences[Preferences.Theme.fontIsUserConfigurable]
	}

	private var messageToggles: some View {
		VStack(alignment: .leading, spacing: 6) {
			PreferencesToggle(
				title: PreferencesStyleStrings.autoScrollbackMarker,
				isOn: model.preferences.binding(for: Preferences.Messages.autoAddScrollbackMark)
			)
			PreferencesToggle(
				title: PreferencesStyleStrings.showDateChanges,
				isOn: model.preferences.binding(for: Preferences.Messages.showDateChanges) { _ in
					TextualPreferences.performReloadAction([.style, .textDirection])
				}
			)
			PreferencesToggle(
				title: PreferencesStyleStrings.showJoinLeave,
				isOn: model.preferences.binding(for: Preferences.Messages.showJoinLeave)
			)
			PreferencesNote(PreferencesStyleStrings.showJoinLeaveNote)
		}
	}

	private var formatFields: some View {
		VStack(alignment: .leading, spacing: 10) {
			LabeledContent {
				PreferencesComboField(
					title: PreferencesStyleStrings.nicknameFormatLabel,
					presets: Self.nicknamePresets,
					text: model.preferences.binding(for: Preferences.Theme.nicknameFormat) { _ in
						TextualPreferences.performReloadAction([.style, .textDirection])
					}
				)
				.disabled(
					model.isReloadingTheme
						|| model.preferences[Preferences.Theme.nicknameFormatIsUserConfigurable] == false
				)
			} label: {
				Text(verbatim: PreferencesStyleStrings.nicknameFormatLabel)
			}
			PreferencesNote(Self.nicknameFormatNote)

			LabeledContent {
				PreferencesComboField(
					title: PreferencesStyleStrings.timestampFormatLabel,
					presets: Self.timestampPresets,
					text: model.preferences.binding(for: Preferences.Theme.timestampFormat) { _ in
						TextualPreferences.performReloadAction([.style, .textDirection])
					}
				)
				.disabled(
					model.isReloadingTheme
						|| model.preferences[Preferences.Theme.timestampFormatIsUserConfigurable] == false
				)
			} label: {
				Text(verbatim: PreferencesStyleStrings.timestampFormatLabel)
			}
			PreferencesNote(PreferencesStyleStrings.timestampFormatNote)
		}
	}

	/** The two placeholders are template tokens the style engine reads, so they
	 stay in the code rather than in a translatable string. */
	private static var nicknameFormatNote: String {
		"\(PreferencesStyleStrings.formatSymbolsLabel) "
			+ "%@ = \(PreferencesStyleStrings.nicknameFormatSymbolMode); "
			+ "%n = \(PreferencesStyleStrings.nicknameFormatSymbolNickname)"
	}

	private var advancedToggles: some View {
		VStack(alignment: .leading, spacing: 6) {
			PreferencesToggle(
				title: PreferencesStyleStrings.disableNicknameColors,
				isOn: model.preferences.binding(
					for: Preferences.Messages.disableNicknameColorHashing
				) { _ in
					TextualPreferences.performReloadAction([.style, .textDirection])
				}
			)
			.disabled(model.isReloadingTheme)
			PreferencesToggle(
				title: PreferencesStyleStrings.inlineNicknameModeSymbol,
				isOn: model.preferences.binding(
					for: Preferences.Appearance.conversationTrackingIncludesModeSymbol
				)
			)
			.disabled(model.isReloadingTheme)
			PreferencesToggle(
				title: PreferencesStyleStrings.showMotd,
				isOn: model.preferences.binding(for: Preferences.Connection.displayServerMOTD)
			)
		}
	}
}
