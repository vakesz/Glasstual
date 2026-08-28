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

enum IRCMembershipEventPolicy {
	static func shouldPrint(
		isLocalUser: Bool,
		showJoinLeave: Bool,
		channelIgnoresEvents: Bool,
		addressBookIgnoresEvents: Bool
	) -> Bool {
		isLocalUser || (showJoinLeave && !channelIgnoresEvents && !addressBookIgnoresEvents)
	}
}

@MainActor
public extension IRCClient {
	@objc(receiveJoin:)
	func receiveJoin(_ message: Message) {
		guard let channelName = message.params.first, let sender = message.senderNickname else { return }
		let printOnly = message.isPrintOnlyMessage
		let isLocalUser = nicknameIsMyself(sender)
		let channel: IRCChannel

		if !printOnly, isLocalUser {
			guard let found = findChannelOrCreate(channelName), !found.isActive, found.isChannel else { return }
			channel = found
			channel.activate()
			userHostmask = message.senderHostmask
			reloadTreeItem(channel)
		} else {
			guard let found = findChannel(channelName), found.isChannel else { return }
			channel = found
		}

		if !printOnly {
			let user = draftUser(withNickname: sender)
			user.nickname = sender
			user.username = message.senderUsername
			user.address = message.senderAddress
			if isCapabilityEnabled(.extendedJoin), message.params.count >= 3 {
				user.account = Self.account(fromWireValue: message.params[1])
				user.realName = message.params[2]
			}
			channel.memberInfo?.addMember(ChannelUser(user: addAndReturn(user)), checkForDuplicates: true)
		}

		if !printOnly, !isLocalUser, let query = findChannel(sender), !query.isActive {
			query.activate()
			print(IRCInboundStrings.Membership.joinedQuery(nickname: sender), by: nil, in: query, as: .join,
			      command: message.command, receivedAt: message.receivedAt)
			reloadTreeItem(query)
		}

		let ignore = isLocalUser ? nil : message.senderHostmask.flatMap(findAddressBookEntry(forHostmask:))
		if let ignore, !printOnly {
			updateTrackingStatus(for: ignore, message: message)
		}
		if postReceivedMessage(message, withText: nil, destinedFor: channel),
		   IRCMembershipEventPolicy.shouldPrint(
		   	isLocalUser: isLocalUser,
		   	showJoinLeave: environment.preferences.showJoinLeave,
		   	channelIgnoresEvents: channel.config.ignoreGeneralEventMessages,
		   	addressBookIgnoresEvents: ignore?.ignoreGeneralEventMessages ?? false
		   )
		{
			let address = (message.senderAddress ?? "").stringByAppendingIRCFormattingStop
			print(
				IRCInboundStrings.Membership.joinedChannel(
					nickname: sender,
					username: message.senderUsername ?? "",
					address: address
				),
				by: nil,
				in: channel, as: .join, command: message.command, receivedAt: message.receivedAt
			)
		}
		guard !printOnly else { return }
		updateTitle(channel)
		if isLocalUser {
			if config.sendWhoCommandRequestsToChannels, !isBrokenIRCdKnownAsTwitch {
				requestModes(for: channel)
			}
		} else {
			_ = notifyEvent(.userJoined, lineType: .join, target: channel, nickname: sender, text: nil)
		}
	}

	@objc(receivePart:)
	func receivePart(_ message: Message) {
		guard !(isQuitting && isConnectedToZNC),
		      let channelName = message.params.first,
		      let channel = findChannel(channelName), channel.isChannel,
		      let sender = message.senderNickname
		else { return }
		let comment = message.params.count > 1 ? message.params[1] : ""
		let isLocalUser = nicknameIsMyself(sender)
		if !message.isPrintOnlyMessage {
			if isLocalUser {
				channel.deactivate()
				reloadTreeItem(channel)
			} else {
				channel.removeMember(withNickname: sender)
				_ = notifyEvent(.userParted, lineType: .part, target: channel, nickname: sender, text: comment)
			}
		}
		let ignore = message.senderHostmask.flatMap(findAddressBookEntry(forHostmask:))
		if postReceivedMessage(message, withText: comment, destinedFor: channel),
		   IRCMembershipEventPolicy.shouldPrint(
		   	isLocalUser: isLocalUser,
		   	showJoinLeave: environment.preferences.showJoinLeave,
		   	channelIgnoresEvents: channel.config.ignoreGeneralEventMessages,
		   	addressBookIgnoresEvents: ignore?.ignoreGeneralEventMessages ?? false
		   )
		{
			var text = IRCInboundStrings.Membership.partedChannel(
				nickname: sender,
				username: message.senderUsername ?? "",
				address: (message.senderAddress ?? "").stringByAppendingIRCFormattingStop
			)
			if !comment.isEmpty {
				text = IRCInboundStrings.Membership.eventWithReason(
					text,
					reason: comment.stringByAppendingIRCFormattingStop
				)
			}
			print(text, by: nil, in: channel, as: .part, command: message.command, receivedAt: message.receivedAt)
		}
		if !message.isPrintOnlyMessage {
			updateTitle(channel)
		}
	}

