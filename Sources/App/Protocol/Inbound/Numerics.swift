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

/** How a WHOIS or WHOWAS line reads.

 WHOWAS answers with the same fields about a connection that has already
 ended, so the two differ only in tense. */
private func whoisConnectionText(
	nickname: String,
	address: String,
	realName: String,
	isHistorical: Bool
) -> String {
	if isHistorical {
		return String(localized: .IRC.miscellaneousMessagesRelatedWasConnected(nickname, address, realName))
	}

	return String(localized: .IRC.isConnected(nickname, address, realName))
}

private func whoisUserhostText(
	nickname: String,
	username: String,
	address: String,
	realName: String,
	isHistorical: Bool
) -> String {
	if isHistorical {
		return String(localized: .IRC.hadUserhostAndRealName(nickname, username, address, realName))
	}

	return String(localized: .IRC.hasUserhostAndRealName(nickname, username, address, realName))
}

@MainActor
extension Client {
	func receiveNumericReply(_ message: Message) {
		let rawNumeric = message.commandNumeric

		if ServerNumeric.isErrorReply(rawNumeric) {
			receiveErrorNumericReply(message)
			return
		}

		let numeric = ServerNumeric(rawValue: rawNumeric)
		let shouldPrint = numeric?.requiresSpecialFiltering == true || shouldPrintReceivedMessage(message)

		if let numeric, let group = numeric.group {
			switch group {
			case .connection:
				handleConnectionNumeric(numeric, message: message, shouldPrint: shouldPrint)
			case .whois:
				handleWhoisNumeric(numeric, message: message, shouldPrint: shouldPrint)
			case .channel:
				handleChannelNumeric(numeric, message: message, shouldPrint: shouldPrint)
			case .presence:
				handlePresenceTrackingNumeric(numeric, message: message, shouldPrint: shouldPrint)
			case .authentication:
				handleAuthenticationTrackingNumeric(numeric, message: message, shouldPrint: shouldPrint)
			}

			return
		}

		guard shouldPrint else { return }
		if inWhoisResponse, message.params.count > 2 {
			printReply(message, in: output?.selectedChannel(on: self))
		} else {
			printReply(message)
		}
	}
}

