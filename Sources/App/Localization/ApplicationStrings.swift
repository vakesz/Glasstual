// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Semantic access to the application-wide strings in the `Application` table.
nonisolated enum ApplicationStrings {
	static var unknownValue: String {
		String(localized: .Application.unknownValuePlaceholder)
	}

	static var defaultQuitMessage: String {
		String(localized: .Application.glasstualIrcClient)
	}

	static var untitledConnection: String {
		String(localized: .Application.untitledConnection)
	}

	static var sleepQuitMessage: String {
		String(localized: .Application.myMacHasGoneToSleep)
	}

	static var closeQuery: String {
		String(localized: .Application.closeQuery)
	}

	static var closeWindow: String {
		String(localized: .Application.closeWindow)
	}

	static var leaveChannel: String {
		String(localized: .Application.leaveChannel)
	}

	static var quitApplication: String {
		String(localized: .Application.quitGlasstual)
	}

	static func disconnect(from networkName: String) -> String {
		String(localized: .Application.disconnectMenuTitle(networkName))
	}

	static var lookUpInDictionary: String {
		String(localized: .Application.lookUpInDictionary)
	}

	static func lookUpInDictionary(_ selection: String) -> String {
		String(localized: .Application.lookUp(selection))
	}

	static func search(with providerName: String) -> String {
		String(localized: .Application.searchProviderMenuTitle(providerName))
	}

	static var requiredField: String {
		String(localized: .Application.fillOutThisField)
	}

	static var invalidRegularExpression: String {
		String(localized: .Application.invalidRegularExpression)
	}

	static var ircColors: String {
		String(localized: .Application.ircColors)
	}

	static func ircColor(at index: Int) -> String {
		String(localized: .Application.ircColorListEntry(index))
	}

	static func duplicatedName(_ name: String) -> String {
		String(localized: .Application.duplicatedConnectionName(name))
	}
}
