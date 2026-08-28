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

struct IRCWHOFlags: Equatable {
	let isAway: Bool
	let isIRCop: Bool
	let isBot: Bool
	let userModes: String

	static func parse(
		_ flags: String,
		monitorAwayStatus: Bool,
		botFlagSupported: Bool,
		modeForPrefix: (String) -> String?
	) -> IRCWHOFlags {
		var isAway = false
		var isIRCop = false
		var isBot = false
		var modes = ""
		for character in flags.map(String.init) {
			switch character {
			case "G": isAway = monitorAwayStatus
			case "*": isIRCop = true
			case "B" where botFlagSupported: isBot = true
			default:
				if let mode = modeForPrefix(character) {
					modes += mode
				}
			}
		}
		return IRCWHOFlags(isAway: isAway, isIRCop: isIRCop, isBot: isBot, userModes: modes)
	}
}

struct IRCWHOReply {
	let nickname: String
	let username: String
	let address: String
	let flags: String
	let realName: String
	let account: String?
	let updatesAccount: Bool
}

@MainActor
extension IRCClient {
	func receiveWhoReply(in channel: IRCChannel, reply: IRCWHOReply) {
		let parsedFlags = IRCWHOFlags.parse(
			reply.flags,
			monitorAwayStatus: monitorAwayStatus,
			botFlagSupported: supportInfo.botModeSymbol != nil,
			modeForPrefix: supportInfo.modeSymbol(forUserPrefix:)
		)

		let existingUser = findUser(reply.nickname)
		let mutableUser = mutableCopyOfUser(withNickname: reply.nickname)
		mutableUser.nickname = reply.nickname
		mutableUser.username = reply.username
		mutableUser.address = reply.address
		mutableUser.isAway = parsedFlags.isAway
		mutableUser.isIRCop = parsedFlags.isIRCop
		if supportInfo.botModeSymbol != nil {
			mutableUser.isBot = parsedFlags.isBot
		}
		mutableUser.realName = reply.realName
		if reply.updatesAccount {
			mutableUser.account = reply.account
		}

		let userChanged = existingUser.map { !$0.isEqual(mutableUser) } ?? false
		let finalUser: User
		if existingUser == nil || userChanged {
			finalUser = addAndReturn(mutableUser)
		} else if let existingUser {
			finalUser = existingUser
		} else {
			preconditionFailure("An unchanged WHO user must already exist")
		}
		if let member = existingUser?.userAssociated(with: channel) {
			if userChanged {
				let staffStatusChanged = existingUser?.isIRCop != finalUser.isIRCop
				if staffStatusChanged {
					channel.memberInfo?.replaceMember(
						member,
						with: member,
						resort: true,
						replaceInAllChannels: TextualPreferences.memberListSortFavorsServerStaff()
					)
				} else if existingUser?.isAway != finalUser.isAway {
					AppController.shared.mainWindow?.updateDrawingForUserInUserList(finalUser)
				}
			}
		} else {
			let member = ChannelUserMutable(user: finalUser)
			member.modes = parsedFlags.userModes
			channel.memberInfo?.addMember(member)
		}

		if nicknameIsMyself(reply.nickname) {
			userHostmask = "\(reply.nickname)!\(reply.username)@\(reply.address)"
		}
	}
}
