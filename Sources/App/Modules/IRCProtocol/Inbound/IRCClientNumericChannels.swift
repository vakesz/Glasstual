/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_
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

private let whoxResponseToken = "152"

@MainActor
extension IRCClient {
	func handleChannelNumeric(_ numeric: UInt, message: Message, shouldPrint: Bool) -> Bool {
		switch numeric {
		case IRCNumeric.channelmodeis.rawValue: handleChannelModeNumeric(message)
		case IRCNumeric.topic.rawValue: handleTopicNumeric(message)
		case IRCNumeric.topicwhotime.rawValue: handleTopicMetadataNumeric(message)
		case IRCNumeric.creationtime.rawValue: break
		case IRCNumeric.inviting.rawValue: handleInvitingNumeric(message, shouldPrint: shouldPrint)
		case IRCNumeric.ison.rawValue: handleISONNumeric(message, shouldPrint: shouldPrint)
		case IRCNumeric.whoreply.rawValue: handleWHONumeric(message, shouldPrint: shouldPrint)
		case IRCNumeric.whospcrpl.rawValue: handleWHOXNumeric(message, shouldPrint: shouldPrint)
		case IRCNumeric.endofwho.rawValue:
			let visible = requestedCommands.visibleWhoRequest
			requestedCommands.recordWhoRequestClosed()
			if visible, shouldPrint {
				printReplyToHiddenCommandResponsesQuery(message)
			}
		case IRCNumeric.namereply.rawValue: handleNamesNumeric(message, shouldPrint: shouldPrint)
		case IRCNumeric.endofnames.rawValue: handleEndOfNamesNumeric(message, shouldPrint: shouldPrint)
		case IRCNumeric.liststart.rawValue:
			channelListDialog()?.contentAlreadyReceived = false
			channelListDialog()?.clear()
		case IRCNumeric.list.rawValue: handleListNumeric(message)
		case IRCNumeric.listend.rawValue: channelListDialog()?.contentAlreadyReceived = true
		case IRCNumeric.banlist.rawValue, IRCNumeric.invitelist.rawValue, IRCNumeric.exceptlist.rawValue,
		     IRCNumeric.quietlist.rawValue:
			handleModeListNumeric(numeric, message: message, shouldPrint: shouldPrint)
		case IRCNumeric.endofbanlist.rawValue, IRCNumeric.endofinvitelist.rawValue, IRCNumeric.endofexceptlist.rawValue,
		     IRCNumeric.endofquietlist.rawValue:
			handleEndOfModeListNumeric(message, shouldPrint: shouldPrint)
		default: return false
		}
		return true
	}

	private func handleChannelModeNumeric(_ message: Message) {
		guard message.params.count > 2 else { return }
		let modeString = message.sequence(2)
		guard modeString != "+", let channel = findChannel(message.params[1]) else { return }
		if channel.isActive {
			channel.modeInfo?.clear()
			_ = channel.modeInfo?.updateModes(modeString)
		}
		let shouldPrint = postReceivedMessage(message, withText: modeString, destinedFor: channel)
		channel.channelModesReceived = true
		if shouldPrint {
			print(
				IRCInboundStrings.ChannelEvent.mode(channel.modeInfo?.stringWithMaskedPassword ?? modeString),
				by: nil,
				in: channel, as: .mode, command: message.command, receivedAt: message.receivedAt
			)
		}
	}

	private func handleTopicNumeric(_ message: Message) {
		guard message.params.count == 3, let channel = findChannel(message.params[1]) else { return }
		let topic = message.params[2]
		let shouldPrint = postReceivedMessage(message, withText: topic, destinedFor: channel)
		channel.topic = topic
		if shouldPrint {
			print(IRCInboundStrings.ChannelEvent.topic(topic), by: nil, in: channel, as: .topic,
			      command: message.command, receivedAt: message.receivedAt)
		}
	}

	private func handleTopicMetadataNumeric(_ message: Message) {
		guard message.params.count == 4, let channel = findChannel(message.params[1]),
		      postReceivedMessage(message, withText: nil, destinedFor: channel)
		else { return }
		let setter = (message.params[2] as NSString).nicknameFromHostmask ?? message.params[2]
		let date = Date(timeIntervalSince1970: TimeInterval(message.params[3]) ?? 0)
		print(
			IRCInboundStrings.ChannelEvent.topicSet(
				by: setter,
				date: formatDateLongStyle(date, true) ?? ""
			),
			by: nil,
			in: channel,
			as: .topic, command: message.command, receivedAt: message.receivedAt
		)
	}

