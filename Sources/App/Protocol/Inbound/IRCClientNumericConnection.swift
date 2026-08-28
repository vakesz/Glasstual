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
	func handleConnectionNumeric(_ numeric: UInt, message: Message, shouldPrint: Bool) -> Bool {
		switch numeric {
		case IRCNumeric.welcome.rawValue:
			receiveInit(message)
			if shouldPrint {
				printReply(message)
			}
		case IRCNumeric.yourhost.rawValue, IRCNumeric.created.rawValue, IRCNumeric.myinfo.rawValue,
		     IRCNumeric.statsconn.rawValue,
		     IRCNumeric.luserclient.rawValue, IRCNumeric.luserhop.rawValue, IRCNumeric.luserunknown.rawValue,
		     IRCNumeric.luserchannels.rawValue, IRCNumeric.luserme.rawValue:
			if shouldPrint {
				printReply(message)
			}
		case IRCNumeric.isupport.rawValue:
			handleISupportNumeric(message, shouldPrint: shouldPrint)
		case IRCNumeric.redir.rawValue:
			handleRedirectNumeric(message)
		case IRCNumeric.localusers.rawValue, IRCNumeric.globalusers.rawValue:
			guard shouldPrint else { return true }
			let text = message.params.count == 4 ? message.sequence(3) : message.sequence
			print(text, by: nil, in: nil, as: .debug, command: message.command, receivedAt: message.receivedAt)
		case IRCNumeric.motd.rawValue, IRCNumeric.motdstart.rawValue, IRCNumeric.endofmotd.rawValue,
		     IRCNumeric.nomotd.rawValue:
			guard shouldPrint, environment.preferences.displayServerMOTD else { return true }
			if numeric == IRCNumeric.nomotd.rawValue {
				printErrorReply(message)
			} else {
				printReply(message)
			}
		case IRCNumeric.umodeis.rawValue:
			handleUserModeNumeric(message)
		case IRCNumeric.away.rawValue:
			handleAwayNumeric(message, shouldPrint: shouldPrint)
		case IRCNumeric.silelist.rawValue:
			handleSilenceListNumeric(message, shouldPrint: shouldPrint)
		case IRCNumeric.endofsilelist.rawValue:
			if shouldPrint {
				printDebugInformation(IRCInboundStrings.Numeric.endOfSilenceList,
				                      in: output?.selectedChannel(on: self),
				                      asCommand: message.command)
			}
		case IRCNumeric.unaway.rawValue, IRCNumeric.nowaway.rawValue:
			handleOwnAwayNumeric(numeric, message: message, shouldPrint: shouldPrint)
		default:
			return false
		}
		return true
	}

	private func handleISupportNumeric(_ message: Message, shouldPrint: Bool) {
		guard message.params.count >= 3 else { return }
		let configuration = message.params.dropFirst().dropLast().joined(separator: " ")
		let explanatoryText = message.params.last ?? ""
		let previousCaseMapping = supportInfo.caseMapping
		let wasUTF8Only = supportInfo.utf8Only
		supportInfo.processConfigurationData(configuration)
		if supportInfo.caseMapping != previousCaseMapping {
			rekeyUserList()
		}
		if shouldPrint {
			printDebugInformation(
				toConsole: IRCInboundStrings.Numeric.supportUpdate(
					previous: supportInfo.stringValueForLastUpdate ?? "",
					explanation: explanatoryText
				),
				asCommand: message.command
			)
		}
		if !wasUTF8Only, supportInfo.utf8Only {
			printDebugInformation(toConsole: IRCInboundStrings.Numeric.utf8EncodingRequired, asCommand: message.command)
		}
	}

	private func handleRedirectNumeric(_ message: Message) {
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
		addDisconnectCallback { [weak self] in
			guard let self else { return }
			temporaryServerAddressOverride = serverAddress
			temporaryServerPortOverride = port
			connect()
		}
		disconnect()
	}

	private func handleUserModeNumeric(_ message: Message) {
		guard message.params.count > 1 else { return }
		let modeString = message.params[1]
		guard modeString != "+", postReceivedMessage(message, withText: modeString, destinedFor: nil) else { return }
		print(
			IRCInboundStrings.Numeric.userModes(nickname: message.params[0], modes: modeString),
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
				user.markAsAway()
			}
			guard user.claimAwayMessagePresentation() else { return }
		}
		guard shouldPrint else { return }
		print(
			IRCInboundStrings.Numeric.away(nickname: nickname, message: message.params[2]),
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
		printDebugInformation(IRCInboundStrings.Numeric.silenceEntry(entry.joined(separator: " ")),
		                      in: output?.selectedChannel(on: self),
		                      asCommand: message.command)
	}

	private func handleOwnAwayNumeric(_ numeric: UInt, message: Message, shouldPrint: Bool) {
		let away = numeric == IRCNumeric.nowaway.rawValue
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
