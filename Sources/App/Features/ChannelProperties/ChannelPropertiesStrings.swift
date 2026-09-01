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
	static var windowTitle: String {
		String(localized: .TDCChannelPropertiesSheet.channelPropertiesWindowTitle)
	}

	static var general: String {
		String(localized: .TDCChannelPropertiesSheet.general)
	}

	static var defaults: String {
		String(localized: .TDCChannelPropertiesSheet.defaults)
	}

	static var notifications: String {
		String(localized: .TDCChannelPropertiesSheet.notifications)
	}

	static var joinOnConnect: String {
		String(localized: .TDCChannelPropertiesSheet.joinOnConnect)
	}

	static var showNotifications: String {
		String(localized: .TDCChannelPropertiesSheet.showNotificationsForChannel)
	}

	static var disableInlineMedia: String {
		String(localized: .TDCChannelPropertiesSheet.disableInlineMedia)
	}

	static var showInlineMedia: String {
		String(localized: .TDCChannelPropertiesSheet.showInlineMedia)
	}

	static var disableGeneralEvents: String {
		String(localized: .TDCChannelPropertiesSheet.disableGeneralEventMessages)
	}

	static var showUnreadCount: String {
		String(localized: .TDCChannelPropertiesSheet.showUnreadCountInChannelList)
	}

	static var disableHighlights: String {
		String(localized: .TDCChannelPropertiesSheet.disableHighlights)
	}

	static var nameLabel: String {
		String(localized: .TDCChannelPropertiesSheet.nameLabel)
	}

	static var passwordLabel: String {
		String(localized: .TDCChannelPropertiesSheet.passwordLabel)
	}

	static var labelLabel: String {
		String(localized: .TDCChannelPropertiesSheet.labelLabel)
	}

	static var optional: String {
		String(localized: .TDCChannelPropertiesSheet.optional)
	}

	static var labelHelp: String {
		String(localized: .TDCChannelPropertiesSheet.labelHelp)
	}

	static var defaultsHelp: String {
		String(localized: .TDCChannelPropertiesSheet.defaultsHelp)
	}

	static var topicLabel: String {
		String(localized: .TDCChannelPropertiesSheet.topicLabel)
	}

	static var modesLabel: String {
		String(localized: .TDCChannelPropertiesSheet.modesLabel)
	}

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
