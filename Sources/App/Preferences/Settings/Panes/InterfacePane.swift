// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// The Interface row: what the window chrome follows, how the member list is
/// ordered, and the colours the two sidebars draw names in.
struct InterfacePane: View {
	let model: SettingsModel
	@State private var confirmsUserListColorReset = false

	var body: some View {
		Section {
			SettingsToggle(
				title: .Settings.interfaceRightToLeftText,
				isOn: model.preferences.binding(for: Preferences.Messages.rightToLeftFormatting) { _ in
					PreferenceReload.perform([.style, .textDirection])
				}
			)
			appearancePicker
			SettingsToggle(
				title: .Settings.interfaceNoModeSymbol,
				isOn: model.preferences.binding(for: Preferences.Appearance.memberListNoModeSymbol) { _ in
					PreferenceReload.perform([.memberListUserBadges, .memberList])
				}
			)
			SettingsToggle(
				title: .Settings.interfaceStaffAtTop,
				isOn: model.preferences.binding(
					for: Preferences.Appearance.memberListSortFavorsServerStaff
				) { _ in PreferenceReload.perform(.memberListSortOrder) }
			)
			SettingsToggle(
				title: .Settings.interfacePopoverUpdatesOnScroll,
				isOn: model.preferences.binding(for: Preferences.Appearance.memberListUpdatesPopoverOnScroll)
			)
		} header: {
			Text(.Settings.headingGeneral)
		}

		Section {
			serverListBadgeColor
		} header: {
			Text(.Settings.interfaceHeadingServerListColors)
		}

		Section {
			ForEach(UserListModeBadge.allCases, id: \.self) { badge in
				ColorPicker(
					selection: model.preferences.colorBinding(for: badge.preferenceKey) {
						PreferenceReload.perform(
							.memberListUserBadges,
							forKey: badge.preferenceKey.name
						)
					},
					supportsOpacity: false
				) {
					Text(badge.displayName)
				}
			}
			Button(String(localized: .Settings.interfaceResetToDefaults), role: .destructive) {
				confirmResetUserListColors()
			}
			.help(Text(.Settings.interfaceResetUserListColors))
			.accessibilityLabel(Text(.Settings.interfaceResetUserListColors))
			.confirmationDialog(
				Text(.Settings.interfaceResetColorsConfirmation),
				isPresented: $confirmsUserListColorReset
			) {
				Button(String(localized: .Settings.interfaceResetToDefaults), role: .destructive) {
					resetUserListColors()
				}
				Button(PromptStrings.Action.cancel, role: .cancel) {}
			} message: {
				Text(.Settings.interfaceResetColorsConfirmationBody)
			}
		} header: {
			Text(.Settings.interfaceHeadingUserListColors)
		} footer: {
			SettingsNote(.Settings.interfaceUserListColorsNote)
		}
	}

	private var appearancePicker: some View {
		Picker(selection: model.preferences.binding(for: Preferences.Appearance.preferredAppearance) { _ in
			PreferenceReload.perform(.appearance)
		}) {
			/* From `allCases`, so the picker offers every appearance the type
			 declares: three rows spelled out here is three rows that go on
			 saying three when a fourth is added. */
			ForEach(PreferredAppearance.allCases, id: \.self) { appearance in
				Text(appearance.displayName).tag(appearance)
			}
		} label: {
			Text(.Settings.interfaceAppearanceLabel)
		}
	}

	private var serverListBadgeColor: some View {
		HStack {
			ColorPicker(
				selection: model.preferences.storedColorBinding(
					for: Preferences.Badges.serverListUnreadHighlight
				) { PreferenceReload.perform(.serverListUnreadBadges) },
				supportsOpacity: false
			) {
				Text(.Settings.interfaceUnreadHighlightColorLabel)
			}
			Spacer()
			Button(String(localized: .Settings.interfaceReset)) {
				model.preferences.reset(Preferences.Badges.serverListUnreadHighlight)
				PreferenceReload.perform(.serverListUnreadBadges)
			}
			.help(Text(.Settings.interfaceResetUnreadHighlightColor))
			.accessibilityLabel(Text(.Settings.interfaceResetUnreadHighlightColor))
		}
	}

	/// Colours the user picked are gone for good, so a reset that would throw
	/// any away asks first. With nothing customised there is nothing to lose.
	private func confirmResetUserListColors() {
		guard hasCustomUserListColors else {
			resetUserListColors()
			return
		}

		confirmsUserListColorReset = true
	}

	private var hasCustomUserListColors: Bool {
		UserListModeBadge.allCases.contains { model.preferences[stored: $0.preferenceKey] != nil }
	}

	private func resetUserListColors() {
		for badge in UserListModeBadge.allCases {
			model.preferences.reset(badge.preferenceKey)
		}
		PreferenceReload.perform([.memberListUserBadges, .memberList])
	}
}
