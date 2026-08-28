/* *********************************************************************
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
 *********************************************************************** */

import Foundation
import GlasstualPluginKit

@MainActor
extension IRCClient {
	@objc(joinKickedChannel:)
	func joinKickedChannel(_ channel: IRCChannel) {
		join(channel)
	}

	@objc(joinChannel:)
	func join(_ channel: IRCChannel) {
		join(channel, password: nil)
	}

	@objc(joinUnlistedChannel:)
	func joinUnlistedChannel(_ channelName: String) {
		joinUnlistedChannel(channelName, password: nil)
	}

	@objc(joinChannel:password:)
	func join(_ channel: IRCChannel, password: String?) {
		guard channel.isChannel, channel.isActive == false else { return }
		channel.status = .joining
		forceJoinChannel(channel.name, password: password ?? channel.secretKey)
	}

	@objc(joinUnlistedChannel:password:)
	func joinUnlistedChannel(_ channelName: String, password: String?) {
		guard stringIsChannelName(channelName) else {
			if channelName == "0" {
				forceJoinChannel(channelName, password: password)
			}
			return
		}
		if let channel = findChannel(channelName) {
			join(channel, password: password)
		} else {
			forceJoinChannel(channelName, password: password)
		}
	}

	@objc(forceJoinChannel:password:)
	func forceJoinChannel(_ channelName: String, password: String?) {
		guard isLoggedIn, channelName.isEmpty == false else { return }
		warnIfJoiningChannelsExceedsLimit([channelName])
		var arguments = [channelName]
		if let password, password.isEmpty == false {
			arguments.append(password)
		}
		send("JOIN", arguments: arguments)
	}

	@objc(joinChannels:)
	func joinChannels(_ channels: [IRCChannel]) {
		guard isLoggedIn, channels.isEmpty == false else { return }
		let pending = channels.filter { $0.isChannel && $0.isActive == false }
		guard pending.isEmpty == false else { return }
		warnIfJoiningChannelsExceedsLimit(pending.map(\.name))
		for channel in pending {
			channel.status = .joining
		}

		// One JOIN per line that fits the protocol budget; a single line with
		// every autojoin channel on it is truncated by the server.
		let batches = IRCJoinBatching.batches(
			for: pending.map { IRCJoinBatching.Target(name: $0.name, key: $0.secretKey) },
			maximumLineLength: Int(supportInfo.maximumLineLength),
			maximumTargets: supportInfo.maximumTargets(forCommand: "JOIN"),
			channelLimits: supportInfo.channelLimits
		)
		for batch in batches {
			var arguments = [batch.channels.joined(separator: ",")]
			if batch.keys.isEmpty == false {
				arguments.append(batch.keys.joined(separator: ","))
			}
			send("JOIN", arguments: arguments)
		}
	}

	@objc(warnIfJoiningChannelsExceedsLimit:)
	func warnIfJoiningChannelsExceedsLimit(_ channelNames: [String]) {
		guard supportInfo.channelLimits.isEmpty == false else { return }

		var joinedCountByPrefix: [Character: UInt] = [:]
		for channel in channelList where channel.isChannel && channel.isActive {
			guard let prefix = channel.name.first else { continue }
			joinedCountByPrefix[prefix, default: 0] += 1
		}

		var warnedPrefixes: Set<Character> = []
		for channelName in channelNames where stringIsChannelName(channelName) {
			if findChannel(channelName)?.isActive == true {
				continue
			}
			guard let prefix = channelName.first else { continue }
			let limit = supportInfo.channelLimit(forChannelNamed: channelName)
			guard limit > 0 else { continue }

			let joinedCount = joinedCountByPrefix[prefix, default: 0] + 1
			joinedCountByPrefix[prefix] = joinedCount
			guard joinedCount > limit, warnedPrefixes.insert(prefix).inserted else { continue }
			printDebugInformation(
				toConsole: IRCISupportStrings.channelLimitExceeded(
					channelName: channelName,
					limit: limit,
					prefix: String(prefix)
				)
			)
		}
	}

	@objc(joinUnlistedChannelsWithStringAndSelectBestMatch:)
	func joinUnlistedChannelsAndSelectBestMatch(_ channelNames: String) {
		joinUnlistedChannelsAndSelectBestMatch(channelNames, passwords: nil)
	}

	@objc(joinUnlistedChannelsWithStringAndSelectBestMatch:passwords:)
	func joinUnlistedChannelsAndSelectBestMatch(_ channelNames: String, passwords: String?) {
		guard channelNames.isEmpty == false else { return }
		joinUnlistedChannelsAndSelectBestMatch(
			channelNames.components(separatedBy: ","),
			passwords: passwords
		)
	}

	@objc(joinUnlistedChannelsAndSelectBestMatch:)
	func joinUnlistedChannelsAndSelectBestMatch(_ channelNames: [String]) {
		joinUnlistedChannelsAndSelectBestMatch(channelNames, passwords: nil)
	}

	@objc(joinUnlistedChannelsAndSelectBestMatch:passwords:)
	func joinUnlistedChannelsAndSelectBestMatch(_ channelNames: [String], passwords: String?) {
		guard isLoggedIn, channelNames.isEmpty == false else { return }

		let selection = channelNames.lazy
			.filter { self.stringIsChannelName($0) }
			.compactMap { self.findChannelOrCreate($0) }
			.first
		let shouldJoin = (selection.map { $0.isActive == false } ?? true) || channelNames.count > 1
		if shouldJoin {
			warnIfJoiningChannelsExceedsLimit(channelNames)
			var arguments = [channelNames.joined(separator: ",")]
			if let passwords, passwords.isEmpty == false {
				arguments.append(passwords)
			}
			send("JOIN", arguments: arguments)
		}

		guard let selection,
		      let treeItem = (selection as AnyObject) as? IRCTreeItem
		else { return }
		output?.selectItem(treeItem)
	}
}
