// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated extension SettingsKeys {
	/// What is shown in a conversation, and how incoming text is treated.
	enum Messages {
		private static let group = "Messages -> "

		static let showDateChanges = SettingsKey(group + "Show Date Changes", default: true)
		static let showInlineMedia = SettingsKey(group + "Show Inline Media", default: false)
		static let showJoinLeave = SettingsKey(group + "Show Join Leave", default: true)
		static let autoAddUnreadMarker = SettingsKey(group + "Auto Add Scrollback Mark", default: true)
		static let copyOnSelect = SettingsKey(group + "Copy On Select", default: false)
		static let removeAllFormatting = SettingsKey(group + "Remove All Formatting", default: false)
		static let rightToLeftFormatting = SettingsKey(group + "Right To Left Formatting", default: false)
		static let replyToCTCPRequests = SettingsKey(group + "Reply To CTCP Requests", default: true)

		/// Whether a CTCP `VERSION` reply names the version number as well as
		/// the application. Off, the reply says which client this is and
		/// nothing that narrows down which release, and so which known flaws.
		static let ctcpRevealsClientVersion = SettingsKey(
			group + "CTCP Reveals Client Version",
			default: false
		)

		/// What a CTCP `USERINFO` query is answered with. Empty by default: the
		/// real name is shown to the server already, and any peer may ask.
		static let ctcpUserInfoReply = SettingsKey(
			group + "CTCP User Info Reply",
			default: "",
			validation: { $0.count <= 400 }
		)

		static let detectHighlightSpam = SettingsKey(group + "Detect Highlight Spam", default: true)
		static let filterUnicodeTextSpam = SettingsKey(group + "Filter Unicode Text Spam", default: false)
		static let openBrowserInBackground = SettingsKey(
			group + "Open Browser In Background",
			default: false
		)

		/// Whether the names, pictures and colours people set on the server
		/// (`draft/metadata-2`) are asked for and shown. Off, nothing is
		/// subscribed to.
		static let showServerProfiles = SettingsKey(group + "Show Server Profiles", default: true)

		static let disableNicknameColorHashing = SettingsKey(
			group + "Disable Nickname Color Hashing",
			default: false
		)

		static let nicknameColorStyleOverrides = UntypedSettingsKey(
			group + "Nickname Color Overrides", validation: SettingsValueRepair.nicknameColors
		)

		static let all: [any AnySettingsKey] = [
			showDateChanges, showInlineMedia, showJoinLeave, autoAddUnreadMarker, copyOnSelect,
			removeAllFormatting, rightToLeftFormatting, replyToCTCPRequests, detectHighlightSpam,
			filterUnicodeTextSpam, openBrowserInBackground, disableNicknameColorHashing,
			nicknameColorStyleOverrides, ctcpRevealsClientVersion, ctcpUserInfoReply, showServerProfiles,
		]
	}
}
