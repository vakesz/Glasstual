// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated extension SettingsKeys {
	/// Command defaults and the "apply to all connections" switches.
	enum Commands {
		private static let group = "Commands -> "

		static let amsgAllConnections = SettingsKey(group + "Amsg All Connections", default: false)
		static let awayAllConnections = SettingsKey(group + "Away All Connections", default: false)
		static let clearAllConnections = SettingsKey(group + "Clear All Connections", default: true)
		static let nickAllConnections = SettingsKey(group + "Nick All Connections", default: false)

		static let kickMessage = SettingsKey(
			group + "Kick Message",
			default: "Your behavior is not conducive to the desired environment."
		)

		static let irCopGlineMessage = SettingsKey(
			group + "IRCop G:Line Message",
			default: "35d Your behavior is not conducive to the desired environment."
		)

		static let irCopKillMessage = SettingsKey(
			group + "IRCop Kill Message",
			default: "Your behavior is not conducive to the desired environment."
		)

		static let irCopShunMessage = SettingsKey(group + "IRCop Shun Message", default: "1d Shunned.")

		static let banFormat = SettingsKey(group + "Ban Format", default: HostmaskBanFormat.whainn)

		static let noticeDestination = SettingsKey(
			group + "Notice Destination",
			default: NoticeSendLocation.serverConsole
		)

		static let giveFocusOnMessageCommand = SettingsKey(
			group + "Give Focus On Message Command",
			default: true
		)

		static let developerMode = SettingsKey(group + "Developer Mode", default: false)

		static let all: [any AnySettingsKey] = [
			amsgAllConnections, awayAllConnections, clearAllConnections, nickAllConnections,
			kickMessage, irCopGlineMessage, irCopKillMessage, irCopShunMessage, banFormat,
			noticeDestination, giveFocusOnMessageCommand, developerMode,
		]
	}
}

/** Where a notice that is not addressed to a conversation is shown.

 Stored as the integer it declares; a stored value with no matching case falls
 back to the key's declared default. */
enum NoticeSendLocation: UInt, Sendable {
	case serverConsole
	case selectedConversation
	case directConversation
}

extension NoticeSendLocation: SettingEnum {}

/// Which parts of a hostmask a generated ban covers.
enum HostmaskBanFormat: UInt, Sendable {
	case whnin
	case whainn
	case whanni
	case exact
}

extension HostmaskBanFormat: SettingEnum {}
