// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated extension Preferences {
	/** What the person is told about, and how.

	 Four switches, the way Messages has four: is a conversation muted, does a
	 mention reach me, does it make a sound, and does it count on the Dock. The
	 per-conversation half is `ChannelConfig.pushNotifications`; the rest is
	 here. The nineteen events times eight settings this replaced is why the
	 `NotificationType -> ` names below read the way they do: keeping them is
	 what carries a person's existing choice over. */
	enum Notifications {
		/** Whether a mention or a private message raises a notification.

		 Stored under the name the old per-event grid gave "Highlight ->
		 Enabled", so someone who switched highlights off keeps them off. */
		static let notifyAboutMentions = PreferenceKey(
			"NotificationType -> Highlight -> Enabled",
			default: true
		)

		static let soundIsMuted = PreferenceKey(
			"Notification Sound Is Muted",
			default: false,
			traits: .unregistered
		)

		static let postWhileInFocus = PreferenceKey("PostNotificationsWhileInFocus", default: true)
		static let displayDockBadge = PreferenceKey("DisplayDockBadges", default: true)

		static let publicMessageCountOnDockBadge = PreferenceKey(
			"DisplayPublicMessageCountInDockBadge",
			default: false
		)

		static let all: [any AnyPreferenceKey] = [
			notifyAboutMentions, soundIsMuted, postWhileInFocus, displayDockBadge,
			publicMessageCountOnDockBadge,
		]
	}
}
