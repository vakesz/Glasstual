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

extension Client {
	@MainActor
	func selectFirstChannelInChannelList() {
		guard let firstChannel = channelList.first else { return }

		output?.select(firstChannel)
	}

	/// Channels are kept ahead of queries, so a channel goes in front of the
	/// first query and everything else goes on the end.
	func add(_ channel: Channel) {
		guard channelListPrivate.contains(channel) == false else { return }

		let index = channel.isChannel
			? channelListPrivate.firstIndex { $0.isChannel == false } ?? channelListPrivate.endIndex
			: channelListPrivate.endIndex

		channelListPrivate.insert(channel, at: index)
		updateStoredChannelList()
	}

	func remove(_ channel: Channel) {
		channelListPrivate.removeAll { $0 === channel }
		updateStoredChannelList()
	}

	func index(of channel: Channel) -> UInt {
		guard let index = channelListPrivate.firstIndex(of: channel) else {
			return UInt(NSNotFound)
		}
		return UInt(index)
	}

	var channelCount: UInt {
		UInt(channelListPrivate.count)
	}

	var channelList: [Channel] {
		get { channelListPrivate }
		set {
			channelListPrivate = newValue
			updateStoredChannelList()
		}
	}

	func channel(at index: UInt) -> Channel? {
		guard index < channelListPrivate.count else { return nil }
		return channelListPrivate[Int(index)]
	}
}

extension Client {
	func findChannel(_ name: String, in channelList: [Channel]) -> Channel? {
		let foldedName = casefoldNickname(name)
		return channelList.first { casefoldNickname($0.name) == foldedName }
	}

	func findChannel(_ name: String) -> Channel? {
		let foldedName = casefoldNickname(name)

		// A hit is only trusted while it still folds to the name asked for: a
		// rename or a new CASEMAPPING can invalidate the mirror between builds.
		if let channel = channelIndex[foldedName: foldedName], casefoldNickname(channel.name) == foldedName {
			return channel
		}

		return channelList.first { casefoldNickname($0.name) == foldedName }
	}

	/// Rebuilds the casefolded mirror of the channel list.
	func rebuildChannelIndex() {
		channelIndex.rebuild(from: channelList, by: casefoldNickname, naming: \.name)
	}

	func findChannelOrCreate(_ name: String, isPrivateMessage: Bool = false) -> Channel? {
		findChannelOrCreate(name, as: isPrivateMessage ? .privateMessage : .channel)
	}

	func findChannelOrCreate(_ name: String, isUtility: Bool) -> Channel? {
		findChannelOrCreate(name, as: isUtility ? .utility : .channel)
	}

	func findChannelOrCreate(_ name: String, as type: ChannelType) -> Channel? {
		if let channel = findChannel(name) {
			return channel
		}

		guard let clientDirectory else { return nil }

		if type == .channel {
			let channel = clientDirectory.createChannel(
				with: ChannelConfig.seed(withName: name),
				on: self,
				add: true,
				adjust: true,
				reload: true
			)
			clientDirectory.savePeriodically()
			return channel
		}

		return clientDirectory.createPrivateMessage(name, on: self, as: type)
	}
}

@MainActor
extension Client {
	private func channelIsSelectedInKeyWindow(_ channel: Channel, output: any ClientOutput) -> Bool {
		output.isKeyWindow && output.isItemSelected(channel)
	}

	func setHighlightState(for channel: Channel) {
		guard let output else { return }
		guard channelIsSelectedInKeyWindow(channel, output: output) == false else { return }

		channel.nicknameHighlightCount += 1
		DockIcon.updateDockIcon()
		output.reloadChatItem(channel)
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
