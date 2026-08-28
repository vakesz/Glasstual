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

enum ChannelUnreadPolicy {
	static func incrementsDockUnreadCount(isChannel: Bool, displaysPublicMessageCount: Bool) -> Bool {
		isChannel == false || displaysPublicMessageCount
	}

	static func refreshesTreeBadge(isHighlight: Bool, showsTreeBadgeCount: Bool) -> Bool {
		isHighlight || showsTreeBadgeCount
	}
}

@MainActor
public extension IRCClient {
	private func channelIsSelectedInKeyWindow(_ channel: IRCChannel, output: any ClientOutput) -> Bool {
		output.windowIsKey && output.isItemSelectedInWindow(channel)
	}

	@objc(setHighlightStateForChannel:)
	func setHighlightState(for channel: IRCChannel) {
		guard let output else { return }
		guard channelIsSelectedInKeyWindow(channel, output: output) == false else { return }

		channel.nicknameHighlightCount += 1
		DockIcon.updateDockIcon()
		output.reloadTreeItem(channel)
	}

	@objc(setUnreadStateForChannel:)
	func setUnreadState(for channel: IRCChannel) {
		setUnreadState(for: channel, isHighlight: false)
	}

	@objc(setUnreadStateForChannel:isHighlight:)
	func setUnreadState(for channel: IRCChannel, isHighlight: Bool) {
		guard let output else { return }
		guard channelIsSelectedInKeyWindow(channel, output: output) == false else { return }

		if ChannelUnreadPolicy.incrementsDockUnreadCount(
			isChannel: channel.isChannel,
			displaysPublicMessageCount: environment.preferences.displayPublicMessageCountOnDockBadge
		) {
			channel.dockUnreadCount += 1
			DockIcon.updateDockIcon()
		}

		channel.treeUnreadCount += 1

		if ChannelUnreadPolicy.refreshesTreeBadge(
			isHighlight: isHighlight,
			showsTreeBadgeCount: channel.config.showTreeBadgeCount
		) {
			output.refreshMessageCount(for: channel)
		}
	}
}
