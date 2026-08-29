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

nonisolated enum PreferencesInterfaceStrings { // nonisolated: value
	static var appearanceDark: String {
		String(localized: .TDCPreferencesController.interfaceAppearanceDark)
	}

	static var appearanceLabel: String {
		String(localized: .TDCPreferencesController.interfaceAppearanceLabel)
	}

	static var appearanceLight: String {
		String(localized: .TDCPreferencesController.interfaceAppearanceLight)
	}

	static var appearanceSystem: String {
		String(localized: .TDCPreferencesController.interfaceAppearanceSystem)
	}

	static var arrangementLabel: String {
		String(localized: .TDCPreferencesController.interfaceArrangementLabel)
	}

	static var arrangementLeftToRight: String {
		String(localized: .TDCPreferencesController.interfaceArrangementLeftToRight)
	}

	static var arrangementTopToBottom: String {
		String(localized: .TDCPreferencesController.interfaceArrangementTopToBottom)
	}

	static var headingServerListColors: String {
		String(localized: .TDCPreferencesController.interfaceHeadingServerListColors)
	}

	static var headingUserListColors: String {
		String(localized: .TDCPreferencesController.interfaceHeadingUserListColors)
	}

	static var modeChannelAdministrator: String {
		String(localized: .TDCPreferencesController.interfaceModeChannelAdministrator)
	}

	static var modeChannelHalfOperator: String {
		String(localized: .TDCPreferencesController.interfaceModeChannelHalfOperator)
	}

	static var modeChannelOperator: String {
		String(localized: .TDCPreferencesController.interfaceModeChannelOperator)
	}

	static var modeChannelOwner: String {
		String(localized: .TDCPreferencesController.interfaceModeChannelOwner)
	}

	static var modeServerStaff: String {
		String(localized: .TDCPreferencesController.interfaceModeServerStaff)
	}

	static var modeVoicedUser: String {
		String(localized: .TDCPreferencesController.interfaceModeVoicedUser)
	}

	static var noModeSymbol: String {
		String(localized: .TDCPreferencesController.interfaceNoModeSymbol)
	}

	static var popoverUpdatesOnScroll: String {
		String(localized: .TDCPreferencesController.interfacePopoverUpdatesOnScroll)
	}

	static var reset: String {
		String(localized: .TDCPreferencesController.interfaceReset)
	}

	static var resetToDefaults: String {
		String(localized: .TDCPreferencesController.interfaceResetToDefaults)
	}

	static var resetUnreadHighlightColor: String {
		String(localized: .TDCPreferencesController.interfaceResetUnreadHighlightColor)
	}

	static var resetUserListColors: String {
		String(localized: .TDCPreferencesController.interfaceResetUserListColors)
	}

	static var rightToLeftText: String {
		String(localized: .TDCPreferencesController.interfaceRightToLeftText)
	}

	static var staffAtTop: String {
		String(localized: .TDCPreferencesController.interfaceStaffAtTop)
	}

	static var unreadHighlightColorLabel: String {
		String(localized: .TDCPreferencesController.interfaceUnreadHighlightColorLabel)
	}

	static var userListColorsNote: String {
		String(localized: .TDCPreferencesController.interfaceUserListColorsNote)
	}
}

nonisolated enum PreferencesStyleStrings { // nonisolated: value
	static var autoScrollbackMarker: String {
		String(localized: .TDCPreferencesController.styleAutoScrollbackMarker)
	}

	static var browseFiles: String {
		String(localized: .TDCPreferencesController.styleBrowseFiles)
	}

	static var browseFilesHelp: String {
		String(localized: .TDCPreferencesController.styleBrowseFilesHelp)
	}

	static var disableNicknameColors: String {
		String(localized: .TDCPreferencesController.styleDisableNicknameColors)
	}

	static var fontChange: String {
		String(localized: .TDCPreferencesController.styleFontChange)
	}

	static var fontChangeHelp: String {
		String(localized: .TDCPreferencesController.styleFontChangeHelp)
	}

	static var fontCurrent: String {
		String(localized: .TDCPreferencesController.styleFontCurrent)
	}

	static func fontDescription(name: String, size: String) -> String {
		String(localized: .TDCPreferencesController.styleFontDescription(name, size))
	}

	static var fontLabel: String {
		String(localized: .TDCPreferencesController.styleFontLabel)
	}

	static var formatSymbolsLabel: String {
		String(localized: .TDCPreferencesController.styleFormatSymbolsLabel)
	}

	static var headingDevelopers: String {
		String(localized: .TDCPreferencesController.styleHeadingDevelopers)
	}

	static var headingScrollback: String {
		String(localized: .TDCPreferencesController.styleHeadingScrollback)
	}

	static var inlineNicknameModeSymbol: String {
		String(localized: .TDCPreferencesController.styleInlineNicknameModeSymbol)
	}

	static var label: String {
		String(localized: .TDCPreferencesController.styleLabel)
	}

	static var modifyStyleSheet: String {
		String(localized: .TDCPreferencesController.styleModifyStyleSheet)
	}

	static var nicknameFormatLabel: String {
		String(localized: .TDCPreferencesController.styleNicknameFormatLabel)
	}

	static var nicknameFormatSymbolMode: String {
		String(localized: .TDCPreferencesController.styleNicknameFormatSymbolMode)
	}

	static var nicknameFormatSymbolNickname: String {
		String(localized: .TDCPreferencesController.styleNicknameFormatSymbolNickname)
	}

	static var reloadCustomStyles: String {
		String(localized: .TDCPreferencesController.styleReloadCustomStyles)
	}

	static var reloadCustomStylesNote: String {
		String(localized: .TDCPreferencesController.styleReloadCustomStylesNote)
	}

	static var scrollbackSaveLimit: String {
		String(localized: .TDCPreferencesController.styleScrollbackSaveLimit)
	}

	static var scrollbackSaveLimitNote: String {
		String(localized: .TDCPreferencesController.styleScrollbackSaveLimitNote)
	}

	static var showDateChanges: String {
		String(localized: .TDCPreferencesController.styleShowDateChanges)
	}

	static var showJoinLeave: String {
		String(localized: .TDCPreferencesController.styleShowJoinLeave)
	}

	static var showJoinLeaveNote: String {
		String(localized: .TDCPreferencesController.styleShowJoinLeaveNote)
	}

	static var showMotd: String {
		String(localized: .TDCPreferencesController.styleShowMotd)
	}

	static var timestampFormatLabel: String {
		String(localized: .TDCPreferencesController.styleTimestampFormatLabel)
	}

	static var timestampFormatNote: String {
		String(localized: .TDCPreferencesController.styleTimestampFormatNote)
	}
}
