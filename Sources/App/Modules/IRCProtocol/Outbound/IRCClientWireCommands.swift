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

private let whoxRequestToken = "152"

@MainActor
public extension IRCClient {
	@objc(changeNickname:)
	func changeNickname(_ nickname: String) {
		guard isConnected, nickname.isEmpty == false else { return }
		send("NICK", arguments: [nickname])
	}

	@objc(partUnlistedChannel:)
	func partUnlistedChannel(_ channelName: String) {
		partUnlistedChannel(channelName, withComment: nil)
	}

	@objc(partChannel:)
	func part(_ channel: IRCChannel) {
		part(channel, withComment: nil)
	}

	@objc(partUnlistedChannel:withComment:)
	func partUnlistedChannel(_ channelName: String, withComment comment: String?) {
		guard stringIsChannelName(channelName), let channel = findChannel(channelName) else { return }
		part(channel, withComment: comment)
	}

	@objc(partChannel:withComment:)
	func part(_ channel: IRCChannel, withComment comment: String?) {
		guard isLoggedIn, channel.isChannel, channel.isActive else { return }
		send("PART", arguments: [channel.name, comment ?? config.normalLeavingComment])
	}

	@objc(sendWhoToChannel:)
	func sendWho(to channel: IRCChannel) {
		sendWho(to: channel, hideResponse: false)
	}

	@objc(sendWhoToChannel:hideResponse:)
	func sendWho(to channel: IRCChannel, hideResponse: Bool) {
		guard channel.isChannel else { return }
		sendWho(toChannelNamed: channel.name, hideResponse: hideResponse)
	}

	@objc(sendWhoToChannelNamed:)
	func sendWho(toChannelNamed channelName: String) {
		sendWho(toChannelNamed: channelName, hideResponse: false)
	}

	@objc(sendWhoToChannelNamed:hideResponse:)
	func sendWho(toChannelNamed channelName: String, hideResponse: Bool) {
		guard isLoggedIn, channelName.isEmpty == false else { return }
		if hideResponse {
			requestedCommands.recordWhoRequestOpened()
		} else {
			requestedCommands.recordWhoRequestOpenedAsVisible()
		}
		if supportInfo.whoxSupported {
			send("WHO", arguments: [channelName, "%tcuhnfar,\(whoxRequestToken)"])
		} else {
			send("WHO", arguments: [channelName])
		}
	}

	@objc(sendWhois:)
	func sendWhois(_ nickname: String) {
		guard isLoggedIn, nickname.isEmpty == false else { return }
		send("WHOIS", arguments: [nickname, nickname])
	}

	@objc(kick:inChannel:)
	func kick(_ nickname: String, in channel: IRCChannel) {
		guard isLoggedIn, channel.isChannel, channel.isActive, nickname.isEmpty == false else { return }
		send("KICK", arguments: [channel.name, nickname, TextualPreferences.defaultKickMessage()])
	}

	@objc(requestModesForChannel:)
	func requestModes(for channel: IRCChannel) {
		sendModes(nil, withParameters: nil, in: channel)
	}

	@objc(requestModesForChannelNamed:)
	func requestModes(forChannelNamed channelName: String) {
		sendModes(nil, withParameters: nil, inChannelNamed: channelName)
	}

	@objc(sendModes:withParameters:inChannel:)
	func sendModes(_ symbols: String?, withParameters parameters: [String]?, in channel: IRCChannel) {
		sendModes(symbols, withParameters: parameters, inChannelNamed: channel.name)
	}

	@objc(sendModes:withParametersString:inChannel:)
	func sendModes(_ symbols: String?, withParametersString parameters: String?, in channel: IRCChannel) {
		sendModes(symbols, withParametersString: parameters, inChannelNamed: channel.name)
	}

	@objc(sendModes:withParameters:inChannelNamed:)
	func sendModes(_ symbols: String?, withParameters parameters: [String]?, inChannelNamed channelName: String) {
		sendModes(symbols, withParametersString: parameters?.joined(separator: " "), inChannelNamed: channelName)
	}

	@objc(sendModes:withParametersString:inChannelNamed:)
	func sendModes(_ symbols: String?, withParametersString parameters: String?, inChannelNamed channelName: String) {
		guard isLoggedIn, channelName.isEmpty == false else { return }
		var arguments = [channelName]
		if let symbols {
			arguments.append(symbols)
		}
		if let parameters {
			arguments.append(parameters)
		}
		send("MODE", arguments: arguments)
	}

