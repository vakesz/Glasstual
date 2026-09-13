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
import GlasstualPluginKit

private enum IRCNumericErrorGroup {
	static let missingTarget: Set<IRCNumeric> = [.nosuchserver, .nosuchchannel]
	static let nicknameCollision: Set<IRCNumeric> = [.nicknameinuse, .erroneusnickname]
	static let joinFailure: Set<IRCNumeric> = [
		.admonly, .badchanmask, .badchanname, .badchannel, .badchannelkey, .bannedfromchan,
		.channelisfull, .delayrejoin, .forbiddenchannel, .inviteonlychan, .linkchannel,
		.needreggednick, .nohiding, .operonly, .operspverify, .secureonlychan, .throttle,
		.toomanychannels, .toomanyjoins,
	]
	static let whoFailure: Set<IRCNumeric> = [.whosyntax, .wholimexceed]
	static let commandFailure: Set<IRCNumeric> = [.disabled, .unknowncommand, .needmoreparams]
}

@MainActor
public extension IRCClient {
	func receiveErrorNumericReply(_ message: Message) {
		let shouldPrint = postReceivedMessage(message)

		/* Servers send error numerics this catalog has no case for, and those
		 print the way any other error does. */
		guard let numeric = IRCNumeric(rawValue: message.commandNumeric) else {
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
		if IRCNumericErrorGroup.missingTarget.contains(numeric) {
			if shouldPrint {
				printErrorReply(message)
			}
			return
		}
		if handleNicknameError(message, numeric: numeric, shouldPrint: shouldPrint) {
			return
		}
		if IRCNumericErrorGroup.whoFailure.contains(numeric) {
			requestedCommands.recordWhoRequestClosed()
			if shouldPrint {
				printErrorReply(message)
			}
			return
		}
		if IRCNumericErrorGroup.commandFailure.contains(numeric) {
			switch message.param(at: 1) {
			case "ISON": requestedCommands.recordIsonRequestClosed()
			case "WHO": requestedCommands.recordWhoRequestClosed()
			default: break
			}
		}
		if shouldPrint {
			printErrorReply(message)
		}
	}
}

@MainActor
private extension IRCClient {
	func handleNicknameError(_ message: Message, numeric: IRCNumeric, shouldPrint: Bool) -> Bool {
		let isNicknameCollision = IRCNumericErrorGroup.nicknameCollision.contains(numeric)
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

	func handleJoinFailure(_ message: Message, numeric: IRCNumeric, shouldPrint: Bool) -> Bool {
		let target = message.param(at: 1)
		let channel = findChannel(target)
		let isPendingJoin = channel?.isChannel == true && channel?.status == .joining && stringIsChannelName(target)
		let isUnavailableChannel = numeric == .nosuchchannel || numeric == .unavailresource
		guard IRCNumericErrorGroup.joinFailure.contains(numeric) || (isUnavailableChannel && isPendingJoin)
		else { return false }
		if let channel {
			// 477 can also reject MODE; only a pending JOIN owns this failure.
			if isPendingJoin, !message.isPrintOnlyMessage {
				channel.status = .parted
				channel.errorOnLastJoinAttempt = true
				output?.reloadTreeItem(channel)
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
