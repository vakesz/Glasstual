// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

enum MembershipEventPolicy {
	static func shouldPrint(
		isLocalUser: Bool,
		showJoinLeave: Bool,
		channelDisplay: GeneralEventMessageDisplay,
		addressBookIgnoresEvents: Bool
	) -> Bool {
		isLocalUser || ((showJoinLeave || channelDisplay == .collapse) && channelDisplay != .hide && !addressBookIgnoresEvents)
	}
}

@MainActor
extension ServerSession {
	/// Whether a membership or mode event prints, weighing the three settings
	/// this connection reads it against: the setting, the channel's own
	/// event filter and the address-book entry the sender matched.
	func printsGeneralEvent(
		isLocalUser: Bool,
		in channel: Conversation,
		ignoring entry: AddressBookEntry?
	) -> Bool {
		MembershipEventPolicy.shouldPrint(
			isLocalUser: isLocalUser,
			showJoinLeave: environment.settings.showJoinLeave,
			channelDisplay: channel.config.generalEventMessageDisplay,
			addressBookIgnoresEvents: entry?.ignoreGeneralEventMessages ?? false
		)
	}

	func receiveJoin(_ message: Message) {
		guard let channelName = message.params.first, let sender = message.senderNickname else { return }
		let printOnly = message.isPrintOnlyMessage
		let isLocalUser = nicknameIsMyself(sender)
		let channel: Conversation

		if !printOnly, isLocalUser {
			guard let found = findConversationOrCreate(channelName), !found.isActive, found.isChannel else { return }
			channel = found
			/* The server's clock where it supplies one, so the burst a bouncer
			 replays right after the JOIN is measured against the same clock its
			 lines are stamped with. A JOIN that is itself replayed carries an old
			 stamp, which would close the grace window before the burst behind it
			 arrives; that one is measured from its arrival instead. */
			channel.activate(at: message.isReplayed ? Date() : message.receivedAt)
			userHostmask = message.senderHostmask
			output?.reloadChatItem(channel)
		} else {
			guard let found = findConversation(channelName), found.isChannel else { return }
			channel = found
		}

		if !printOnly {
			var user = draftUser(withNickname: sender)
			user.nickname = sender
			user.username = message.senderUsername
			user.address = message.senderAddress
			if isCapabilityEnabled(.extendedJoin), message.params.count >= 3 {
				user.account = IdentityPolicy.account(fromWireValue: message.params[1])
				user.realName = message.params[2]
			}
			channel.memberInfo?.addMember(
				Member(user: addAndReturn(user), prefixes: currentUserPrefixes)
			)
		}

		if !printOnly, !isLocalUser, let directConversation = findConversation(sender), !directConversation.isActive {
			directConversation.activate()
			print(String(localized: .IRC.joinedTheQueryByConnecting(sender)), by: nil, in: directConversation, as: .join,
			      command: message.command, receivedAt: message.receivedAt)
			output?.reloadChatItem(directConversation)
		}

		let ignore = isLocalUser ? nil : message.senderHostmask.flatMap(findAddressBookEntry(forHostmask:))
		if let ignore, !printOnly {
			updateTrackingStatus(for: ignore, message: message)
		}
		if shouldPrintReceivedMessage(message, withText: nil, destinedFor: channel),
		   printsGeneralEvent(isLocalUser: isLocalUser, in: channel, ignoring: ignore)
		{
			let address = (message.senderAddress ?? "").stringByAppendingIRCFormattingStop
			print(
				String(localized: .IRC.joinedTheChannel(sender, message.senderUsername ?? "", address)),
				by: nil,
				in: channel, as: .join, command: message.command, receivedAt: message.receivedAt
			)
		}
		guard !printOnly else { return }
		output?.updateTitle(for: channel)
		if isLocalUser, config.sendWhoCommandRequestsToChannels, !isBrokenIRCdKnownAsTwitch {
			requestModes(inChannelNamed: channel.name)
		}
	}

	func receivePart(_ message: Message) {
		guard !(isQuitting && znc.isConnected),
		      let channelName = message.params.first,
		      let channel = findConversation(channelName), channel.isChannel,
		      let sender = message.senderNickname
		else { return }
		let comment = message.params.count > 1 ? message.params[1] : ""
		let isLocalUser = nicknameIsMyself(sender)
		if !message.isPrintOnlyMessage {
			if isLocalUser {
				channel.deactivate()
				output?.reloadChatItem(channel)
			} else {
				channel.removeMember(withNickname: sender)
			}
		}
		let ignore = message.senderHostmask.flatMap(findAddressBookEntry(forHostmask:))
		if shouldPrintReceivedMessage(message, withText: comment, destinedFor: channel),
		   printsGeneralEvent(isLocalUser: isLocalUser, in: channel, ignoring: ignore)
		{
			var text = String(localized: .IRC.leftTheChannel(
				sender,
				message.senderUsername ?? "",
				(message.senderAddress ?? "").stringByAppendingIRCFormattingStop
			))
			if !comment.isEmpty {
				text = String(localized: .IRC.miscellaneousMessagesRelated(text, comment.stringByAppendingIRCFormattingStop))
			}
			print(text, by: nil, in: channel, as: .part, command: message.command, receivedAt: message.receivedAt)
		}
		if !message.isPrintOnlyMessage {
			output?.updateTitle(for: channel)
		}
	}