@MainActor
extension Client {
	func handleConnectionNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		switch numeric {
		case .welcome:
			receiveInit(message)
			if shouldPrint {
				printReply(message)
			}
		case .yourhost, .created, .myinfo, .statsconn,
		     .luserclient, .luserhop, .luserunknown, .luserchannels, .luserme:
			if shouldPrint {
				printReply(message)
			}
		case .isupport:
			handleISupportNumeric(message, shouldPrint: shouldPrint)
		case .redir:
			handleRedirectNumeric(message, shouldPrint: shouldPrint)
		case .localusers, .globalusers:
			guard shouldPrint else { return }
			let text = message.params.count == 4 ? message.sequence(3) : message.sequence
			print(text, by: nil, in: nil, as: .debug, command: message.command, receivedAt: message.receivedAt)
		case .motd, .motdstart, .endofmotd, .nomotd:
			guard shouldPrint, environment.preferences.displayServerMOTD else { return }
			if numeric == .nomotd {
				printErrorReply(message)
			} else {
				printReply(message)
			}
		case .umodeis:
			handleUserModeNumeric(message)
		case .away:
			handleAwayNumeric(message, shouldPrint: shouldPrint)
		case .silelist:
			handleSilenceListNumeric(message, shouldPrint: shouldPrint)
		case .endofsilelist:
			if shouldPrint {
				printDebugInformation(String(localized: .IRC.endOfSilenceList),
				                      in: output?.selectedChannel(on: self),
				                      asCommand: message.command)
			}
		case .unaway, .nowaway:
			handleOwnAwayNumeric(numeric, message: message, shouldPrint: shouldPrint)
		default:
			break
		}
	}

	private func handleISupportNumeric(_ message: Message, shouldPrint: Bool) {
		guard message.params.count >= 3 else { return }
		let configuration = message.params.dropFirst().dropLast().joined(separator: " ")
		let explanatoryText = message.params.last ?? ""
		let previousCaseMapping = supportInfo.caseMapping
		let previousPrefixes = currentUserPrefixes
		let wasUTF8Only = supportInfo.utf8Only
		supportInfo.processConfigurationData(configuration)
		/* The socket is what measures the assembled line, and until 005 lands it
		 has only the RFC's 512 to measure against. A `LINELEN` that raises the
		 budget every other outbound path already reads has to reach it too, or
		 a line those paths sized for 1024 is cut to 510 on the way out. */
		socket?.maximumLineLength = supportInfo.maximumLineLength > 0
			? Int(clamping: supportInfo.maximumLineLength)
			: ProtocolLimits.maximumBodyLength + ProtocolLimits.lineTerminatorLength
		let caseMappingChanged = supportInfo.caseMapping != previousCaseMapping
		if caseMappingChanged {
			rekeyUserList()
		}
		/* A member carries the prefix table it was stamped with, because it has
		 no client to ask off the main actor. A 005 that changes `PREFIX` or
		 `CASEMAPPING` therefore changes how every member already in a channel
		 ranks and marks itself, and until now only a preferences reload ever
		 re-stamped them: the ranks stayed on the table that was current when
		 each member joined, and the member list stayed in an order built from
		 it. Servers do send a second 005 — a bouncer replays the network's on
		 attach, and services reload theirs — so this is not hypothetical. */
		let prefixes = currentUserPrefixes
		let prefixesChanged = prefixes.modeSymbols != previousPrefixes.modeSymbols ||
			prefixes.prefixCharacters != previousPrefixes.prefixCharacters
		if caseMappingChanged || prefixesChanged {
			for channel in channelList where channel.isChannel {
				channel.memberInfo?.sortMembers()
			}
		}
		if shouldPrint {
			printDebugInformation(
				toConsole: String(localized: .IRC.miscellaneousMessagesRelated2(
					supportInfo.stringValueForLastUpdate ?? "",
					explanatoryText
				)),
				asCommand: message.command
			)
		}
		if !wasUTF8Only, supportInfo.utf8Only {
			printDebugInformation(toConsole: String(localized: .IRC.thisServerOnlyAcceptsUtf8), asCommand: message.command)
		}
	}

	/** `RPL_BOUNCE`: the server is full and names another to try.

	 It is only a redirect while registration is still under way; after 001 the
	 client has a session worth keeping, and a numeric sent then is shown rather
	 than obeyed. The next connection is as encrypted as this one was meant to
	 be, whatever port the server named: a redirect is server-controlled input,
	 and one that could turn TLS off would hand the credentials sent at
	 registration to whoever answers in clear. A plaintext port refuses the
	 handshake, which is the right outcome for that server. */
	private func handleRedirectNumeric(_ message: Message, shouldPrint: Bool) {
		guard isLoggedIn == false else {
			if shouldPrint {
				printReply(message)
			}
			return
		}
		guard message.params.count == 4 else { return }
		let serverAddress = message.params[1]
		let serverPort = message.params[2]
		disconnectType = .serverRedirect
		guard (serverAddress as NSString).isValidInternetAddress,
		      (serverPort as NSString).isValidInternetPort,
		      let port = UInt16(serverPort)
		else {
			disconnect()
			return
		}
		/* Assign the overrides inside the callback so the redirect stays atomic: if
		 disconnect() finds nothing to close, nothing is left half-applied. */
		let endpoint = PendingIRCEndpoint(
			host: serverAddress,
			port: port,
			secured: sessionPrefersSecuredConnection,
			origin: server,
			reason: .serverRedirect
		)
		addDisconnectCallback { [weak self] in
			guard let self else { return }
			pendingEndpoint = endpoint
			connect()
		}
		disconnect()
	}

	private func handleUserModeNumeric(_ message: Message) {
		guard message.params.count > 1 else { return }
		let modeString = message.params[1]
		guard modeString != "+", shouldPrintReceivedMessage(message, withText: modeString, destinedFor: nil) else { return }
		print(
			String(localized: .IRC.yourUserModes(message.params[0], modeString)),
			by: nil,
			in: nil,
			as: .debug,
			command: message.command, receivedAt: message.receivedAt
		)
	}

	private func handleAwayNumeric(_ message: Message, shouldPrint: Bool) {
		guard message.params.count == 3 else { return }
		let nickname = message.params[1]
		let channel = findChannel(nickname) ?? output?.selectedChannel(on: self)
		if let user = findUser(nickname) {
			if monitorAwayStatus {
				modify(user) { $0.markAsAway() }
			}
			guard claimAwayMessagePresentation(for: user) else { return }
		}
		guard shouldPrint else { return }
		print(
			String(localized: .IRC.isAway(nickname, message.params[2])),
			by: nil,
			in: channel,
			as: .debug,
			command: message.command, receivedAt: message.receivedAt
		)
	}

	private func handleSilenceListNumeric(_ message: Message, shouldPrint: Bool) {
		guard message.params.count > 1 else { return }
		var entry: [String] = []
		for parameter in message.params.dropFirst() {
			if entry.isEmpty, nicknameIsMyself(parameter) {
				continue
			}
			entry.append(parameter)
		}
		guard shouldPrint, !entry.isEmpty else { return }
		printDebugInformation(String(localized: .IRC.silenceListEntry(entry.joined(separator: " "))),
		                      in: output?.selectedChannel(on: self),
		                      asCommand: message.command)
	}

	private func handleOwnAwayNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		let away = numeric == .nowaway
		userIsAway = away
		output?.updateTitle()
		if shouldPrint {
			printReply(message)
		}
		if let myself {
			modify(myself, asAway: away)
		}
	}
}

