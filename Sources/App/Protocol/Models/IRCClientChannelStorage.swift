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

enum IRCClientChannelStoragePolicy {
	static func insertionIndex(isChannel: Bool, existingKinds: [Bool]) -> Int {
		guard isChannel else { return existingKinds.endIndex }
		return existingKinds.firstIndex(of: false) ?? existingKinds.endIndex
	}
}

public extension IRCClient {
	@MainActor
	func selectFirstChannelInChannelList() {
		guard let firstChannel = channelList.first else { return }

		output?.selectItem(firstChannel)
	}

	func add(_ channel: IRCChannel) {
		guard channelListPrivate.contains(channel) == false else { return }
		let index = IRCClientChannelStoragePolicy.insertionIndex(
			isChannel: channel.isChannel,
			existingKinds: channelListPrivate.map(\.isChannel)
		)
		channelListPrivate.insert(channel, at: index)
		updateStoredChannelList()
	}

	func remove(_ channel: IRCChannel) {
		channelListPrivate.removeAll { $0 === channel }
		updateStoredChannelList()
	}

	func index(of channel: IRCChannel) -> UInt {
		guard let index = channelListPrivate.firstIndex(of: channel) else {
			return UInt(NSNotFound)
		}
		return UInt(index)
	}

	var channelCount: UInt {
		UInt(channelListPrivate.count)
	}

	var channelList: [IRCChannel] {
		get { channelListPrivate }
		set {
			channelListPrivate = newValue
			updateStoredChannelList()
		}
	}

	func channel(at index: UInt) -> IRCChannel? {
		guard index < channelListPrivate.count else { return nil }
		return channelListPrivate[Int(index)]
	}
}
