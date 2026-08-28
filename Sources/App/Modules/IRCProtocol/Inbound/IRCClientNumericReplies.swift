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

enum IRCNumericReplyPolicy {
	static func requiresSpecialFiltering(_ numeric: UInt) -> Bool {
		[
			IRCNumeric.umodeis.rawValue, IRCNumeric.channelmodeis.rawValue, IRCNumeric.topic.rawValue,
			IRCNumeric.topicwhotime.rawValue,
		].contains(numeric)
	}
}

@MainActor
public extension IRCClient {
	@objc(receiveNumericReply:)
	func receiveNumericReply(_ message: Message) {
		let numeric = message.commandNumeric
		if IRCNumeric.isErrorReply(numeric) {
			receiveErrorNumericReply(message)
			return
		}

		let shouldPrint = IRCNumericReplyPolicy.requiresSpecialFiltering(numeric) || postReceivedMessage(message)
		if handleConnectionNumeric(numeric, message: message, shouldPrint: shouldPrint) {
			return
		}
		if handleWhoisNumeric(numeric, message: message, shouldPrint: shouldPrint) {
			return
		}
		if handleChannelNumeric(numeric, message: message, shouldPrint: shouldPrint) {
			return
		}
		if handleTrackingNumeric(numeric, message: message, shouldPrint: shouldPrint) {
			return
		}

		let numericString = String(numeric)
		guard !SharedApplication.sharedPluginManager().supportedServerInputCommands.contains(numericString) else {
			return
		}
		guard shouldPrint else { return }
		if inWhoisResponse, message.params.count > 2 {
			printReply(message, in: AppController.shared.mainWindow.selectedChannel(on: self))
		} else {
			printReply(message)
		}
	}
}