@MainActor
extension Client {
	func handleChannelNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		switch numeric {
		case .channelmodeis: handleChannelModeNumeric(message)
		case .topic: handleTopicNumeric(message)
		case .topicwhotime: handleTopicMetadataNumeric(message)
		case .creationtime: break
		case .inviting: handleInvitingNumeric(message, shouldPrint: shouldPrint)
		case .ison: handleISONNumeric(message, shouldPrint: shouldPrint)
		case .whoreply: handleWHONumeric(message, shouldPrint: shouldPrint)
		case .whospcrpl: handleWHOXNumeric(message, shouldPrint: shouldPrint)
		case .endofwho:
			let visible = requestedCommands.visibleWhoRequest
			requestedCommands.recordWhoRequestClosed()
			if visible, shouldPrint {
				printReplyToHiddenCommandResponsesQuery(message)
			}
		case .namereply: handleNamesNumeric(message, shouldPrint: shouldPrint)
		case .endofnames: handleEndOfNamesNumeric(message, shouldPrint: shouldPrint)
		case .liststart: channelListPresentation?.channelListDidStart(for: self)
		case .list: handleListNumeric(message)
		case .listend: channelListPresentation?.channelListDidFinish(for: self)
		case .banlist, .invitelist, .exceptlist, .quietlist:
			handleModeListNumeric(numeric, message: message, shouldPrint: shouldPrint)
		case .endofbanlist, .endofinvitelist, .endofexceptlist, .endofquietlist:
			handleEndOfModeListNumeric(numeric, message: message, shouldPrint: shouldPrint)
		default: break
		}
	}

	private func handleChannelModeNumeric(_ message: Message) {
		guard message.params.count > 2 else { return }
		let modeString = message.sequence(2)
		guard modeString != "+", let channel = findChannel(message.params[1]) else { return }
		if channel.isActive {
			channel.modeInfo?.clear()
			_ = channel.modeInfo?.updateModes(modeString)
		}
		let shouldPrint = shouldPrintReceivedMessage(message, withText: modeString, destinedFor: channel)
		channel.channelModesReceived = true
		if shouldPrint {
			print(
				String(localized: .IRC.miscellaneousMessagesRelatedMode(channel.modeInfo?.stringWithMaskedPassword ?? modeString)),
				by: nil,
				in: channel, as: .mode, command: message.command, receivedAt: message.receivedAt
			)
		}
	}

	private func handleTopicNumeric(_ message: Message) {
		guard message.params.count == 3, let channel = findChannel(message.params[1]) else { return }
		let topic = message.params[2]
		let shouldPrint = shouldPrintReceivedMessage(message, withText: topic, destinedFor: channel)
		channel.topic = topic
		if shouldPrint {
			print(String(localized: .IRC.miscellaneousMessagesRelatedTopic(topic)), by: nil, in: channel, as: .topic,
			      command: message.command, receivedAt: message.receivedAt)
		}
	}

	private func handleTopicMetadataNumeric(_ message: Message) {
		guard message.params.count == 4, let channel = findChannel(message.params[1]),
		      shouldPrintReceivedMessage(message, withText: nil, destinedFor: channel)
		else { return }
		let setter = (message.params[2] as NSString).nicknameFromHostmask
		/* An unreadable timestamp leaves the date out rather than claiming the
		 topic was set in 1970. */
		let date = ircWireTimestampDate(from: message.params[3])
		print(
			String(localized: .IRC.miscellaneousMessagesRelatedSet(
				setter,
				date.flatMap { DateFormatting.formatted($0, dateStyle: .long, timeStyle: .long, relative: true) } ?? ""
			)),
			by: nil,
			in: channel,
			as: .topic, command: message.command, receivedAt: message.receivedAt
		)
	}

	private func handleInvitingNumeric(_ message: Message, shouldPrint: Bool) {
		guard shouldPrint, message.params.count == 3, let channel = findChannel(message.params[2]) else { return }
		print(
			String(localized: .IRC.invitingToJoin(message.params[1], channel.name)),
			by: nil,
			in: channel,
			as: .debug,
			command: message.command, receivedAt: message.receivedAt
		)
	}

	/** Reconciles presence with one `RPL_ISON`.

	 The reply names who is online among the nicknames its own command asked
	 about, and says nothing about anyone else: a poll longer than one command
	 draws one reply per command. Only those nicknames are reconciled. */
	private func handleISONNumeric(_ message: Message, shouldPrint: Bool) {
		let visible = requestedCommands.visibleIsonRequest
		let asked = Set(requestedCommands.recordIsonRequestClosed().map(casefoldNickname))
		if visible {
			if shouldPrint {
				printReplyToHiddenCommandResponsesQuery(message)
			}
			return
		}
		let online = LineParser.wireTokens(in: message.sequence)
		let tracked = supportsAdvancedTracking ? [:] : trackedUsers.trackedUsers
		let foldedOnline = Set(online.map(casefoldNickname))
		for (nickname, previousValue) in tracked where asked.contains(casefoldNickname(nickname)) {
			let isOnline = foldedOnline.contains(casefoldNickname(nickname))
			let status: AddressBookUserTrackingStatus = if previousValue, !isOnline,
			                                               !invokingISONCommandForFirstTime
			{
				.signedOff
			} else if !previousValue, isOnline {
				invokingISONCommandForFirstTime ? .available : .signedOn
			} else {
				.unknown
			}
			if status != .unknown {
				setTrackedNickname(nickname, status: status, notify: true)
			}
		}
		/* The first poll is every command it sent, not just the first reply. */
		if requestedCommands.hasOpenIsonRequest == false {
			invokingISONCommandForFirstTime = false
		}
		for channel in channelList where channel.isPrivateMessage {
			let foldedName = casefoldNickname(channel.name)
			guard asked.contains(foldedName) else { continue }
			applyPresence(foldedOnline.contains(foldedName), to: channel)
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
		receiveWhoReply(in: channel, reply: WHOReply(
			nickname: message.params[5], username: message.params[2], address: message.params[3],
			flags: message.params[6], realName: realName, account: nil, updatesAccount: false
		))
	}

	private func handleWHOXNumeric(_ message: Message, shouldPrint: Bool) {
		guard message.params.count >= 9 else { return }
		guard message.params[1] == ServerQuirks.whoxToken, !requestedCommands.visibleWhoRequest else {
			if shouldPrint {
				printReplyToHiddenCommandResponsesQuery(message)
			}
			return
		}
		guard let channel = findChannel(message.params[2]) else { return }
		receiveWhoReply(in: channel, reply: WHOReply(
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
		channel.withMemberPresentationUpdates {
			for rawName in LineParser.wireTokens(in: message.params[3]) {
				addName(rawName, to: channel)
			}
		}
	}

	private func addName(_ rawName: String, to channel: Channel) {
		var modes = ""
		var nameStart = rawName.startIndex
		while nameStart < rawName.endIndex,
		      let mode = supportInfo.modeSymbol(forUserPrefix: String(rawName[nameStart]))
		{
			modes += mode
			nameStart = rawName.index(after: nameStart)
		}
		/* The prefixes arrive in the server's rank order, so the set built from
		 them is already ordered. */
		let hostmask = String(rawName[nameStart...])

		/* A token that is nothing but prefix characters names nobody. Taking it
		 anyway added a member and a directory user under the empty nickname,
		 which every later lookup then matched by accident. */
		guard hostmask.isEmpty == false else { return }

		let parsed = (hostmask as NSString).hostmask(on: self)
		let nickname = parsed?.nickname ?? hostmask
		let user: User
		if let existing = findUser(nickname) {
			user = existing
		} else {
			var newUser = User(nickname: nickname)
			newUser.username = parsed?.username
			newUser.address = parsed?.address
			user = addAndReturn(newUser)
		}
		/* The NAMES reply is the server's own list, so its prefixes are the
		 truth about every name in it — including one the client already holds a
		 member for. Keeping the member and dropping its prefixes left an
		 operator unmarked whenever the reply arrived after the JOIN did. */
		var editedMember = userAssociated(user, with: channel)
			?? ChannelUser(user: user, prefixes: currentUserPrefixes)
		editedMember.prefixes = currentUserPrefixes
		editedMember.modes = ChannelModeSymbolSet(letters: modes)
		channel.memberInfo?.addMember(editedMember)
	}

	private func handleEndOfNamesNumeric(_ message: Message, shouldPrint: Bool) {
		guard message.params.count == 3 else { return }
		if shouldPrint {
			printReplyToHiddenCommandResponsesQuery(message)
		}
		guard let channel = findChannel(message.params[1]), !channel.channelNamesReceived else { return }
		channel.channelNamesReceived = true
		sendInitialWhoRequest(to: channel)
		if channel.numberOfMembers == 1, !isBrokenIRCdKnownAsTwitch {
			if let defaultModes = channel.config.defaultModes, !defaultModes.isEmpty {
				sendModes(defaultModes, withParametersString: nil, inChannelNamed: channel.name)
			}
			if let defaultTopic = channel.config.defaultTopic, !defaultTopic.isEmpty {
				sendTopic(to: defaultTopic, in: channel)
			}
		}
		output?.updateTitle(for: channel)
	}

	private func handleListNumeric(_ message: Message) {
		guard message.params.count > 2, message.params[1] != "*" else { return }
		channelListPresentation?.channelListDidReceive(
			channelNamed: message.params[1],
			memberCount: UInt(message.params[2]) ?? 0,
			topic: message.sequence(3),
			for: self
		)
	}

	private func handleModeListNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		guard message.params.count > 2 else { return }
		/* RPL_QUIETLIST (728) writes the mode letter between the channel and the
		 mask, and nothing else does. The letter itself is what says the field is
		 there: counting parameters misreads a 728 that omits the setter and
		 timestamp, and one that carries an extra field. */
		let hasModeLetterField = numeric == .quietlist &&
			message.params.count > 3 && (message.params[2] as NSString).isModeSymbol
		let offset = hasModeLetterField ? 1 : 0
		let mask = message.params[2 + offset]
		let extended = message.params.count > 4 + offset
		let author = extended ? (message.params[3 + offset] as NSString).nicknameFromHostmask : nil
		/* An unreadable timestamp drops the "set by" clause rather than dating
		 the entry to 1970. */
		let date = extended ? ircWireTimestampDate(from: message.params[4 + offset]) : nil
		let channelName = message.params[1]
		let took = output?.accessListEntryReceived(
			for: self,
			inChannelNamed: channelName,
			modeSymbol: hasModeLetterField ? message.params[2] : accessListModeSymbol(forNumeric: numeric),
			mask: mask,
			setBy: author,
			creationDate: date
		)
		if took == true {
			return
		}
		guard shouldPrint else { return }
		let text = ChannelBanListKind(numeric: numeric).entryText(
			channelName: channelName,
			mask: mask,
			setBy: author,
			date: date.flatMap { DateFormatting.formatted($0, dateStyle: .long, timeStyle: .long, relative: true) }
		)
		print(text, by: nil, in: nil, as: .debug, command: message.command, receivedAt: message.receivedAt)
	}

	private func handleEndOfModeListNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		/* RPL_ENDOFQUIETLIST writes the mode letter between the channel and the
		 explanatory text, the way its RPL_QUIETLIST siblings do. */
		let hasModeLetterField = numeric == .endofquietlist &&
			message.params.count > 3 && (message.params[2] as NSString).isModeSymbol
		let took = message.params.count > 1
			? output?.accessListFinished(
				for: self,
				inChannelNamed: message.params[1],
				modeSymbol: hasModeLetterField ? message.params[2] : accessListModeSymbol(forNumeric: numeric)
			)
			: nil
		if took != true, shouldPrint {
			printReply(message)
		}
	}

	/** The mode letter the list a numeric belongs to is kept under.

	 Only the quiet numerics write the letter on the wire; for the rest it is
	 what ISUPPORT says, which is also what the window showing the list asked
	 for. `EXCEPTS` and `INVEX` may name a letter other than `e` and `I`, so the
	 letter is read from the same place the window read it rather than assumed.
	 An unadvertised list has no letter, and an entry for one belongs to no
	 window. */
	private func accessListModeSymbol(forNumeric numeric: ServerNumeric) -> String {
		supportInfo.modeSymbol(forList: ChannelBanListKind(numeric: numeric).supportListType) ?? ""
	}
}