	func receiveKick(_ message: Message) {
		guard message.params.count > 1,
		      let channel = findConversation(message.params[0]), channel.isChannel,
		      let sender = message.senderNickname
		else { return }
		let target = message.params[1]
		let comment = message.params.count > 2 ? message.params[2] : ""
		let isLocalUser = nicknameIsMyself(target)
		if !message.isPrintOnlyMessage {
			if isLocalUser {
				channel.deactivate()
				output?.reloadChatItem(channel)
				notifyEvent(.kick, lineType: .kick, target: channel, nickname: sender, text: comment)
				if environment.settings.rejoinOnKick, !channel.errorOnLastJoinAttempt {
					printDebugInformation(String(localized: .IRC.attemptingToRejoinChannelInThree), in: channel)
					let key = channel.uniqueIdentifier
					rejoinTasks[key]?.cancel()
					rejoinTasks[key] = Task { [weak self, weak channel] in
						try? await Task.sleep(for: .seconds(3))

						guard Task.isCancelled == false, let self, let channel else { return }

						rejoinTasks[key] = nil
						join(channel)
					}
				}
			} else {
				channel.removeMember(withNickname: target)
			}
		}
		let ignore = message.senderHostmask.flatMap(findAddressBookEntry(forHostmask:))
		if shouldPrintReceivedMessage(message, withText: comment, destinedFor: channel),
		   printsGeneralEvent(isLocalUser: isLocalUser, in: channel, ignoring: ignore)
		{
			let text = String(localized: .IRC.kickedFromTheChannel(sender, target, comment.stringByAppendingIRCFormattingStop))
			print(text, by: nil, in: channel, as: .kick, command: message.command, receivedAt: message.receivedAt)
		}
		if !message.isPrintOnlyMessage {
			output?.updateTitle(for: channel)
		}
	}

	func receiveQuit(_ message: Message) {
		guard !message.params.isEmpty, let sender = message.senderNickname else { return }
		let printOnly = message.isPrintOnlyMessage
		let conversationName = printOnly ? message.params[0] : nil
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

		var quitText = String(localized: .IRC.leftIrc(
			sender,
			message.senderUsername ?? "",
			(message.senderAddress ?? "").stringByAppendingIRCFormattingStop
		))
		if !comment.isEmpty {
			quitText = String(localized: .IRC.miscellaneousMessagesRelatedToIrcEvents(quitText, comment.stringByAppendingIRCFormattingStop))
		}

		func process(_ conversation: Conversation) {
			if !isLocalUser, !printOnly, let user {
				if conversation.isChannel {
					guard let member = userAssociated(user, with: conversation) else { return }
					conversation.memberInfo?.removeMember(member)
				} else if conversation.isDirect, casefoldNickname(sender) == casefoldNickname(conversation.name) {
					applyPresence(false, to: conversation)
				} else {
					return
				}
			}
			let text = conversation.isChannel ? quitText : String(localized: .IRC.leftTheQueryByDisconnecting(sender))
			if conversation.isChannel {
				let canPrint = shouldPrintReceivedMessage(message, withText: comment, destinedFor: conversation) &&
					printsGeneralEvent(isLocalUser: isLocalUser, in: conversation, ignoring: ignore)
				output?.updateTitle(for: conversation)
				guard canPrint else { return }
			}
			print(text, by: nil, in: conversation, as: .quit, command: message.command, receivedAt: message.receivedAt)
		}

		if printOnly {
			guard let conversationName, let conversation = findConversation(conversationName) else { return }
			process(conversation)
		} else {
			conversationList.forEach(process)
			if !isLocalUser {
				output?.updateTitle(for: self)
			}
		}
	}

	func receiveKill(_ message: Message) {
		guard let nickname = message.params.first else { return }
		for conversation in conversationList {
			conversation.removeMember(withNickname: nickname)
		}
	}

