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

@MainActor
extension IRCClient {
	func handleWhoisNumeric(_ numeric: UInt, message: Message, shouldPrint: Bool) -> Bool {
		let selectedChannel = AppController.shared.mainWindow.selectedChannel(on: self)
		switch numeric {
		case IRCNumeric.whoisbot.rawValue:
			handleWhoisBot(message, shouldPrint: shouldPrint, channel: selectedChannel)
		case IRCNumeric.channelsmsg.rawValue, IRCNumeric.whoishelpop.rawValue, IRCNumeric.whoishost.rawValue,
		     IRCNumeric.whoismodes.rawValue,
		     IRCNumeric.whoisoperator.rawValue, IRCNumeric.whoisrealip.rawValue, IRCNumeric.whoisregnick.rawValue,
		     IRCNumeric.whoissecure.rawValue, IRCNumeric.whoisspecial.rawValue:
			if shouldPrint, message.params.count > 2 {
				printReply(message, in: selectedChannel)
			}
		case IRCNumeric.whoisactually.rawValue:
			guard shouldPrint, message.params.count == 5 else { return true }
			printWhoisLine(
				IRCInboundStrings.Whois.connection(
					nickname: message.params[1],
					address: message.params[2],
					realName: message.params[3],
					isHistorical: inWhowasResponse
				),
				message: message, channel: selectedChannel
			)
		case IRCNumeric.whoisuser.rawValue, IRCNumeric.whowasuser.rawValue:
			handleWhoisUser(numeric, message: message, shouldPrint: shouldPrint, channel: selectedChannel)
		case IRCNumeric.whoisserver.rawValue:
			handleWhoisServer(message, shouldPrint: shouldPrint, channel: selectedChannel)
		case IRCNumeric.whoisidle.rawValue:
			handleWhoisIdle(message, shouldPrint: shouldPrint, channel: selectedChannel)
		case IRCNumeric.whoischannels.rawValue:
			guard shouldPrint, message.params.count == 3 else { return true }
			printWhoisLine(
				IRCInboundStrings.Whois.channels(nickname: message.params[1], channels: message.params[2]),
				message: message, channel: selectedChannel
			)
		case IRCNumeric.whoisaccount.rawValue:
			guard shouldPrint, message.params.count == 4 else { return true }
			printWhoisLine("\(message.params[1]) \(message.sequence(3)) \(message.params[2])",
			               message: message, channel: selectedChannel)
		case IRCNumeric.endofwhois.rawValue:
			inWhoisResponse = false
		case IRCNumeric.endofwhowas.rawValue:
			inWhowasResponse = false
		default:
			return false
		}
		return true
	}

	private func handleWhoisBot(_ message: Message, shouldPrint: Bool, channel: IRCChannel?) {
		guard message.params.count > 1 else { return }
		let nickname = message.params[1]
		modifyUser(withNickname: nickname) { $0.isBot = true }
		guard shouldPrint else { return }
		if message.params.count > 2 {
			printReply(message, in: channel)
		} else {
			print(
				IRCInboundStrings.Whois.bot(nickname: nickname),
				by: nil,
				in: channel,
				as: .debug,
				command: message.command,
				receivedAt: message.receivedAt
			)
		}
	}

	private func handleWhoisServer(_ message: Message, shouldPrint: Bool, channel: IRCChannel?) {
		guard shouldPrint, message.params.count == 4 else { return }
		let serverInfo = message.params[3]
		let text = if inWhowasResponse {
			IRCInboundStrings.Whois.connectedAt(
				nickname: message.params[1],
				server: message.params[2],
				date: formatDateLongStyle(serverInfo, true) ?? serverInfo
			)
		} else {
			IRCInboundStrings.Whois.server(
				nickname: message.params[1],
				server: message.params[2],
				information: serverInfo
			)
		}
		printWhoisLine(text, message: message, channel: channel)
	}

	private func handleWhoisIdle(_ message: Message, shouldPrint: Bool, channel: IRCChannel?) {
		guard shouldPrint, message.params.count >= 4 else { return }
		let idle = humanReadableTimeInterval(TimeInterval(message.params[2]) ?? 0, false, 0) as String? ?? ""
		let connected = formatDateLongStyle(
			Date(timeIntervalSince1970: TimeInterval(message.params[3]) ?? 0),
			true
		) ?? ""
		printWhoisLine(
			IRCInboundStrings.Whois.signOnAndIdle(
				nickname: message.params[1],
				connected: connected,
				idle: idle
			),
			message: message,
			channel: channel
		)
	}

	private func handleWhoisUser(_ numeric: UInt, message: Message, shouldPrint: Bool, channel: IRCChannel?) {
		guard message.params.count >= 6 else { return }
		let nickname = message.params[1]
		let username = message.params[2]
		let address = message.params[3]
		let realName = String(message.params[5].drop(while: { $0 == ":" }))
		inWhoisResponse = numeric == IRCNumeric.whoisuser.rawValue
		inWhowasResponse = numeric == IRCNumeric.whowasuser.rawValue
		if !inWhowasResponse, nicknameIsMyself(nickname) {
			userHostmask = "\(nickname)!\(username)@\(address)"
		}
		guard shouldPrint else { return }
		let text = IRCInboundStrings.Whois.userhost(
			nickname: nickname,
			username: username,
			address: address,
			realName: realName,
			isHistorical: inWhowasResponse
		)
		printWhoisLine(text, message: message, channel: channel)
	}

	private func printWhoisLine(_ text: String, message: Message, channel: IRCChannel?) {
		print(text, by: nil, in: channel, as: .debug, command: message.command, receivedAt: message.receivedAt)
	}
}
