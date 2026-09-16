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
	static var heading: String {
		String(localized: .ChannelProperties.channelPropertiesWindowTitle)
	}

	static var sectionPickerLabel: String {
		String(localized: .ChannelProperties.sectionPickerLabel)
	}

	static var general: String {
		String(localized: .ChannelProperties.general)
	}

	static var defaults: String {
		String(localized: .ChannelProperties.defaults)
	}

	static var notifications: String {
		String(localized: .ChannelProperties.notifications)
	}

	static var joinOnConnect: String {
		String(localized: .ChannelProperties.joinOnConnect)
	}

	static var showNotifications: String {
		String(localized: .ChannelProperties.showNotificationsForChannel)
	}

	static var disableInlineMedia: String {
		String(localized: .ChannelProperties.disableInlineMedia)
	}

	static var showInlineMedia: String {
		String(localized: .ChannelProperties.showInlineMedia)
	}

	static var disableGeneralEvents: String {
		String(localized: .ChannelProperties.disableGeneralEventMessages)
	}

	static var showUnreadCount: String {
		String(localized: .ChannelProperties.showUnreadCountInChannelList)
	}

	static var disableHighlights: String {
		String(localized: .ChannelProperties.disableHighlights)
	}

	static var nameLabel: String {
		String(localized: .ChannelProperties.nameLabel)
	}

	static var passwordLabel: String {
		String(localized: .ChannelProperties.passwordLabel)
	}

	static var labelLabel: String {
		String(localized: .ChannelProperties.labelLabel)
	}

	static var channelNamePlaceholder: String {
		String(localized: .ChannelProperties.channelNamePlaceholder)
	}

	static var passwordHelp: String {
		String(localized: .ChannelProperties.passwordHelp)
	}

	static func secretKeyLength(_ length: Int, maximum: Int) -> String {
		String(localized: .ChannelProperties.secretKeyLength(length, maximum))
	}

	static func secretKeyTooLong(networkName: String, maximumLength: Int) -> String {
		String(localized: .ChannelProperties.secretKeyTooLong(networkName, maximumLength))
	}

	static var optional: String {
		String(localized: .ChannelProperties.optional)
	}

	static var labelHelp: String {
		String(localized: .ChannelProperties.labelHelp)
	}

	static var defaultsHelp: String {
		String(localized: .ChannelProperties.defaultsHelp)
	}

	static var topicLabel: String {
		String(localized: .ChannelProperties.topicLabel)
	}

	static var modesLabel: String {
		String(localized: .ChannelProperties.modesLabel)
	}

	static var invalidChannelName: String {
		String(localized: .ChannelProperties.pleaseEnterAProperlyFormattedChannel)
	}

	static var reloadButton: String {
		String(localized: .ChannelProperties.reloadButton)
	}

	static var configurationChangedTitle: String {
		String(localized: .ChannelProperties.thisChannelsConfigurationHasChangedDo)
	}

	static var unsavedChangesWarning: String {
		String(localized: .ChannelProperties.youWillLooseUnsavedChangesIf)
	}
}