private enum ServerNumericErrorGroup {
	static let missingTarget: Set<ServerNumeric> = [.nosuchserver, .nosuchchannel]
	static let nicknameCollision: Set<ServerNumeric> = [.nicknameinuse, .erroneusnickname]
	static let joinFailure: Set<ServerNumeric> = [
		.admonly, .badchanmask, .badchanname, .badchannel, .badchannelkey, .bannedfromchan,
		.channelisfull, .delayrejoin, .forbiddenchannel, .inviteonlychan, .linkchannel,
		.needreggednick, .nohiding, .operonly, .operspverify, .secureonlychan, .throttle,
		.toomanychannels, .toomanyjoins,
	]
	static let whoFailure: Set<ServerNumeric> = [.whosyntax, .wholimexceed]
	static let commandFailure: Set<ServerNumeric> = [.disabled, .unknowncommand, .needmoreparams]
}

@MainActor
extension Client {
	func receiveErrorNumericReply(_ message: Message) {
		let shouldPrint = shouldPrintReceivedMessage(message)

		/* Servers send error numerics this catalog has no case for, and those
		 print the way any other error does. */
		guard let numeric = ServerNumeric(rawValue: message.commandNumeric) else {
			if shouldPrint {
				printErrorReply(message)
			}

			return
		}

		if numeric == .nosuchnick || numeric == .cannotsendtochan {
			guard shouldPrint else { return }
			printError(message, inTargetChannelNamed: message.param(at: 1))
			return
		}
		if handleJoinFailure(message, numeric: numeric, shouldPrint: shouldPrint) {
			return
		}
		if ServerNumericErrorGroup.missingTarget.contains(numeric) {
			if shouldPrint {
				printErrorReply(message)
			}
			return
		}
		if handleNicknameError(message, numeric: numeric, shouldPrint: shouldPrint) {
			return
		}
		if ServerNumericErrorGroup.whoFailure.contains(numeric) {
			requestedCommands.recordWhoRequestClosed()
			if shouldPrint {
				printErrorReply(message)
			}
			return
		}
		if ServerNumericErrorGroup.commandFailure.contains(numeric) {
			switch message.param(at: 1) {
			case "ISON": requestedCommands.recordIsonRequestClosed()
			case "WHO": requestedCommands.recordWhoRequestClosed()
			/* A refused LIST sends no RPL_LISTEND, and a list left waiting for
			 one spins with its Refresh button disabled. */
			case "LIST": channelListPresentation?.channelListDidFinish(for: self)
			default: break
			}
		}
		if shouldPrint {
			printErrorReply(message)
		}
	}
}

