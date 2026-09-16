/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation

nonisolated extension Preferences { // nonisolated: value
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