	@objc(sendPing:)
	func sendPing(_ token: String) {
		guard isConnected else { return }
		send("PING", arguments: [token])
	}

	@objc(sendPong:)
	func sendPong(_ token: String) {
		guard isConnected else { return }
		send("PONG", arguments: [token])
	}

	@objc(sendInviteTo:toJoinChannel:)
	func sendInvite(to nickname: String, toJoin channel: IRCChannel) {
		guard channel.isChannel else { return }
		sendInvite(to: nickname, toJoinChannelNamed: channel.name)
	}

	@objc(sendInviteTo:toJoinChannelNamed:)
	func sendInvite(to nickname: String, toJoinChannelNamed channelName: String) {
		guard nickname.isEmpty == false, channelName.isEmpty == false else { return }
		send("INVITE", arguments: [nickname, channelName])
	}

	@objc(requestTopicForChannel:)
	func requestTopic(for channel: IRCChannel) {
		sendTopic(to: nil, in: channel)
	}

	@objc(requestTopicForChannelNamed:)
	func requestTopic(forChannelNamed channelName: String) {
		sendTopic(to: nil, inChannelNamed: channelName)
	}

	@objc(sendTopicTo:inChannel:)
	func sendTopic(to topic: String?, in channel: IRCChannel) {
		guard channel.isChannel, channel.isActive else { return }
		sendTopic(to: topic, inChannelNamed: channel.name)
	}

	@objc(sendTopicTo:inChannelNamed:)
	func sendTopic(to topic: String?, inChannelNamed channelName: String) {
		guard isLoggedIn, channelName.isEmpty == false else { return }
		var arguments = [channelName]
		if let topic {
			arguments.append(topic)
		}
		send("TOPIC", arguments: arguments)
	}

	@objc(sendCapability:data:)
	func sendCapability(_ subcommand: String, data: String?) {
		guard isConnected else { return }
		var arguments = [subcommand]
		if let data {
			arguments.append(data)
		}
		send("CAP", arguments: arguments)
	}

	@objc(sendCapabilityAuthenticate:)
	func sendCapabilityAuthenticate(_ data: String) {
		guard isConnected, data.isEmpty == false else { return }
		send("AUTHENTICATE", arguments: [data])
	}

	@objc(sendIsonForNicknames:)
	func sendIson(forNicknames nicknames: [String]) {
		sendIson(forNicknames: nicknames, hideResponse: false)
	}

	@objc(sendIsonForNicknames:hideResponse:)
	func sendIson(forNicknames nicknames: [String], hideResponse: Bool) {
		guard isLoggedIn, nicknames.isEmpty == false else { return }
		if hideResponse {
			requestedCommands.recordIsonRequestOpened()
		} else {
			requestedCommands.recordIsonRequestOpenedAsVisible()
		}
		send("ISON", arguments: [nicknames.joined(separator: " ")])
	}

	@objc(requestChannelList)
	func requestChannelList() {
		requestChannelList(withArguments: nil)
	}

	@objc(requestChannelListWithArguments:)
	func requestChannelList(withArguments arguments: String?) {
		guard isLoggedIn else { return }
		send("LIST", arguments: arguments.map { [$0] } ?? [])
	}

	@objc(sendPassword:)
	func sendPassword(_ password: String) {
		guard isConnected, password.isEmpty == false else { return }
		send("PASS", arguments: [password])
	}

	@objc(modifyWatchListBy:nicknames:)
	func modifyWatchList(byAdding adding: Bool, nicknames: [String]) {
		for group in nicknames.chunked(maximumCount: 8) {
			modifyWatchListGroup(byAdding: adding, nicknames: group)
		}
	}

	private func modifyWatchListGroup(byAdding adding: Bool, nicknames: [String]) {
		guard isLoggedIn, nicknames.isEmpty == false else { return }
		if isCapabilityEnabled(.monitorCommand) {
			send("MONITOR", arguments: [adding ? "+" : "-", nicknames.joined(separator: ",")])
		} else if isCapabilityEnabled(.watchCommand) {
			let modifier = adding ? " +" : " -"
			send("WATCH", arguments: [modifier + nicknames.joined(separator: modifier)])
		}
	}
}

private extension Array {
	func chunked(maximumCount: Int) -> [[Element]] {
		guard maximumCount > 0 else { return [] }
		return stride(from: 0, to: count, by: maximumCount).map {
			Array(self[$0 ..< Swift.min($0 + maximumCount, count)])
		}
	}
}
