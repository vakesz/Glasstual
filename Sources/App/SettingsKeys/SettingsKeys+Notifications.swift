// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated extension SettingsKeys {
	/** What the person is told about, and how.

	 Four switches, the way Messages has four: is a conversation muted, does a
	 mention reach me, does it make a sound, and does it count on the Dock. The
	 per-conversation half is `ConversationConfig.pushNotifications`; the rest is
	 here. */
	enum Notifications {
		private static let group = "Notifications -> "

		/// Whether a mention or a private message raises a notification.
		static let notifyAboutMentions = SettingsKey(group + "Notify About Mentions", default: true)

		static let soundIsMuted = SettingsKey(
			group + "Sound Is Muted",
			default: false,
			traits: .unregistered
		)

		static let postWhileInFocus = SettingsKey(group + "Post While In Focus", default: true)
		static let displayDockBadge = SettingsKey(group + "Display Dock Badge", default: true)

		static let publicMessageCountOnDockBadge = SettingsKey(
			group + "Public Message Count On Dock Badge",
			default: false
		)

		static let all: [any AnySettingsKey] = [
			notifyAboutMentions, soundIsMuted, postWhileInFocus, displayDockBadge,
			publicMessageCountOnDockBadge,
		]
	}
}
