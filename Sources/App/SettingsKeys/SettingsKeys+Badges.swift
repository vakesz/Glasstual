// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The user-list mode badges, keyed by the mode symbol they colour.

 The symbol, the setting key and the shipped colour are one declaration
 here rather than three literal lists in as many files. */
nonisolated enum UserListModeBadge: String, CaseIterable, Sendable {
	case ircOperator = "+y"
	case channelOwner = "+q"
	case superOperator = "+a"
	case normalOperator = "+o"
	case halfOperator = "+h"
	case voiced = "+v"

	var modeSymbol: String {
		rawValue
	}

	private var defaultColor: SettingsColor {
		switch self {
		case .ircOperator: SettingsColor(red: 0.632, green: 0.335, blue: 0.226)
		case .channelOwner: SettingsColor(red: 0.726, green: 0.0, blue: 0.0)
		case .superOperator: SettingsColor(red: 0.613, green: 0.0, blue: 0.347)
		case .normalOperator: SettingsColor(red: 0.351, green: 0.199, blue: 0.609)
		case .halfOperator: SettingsColor(red: 0.066, green: 0.488, blue: 0.074)
		case .voiced: SettingsColor(red: 0.199, green: 0.480, blue: 0.609)
		}
	}

	var settingsKey: SettingsKey<SettingsColor> {
		SettingsKey(SettingsKeys.Badges.group + "Mode Badge Colors -> \(rawValue)", default: defaultColor)
	}
}

nonisolated extension SettingsKeys {
	/// The colour wells in the "User List" and "Server List" settings panes.
	enum Badges {
		/// Not private, unlike every other domain's: the mode badges build their
		/// own names from it, beside the mode symbol and colour they belong to.
		static let group = "Badges -> "

		static let userListMode = UserListModeBadge.allCases.map(\.settingsKey)

		/** Unregistered on purpose: with nothing stored the server-list cell uses
		 the colour its appearance defines, which changes with the window's
		 active state and so cannot be written as a fixed default. Read it with
		 `storedColor(for:)`, not `color(for:)`. */
		static let sidebarUnreadHighlight = SettingsKey(
			group + "Sidebar Unread Highlight",
			default: SettingsColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
			traits: .unregistered
		)

		static let all: [any AnySettingsKey] = userListMode + [sidebarUnreadHighlight]
	}
}

/** What the settings call each user-list mode.

 The pane's colour wells and the inventory that gives every bound key a
 user-facing name read the same declaration, so a mode cannot be spelled one
 way beside its colour and another in an import preview. */
extension UserListModeBadge {
	var displayName: LocalizedStringResource {
		switch self {
		case .ircOperator: .Settings.interfaceModeServerStaff
		case .channelOwner: .Settings.interfaceModeChannelOwner
		case .superOperator: .Settings.interfaceModeChannelAdministrator
		case .normalOperator: .Settings.interfaceModeChannelOperator
		case .halfOperator: .Settings.interfaceModeChannelHalfOperator
		case .voiced: .Settings.interfaceModeVoicedUser
		}
	}
}
