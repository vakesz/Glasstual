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

@MainActor
extension IRCClient {
	func handlePresenceTrackingNumeric(_ numeric: IRCNumeric, message: Message, shouldPrint: Bool) {
		switch numeric {
		case .youreoper:
			guard !userIsIRCop else { return }
			userIsIRCop = true
			if shouldPrint {
				print(
					IRCInboundStrings.Numeric.operatorStatus(networkName: message.senderNickname ?? ""),
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
				IRCInboundStrings.Numeric.website(message.params[2]),
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
		case .toomanywatch, .monlistfull:
			if shouldPrint {
				printErrorReply(message)
			}
		case .mononline, .monoffline:
			handleMonitorStatusNumeric(numeric, message: message, shouldPrint: shouldPrint)
		case .targumodeg:
			break
		default:
			break
		}
	}

	func handleAuthenticationTrackingNumeric(_ numeric: IRCNumeric, message: Message, shouldPrint: Bool) {
		switch numeric {
		case .targnotify:
			if shouldPrint, message.params.count == 3 {
				printDebugInformation(IRCInboundStrings.Numeric.cannotMessageUnrecognizedUser(message.params[1]))
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

	private func handleTrackedAwayNumeric(_ numeric: IRCNumeric, message: Message, shouldPrint: Bool) {
		guard message.params.count > 4 else { return }
		if shouldPrint {
			printReplyToHiddenCommandResponsesQuery(message)
		}
		let nickname = message.params[1]
		guard findUserTrackingAddressBookEntry(forNickname: nickname) != nil else { return }
		modifyUser(withNickname: nickname, asAway: numeric != .notaway)
	}

	private func handleTrackedStatusNumeric(_ numeric: IRCNumeric, message: Message, shouldPrint: Bool) {
		guard message.params.count > 4 else { return }
		if shouldPrint {
			printReplyToHiddenCommandResponsesQuery(message)
		}
		let nickname = message.params[1]
		let isOnline = numeric == .logon || numeric == .nowon
		applyPresence(isOnline, toQueryWith: nickname)
		guard findUserTrackingAddressBookEntry(forNickname: nickname) != nil else { return }
		let status: IRCAddressBookUserTrackingStatus
		let notify: Bool
		switch numeric {
		case .logon: status = .signedOn; notify = true
		case .logoff: status = .signedOff; notify = true
		case .nowon: status = .available; notify = false
		default: status = .notAvailable; notify = false
		}
		setTrackedNickname(nickname, status: status, notify: notify)
	}

	private func handleMonitorStatusNumeric(_ numeric: IRCNumeric, message: Message, shouldPrint: Bool) {
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
		let text = IRCInboundStrings.Numeric.privateMessageBlocked(
			nickname: message.params[1],
			account: message.params[2]
		)
		if environment.preferences.locationToSendNotices == .selectedChannel,
		   let channel = output?.selectedChannel(on: self)
		{
			printDebugInformation(text, in: channel)
		} else {
			printDebugInformation(toConsole: text)
		}
	}

	private func handleSASLMechanismsNumeric(_ message: Message, shouldPrint: Bool) {
		if shouldPrint {
			printErrorReply(message)
		}
		guard isCapabilityEnabled(.isInSASLNegotiation) else { return }
		let mechanisms = message.params.count >= 2
			? message.params[1].components(separatedBy: CharacterSet(charactersIn: ", ")).filter { !$0.isEmpty }
			: []
		guard !retrySASLNegotiation(withMechanisms: mechanisms) else { return }
		finishSASLNegotiation(failed: true)
	}

	/// The numerics that mean the server refused this SASL attempt, as opposed
	/// to 903 (success) or 907 (already authenticated).
	private static let saslFailureNumerics: Set<IRCNumeric> = [.nicklocked, .saslfail, .sasltoolong, .saslaborted]

	private func handleSASLResultNumeric(_ numeric: IRCNumeric, message: Message, shouldPrint: Bool) {
		if shouldPrint {
			if numeric == .saslsuccess {
				printReply(message)
			} else {
				printErrorReply(message)
			}
		}
		guard isCapabilityEnabled(.isInSASLNegotiation) else { return }
		let failed = Self.saslFailureNumerics.contains(numeric)
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
