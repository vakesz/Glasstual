/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

private enum IRCNumericErrorGroup {
	static let missingTarget: Set<UInt> = [IRCNumeric.nosuchserver.rawValue, IRCNumeric.nosuchchannel.rawValue]
	static let nicknameCollision: Set<UInt> = [IRCNumeric.nicknameinuse.rawValue, IRCNumeric.erroneusnickname.rawValue]
	static let joinFailure: Set<UInt> = [
		IRCNumeric.admonly.rawValue, IRCNumeric.badchanmask.rawValue, IRCNumeric.badchanname.rawValue,
		IRCNumeric.badchannel.rawValue,
		IRCNumeric.badchannelkey.rawValue, IRCNumeric.bannedfromchan.rawValue, IRCNumeric.channelisfull.rawValue,
		IRCNumeric.delayrejoin.rawValue,
		IRCNumeric.forbiddenchannel.rawValue, IRCNumeric.inviteonlychan.rawValue, IRCNumeric.linkchannel.rawValue,
		IRCNumeric.needreggednick.rawValue,
		IRCNumeric.nohiding.rawValue, IRCNumeric.operonly.rawValue, IRCNumeric.operspverify.rawValue,
		IRCNumeric.secureonlychan.rawValue,
		IRCNumeric.throttle.rawValue, IRCNumeric.toomanychannels.rawValue, IRCNumeric.toomanyjoins.rawValue,
	]
	static let whoFailure: Set<UInt> = [IRCNumeric.whosyntax.rawValue, IRCNumeric.wholimexceed.rawValue]
	static let commandFailure: Set<UInt> = [
		IRCNumeric.disabled.rawValue,
		IRCNumeric.unknowncommand.rawValue,
		IRCNumeric.needmoreparams.rawValue,
	]
}

@MainActor
public extension IRCClient {
	@objc(receiveErrorNumericReply:)
	func receiveErrorNumericReply(_ message: Message) {
		let numeric = message.commandNumeric
		let shouldPrint = postReceivedMessage(message)

		if numeric == IRCNumeric.nosuchnick.rawValue || numeric == IRCNumeric.cannotsendtochan.rawValue {
			guard shouldPrint else { return }
			printError(message, inTargetChannelNamed: message.param(at: 1))
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
		if handleJoinFailure(message, numeric: numeric, shouldPrint: shouldPrint) {
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
	func handleNicknameError(_ message: Message, numeric: UInt, shouldPrint: Bool) -> Bool {
		let isNicknameCollision = IRCNumericErrorGroup.nicknameCollision.contains(numeric)
		let isUnavailableResource = numeric == IRCNumeric.unavailresource.rawValue
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

	func handleJoinFailure(_ message: Message, numeric: UInt, shouldPrint: Bool) -> Bool {
		guard IRCNumericErrorGroup.joinFailure.contains(numeric) else { return false }
		if let channel = findChannel(message.param(at: 1)) {
			channel.errorOnLastJoinAttempt = true
			if shouldPrint {
				printErrorReply(message, in: channel, withSequence: 2)
			}
		}
		if shouldPrint {
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