@MainActor
private extension Client {
	func handleNicknameError(_ message: Message, numeric: ServerNumeric, shouldPrint: Bool) -> Bool {
		let isNicknameCollision = ServerNumericErrorGroup.nicknameCollision.contains(numeric)
		let isUnavailableResource = numeric == .unavailresource
		guard isNicknameCollision || isUnavailableResource else { return false }

		let unavailableTargetIsNickname = isUnavailableResource && stringIsNickname(message.param(at: 1))
		if isLoggedIn || (isUnavailableResource && unavailableTargetIsNickname == false) {
			if shouldPrint {
				printErrorReply(message)
			}
		} else {
			receiveNicknameCollisionError(message)
		}
		return true
	}

	func handleJoinFailure(_ message: Message, numeric: ServerNumeric, shouldPrint: Bool) -> Bool {
		let target = message.param(at: 1)
		let channel = findChannel(target)
		let isPendingJoin = channel?.isChannel == true && channel?.status == .joining && stringIsChannelName(target)
		let isUnavailableChannel = numeric == .nosuchchannel || numeric == .unavailresource
		guard ServerNumericErrorGroup.joinFailure.contains(numeric) || (isUnavailableChannel && isPendingJoin)
		else { return false }
		if let channel {
			// 477 can also reject MODE; only a pending JOIN owns this failure.
			if isPendingJoin, !message.isPrintOnlyMessage {
				channel.status = .parted
				channel.errorOnLastJoinAttempt = true
				output?.reloadChatItem(channel)
				output?.updateTitle(for: channel)
			}
			if shouldPrint {
				printErrorReply(message, in: channel, withSequence: 2)
			}
		} else if shouldPrint {
			printErrorReply(message)
		}
		return true
	}

