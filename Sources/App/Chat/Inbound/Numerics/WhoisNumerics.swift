// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** How a WHOIS or WHOWAS line reads.

 WHOWAS answers with the same fields about a connection that has already
 ended, so the two differ only in tense. */
private func whoisConnectionText(
	nickname: String,
	address: String,
	realName: String,
	fromWhowas: Bool
) -> String {
	if fromWhowas {
		return String(localized: .IRC.miscellaneousMessagesRelatedWasConnected(nickname, address, realName))
	}

	return String(localized: .IRC.isConnected(nickname, address, realName))
}

private func whoisUserhostText(
	nickname: String,
	username: String,
	address: String,
	realName: String,
	fromWhowas: Bool
) -> String {
	if fromWhowas {
		return String(localized: .IRC.hadUserhostAndRealName(nickname, username, address, realName))
	}

	return String(localized: .IRC.hasUserhostAndRealName(nickname, username, address, realName))
}

@MainActor
extension ServerSession {
	func handleWhoisNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		let selectedConversation = output?.selectedConversation(on: self)
		switch numeric {
		case .whoisbot:
			handleWhoisBot(message, shouldPrint: shouldPrint, in: selectedConversation)
		case .channelsmsg, .whoishelpop, .whoishost, .whoismodes,
		     .whoisoperator, .whoisrealip, .whoisregnick, .whoissecure, .whoisspecial:
			if shouldPrint, message.params.count > 2 {
				printReply(message, in: selectedConversation)
			}
		case .whoisactually:
			handleWhoisActually(message, shouldPrint: shouldPrint, in: selectedConversation)
		case .whoisuser, .whowasuser:
			handleWhoisUser(numeric, message: message, shouldPrint: shouldPrint, in: selectedConversation)
		case .whoisserver:
			handleWhoisServer(message, shouldPrint: shouldPrint, in: selectedConversation)
		case .whoisidle:
			handleWhoisIdle(message, shouldPrint: shouldPrint, in: selectedConversation)
		case .whoischannels:
			guard shouldPrint, message.params.count == 3 else { return }
			printWhoisLine(
				String(localized: .IRC.miscellaneousMessagesRelatedIs(message.params[1], message.params[2])),
				message: message, in: selectedConversation
			)
		case .whoisaccount:
			guard shouldPrint, message.params.count == 4 else { return }
			printWhoisLine("\(message.params[1]) \(message.sequence(3)) \(message.params[2])",
			               message: message, in: selectedConversation)
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
	private func handleWhoisActually(_ message: Message, shouldPrint: Bool, in conversation: Conversation?) {
		guard shouldPrint else { return }

		if message.params.count == 5 {
			printWhoisLine(
				whoisConnectionText(
					nickname: message.params[1],
					address: message.params[2],
					realName: message.params[3],
					fromWhowas: inWhowasResponse
				),
				message: message, in: conversation
			)
			return
		}

		guard message.params.count > 2 else { return }

		printReply(message, in: conversation)
	}

	private func handleWhoisBot(_ message: Message, shouldPrint: Bool, in conversation: Conversation?) {
		guard message.params.count > 1 else { return }
		let nickname = message.params[1]
		modifyUser(withNickname: nickname) { $0.isBot = true }
		guard shouldPrint else { return }
		if message.params.count > 2 {
			printReply(message, in: conversation)
		} else {
			print(
				String(localized: .IRC.isABot(nickname)),
				by: nil,
				in: conversation,
				as: .debug,
				command: message.command,
				receivedAt: message.receivedAt
			)
		}
	}

	private func handleWhoisServer(_ message: Message, shouldPrint: Bool, in conversation: Conversation?) {
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
		printWhoisLine(text, message: message, in: conversation)
	}

	private func handleWhoisIdle(_ message: Message, shouldPrint: Bool, in conversation: Conversation?) {
		guard shouldPrint, message.params.count >= 4 else { return }
		let idle = DateFormatting.humanReadable(TimeInterval(message.params[2]) ?? 0, shortValue: false)
		/* An unreadable sign-on timestamp leaves the date out rather than
		 reporting that the person connected in 1970. */
		let connected = ircWireTimestampDate(from: message.params[3])
			.flatMap { DateFormatting.formatted($0, dateStyle: .long, timeStyle: .long, relative: true) } ?? ""
		printWhoisLine(
			String(localized: .IRC.signedOnAtAndHasBeen(message.params[1], connected, idle)),
			message: message,
			in: conversation
		)
	}

	private func handleWhoisUser(
		_ numeric: ServerNumeric,
		message: Message,
		shouldPrint: Bool,
		in conversation: Conversation?
	) {
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
			fromWhowas: inWhowasResponse
		)
		printWhoisLine(text, message: message, in: conversation)
	}

	private func printWhoisLine(_ text: String, message: Message, in conversation: Conversation?) {
		print(text, by: nil, in: conversation, as: .debug, command: message.command, receivedAt: message.receivedAt)
	}
}
