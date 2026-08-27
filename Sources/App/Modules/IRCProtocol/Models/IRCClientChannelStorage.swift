/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
import ObjectiveC

enum IRCClientChannelStoragePolicy {
	static func insertionIndex(isChannel: Bool, existingKinds: [Bool]) -> Int {
		guard isChannel else { return existingKinds.endIndex }
		return existingKinds.firstIndex(of: false) ?? existingKinds.endIndex
	}
}

public extension IRCClient {
	@objc(selectFirstChannelInChannelList)
	@MainActor
	func selectFirstChannelInChannelList() {
		guard let firstChannel = channelList.first,
		      let treeItem = (firstChannel as AnyObject) as? IRCTreeItem
		else { return }
		NSObject.applicationController().mainWindow.select(treeItem)
	}

	@objc(addChannel:)
	func add(_ channel: IRCChannel) {
		withChannelStorageLock {
			guard channelListPrivate.contains(channel) == false else { return }
			let index = IRCClientChannelStoragePolicy.insertionIndex(
				isChannel: channel.isChannel,
				existingKinds: channelStorageSnapshot.map(\.isChannel)
			)
			channelListPrivate.insert(channel, at: index)
			updateStoredChannelList()
		}
	}

	@objc(addChannel:atPosition:)
	func add(_ channel: IRCChannel, atPosition position: UInt) {
		withChannelStorageLock {
			guard channelListPrivate.contains(channel) == false else { return }
			channelListPrivate.insert(channel, at: Int(position))
			updateStoredChannelList()
		}
	}

	@objc(removeChannel:)
	func remove(_ channel: IRCChannel) {
		withChannelStorageLock {
			channelListPrivate.removeObject(identicalTo: channel)
			updateStoredChannelList()
		}
	}

	@objc(indexOfChannel:)
	func index(of channel: IRCChannel) -> UInt {
		withChannelStorageLock {
			let index = channelListPrivate.index(of: channel)
			return index == NSNotFound ? UInt(NSNotFound) : UInt(index)
		}
	}

	@objc var channelCount: UInt {
		withChannelStorageLock { UInt(channelListPrivate.count) }
	}

	@objc var channelList: [IRCChannel] {
		get { withChannelStorageLock { channelStorageSnapshot } }
		set {
			withChannelStorageLock {
				channelListPrivate.removeAllObjects()
				channelListPrivate.addObjects(from: newValue)
				updateStoredChannelList()
			}
		}
	}

	@objc(channelAtIndex:)
	func channel(at index: UInt) -> IRCChannel? {
		withChannelStorageLock { () -> IRCChannel? in
			guard index < channelListPrivate.count else { return nil }
			return channelListPrivate.object(at: Int(index)) as? IRCChannel
		}
	}

	private var channelStorageSnapshot: [IRCChannel] {
		channelListPrivate.compactMap { $0 as? IRCChannel }
	}

	private func withChannelStorageLock<Result>(_ operation: () -> Result) -> Result {
		objc_sync_enter(channelListPrivate)
		defer { objc_sync_exit(channelListPrivate) }
		return operation()
	}
}
