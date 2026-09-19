// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated extension SettingsKeys {
	/// Window chrome and the two sidebars.
	enum Appearance {
		private static let group = "Appearance -> "

		static let preferredAppearance = SettingsKey(
			group + "Preferred Appearance",
			default: PreferredAppearance.inherited
		)

		static let disableSidebarTranslucency = SettingsKey(
			group + "Disable Sidebar Translucency",
			default: false
		)
		static let memberListNoModeSymbol = SettingsKey(group + "Member List No Mode Symbol", default: true)
		static let memberListSortFavorsServerStaff = SettingsKey(
			group + "Member List Sort Favors Server Staff",
			default: false
		)

		static let memberListUpdatesPopoverOnScroll = SettingsKey(
			group + "Member List Updates Popover On Scroll",
			default: true
		)

		static let conversationTrackingIncludesModeSymbol = SettingsKey(
			group + "Conversation Tracking Includes Mode Symbol",
			default: false
		)

		/** The largest channel a WHO sweep still tracks away status in.

		 The Settings slider is a `Double`, so the bound has to be a count that
		 survives that round trip exactly: `Int(Double(UInt(Int.max)))` is one
		 past `Int.max` and traps. `Int32.max` is exact as a `Double`, and no
		 channel comes within seven orders of magnitude of it. */
		static let trackUserAwayStatusMaximumChannelSize = SettingsKey(
			group + "Track User Away Status Maximum Channel Size",
			default: UInt(300),
			validation: { $0 <= UInt(Int32.max) }
		)

		/// Whether moving to the next or previous conversation stays inside the
		/// selected server rather than running through the whole sidebar.
		static let conversationNavigationIsServerSpecific = SettingsKey(
			group + "Conversation Navigation Is Server Specific",
			default: true
		)

		static let connectOnDoubleClick = SettingsKey(group + "Connect On Double Click", default: false)
		static let disconnectOnDoubleClick = SettingsKey(
			group + "Disconnect On Double Click",
			default: false
		)

		static let joinOnDoubleClick = SettingsKey(group + "Join On Double Click", default: false)
		static let leaveOnDoubleClick = SettingsKey(group + "Leave On Double Click", default: false)

		/// Whether one-to-one conversations survive a quit: kept in the server's
		/// configuration, and their scrollback reloaded on the next launch.
		static let rememberDirectConversations = SettingsKey(
			group + "Remember Direct Conversations",
			default: false
		)

		static let all: [any AnySettingsKey] = [
			preferredAppearance, disableSidebarTranslucency, memberListNoModeSymbol,
			memberListSortFavorsServerStaff, memberListUpdatesPopoverOnScroll,
			conversationTrackingIncludesModeSymbol, trackUserAwayStatusMaximumChannelSize,
			conversationNavigationIsServerSpecific, connectOnDoubleClick, disconnectOnDoubleClick,
			joinOnDoubleClick, leaveOnDoubleClick, rememberDirectConversations,
		]
	}
}

/** What the window chrome follows.

 The case order is the order the appearance picker offers, because the picker
 builds its rows from `allCases`. The conformance is here rather than beside the
 picker because the synthesis only happens in the file that declares the enum. */
enum PreferredAppearance: UInt, CaseIterable, Sendable {
	case inherited
	case light
	case dark
}

extension PreferredAppearance: SettingEnum {}

extension PreferredAppearance {
	/// What the appearance picker calls this choice.
	var displayName: LocalizedStringResource {
		switch self {
		case .inherited: .Settings.interfaceAppearanceSystem
		case .light: .Settings.interfaceAppearanceLight
		case .dark: .Settings.interfaceAppearanceDark
		}
	}
}
