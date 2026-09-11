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
		var channels = existingUser.map { relations(of: $0).map(\.channel) } ?? []
		if !channels.contains(where: { $0 === channel }) {
			channels.append(channel)
		}
		var seenLists: Set<ObjectIdentifier> = []
		let memberLists = channels.compactMap(\.memberInfo).filter { seenLists.insert(ObjectIdentifier($0)).inserted }
		memberLists.forEach { $0.beginPresentationUpdates() }
		defer { memberLists.forEach { $0.endPresentationUpdates() } }
		var editedUser = draftUser(withNickname: reply.nickname)
		editedUser.nickname = reply.nickname
		editedUser.username = reply.username
		editedUser.address = reply.address
		editedUser.isAway = parsedFlags.isAway
		editedUser.isIRCop = parsedFlags.isIRCop
		if supportInfo.botModeSymbol != nil {
			editedUser.isBot = parsedFlags.isBot
		}
		editedUser.realName = reply.realName
		if reply.updatesAccount {
			editedUser.account = reply.account
		}

		let userChanged = existingUser.map { $0 != editedUser } ?? false
		let finalUser: User
		if existingUser == nil || userChanged {
			finalUser = addAndReturn(editedUser)
		} else if let existingUser {
			finalUser = existingUser
		} else {
			preconditionFailure("An unchanged WHO user must already exist")
		}
		if let existingUser, let member = userAssociated(existingUser, with: channel) {
			var editedMember = member
			editedMember.changeUser(to: finalUser)
			editedMember.prefixes = currentUserPrefixes
			editedMember.modes = membershipModes(
				reportedBy: parsedFlags.userModes,
				heldBy: member
			)

			let staffStatusChanged = existingUser.isIRCop != finalUser.isIRCop
			let favorsServerStaff = environment.preferences.memberListSortFavorsServerStaff
			/* A WHO sweep answers for every member of the channel, and a
			 re-sort per line sorted a two-thousand-member list two thousand
			 times over for a reply that usually changes nothing a sort reads.
			 The order is the conversation weight, the staff flag when it is
			 favoured, the channel rank and the nickname — and a WHO reply moves
			 only the middle two. */
			let orderChanged = editedMember.channelRank != member.channelRank
				|| (staffStatusChanged && favorsServerStaff)
			channel.memberInfo?.replaceMember(
				member,
				with: editedMember,
				resort: orderChanged,
				replaceInAllChannels: staffStatusChanged && favorsServerStaff
			)
		} else {
			var member = ChannelUser(user: finalUser, prefixes: currentUserPrefixes)
			member.modes = ChannelModeSymbolSet(letters: parsedFlags.userModes)
			channel.memberInfo?.addMember(member)
		}

		if nicknameIsMyself(reply.nickname) {
			userHostmask = "\(reply.nickname)!\(reply.username)@\(reply.address)"
		}
	}

	/** The membership modes a WHO reply leaves a member holding.

	 A WHO reply's flag field carries the person's channel status, and it used to
	 reach a member only on the way in: someone opped or devoiced while the client
	 was already in the channel kept whatever mark they had when they joined,
	 because the reply that says otherwise arrives for a member that already
	 exists.

	 How much of that field to believe depends on `multi-prefix`. With it the
	 server lists every prefix the person holds, so the reply is the whole answer
	 and replaces what the member had. Without it RFC 1459 6.2 gives one character
	 — the highest — so a reply that says `@` says nothing about the `+` the
	 member also holds, and the modes are merged instead of replaced. */
	private func membershipModes(reportedBy reported: String, heldBy member: ChannelUser) -> ChannelModeSymbolSet {
		let reportedModes = ChannelModeSymbolSet(letters: reported)

		guard isCapabilityEnabled(.multiPrefix) == false else {
			return reportedModes
		}

		var modes = member.modes
		let prefixRanks = supportInfo

		for mode in reportedModes {
			modes.insert(mode) { prefixRanks.rankForUserPrefix(withMode: String($0.character)) }
		}

		return modes
	}
}