	func printError(_ message: Message, inTargetChannelNamed channelName: String) {
		if let channel = findChannel(channelName) {
			printErrorReply(message, in: channel, withSequence: 2)
		} else {
			printErrorReply(message)
		}
	}
}

@MainActor
extension Client {
	func handlePresenceTrackingNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		switch numeric {
		case .youreoper:
			guard !userIsIRCop else { return }
			userIsIRCop = true
			if shouldPrint {
				print(
					String(localized: .IRC.youAreNowAnIrcOperator(message.senderNickname ?? "")),
					by: nil,
					in: nil,
					as: .debug,
					command: message.command, receivedAt: message.receivedAt
				)
			}
		case .channelUrl:
			guard shouldPrint, message.params.count == 3,
			      let channel = findChannel(message.params[1]) else { return }
			print(
				String(localized: .IRC.miscellaneousMessagesRelatedWebsite(message.params[2])),
				by: nil,
				in: channel,
				as: .website,
				command: message.command, receivedAt: message.receivedAt
			)
		case .watchstat, .watchlist, .watchoff, .endofwatchlist, .monlist, .endofmonlist:
			if shouldPrint {
				printReplyToHiddenCommandResponsesQuery(message)
			}
		case .reaway, .goneaway, .notaway:
			handleTrackedAwayNumeric(numeric, message: message, shouldPrint: shouldPrint)
		case .logon, .logoff, .nowon, .nowoff:
			handleTrackedStatusNumeric(numeric, message: message, shouldPrint: shouldPrint)
		case .monlistfull:
			if shouldPrint {
				printErrorReply(message)
			}
		case .mononline, .monoffline:
			handleMonitorStatusNumeric(numeric, message: message, shouldPrint: shouldPrint)
		case .targumodeg:
			/* RPL_TARGUMODEG: the message went nowhere because the recipient is
			 in +g. Swallowing it left the user believing it had arrived. */
			if shouldPrint {
				printReply(message)
			}
		default:
			break
		}
	}

	func handleAuthenticationTrackingNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		switch numeric {
		case .targnotify:
			if shouldPrint, message.params.count == 3 {
				printDebugInformation(String(localized: .IRC.youCannotSendPrivateMessages(message.params[1])))
			}
		case .umodegmsg: handleUserModeMessageNumeric(message, shouldPrint: shouldPrint)
		case .loggedin:
			guard message.params.count == 4, message.senderIsServer,
			      nicknameIsMyself(message.params[0]), message.params[2] != "*",
			      !message.params[2].isEmpty else { return }
			guard scramMutualAuthenticationIsSatisfied() else {
				abortUnverifiedSASLSuccess()
				return
			}
			noteAccountAuthenticated()
			if shouldPrint {
				printNumericSequence(message, startingAt: 3)
			}
		case .loggedout:
			guard message.params.count == 3 else { return }
			resetSASLNegotiation()
			if startup.authentication == .confirmed {
				startup.authentication = .pending
			}
			userIsIdentifiedWithNickServ = false
			if shouldPrint {
				printNumericSequence(message, startingAt: 2)
			}
		case .saslmechs: handleSASLMechanismsNumeric(message, shouldPrint: shouldPrint)
		case .saslsuccess, .nicklocked, .saslfail, .sasltoolong, .saslaborted, .saslalready:
			handleSASLResultNumeric(numeric, message: message, shouldPrint: shouldPrint)
		default: break
		}
	}

	private func handleTrackedAwayNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		guard message.params.count > 4 else { return }
		if shouldPrint {
			printReplyToHiddenCommandResponsesQuery(message)
		}
		let nickname = message.params[1]
		guard findUserTrackingAddressBookEntry(forNickname: nickname) != nil else { return }
		modifyUser(withNickname: nickname, asAway: numeric != .notaway)
	}

	private func handleTrackedStatusNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		guard message.params.count > 4 else { return }
		if shouldPrint {
			printReplyToHiddenCommandResponsesQuery(message)
		}
		let nickname = message.params[1]
		let isOnline = numeric == .logon || numeric == .nowon
		applyPresence(isOnline, toQueryWith: nickname)
		guard findUserTrackingAddressBookEntry(forNickname: nickname) != nil else { return }
		let status: AddressBookUserTrackingStatus
		let notify: Bool
		switch numeric {
		case .logon: status = .signedOn; notify = true
		case .logoff: status = .signedOff; notify = true
		case .nowon: status = .available; notify = false
		default: status = .notAvailable; notify = false
		}
		setTrackedNickname(nickname, status: status, notify: notify)
	}

	private func handleMonitorStatusNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		guard message.params.count == 2 else { return }
		if shouldPrint {
			printReplyToHiddenCommandResponsesQuery(message)
		}
		let isOnline = numeric == .mononline
		for changedUser in message.params[1].components(separatedBy: ",") {
			let nickname = (changedUser as NSString).nicknameFromHostmask
			applyPresence(isOnline, toQueryWith: nickname)
			guard findUserTrackingAddressBookEntry(forNickname: nickname) != nil else { continue }
			setTrackedNickname(nickname, status: isOnline ? .signedOn : .signedOff, notify: true)
		}
	}

	private func handleUserModeMessageNumeric(_ message: Message, shouldPrint: Bool) {
		guard shouldPrint, message.params.count == 4 else { return }
		let text = String(localized: .IRC.triedToSendYouAPrivate(message.params[1], message.params[2]))
		if environment.preferences.locationToSendNotices == .selectedChannel,
		   let channel = output?.selectedChannel(on: self)
		{
			printDebugInformation(text, in: channel)
		} else {
			printDebugInformation(toConsole: text)
		}
	}

	/** `RPL_SASLMECHS`: the mechanisms the server would have taken.

	 The server sends this when it refuses the mechanism the client named, and
	 follows it with `ERR_SASLFAIL`. The failure is what moves the exchange on
	 to the next mechanism; this only narrows what that next one may be. Moving
	 on here as well sent the retry ahead of the 904 that belonged to the
	 refused attempt, and the 904 then ended the retry before it began. */
	private func handleSASLMechanismsNumeric(_ message: Message, shouldPrint: Bool) {
		if shouldPrint {
			printErrorReply(message)
		}
		guard isCapabilityEnabled(.isInSASLNegotiation), message.params.count >= 2 else { return }
		let mechanisms = message.params[1]
			.components(separatedBy: CharacterSet(charactersIn: ", "))
			.filter { !$0.isEmpty }
		guard !mechanisms.isEmpty else { return }
		sasl.offeredMechanisms = mechanisms
	}

	/// The numerics that mean the server refused this SASL attempt, as opposed
	/// to 903 (success) or 907 (already authenticated).
	private static let saslFailureNumerics: Set<ServerNumeric> = [.nicklocked, .saslfail, .sasltoolong, .saslaborted]

	private func handleSASLResultNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		if shouldPrint {
			if numeric == .saslsuccess {
				printReply(message)
			} else {
				printErrorReply(message)
			}
		}
		guard isCapabilityEnabled(.isInSASLNegotiation) else { return }
		let failed = Self.saslFailureNumerics.contains(numeric)
		/* 904 is a refused attempt, not a refused login: a certificate the
		 account does not know fails EXTERNAL while the password would still
		 pass SCRAM. The exchange ends only once every mechanism both sides
		 speak has been tried. The other failures are about the account or the
		 exchange itself, and another mechanism would not change them. */
		if numeric == .saslfail, retrySASLNegotiation(withMechanisms: []) {
			return
		}
		if !failed, scramMutualAuthenticationIsSatisfied() == false {
			abortUnverifiedSASLSuccess()
			return
		}
		if !failed {
			enableCapability(.isIdentifiedWithSASL)
			noteAccountAuthenticated()
		}
		finishSASLNegotiation(failed: failed)
	}

	private func printNumericSequence(_ message: Message, startingAt index: UInt) {
		print(message.sequence(index), by: nil, in: nil, as: .debug, command: message.command,
		      receivedAt: message.receivedAt)
	}
}

