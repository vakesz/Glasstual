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
import GlasstualPluginKit

public extension IRCClient {
	@objc(findChannel:inList:)
	internal func findChannel(_ name: String, in channelList: [IRCChannel]) -> IRCChannel? {
		let foldedName = casefoldNickname(name)
		return channelList.first { casefoldNickname($0.name) == foldedName }
	}

	@objc(findChannel:)
	func findChannel(_ name: String) -> IRCChannel? {
		findChannel(name, in: channelList)
	}

	@objc(findChannelOrCreate:)
	func findChannelOrCreate(_ name: String) -> IRCChannel? {
		findChannelOrCreate(name, isPrivateMessage: false)
	}

	@objc(findChannelOrCreate:isPrivateMessage:)
	func findChannelOrCreate(_ name: String, isPrivateMessage: Bool) -> IRCChannel? {
		findChannelOrCreate(name, as: isPrivateMessage ? .privateMessage : .channel)
	}

	@objc(findChannelOrCreate:isUtility:)
	internal func findChannelOrCreate(_ name: String, isUtility: Bool) -> IRCChannel? {
		findChannelOrCreate(name, as: isUtility ? .utility : .channel)
	}

	internal func findChannelOrCreate(_ name: String, as type: ChannelType) -> IRCChannel? {
		if let channel = findChannel(name) {
			return channel
		}

		guard let world = NSObject.applicationController().world else { return nil }

		if type == .channel {
			let channel = world.createChannel(
				with: ChannelConfig.seed(withName: name),
				on: self,
				add: true,
				adjust: true,
				reload: true
			)
			world.savePeriodically()
			return channel
		}

		return world.createPrivateMessage(name, on: self, as: type)
	}

	@objc(findChannelOrCreate:asType:)
	internal func findChannelOrCreateFromObjectiveC(_ name: String, asType rawValue: UInt) -> IRCChannel? {
		guard let type = ChannelType(rawValue: rawValue) else { return nil }
		return findChannelOrCreate(name, as: type)
	}
}
