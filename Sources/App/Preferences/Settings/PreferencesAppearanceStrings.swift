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

import Foundation

enum PreferencesInterfaceStrings {
	static var appearanceDark: String {
		String(localized: .Settings.interfaceAppearanceDark)
	}

	static var appearanceLabel: String {
		String(localized: .Settings.interfaceAppearanceLabel)
	}

	static var appearanceLight: String {
		String(localized: .Settings.interfaceAppearanceLight)
	}

	static var appearanceSystem: String {
		String(localized: .Settings.interfaceAppearanceSystem)
	}

	static var headingServerListColors: String {
		String(localized: .Settings.interfaceHeadingServerListColors)
	}

	static var headingUserListColors: String {
		String(localized: .Settings.interfaceHeadingUserListColors)
	}

	static var modeChannelAdministrator: String {
		String(localized: .Settings.interfaceModeChannelAdministrator)
	}

	static var modeChannelHalfOperator: String {
		String(localized: .Settings.interfaceModeChannelHalfOperator)
	}

	static var modeChannelOperator: String {
		String(localized: .Settings.interfaceModeChannelOperator)
	}

	static var modeChannelOwner: String {
		String(localized: .Settings.interfaceModeChannelOwner)
	}

	static var modeServerStaff: String {
		String(localized: .Settings.interfaceModeServerStaff)
	}

	static var modeVoicedUser: String {
		String(localized: .Settings.interfaceModeVoicedUser)
	}

	static var noModeSymbol: String {
		String(localized: .Settings.interfaceNoModeSymbol)
	}

	static var popoverUpdatesOnScroll: String {
		String(localized: .Settings.interfacePopoverUpdatesOnScroll)
	}

	static var reset: String {
		String(localized: .Settings.interfaceReset)
	}

	static var resetToDefaults: String {
		String(localized: .Settings.interfaceResetToDefaults)
	}

	static var resetColorsConfirmationTitle: String {
		String(localized: .Settings.interfaceResetColorsConfirmation)
	}

	static var resetColorsConfirmationBody: String {
		String(localized: .Settings.interfaceResetColorsConfirmationBody)
	}

	static var resetThemeConfirmationTitle: String {
		String(localized: .Settings.interfaceResetThemeConfirmation)
	}

	static var resetThemeConfirmationBody: String {
		String(localized: .Settings.interfaceResetThemeConfirmationBody)
	}

	static var resetUnreadHighlightColor: String {
		String(localized: .Settings.interfaceResetUnreadHighlightColor)
	}

	static var resetUserListColors: String {
		String(localized: .Settings.interfaceResetUserListColors)
	}

	static var rightToLeftText: String {
		String(localized: .Settings.interfaceRightToLeftText)
	}

	static var staffAtTop: String {
		String(localized: .Settings.interfaceStaffAtTop)
	}

	static var unreadHighlightColorLabel: String {
		String(localized: .Settings.interfaceUnreadHighlightColorLabel)
	}

	static var userListColorsNote: String {
		String(localized: .Settings.interfaceUserListColorsNote)
	}
}

enum PreferencesStyleStrings {
	static var autoScrollbackMarker: String {
		String(localized: .Settings.styleAutoScrollbackMarker)
	}

	static var disableNicknameColors: String {
		String(localized: .Settings.styleDisableNicknameColors)
	}

	static var fontChange: String {
		String(localized: .Settings.styleFontChange)
	}

	static func fontDescription(name: String, size: String) -> String {
		String(localized: .Settings.styleFontDescription(name, size))
	}

	static var fontLabel: String {
		String(localized: .Settings.styleFontLabel)
	}

	static var fontPickerChoose: String {
		String(localized: .Settings.styleFontPickerChoose)
	}

	static var fontPickerTitle: String {
		String(localized: .Settings.styleFontPickerTitle)
	}

	static var fontSizeLabel: String {
		String(localized: .Settings.styleFontSizeLabel)
	}

	static func colorAccessibility(role: String, appearance: String) -> String {
		String(localized: .Settings.styleColorAccessibility(role, appearance))
	}

	static var formatSymbolsLabel: String {
		String(localized: .Settings.styleFormatSymbolsLabel)
	}

	static var headingLayout: String {
		String(localized: .Settings.styleHeadingLayout)
	}

	static var headingScrollback: String {
		String(localized: .Settings.styleHeadingScrollback)
	}

	static var nicknameFormatLabel: String {
		String(localized: .Settings.styleNicknameFormatLabel)
	}

	static var nicknameFormatSymbolMode: String {
		String(localized: .Settings.styleNicknameFormatSymbolMode)
	}

	static var nicknameFormatSymbolNickname: String {
		String(localized: .Settings.styleNicknameFormatSymbolNickname)
	}

	static var scrollbackSaveLimit: String {
		String(localized: .Settings.styleScrollbackSaveLimit)
	}

	static var scrollbackSaveLimitNote: String {
		String(localized: .Settings.styleScrollbackSaveLimitNote)
	}

	static var showDateChanges: String {
		String(localized: .Settings.styleShowDateChanges)
	}

	static var showJoinLeave: String {
		String(localized: .Settings.styleShowJoinLeave)
	}

	static var showMotd: String {
		String(localized: .Settings.styleShowMotd)
	}

	static var timestampFormatLabel: String {
		String(localized: .Settings.styleTimestampFormatLabel)
	}

	static var timestampFormatNote: String {
		String(localized: .Settings.styleTimestampFormatNote)
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

	var title: String {
		String(localized: displayName)
	}
}

extension PreferredAppearance {
	var title: String {
		let resource: LocalizedStringResource = switch self {
		case .inherited: .Settings.interfaceAppearanceSystem
		case .light: .Settings.interfaceAppearanceLight
		case .dark: .Settings.interfaceAppearanceDark
		}
		return String(localized: resource)
	}
}
