// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated extension SettingsKeys {
	/// Connecting, joining, and the behaviour of the connection itself.
	enum Connection {
		private static let group = "Connection -> "

		static let autojoinOnInvite = SettingsKey(group + "Autojoin On Invite", default: false)

		static let autojoinDelayAfterIdentification = SettingsKey(
			group + "Autojoin Delay After Identification",
			default: 0.0,
			validation: { $0.isFinite && $0 >= 0 && $0 < Double(Int64.max) / 1_000_000_000 }
		)

		static let disconnectOnSleep = SettingsKey(group + "Disconnect On Sleep", default: true)

		/// Holds off idle system sleep while a server is logged in.
		static let preventSleepWhileConnected = SettingsKey(
			group + "Prevent Sleep While Connected",
			default: false
		)
		static let awayOnScreenSleep = SettingsKey(group + "Away On Screen Sleep", default: false)
		/// Marks the user away once the Mac has had no input for `idleAwayMinutes`.
		static let awayOnIdle = SettingsKey(group + "Away On Idle", default: false)
		static let idleAwayMinutes = SettingsKey(
			group + "Idle Away Minutes",
			default: IdleAwayDecision.defaultMinutes,
			validation: {
				$0.isFinite && $0 >= IdleAwayDecision.minimumMinutes && $0 <= IdleAwayDecision.maximumMinutes
			}
		)
		/// The away comment while idle. Empty uses the localized default.
		static let idleAwayMessage = SettingsKey(group + "Idle Away Message", default: "")
		static let displayServerMOTD = SettingsKey(group + "Display Server MOTD", default: true)
		static let rejoinOnKick = SettingsKey(group + "Rejoin On Kick", default: false)
		static let sendTypingNotifications = SettingsKey(group + "Send Typing Notifications", default: true)
		static let displayTypingNotifications = SettingsKey(
			group + "Display Typing Notifications",
			default: true
		)
		static let confirmQuit = SettingsKey(group + "Confirm Quit", default: true)
		static let requestChatHistory = SettingsKey(group + "Request Chat History", default: true)
		static let synchronizeReadMarkers = SettingsKey(group + "Synchronize Read Markers", default: true)

		static let echoMessageCapability = SettingsKey(
			group + "Echo Message Capability",
			default: false
		)

		/** The IRCv3 capabilities the user switched off, by their wire name.

		 Absence is the enabled state, so a capability added to the registry
		 later starts enabled, and a name left behind by a capability that was
		 removed does nothing. */
		static let disabledCapabilities = SettingsKey(
			group + "Disabled Capabilities",
			default: [String]()
		)

		static let stsPolicies = UntypedSettingsKey(
			group + "STS Policies",
			default: .emptyDictionary,
			traits: .excludedFromExport
		)

		static let all: [any AnySettingsKey] = [
			autojoinOnInvite, autojoinDelayAfterIdentification, disconnectOnSleep, awayOnScreenSleep,
			awayOnIdle, idleAwayMinutes, idleAwayMessage,
			displayServerMOTD, rejoinOnKick, sendTypingNotifications, displayTypingNotifications,
			confirmQuit, requestChatHistory, synchronizeReadMarkers, echoMessageCapability,
			disabledCapabilities, stsPolicies, preventSleepWhileConnected,
		]
	}
}