@MainActor
extension Client {
	func handleWhoisNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		let selectedChannel = output?.selectedChannel(on: self)
		switch numeric {
		case .whoisbot:
			handleWhoisBot(message, shouldPrint: shouldPrint, channel: selectedChannel)
		case .channelsmsg, .whoishelpop, .whoishost, .whoismodes,
		     .whoisoperator, .whoisrealip, .whoisregnick, .whoissecure, .whoisspecial:
			if shouldPrint, message.params.count > 2 {
				printReply(message, in: selectedChannel)
			}
		case .whoisactually:
			handleWhoisActually(message, shouldPrint: shouldPrint, channel: selectedChannel)
		case .whoisuser, .whowasuser:
			handleWhoisUser(numeric, message: message, shouldPrint: shouldPrint, channel: selectedChannel)
		case .whoisserver:
			handleWhoisServer(message, shouldPrint: shouldPrint, channel: selectedChannel)
		case .whoisidle:
			handleWhoisIdle(message, shouldPrint: shouldPrint, channel: selectedChannel)
		case .whoischannels:
			guard shouldPrint, message.params.count == 3 else { return }
			printWhoisLine(
				String(localized: .IRC.miscellaneousMessagesRelatedIs(message.params[1], message.params[2])),
				message: message, channel: selectedChannel
			)
		case .whoisaccount:
			guard shouldPrint, message.params.count == 4 else { return }
			printWhoisLine("\(message.params[1]) \(message.sequence(3)) \(message.params[2])",
			               message: message, channel: selectedChannel)
		case .endofwhois:
			inWhoisResponse = false
		case .endofwhowas:
			inWhowasResponse = false
		default:
			break
		}
	}

	/** RPL_WHOISACTUALLY (338), which no specification pins down.

	 ircu and Hybrid send `<me> <nick> <user@host> <ip> :is actually using host`,
	 which is the five-parameter form below. InspIRCd and Charybdis send
	 `<me> <nick> <ip> :is actually using host` instead, and swallowing that one
	 as handled printed nothing at all: the generic reply printer spells it out
	 the way the server wrote it. */
	private func handleWhoisActually(_ message: Message, shouldPrint: Bool, channel: Channel?) {
		guard shouldPrint else { return }

		if message.params.count == 5 {
			printWhoisLine(
				whoisConnectionText(
					nickname: message.params[1],
					address: message.params[2],
					realName: message.params[3],
					isHistorical: inWhowasResponse
				),
				message: message, channel: channel
			)
			return
		}

		guard message.params.count > 2 else { return }

		printReply(message, in: channel)
	}

	private func handleWhoisBot(_ message: Message, shouldPrint: Bool, channel: Channel?) {
		guard message.params.count > 1 else { return }
		let nickname = message.params[1]
		modifyUser(withNickname: nickname) { $0.isBot = true }
		guard shouldPrint else { return }
		if message.params.count > 2 {
			printReply(message, in: channel)
		} else {
			print(
				String(localized: .IRC.isABot(nickname)),
				by: nil,
				in: channel,
				as: .debug,
				command: message.command,
				receivedAt: message.receivedAt
			)
		}
	}

	private func handleWhoisServer(_ message: Message, shouldPrint: Bool, channel: Channel?) {
		guard shouldPrint, message.params.count == 4 else { return }
		let serverInfo = message.params[3]
		let text = if inWhowasResponse {
			String(localized: .IRC.wasConnected(
				message.params[1],
				message.params[2],
				DateFormatting.formatted(serverText: serverInfo, dateStyle: .long, timeStyle: .long, relative: true) ?? serverInfo
			))
		} else {
			String(localized: .IRC.miscellaneousMessagesRelatedIsConnected(message.params[1], message.params[2], serverInfo))
		}
		printWhoisLine(text, message: message, channel: channel)
	}

	private func handleWhoisIdle(_ message: Message, shouldPrint: Bool, channel: Channel?) {
		guard shouldPrint, message.params.count >= 4 else { return }
		let idle = DateFormatting.humanReadable(TimeInterval(message.params[2]) ?? 0, shortValue: false)
		/* An unreadable sign-on timestamp leaves the date out rather than
		 reporting that the person connected in 1970. */
		let connected = ircWireTimestampDate(from: message.params[3])
			.flatMap { DateFormatting.formatted($0, dateStyle: .long, timeStyle: .long, relative: true) } ?? ""
		printWhoisLine(
			String(localized: .IRC.signedOnAtAndHasBeen(message.params[1], connected, idle)),
			message: message,
			channel: channel
		)
	}

	private func handleWhoisUser(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool, channel: Channel?) {
		guard message.params.count >= 6 else { return }
		let nickname = message.params[1]
		let username = message.params[2]
		let address = message.params[3]
		let realName = String(message.params[5].drop(while: { $0 == ":" }))
		inWhoisResponse = numeric == .whoisuser
		inWhowasResponse = numeric == .whowasuser
		if !inWhowasResponse, nicknameIsMyself(nickname) {
			userHostmask = "\(nickname)!\(username)@\(address)"
		}
		guard shouldPrint else { return }
		let text = whoisUserhostText(
			nickname: nickname,
			username: username,
			address: address,
			realName: realName,
			isHistorical: inWhowasResponse
		)
		printWhoisLine(text, message: message, channel: channel)
	}

	private func printWhoisLine(_ text: String, message: Message, channel: Channel?) {
		print(text, by: nil, in: channel, as: .debug, command: message.command, receivedAt: message.receivedAt)
	}
}
