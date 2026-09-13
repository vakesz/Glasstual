/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
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

@MainActor
public extension IRCClient {
	private func channelIsSelectedInKeyWindow(_ channel: Channel, output: any ClientOutput) -> Bool {
		output.isKeyWindow && output.isItemSelected(channel)
	}

	func setHighlightState(for channel: Channel) {
		guard let output else { return }
		guard channelIsSelectedInKeyWindow(channel, output: output) == false else { return }

		channel.nicknameHighlightCount += 1
		DockIcon.updateDockIcon()
		output.reloadTreeItem(channel)
	}

	/** Raises the unread counts by `count`, which defaults to the single line
	 that is raising them.

	 A larger count belongs to the one caller that learns about several unread
	 lines at once: a read marker the server sends names a point, and everything
	 a person said after it is unread. */
	func setUnreadState(for channel: Channel, isHighlight: Bool = false, count: Int = 1) {
		assert(count >= 1, "An unread badge counts at least one line")

		let count = max(1, count)

		guard let output else { return }
		guard channelIsSelectedInKeyWindow(channel, output: output) == false else { return }

		/* A query always counts on the dock badge; a channel does so only when
		 the user asked for public messages to be counted there. */
		if channel.isChannel == false || environment.preferences.displayPublicMessageCountOnDockBadge {
			channel.dockUnreadCount += count
			DockIcon.updateDockIcon()
		}

		channel.treeUnreadCount += count

		if isHighlight || channel.config.showTreeBadgeCount {
			output.refreshMessageCount(for: channel)
		}
	}
}