	func receiveNick(_ message: Message) {
		guard !message.params.isEmpty, let oldNickname = message.senderNickname else { return }
		let printOnly = message.isPrintOnlyMessage
		let conversationName = printOnly ? message.params[0] : nil
		guard let newNickname = message.params.count > (printOnly ? 1 : 0)
			? message.params[printOnly ? 1 : 0] : nil,
			oldNickname != newNickname
		else { return }
		let isLocalUser = nicknameIsMyself(oldNickname)
		let oldIgnore = isLocalUser ? nil : message.senderHostmask.flatMap(findAddressBookEntry(forHostmask:))

		if !printOnly {
			if isLocalUser {
				userNickname = newNickname
				if nicknameRetry.sentNickname != nil {
					nicknameRetry.sentNickname = newNickname
				}
				/* A nickname the session now holds is the retry sequence resolved,
				 whether the session asked for it or the user did. Leaving the count
				 where it was is what would keep the ceiling in force for the rest of
				 the session. */
				nicknameRetry.attempt = 0
				output?.updateTitle(for: self)
			} else {
				if let oldIgnore {
					updateTrackingStatus(for: oldIgnore, message: message)
				}
				if let newEntry = findUserTrackingAddressBookEntry(forNickname: newNickname) {
					updateTrackingStatus(for: newEntry, message: message)
				}
			}
		}
		NotificationCenter.default.post(
			name: .serverSessionUserNicknameChanged, object: self,
			userInfo: ["oldNickname": oldNickname, "newNickname": newNickname]
		)
		let user = printOnly ? nil : findUser(oldNickname)
		if !printOnly, user == nil {
			return
		}
		let text = isLocalUser
			? String(localized: .IRC.youreNowKnown(newNickname))
			: String(localized: .IRC.isNowKnown(oldNickname, newNickname))

		func process(_ conversation: Conversation) {
			if !printOnly, let user {
				if conversation.isChannel {
					guard let member = userAssociated(user, with: conversation) else { return }
					conversation.memberInfo?.resortMember(member)
				} else if conversation.isDirect {
					guard casefoldNickname(oldNickname) == casefoldNickname(conversation.name) else { return }
					renameDirectConversation(conversation, from: oldNickname, to: newNickname)
				} else {
					return
				}
			}
			if conversation.isChannel {
				guard shouldPrintReceivedMessage(message, withText: newNickname, destinedFor: conversation),
				      printsGeneralEvent(isLocalUser: isLocalUser, in: conversation, ignoring: oldIgnore)
				else { return }
			}
			print(text, by: nil, in: conversation, as: .nick, command: message.command, receivedAt: message.receivedAt)
		}

		if printOnly {
			guard let conversationName, let conversation = findConversation(conversationName) else { return }
			process(conversation)
		} else if let user {
			rename(user, to: newNickname)
			conversationList.forEach(process)
		}
	}

	/** Follows the direct conversation with `oldNickname` onto the name its peer
	 just took.

	 Two direct conversations cannot share a name, so a rename into a nickname
	 that already has one open has to pick a winner, and the winner is the
	 conversation that is already called `newNickname`: it is the one the sidebar
	 shows under that name, the one the user has been reading, and the one the
	 server is already watching. The renamed conversation keeps its transcript
	 under the old nickname and is closed — drawn as offline, and its watch entry
	 released, because the person it was with is not there any more. Leaving it
	 alone stranded it: it was never renamed and `stopTrackingDirectPeer` was never
	 called, so the watch list kept asking after a nickname that now belongs to
	 somebody else. */
	private func renameDirectConversation(
		_ directConversation: Conversation,
		from oldNickname: String,
		to newNickname: String
	) {
		/* A rename that only changes case finds the conversation itself under the
		 new name, and is no collision. */
		guard let existing = findConversation(newNickname), existing !== directConversation else {
			retitleDirectConversation(directConversation, from: oldNickname, to: newNickname)
			return
		}

		stopTrackingDirectPeer(oldNickname)
		applyPresence(false, to: directConversation)
		output?.reloadChatItem(directConversation)

		if existing.isDirect {
			applyPresence(true, to: existing)
		}
	}

	/** Puts `directConversation` under `newNickname`, and moves the server's
	 watch entry for its peer along with it.

	 The one rename both a peer's NICK and `/setqueryname` go through: renaming
	 the conversation alone left the watch list asking after the old nickname and
	 never reporting the new one, so the row stopped following its peer. */
	func retitleDirectConversation(
		_ directConversation: Conversation,
		from oldNickname: String,
		to newNickname: String
	) {
		let peerChanged = casefoldNickname(oldNickname) != casefoldNickname(newNickname)

		if peerChanged {
			stopTrackingDirectPeer(oldNickname)
		}

		directConversation.name = newNickname

		if peerChanged {
			trackDirectPeer(newNickname)
		}

		output?.reloadChatItem(directConversation)
		output?.updateTitle(for: directConversation)
	}

	private func updateTrackingStatus(for entry: AddressBookEntry, message: Message) {
		updateUserTrackingStatus(for: entry, message: message)
	}
}