	private func handleInvitingNumeric(_ message: Message, shouldPrint: Bool) {
		guard shouldPrint, message.params.count == 3, let channel = findChannel(message.params[2]) else { return }
		print(
			IRCInboundStrings.ChannelEvent.inviting(message.params[1], to: channel.name),
			by: nil,
			in: channel,
			as: .debug,
			command: message.command, receivedAt: message.receivedAt
		)
	}

	private func handleISONNumeric(_ message: Message, shouldPrint: Bool) {
		let visible = requestedCommands.visibleIsonRequest
		requestedCommands.recordIsonRequestClosed()
		if visible {
			if shouldPrint {
				printReplyToHiddenCommandResponsesQuery(message)
			}
			return
		}
		let online = LineParser.wireTokens(in: message.sequence)
		let tracked = supportsAdvancedTracking ? [:] : trackedUsers.trackedUsers
		for (nickname, previousValue) in tracked {
			let isOnline = online.contains { $0.caseInsensitiveCompare(nickname) == .orderedSame }
			let status: IRCAddressBookUserTrackingStatus = if previousValue.boolValue, !isOnline,
			                                                  !invokingISONCommandForFirstTime
			{
				.signedOff
			} else if !previousValue.boolValue, isOnline {
				invokingISONCommandForFirstTime ? .available : .signedOn
			} else {
				.unknown
			}
			if status != .unknown {
				setTrackedNickname(nickname, status: status, notify: true)
			}
		}
		invokingISONCommandForFirstTime = false
		for channel in channelList where channel.isPrivateMessage {
			let isOnline = online.contains { $0.caseInsensitiveCompare(channel.name) == .orderedSame }
			guard channel.isActive != isOnline else { continue }
			if isOnline {
				channel.activate()
			} else {
				channel.deactivate()
			}
			if let treeItem = (channel as AnyObject) as? IRCTreeItem {
				NSObject.applicationController().mainWindow.reloadTreeItem(treeItem)
			}
		}
	}

	private func handleWHONumeric(_ message: Message, shouldPrint: Bool) {
		guard message.params.count >= 8 else { return }
		if requestedCommands.visibleWhoRequest {
			if shouldPrint {
				printReplyToHiddenCommandResponsesQuery(message)
			}
			return
		}
		guard let channel = findChannel(message.params[1]) else { return }
		let rawRealName = message.params[7]
		let realName = rawRealName.firstIndex(of: " ").map { String(rawRealName[rawRealName.index(after: $0)...]) }
			?? rawRealName
		receiveWhoReply(in: channel, reply: IRCWHOReply(
			nickname: message.params[5], username: message.params[2], address: message.params[3],
			flags: message.params[6], realName: realName, account: nil, updatesAccount: false
		))
	}

	private func handleWHOXNumeric(_ message: Message, shouldPrint: Bool) {
		guard message.params.count >= 9 else { return }
		guard message.params[1] == whoxResponseToken, !requestedCommands.visibleWhoRequest else {
			if shouldPrint {
				printReplyToHiddenCommandResponsesQuery(message)
			}
			return
		}
		guard let channel = findChannel(message.params[2]) else { return }
		receiveWhoReply(in: channel, reply: IRCWHOReply(
			nickname: message.params[5], username: message.params[3], address: message.params[4],
			flags: message.params[6], realName: message.params[8],
			account: Self.account(fromWireValue: message.params[7]),
			updatesAccount: true
		))
	}

	private func handleNamesNumeric(_ message: Message, shouldPrint: Bool) {
		guard message.params.count > 3 else { return }
		if shouldPrint {
			printReplyToHiddenCommandResponsesQuery(message)
		}
		guard let channel = findChannel(message.params[2]), !channel.channelNamesReceived else { return }
		for rawName in LineParser.wireTokens(in: message.params[3]) {
			addName(rawName, to: channel)
		}
	}

