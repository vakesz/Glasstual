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

enum PreferencesControlsStrings {
	static var commandReturnAction: String {
		String(localized: .Settings.controlsCommandReturnAction)
	}

	static var commandWCloseWindow: String {
		String(localized: .Settings.controlsCommandWCloseWindow)
	}

	static var commandWDisconnect: String {
		String(localized: .Settings.controlsCommandWDisconnect)
	}

	static var commandWLabel: String {
		String(localized: .Settings.controlsCommandWLabel)
	}

	static var commandWPartChannel: String {
		String(localized: .Settings.controlsCommandWPartChannel)
	}

	static var commandWTerminate: String {
		String(localized: .Settings.controlsCommandWTerminate)
	}

	static func completionPreview(suffix: String) -> String {
		String(localized: .Settings.controlsCompletionPreview(suffix))
	}

	static var completionPreviewLabel: String {
		String(localized: .Settings.controlsCompletionPreviewLabel)
	}

	static var completionSuffixAccessibility: String {
		String(localized: .Settings.controlsCompletionSuffixAccessibility)
	}

	static var completionSuffixLabel: String {
		String(localized: .Settings.controlsCompletionSuffixLabel)
	}

	static var connectOnDoubleClick: String {
		String(localized: .Settings.controlsConnectOnDoubleClick)
	}

	static var controlEnterSends: String {
		String(localized: .Settings.controlsControlEnterSends)
	}

	static var copyOnSelect: String {
		String(localized: .Settings.controlsCopyOnSelect)
	}

	static var copyOnSelectNote: String {
		String(localized: .Settings.controlsCopyOnSelectNote)
	}

	static var disconnectOnDoubleClick: String {
		String(localized: .Settings.controlsDisconnectOnDoubleClick)
	}

	static var grammarCheck: String {
		String(localized: .Settings.controlsGrammarCheck)
	}

	static var headingKeyboardMouse: String {
		String(localized: .Settings.controlsHeadingKeyboardMouse)
	}

	static var headingTextField: String {
		String(localized: .Settings.controlsHeadingTextField)
	}

	static var historyPerSelection: String {
		String(localized: .Settings.controlsHistoryPerSelection)
	}

	static var joinOnDoubleClick: String {
		String(localized: .Settings.controlsJoinOnDoubleClick)
	}

	static var leaveOnDoubleClick: String {
		String(localized: .Settings.controlsLeaveOnDoubleClick)
	}

	static var navigationServerSpecific: String {
		String(localized: .Settings.controlsNavigationServerSpecific)
	}

	static var openLinksInBackground: String {
		String(localized: .Settings.controlsOpenLinksInBackground)
	}

	static var spellCheck: String {
		String(localized: .Settings.controlsSpellCheck)
	}

	static var spellCorrection: String {
		String(localized: .Settings.controlsSpellCorrection)
	}

	static var tabKeyComplete: String {
		String(localized: .Settings.controlsTabKeyComplete)
	}

	static var tabKeyLabel: String {
		String(localized: .Settings.controlsTabKeyLabel)
	}

	static var tabKeyNone: String {
		String(localized: .Settings.controlsTabKeyNone)
	}

	static var tabKeyUnread: String {
		String(localized: .Settings.controlsTabKeyUnread)
	}

	static var textSizeExtraLarge: String {
		String(localized: .Settings.controlsTextSizeExtraLarge)
	}

	static var textSizeHumongous: String {
		String(localized: .Settings.controlsTextSizeHumongous)
	}

	static var textSizeLabel: String {
		String(localized: .Settings.controlsTextSizeLabel)
	}

	static var textSizeLarge: String {
		String(localized: .Settings.controlsTextSizeLarge)
	}

	static var textSizeNormal: String {
		String(localized: .Settings.controlsTextSizeNormal)
	}

	static var userDoubleClickInsert: String {
		String(localized: .Settings.controlsUserDoubleClickInsert)
	}

	static var userDoubleClickLabel: String {
		String(localized: .Settings.controlsUserDoubleClickLabel)
	}

	static var userDoubleClickQuery: String {
		String(localized: .Settings.controlsUserDoubleClickQuery)
	}

	static var userDoubleClickWhois: String {
		String(localized: .Settings.controlsUserDoubleClickWhois)
	}
}

enum PreferencesDefaultIdentityStrings {
	static var allOptional: String {
		String(localized: .Settings.defaultIdentityAllOptional)
	}

	static var awayNickname: String {
		String(localized: .Settings.defaultIdentityAwayNickname)
	}

	static var nickname: String {
		String(localized: .Settings.defaultIdentityNickname)
	}

	static var note: String {
		String(localized: .Settings.defaultIdentityNote)
	}

	static var optional: String {
		String(localized: .Settings.defaultIdentityOptional)
	}

	static var realname: String {
		String(localized: .Settings.defaultIdentityRealname)
	}

	static var username: String {
		String(localized: .Settings.defaultIdentityUsername)
	}
}

enum PreferencesIRCopStrings {
	static var glineLabel: String {
		String(localized: .Settings.ircopGlineLabel)
	}

	static var includesBanLength: String {
		String(localized: .Settings.ircopIncludesBanLength)
	}

	static var killLabel: String {
		String(localized: .Settings.ircopKillLabel)
	}

	static var shunLabel: String {
		String(localized: .Settings.ircopShunLabel)
	}
}
