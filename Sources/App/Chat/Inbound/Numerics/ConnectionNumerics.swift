// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

@MainActor
extension ServerSession {
	func handleConnectionNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		switch numeric {
		case .welcome:
			receiveInit(message)
			if shouldPrint {
				printReply(message)
			}
		case .yourhost, .created, .myinfo, .statsconn,
		     .lusersession, .luserhop, .luserunknown, .luserchannels, .luserme:
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
			guard shouldPrint, environment.settings.displayServerMOTD else { return }
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
				                      in: output?.selectedConversation(on: self),
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
		apply(supportInfo.processConfigurationData(configuration))
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
		 no session to ask off the main actor. A 005 that changes `PREFIX` or
		 `CASEMAPPING` therefore changes how every member already in a channel
		 ranks and marks itself, and until now only a settings reload ever
		 re-stamped them: the ranks stayed on the table that was current when
		 each member joined, and the member list stayed in an order built from
		 it. Servers do send a second 005 — a bouncer replays the network's on
		 attach, and services reload theirs — so this is not hypothetical. */
		let prefixes = currentUserPrefixes
		let prefixesChanged = prefixes.modeSymbols != previousPrefixes.modeSymbols ||
			prefixes.prefixCharacters != previousPrefixes.prefixCharacters
		if caseMappingChanged || prefixesChanged {
			for channel in conversationList where channel.isChannel {
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
	 session has a session worth keeping, and a numeric sent then is shown rather
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
		guard serverAddress.isValidInternetAddress,
		      serverPort.isValidInternetPort,
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
		let destination = findConversation(nickname) ?? output?.selectedConversation(on: self)
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
			in: destination,
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
		                      in: output?.selectedConversation(on: self),
		                      asCommand: message.command)
	}

	private func handleOwnAwayNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		let isAway = numeric == .nowaway
		away.isAway = isAway
		output?.updateTitle()
		if shouldPrint {
			printReply(message)
		}
		if let myself {
			modify(myself, asAway: isAway)
		}
	}
}
