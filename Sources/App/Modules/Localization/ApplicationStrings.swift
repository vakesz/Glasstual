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
		String(localized: .BasicLanguage.vblXi)
	}

	static var defaultQuitMessage: String {
		String(localized: .BasicLanguage._1Dd0F)
	}

	static var untitledConnection: String {
		String(localized: .BasicLanguage.vfuC0)
	}

	static var sleepQuitMessage: String {
		String(localized: .BasicLanguage.qi75Y)
	}

	static var closeQuery: String {
		String(localized: .BasicLanguage.hriL0)
	}

	static var closeWindow: String {
		String(localized: .BasicLanguage._1F6Bg)
	}

	static var leaveChannel: String {
		String(localized: .BasicLanguage._5Td3F)
	}

	static var quitApplication: String {
		String(localized: .BasicLanguage.x97Ro)
	}

	static func disconnect(from networkName: String) -> String {
		String(localized: .BasicLanguage.w3AJe(networkName))
	}

	static var copyLogAsHTML: String {
		String(localized: .BasicLanguage._6CwNi)
	}

	static var forceReloadStyle: String {
		String(localized: .BasicLanguage.ngdMs)
	}

	static var openWebInspector: String {
		String(localized: .BasicLanguage.tfjM9)
	}

	static var lookUpInDictionary: String {
		String(localized: .BasicLanguage.o5L4S)
	}

	static func lookUpInDictionary(_ selection: String) -> String {
		String(localized: .BasicLanguage.zxsYy(selection))
	}

	static func search(with providerName: String) -> String {
		String(localized: .BasicLanguage._1LlH9(providerName))
	}

	static var noActionsAvailable: String {
		String(localized: .BasicLanguage._7KcMo)
	}

	static var builtInTheme: String {
		String(localized: .BasicLanguage._7LmBq)
	}

	static var customTheme: String {
		String(localized: .BasicLanguage.bm24P)
	}

	static var requiredField: String {
		String(localized: .BasicLanguage.fo81H)
	}

	static var ircColors: String {
		String(localized: .BasicLanguage.iwpCg)
	}

	static func ircColor(at index: Int) -> String {
		String(localized: .BasicLanguage.hamVk(index))
	}

	static func relativeTime(_ duration: String) -> String {
		String(localized: .BasicLanguage._4UmW4(duration))
	}
}
