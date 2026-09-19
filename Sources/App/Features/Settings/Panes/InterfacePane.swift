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
				isOn: model.settings.binding(for: SettingsKeys.Messages.rightToLeftFormatting)
			)
			appearancePicker
			SettingsToggle(
				title: .Settings.interfaceStaffAtTop,
				isOn: model.settings.binding(
					for: SettingsKeys.Appearance.memberListSortFavorsServerStaff
				)
			)
			SettingsToggle(
				title: .Settings.interfacePopoverUpdatesOnScroll,
				isOn: model.settings.binding(for: SettingsKeys.Appearance.memberListUpdatesPopoverOnScroll)
			)
		} header: {
			Text(.Settings.headingGeneral)
		}

		Section {
			sidebarBadgeColor
		} header: {
			Text(.Settings.interfaceHeadingServerListColors)
		}

		Section {
			ForEach(UserListModeBadge.allCases, id: \.self) { badge in
				ColorPicker(
					selection: model.settings.colorBinding(for: badge.settingsKey),
					supportsOpacity: false
				) {
					Text(badge.displayName)
				}
			}
			Button(.Settings.interfaceResetToDefaults, role: .destructive) {
				confirmResetUserListColors()
			}
			.help(Text(.Settings.interfaceResetUserListColors))
			.accessibilityLabel(Text(.Settings.interfaceResetUserListColors))
			.confirmationDialog(
				Text(.Settings.interfaceResetColorsConfirmation),
				isPresented: $confirmsUserListColorReset
			) {
				Button(.Settings.interfaceResetToDefaults, role: .destructive) {
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
		Picker(selection: model.settings.binding(for: SettingsKeys.Appearance.preferredAppearance)) {
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

	private var sidebarBadgeColor: some View {
		HStack {
			ColorPicker(
				selection: model.settings.storedColorBinding(
					for: SettingsKeys.Badges.sidebarUnreadHighlight
				),
				supportsOpacity: false
			) {
				Text(.Settings.interfaceUnreadHighlightColorLabel)
			}
			Spacer()
			Button(.Settings.interfaceReset) {
				model.settings.reset(SettingsKeys.Badges.sidebarUnreadHighlight)
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
		UserListModeBadge.allCases.contains { model.settings[stored: $0.settingsKey] != nil }
	}

	private func resetUserListColors() {
		for badge in UserListModeBadge.allCases {
			model.settings.reset(badge.settingsKey)
		}
	}
}
