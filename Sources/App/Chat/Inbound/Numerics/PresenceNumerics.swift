// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

@MainActor
extension ServerSession {
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
			      let channel = findConversation(message.params[1]) else { return }
			print(
				String(localized: .IRC.miscellaneousMessagesRelatedWebsite(message.params[2])),
				by: nil,
				in: channel,
				as: .website,
				command: message.command, receivedAt: message.receivedAt
			)
		case .watchstat, .watchlist, .watchoff, .endofwatchlist, .monlist, .endofmonlist:
			if shouldPrint {
				printReplyToHiddenCommandResponsesConsole(message)
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

	private func handleTrackedAwayNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		guard message.params.count > 4 else { return }
		if shouldPrint {
			printReplyToHiddenCommandResponsesConsole(message)
		}
		let nickname = message.params[1]
		guard findUserTrackingAddressBookEntry(forNickname: nickname) != nil else { return }
		modifyUser(withNickname: nickname, asAway: numeric != .notaway)
	}

	private func handleTrackedStatusNumeric(_ numeric: ServerNumeric, message: Message, shouldPrint: Bool) {
		guard message.params.count > 4 else { return }
		if shouldPrint {
			printReplyToHiddenCommandResponsesConsole(message)
		}
		let nickname = message.params[1]
		let isOnline = numeric == .logon || numeric == .nowon
		applyPresence(isOnline, toDirectWith: nickname)
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
			printReplyToHiddenCommandResponsesConsole(message)
		}
		let isOnline = numeric == .mononline
		for changedUser in message.params[1].components(separatedBy: ",") {
			let nickname = changedUser.nicknameFromHostmask
			applyPresence(isOnline, toDirectWith: nickname)
			guard findUserTrackingAddressBookEntry(forNickname: nickname) != nil else { continue }
			setTrackedNickname(nickname, status: isOnline ? .signedOn : .signedOff, notify: true)
		}
	}
}