	private func addName(_ rawName: String, to channel: IRCChannel) {
		var modes = ""
		var nameStart = rawName.startIndex
		while nameStart < rawName.endIndex,
		      let mode = supportInfo.modeSymbol(forUserPrefix: String(rawName[nameStart]))
		{
			modes += mode
			nameStart = rawName.index(after: nameStart)
		}
		let hostmask = String(rawName[nameStart...])
		var parsedNickname: NSString?
		var parsedUsername: NSString?
		var parsedAddress: NSString?
		let parsed = (hostmask as NSString).hostmaskComponents(
			&parsedNickname, username: &parsedUsername, address: &parsedAddress, on: self
		)
		let nickname = parsed ? (parsedNickname as String? ?? hostmask) : hostmask
		let user: User
		if let existing = findUser(nickname) {
			user = existing
		} else {
			let mutable = UserMutable(nickname: nickname, on: self)
			mutable.username = parsedUsername as String?
			mutable.address = parsedAddress as String?
			user = addAndReturn(mutable)
		}
		let mutableMember: ChannelUserMutable
		if let member = user.userAssociated(with: channel) {
			guard nicknameIsMyself(nickname), let copy = member.mutableCopy() as? ChannelUserMutable else { return }
			mutableMember = copy
		} else {
			mutableMember = ChannelUserMutable(user: user)
		}
		mutableMember.modes = modes
		channel.memberInfo?.addMember(mutableMember, checkForDuplicates: true)
	}

	private func handleEndOfNamesNumeric(_ message: Message, shouldPrint: Bool) {
		guard message.params.count == 3 else { return }
		if shouldPrint {
			printReplyToHiddenCommandResponsesQuery(message)
		}
		guard let channel = findChannel(message.params[1]), !channel.channelNamesReceived else { return }
		channel.channelNamesReceived = true
		if channel.numberOfMembers == 1, !isBrokenIRCdKnownAsTwitch {
			if let defaultModes = channel.config.defaultModes, !defaultModes.isEmpty {
				sendModes(defaultModes, withParametersString: nil, in: channel)
			}
			if let defaultTopic = channel.config.defaultTopic, !defaultTopic.isEmpty {
				sendTopic(to: defaultTopic, in: channel)
			}
		}
		NSObject.applicationController().mainWindow.updateTitle(for: channel)
	}

	private func handleListNumeric(_ message: Message) {
		guard message.params.count > 2, message.params[1] != "*" else { return }
		channelListDialog()?.addChannel(
			message.params[1],
			count: UInt(message.params[2]) ?? 0,
			topic: message.sequence(3)
		)
	}

	private func handleModeListNumeric(_ numeric: UInt, message: Message, shouldPrint: Bool) {
		guard message.params.count > 2 else { return }
		let offset = numeric == IRCNumeric.quietlist.rawValue && message.params.count == 6 ? 1 : 0
		let mask = message.params[2 + offset]
		let extended = message.params.count > 4 + offset
		let author = extended ? (message.params[3 + offset] as NSString).nicknameFromHostmask : nil
		let date = extended ? Date(timeIntervalSince1970: TimeInterval(message.params[4 + offset]) ?? 0) : nil
		if let sheet = SharedApplication.sharedWindowController().window(fromWindowList: "TDCChannelBanListSheet")
			as? ChannelBanListSheet
		{
			if sheet.contentAlreadyReceived {
				sheet.contentAlreadyReceived = false; sheet.clear()
			}
			sheet.addEntry(mask, setBy: author, creationDate: date)
			return
		}
		guard shouldPrint else { return }
		let text = IRCChannelAccessListStrings.entry(
			kind: IRCChannelAccessListKind(numeric: numeric),
			channelName: message.params[1],
			mask: mask,
			setBy: extended ? author ?? "" : nil,
			date: extended ? date.flatMap { formatDateLongStyle($0, true) } ?? "" : nil
		)
		print(text, by: nil, in: nil, as: .debug, command: message.command, receivedAt: message.receivedAt)
	}

	private func handleEndOfModeListNumeric(_ message: Message, shouldPrint: Bool) {
		if let sheet = SharedApplication.sharedWindowController().window(fromWindowList: "TDCChannelBanListSheet")
			as? ChannelBanListSheet
		{
			sheet.contentAlreadyReceived = true
		} else if shouldPrint {
			printReply(message)
		}
	}
}
