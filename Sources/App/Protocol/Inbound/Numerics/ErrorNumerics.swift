// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

@MainActor
extension ServerSession {
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
			printError(message, inConversationNamed: message.param(at: 1))
			return
		}
		if handleJoinFailure(message, numeric: numeric, shouldPrint: shouldPrint) {
			return
		}
		if numeric.errorKind == .missingTarget {
			if shouldPrint {
				printErrorReply(message)
			}
			return
		}
		if handleNicknameError(message, numeric: numeric, shouldPrint: shouldPrint) {
			return
		}
		if numeric.errorKind == .whoFailure {
			requestedCommands.recordWhoRequestClosed()
			if shouldPrint {
				printErrorReply(message)
			}
			return
		}
		if numeric.errorKind == .commandFailure {
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
private extension ServerSession {
	func handleNicknameError(_ message: Message, numeric: ServerNumeric, shouldPrint: Bool) -> Bool {
		let isNicknameCollision = numeric.errorKind == .nicknameCollision
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
		let channel = findConversation(target)
		let isPendingJoin = channel?.isChannel == true && channel?.status == .joining && stringIsChannelName(target)
		let isUnavailableChannel = numeric == .nosuchchannel || numeric == .unavailresource
		guard numeric.errorKind == .joinFailure || (isUnavailableChannel && isPendingJoin)
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

	/// `ERR_NOSUCHNICK` and `ERR_CANNOTSENDTOCHAN` name whatever the failed
	/// command was addressed to, so the target is a nickname as often as it is a
	/// channel; the error prints in that conversation when one is open.
	func printError(_ message: Message, inConversationNamed conversationName: String) {
		if let conversation = findConversation(conversationName) {
			printErrorReply(message, in: conversation, withSequence: 2)
		} else {
			printErrorReply(message)
		}
	}
}
