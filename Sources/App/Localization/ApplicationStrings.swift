/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

/// Semantic access to application-wide strings retained in the legacy-compatible
/// `BasicLanguage` table.
nonisolated enum ApplicationStrings {
	static var unknownValue: String {
		String(localized: .BasicLanguage.unknownValuePlaceholder)
	}

	static var defaultQuitMessage: String {
		String(localized: .BasicLanguage.glasstualIrcClient)
	}

	static var untitledConnection: String {
		String(localized: .BasicLanguage.untitledConnection)
	}

	static var sleepQuitMessage: String {
		String(localized: .BasicLanguage.myMacHasGoneToSleep)
	}

	static var closeQuery: String {
		String(localized: .BasicLanguage.closeQuery)
	}

	static var closeWindow: String {
		String(localized: .BasicLanguage.closeWindow)
	}

	static var leaveChannel: String {
		String(localized: .BasicLanguage.leaveChannel)
	}

	static var quitApplication: String {
		String(localized: .BasicLanguage.quitGlasstual)
	}

	static func disconnect(from networkName: String) -> String {
		String(localized: .BasicLanguage.disconnectMenuTitle(networkName))
	}

	static var copyLogAsHTML: String {
		String(localized: .BasicLanguage.copyLogAsHtml)
	}

	static var forceReloadStyle: String {
		String(localized: .BasicLanguage.forceReloadStyle)
	}

	static var openWebInspector: String {
		String(localized: .BasicLanguage.openWebInspector)
	}

	static var lookUpInDictionary: String {
		String(localized: .BasicLanguage.lookUpInDictionary)
	}

	static func lookUpInDictionary(_ selection: String) -> String {
		String(localized: .BasicLanguage.lookUp(selection))
	}

	static func search(with providerName: String) -> String {
		String(localized: .BasicLanguage.searchProviderMenuTitle(providerName))
	}

	static var noActionsAvailable: String {
		String(localized: .BasicLanguage.noActionsAvailable)
	}

	static var builtInTheme: String {
		String(localized: .BasicLanguage.builtInThemeGroup)
	}

	static var customTheme: String {
		String(localized: .BasicLanguage.customThemeGroupTitle)
	}

	static var requiredField: String {
		String(localized: .BasicLanguage.fillOutThisField)
	}

	static var ircColors: String {
		String(localized: .BasicLanguage.ircColors)
	}

	static func ircColor(at index: Int) -> String {
		String(localized: .BasicLanguage.ircColorListEntry(index))
	}

	static func relativeTime(_ duration: String) -> String {
		String(localized: .BasicLanguage.relativeDateSuffixAgo(duration))
	}
}
