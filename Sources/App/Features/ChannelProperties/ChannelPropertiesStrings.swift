/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 *    Copyright (c) 2018 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

nonisolated enum ChannelPropertiesStrings { // nonisolated: value
	static var invalidChannelName: String {
		String(localized: .TDCChannelPropertiesSheet.pleaseEnterAProperlyFormattedChannel)
	}

	static var configurationChangedTitle: String {
		String(localized: .TDCChannelPropertiesSheet.thisChannelsConfigurationHasChangedDo)
	}

	static var unsavedChangesWarning: String {
		String(localized: .TDCChannelPropertiesSheet.youWillLooseUnsavedChangesIf)
	}
}