	@objc(receiveKick:)
	func receiveKick(_ message: Message) {
		guard message.params.count > 1,
		      let channel = findChannel(message.params[0]), channel.isChannel,
		      let sender = message.senderNickname
		else { return }
		let target = message.params[1]
		let comment = message.params.count > 2 ? message.params[2] : ""
		let isLocalUser = nicknameIsMyself(target)
		if !message.isPrintOnlyMessage {
			if isLocalUser {
				channel.deactivate()
				reloadTreeItem(channel)
				_ = notifyEvent(.kick, lineType: .kick, target: channel, nickname: sender, text: comment)
				if environment.preferences.rejoinOnKick, !channel.errorOnLastJoinAttempt {
					printDebugInformation(IRCInboundStrings.Membership.rejoinScheduled, in: channel)
					NSObject.cancelPreviousPerformRequests(
						withTarget: self, selector: #selector(joinKickedChannel(_:)), object: channel
					)
					perform(#selector(joinKickedChannel(_:)), with: channel, afterDelay: 3)
				}
			} else {
				channel.removeMember(withNickname: target)
			}
		}
		let ignore = message.senderHostmask.flatMap(findAddressBookEntry(forHostmask:))
		if postReceivedMessage(message, withText: comment, destinedFor: channel),
		   IRCMembershipEventPolicy.shouldPrint(
		   	isLocalUser: isLocalUser,
		   	showJoinLeave: environment.preferences.showJoinLeave,
		   	channelIgnoresEvents: channel.config.ignoreGeneralEventMessages,
		   	addressBookIgnoresEvents: ignore?.ignoreGeneralEventMessages ?? false
		   )
		{
			let text = IRCInboundStrings.Membership.kicked(
				sender: sender,
				target: target,
				reason: comment.stringByAppendingIRCFormattingStop
			)
			print(text, by: nil, in: channel, as: .kick, command: message.command, receivedAt: message.receivedAt)
		}
		if !message.isPrintOnlyMessage {
			updateTitle(channel)
		}
	}

	@objc(receiveQuit:)
	func receiveQuit(_ message: Message) {
		guard !message.params.isEmpty, let sender = message.senderNickname else { return }
		let printOnly = message.isPrintOnlyMessage
		let channelName = printOnly ? message.params[0] : nil
		let comment = message.params.count > (printOnly ? 1 : 0) ? message.params[printOnly ? 1 : 0] : ""
		let isLocalUser = nicknameIsMyself(sender)
		let user = printOnly ? nil : findUser(sender)
		if !printOnly, user == nil {
			return
		}
		let ignore = isLocalUser ? nil : message.senderHostmask.flatMap(findAddressBookEntry(forHostmask:))
		if let ignore, !printOnly {
			updateTrackingStatus(for: ignore, message: message)
		}

		var quitText = IRCInboundStrings.Membership.quit(
			nickname: sender,
			username: message.senderUsername ?? "",
			address: (message.senderAddress ?? "").stringByAppendingIRCFormattingStop
		)
		if !comment.isEmpty {
			quitText = IRCInboundStrings.Membership.eventWithComment(
				quitText,
				comment: comment.stringByAppendingIRCFormattingStop
			)
		}

		func process(_ channel: IRCChannel) {
			if !isLocalUser, !printOnly, let user {
				if channel.isChannel {
					guard let member = user.userAssociated(with: channel) else { return }
					channel.memberInfo?.removeMember(member)
				} else if channel.isPrivateMessage, casefoldNickname(sender) == casefoldNickname(channel.name) {
					if channel.isActive {
						channel.deactivate(); reloadTreeItem(channel)
					}
				} else {
					return
				}
			}
			let text = channel.isChannel ? quitText : IRCInboundStrings.Membership.leftQuery(nickname: sender)
			if channel.isChannel {
				let canPrint = postReceivedMessage(message, withText: comment, destinedFor: channel) &&
					IRCMembershipEventPolicy.shouldPrint(
						isLocalUser: isLocalUser,
						showJoinLeave: environment.preferences.showJoinLeave,
						channelIgnoresEvents: channel.config.ignoreGeneralEventMessages,
						addressBookIgnoresEvents: ignore?.ignoreGeneralEventMessages ?? false
					)
				updateTitle(channel)
				guard canPrint else { return }
			}
			print(text, by: nil, in: channel, as: .quit, command: message.command, receivedAt: message.receivedAt)
		}

		if printOnly {
			guard let channelName, let channel = findChannel(channelName) else { return }
			process(channel)
		} else {
			channelList.forEach(process)
			if !isLocalUser {
				updateTitle(self)
				_ = notifyEvent(.userDisconnected, lineType: .quit, target: nil, nickname: sender, text: comment)
			}
		}
	}

	@objc(receiveKill:)
	func receiveKill(_ message: Message) {
		guard let nickname = message.params.first else { return }
		for channel in channelList {
			channel.removeMember(withNickname: nickname)
		}
	}

	@objc(receiveNick:)
	func receiveNick(_ message: Message) {
		guard !message.params.isEmpty, let oldNickname = message.senderNickname else { return }
		let printOnly = message.isPrintOnlyMessage
		let channelName = printOnly ? message.params[0] : nil
		guard let newNickname = message.params.count > (printOnly ? 1 : 0)
			? message.params[printOnly ? 1 : 0] : nil,
			oldNickname != newNickname
		else { return }
		let isLocalUser = nicknameIsMyself(oldNickname)
		let oldIgnore = isLocalUser ? nil : message.senderHostmask.flatMap(findAddressBookEntry(forHostmask:))

		if !printOnly {
			if isLocalUser {
				userNickname = newNickname
				if tryingNicknameSentNickname != nil {
					tryingNicknameSentNickname = newNickname
				}
				updateTitle(self)
			} else {
				if let oldIgnore {
					updateTrackingStatus(for: oldIgnore, message: message)
				}
				if let newEntry = findUserTrackingAddressBookEntry(forNickname: newNickname) {
					updateTrackingStatus(for: newEntry, message: message)
				}
			}
			postEvent(toViewController: "nicknameChanged")
		}
		NotificationCenter.default.post(
			name: .IRCClientUserNicknameChanged, object: self,
			userInfo: ["oldNickname": oldNickname, "newNickname": newNickname]
		)
		let user = printOnly ? nil : findUser(oldNickname)
		if !printOnly, user == nil {
			return
		}
		let text = isLocalUser
			? IRCInboundStrings.Membership.localNicknameChanged(to: newNickname)
			: IRCInboundStrings.Membership.nicknameChanged(from: oldNickname, to: newNickname)

		func process(_ channel: IRCChannel) {
			if !printOnly, let user {
				if channel.isChannel {
					guard let member = user.userAssociated(with: channel) else { return }
					channel.memberInfo?.resortMember(member)
				} else if channel.isPrivateMessage {
					guard casefoldNickname(oldNickname) == casefoldNickname(channel.name) else { return }
					if findChannel(newNickname) == nil {
						channel.name = newNickname
						reloadTreeItem(channel)
						updateTitle(channel)
					}
				} else {
					return
				}
			}
			if channel.isChannel {
				guard postReceivedMessage(message, withText: newNickname, destinedFor: channel),
				      IRCMembershipEventPolicy.shouldPrint(
				      	isLocalUser: isLocalUser,
				      	showJoinLeave: environment.preferences.showJoinLeave,
				      	channelIgnoresEvents: channel.config.ignoreGeneralEventMessages,
				      	addressBookIgnoresEvents: oldIgnore?.ignoreGeneralEventMessages ?? false
				      )
				else { return }
			}
			print(text, by: nil, in: channel, as: .nick, command: message.command, receivedAt: message.receivedAt)
		}

		if printOnly {
			guard let channelName, let channel = findChannel(channelName) else { return }
			process(channel)
		} else if let user {
			rename(user, to: newNickname)
			channelList.forEach(process)
		}
	}

	private func reloadTreeItem(_ item: AnyObject) {
		guard let legacyItem = item as? IRCTreeItem else { return }
		output?.reloadTreeItem(legacyItem)
	}

	private func updateTitle(_ item: AnyObject) {
		guard let legacyItem = item as? IRCTreeItem else { return }
		output?.updateTitle(for: legacyItem)
	}

	private func updateTrackingStatus(for entry: AddressBookEntry, message: Message) {
		updateUserTrackingStatus(for: entry, message: message)
	}
}
