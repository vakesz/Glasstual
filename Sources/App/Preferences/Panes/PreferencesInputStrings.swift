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

nonisolated enum PreferencesControlsStrings { // nonisolated: value
	static var commandReturnAction: String {
		String(localized: .TDCPreferencesController.controlsCommandReturnAction)
	}

	static var commandWCloseWindow: String {
		String(localized: .TDCPreferencesController.controlsCommandWCloseWindow)
	}

	static var commandWDisconnect: String {
		String(localized: .TDCPreferencesController.controlsCommandWDisconnect)
	}

	static var commandWLabel: String {
		String(localized: .TDCPreferencesController.controlsCommandWLabel)
	}

	static var commandWPartChannel: String {
		String(localized: .TDCPreferencesController.controlsCommandWPartChannel)
	}

	static var commandWTerminate: String {
		String(localized: .TDCPreferencesController.controlsCommandWTerminate)
	}

	static func completionPreview(suffix: String) -> String {
		String(localized: .TDCPreferencesController.controlsCompletionPreview(suffix))
	}

	static var completionPreviewLabel: String {
		String(localized: .TDCPreferencesController.controlsCompletionPreviewLabel)
	}

	static var completionSuffixAccessibility: String {
		String(localized: .TDCPreferencesController.controlsCompletionSuffixAccessibility)
	}

	static var completionSuffixLabel: String {
		String(localized: .TDCPreferencesController.controlsCompletionSuffixLabel)
	}

	static var connectOnDoubleClick: String {
		String(localized: .TDCPreferencesController.controlsConnectOnDoubleClick)
	}

	static var controlEnterSends: String {
		String(localized: .TDCPreferencesController.controlsControlEnterSends)
	}

	static var copyOnSelect: String {
		String(localized: .TDCPreferencesController.controlsCopyOnSelect)
	}

	static var copyOnSelectNote: String {
		String(localized: .TDCPreferencesController.controlsCopyOnSelectNote)
	}

	static var disconnectOnDoubleClick: String {
		String(localized: .TDCPreferencesController.controlsDisconnectOnDoubleClick)
	}

	static var grammarCheck: String {
		String(localized: .TDCPreferencesController.controlsGrammarCheck)
	}

	static var headingKeyboardMouse: String {
		String(localized: .TDCPreferencesController.controlsHeadingKeyboardMouse)
	}

	static var headingTextField: String {
		String(localized: .TDCPreferencesController.controlsHeadingTextField)
	}

	static var historyPerSelection: String {
		String(localized: .TDCPreferencesController.controlsHistoryPerSelection)
	}

	static var joinOnDoubleClick: String {
		String(localized: .TDCPreferencesController.controlsJoinOnDoubleClick)
	}

	static var leaveOnDoubleClick: String {
		String(localized: .TDCPreferencesController.controlsLeaveOnDoubleClick)
	}

	static var navigationServerSpecific: String {
		String(localized: .TDCPreferencesController.controlsNavigationServerSpecific)
	}

	static var spellCheck: String {
		String(localized: .TDCPreferencesController.controlsSpellCheck)
	}

	static var spellCorrection: String {
		String(localized: .TDCPreferencesController.controlsSpellCorrection)
	}

	static var tabKeyComplete: String {
		String(localized: .TDCPreferencesController.controlsTabKeyComplete)
	}

	static var tabKeyLabel: String {
		String(localized: .TDCPreferencesController.controlsTabKeyLabel)
	}

	static var tabKeyNone: String {
		String(localized: .TDCPreferencesController.controlsTabKeyNone)
	}

	static var tabKeyUnread: String {
		String(localized: .TDCPreferencesController.controlsTabKeyUnread)
	}

	static var textSizeExtraLarge: String {
		String(localized: .TDCPreferencesController.controlsTextSizeExtraLarge)
	}

	static var textSizeHumongous: String {
		String(localized: .TDCPreferencesController.controlsTextSizeHumongous)
	}

	static var textSizeLabel: String {
		String(localized: .TDCPreferencesController.controlsTextSizeLabel)
	}

	static var textSizeLarge: String {
		String(localized: .TDCPreferencesController.controlsTextSizeLarge)
	}

	static var textSizeNormal: String {
		String(localized: .TDCPreferencesController.controlsTextSizeNormal)
	}

	static var userDoubleClickInsert: String {
		String(localized: .TDCPreferencesController.controlsUserDoubleClickInsert)
	}

	static var userDoubleClickLabel: String {
		String(localized: .TDCPreferencesController.controlsUserDoubleClickLabel)
	}

	static var userDoubleClickQuery: String {
		String(localized: .TDCPreferencesController.controlsUserDoubleClickQuery)
	}

	static var userDoubleClickWhois: String {
		String(localized: .TDCPreferencesController.controlsUserDoubleClickWhois)
	}
}

nonisolated enum PreferencesAddOnsStrings { // nonisolated: value
	static var commandsLabel: String {
		String(localized: .TDCPreferencesController.addonsCommandsLabel)
	}

	static var commandsList: String {
		String(localized: .TDCPreferencesController.addonsCommandsList)
	}

	static var commandsNote: String {
		String(localized: .TDCPreferencesController.addonsCommandsNote)
	}

	static var locationLabel: String {
		String(localized: .TDCPreferencesController.addonsLocationLabel)
	}

	static var openInFinder: String {
		String(localized: .TDCPreferencesController.addonsOpenInFinder)
	}

	static var openInFinderHelp: String {
		String(localized: .TDCPreferencesController.addonsOpenInFinderHelp)
	}
}

nonisolated enum PreferencesDefaultIdentityStrings { // nonisolated: value
	static var allOptional: String {
		String(localized: .TDCPreferencesController.defaultIdentityAllOptional)
	}

	static var awayNickname: String {
		String(localized: .TDCPreferencesController.defaultIdentityAwayNickname)
	}

	static var nickname: String {
		String(localized: .TDCPreferencesController.defaultIdentityNickname)
	}

	static var note: String {
		String(localized: .TDCPreferencesController.defaultIdentityNote)
	}

	static var optional: String {
		String(localized: .TDCPreferencesController.defaultIdentityOptional)
	}

	static var realname: String {
		String(localized: .TDCPreferencesController.defaultIdentityRealname)
	}

	static var username: String {
		String(localized: .TDCPreferencesController.defaultIdentityUsername)
	}
}

nonisolated enum PreferencesIRCopStrings { // nonisolated: value
	static var glineLabel: String {
		String(localized: .TDCPreferencesController.ircopGlineLabel)
	}

	static var includesBanLength: String {
		String(localized: .TDCPreferencesController.ircopIncludesBanLength)
	}

	static var killLabel: String {
		String(localized: .TDCPreferencesController.ircopKillLabel)
	}

	static var shunLabel: String {
		String(localized: .TDCPreferencesController.ircopShunLabel)
	}
}
