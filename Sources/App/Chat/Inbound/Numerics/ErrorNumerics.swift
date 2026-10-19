// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

@MainActor
extension ServerSession {
	func receiveErrorNumericReply(_ message: Message) {
		let label = message.messageTags?["label"] ?? message.parentBatchMessage?.labeledResponseBatch?.labeledDelivery.label
		if label?.hasPrefix(ChatHistoryPolicy.requestLabelPrefix) == true {
			_ = noteChatHistoryFailure(message)
		}
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

	/** A rate limit answer for a command whose terminator never follows it.

	 The server answers a refused `WHO` with `RPL_TRYAGAIN` (or one of WHO's
	 oversized answers with `ERR_TOOMANYMATCHES`) and no `315`; a refused `LIST`
	 draws the same with no `RPL_LISTEND`. Left open, a WHO request misassigns
	 every reply behind it, and a LIST keeps its Refresh button disabled — so
	 the request is closed here, by the command name the refusal names as its
	 first parameter, exactly the way a failure numeric closes it.

	 A `315` prints through the hands-on command console whenever the request
	 being closed was the user's own; the refusal prints the same way. A
	 refused `LIST` prints like the failure numerics do.

	 Called from `InboundDispatch`, before the ordinary reply groups and error
	 path. `416` is an error numeric while 263 and 736 are not, but all three
	 have the same terminator-less request-lifecycle effect. */
	func receiveRateLimitRefusalReply(_ message: Message, shouldPrint: Bool) {
		switch message.param(at: 1).uppercased() {
		case "WHO":
			/* `263` names only the command, while 416 and 736 also name the
			 target. Use the target when it exists; otherwise IRC's wire order is
			 the only correlation an unlabelled refusal provides. */
			let requestWasHidden: Bool? = if message.commandNumeric == ServerNumeric.tryagain.rawValue {
				requestedCommands.recordWhoRequestClosed()
			} else if message.params.count > 3 {
				requestedCommands.recordWhoRequestClosed(for: casefoldedTarget(message.param(at: 2)))
			} else {
				requestedCommands.recordWhoRequestClosed()
			}
			if requestWasHidden == false, shouldPrint {
				printReplyToHiddenCommandResponsesConsole(message)
			}

			return
		/* A refused LIST sends no RPL_LISTEND, and a list left waiting for
		 one spins with its Refresh button disabled. */
		case "LIST":
			channelListPresentation?.channelListDidFinish(for: self)
		default:
			break
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
