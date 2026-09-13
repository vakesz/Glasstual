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
public extension IRCClient {
	func receiveNumericReply(_ message: Message) {
		let rawNumeric = message.commandNumeric

		if IRCNumeric.isErrorReply(rawNumeric) {
			receiveErrorNumericReply(message)
			return
		}

		let numeric = IRCNumeric(rawValue: rawNumeric)
		let shouldPrint = numeric?.requiresSpecialFiltering == true || postReceivedMessage(message)

		if let numeric, let group = numeric.group {
			switch group {
			case .connection:
				handleConnectionNumeric(numeric, message: message, shouldPrint: shouldPrint)
			case .whois:
				handleWhoisNumeric(numeric, message: message, shouldPrint: shouldPrint)
			case .channel:
				handleChannelNumeric(numeric, message: message, shouldPrint: shouldPrint)
			case .presence:
				handlePresenceTrackingNumeric(numeric, message: message, shouldPrint: shouldPrint)
			case .authentication:
				handleAuthenticationTrackingNumeric(numeric, message: message, shouldPrint: shouldPrint)
			}

			return
		}

		/* A plugin subscribes by the wire token, which keeps the leading zeros a
		 numeric is always written with: "001", never "1". `PluginItem` stores
		 the subscription lowercased, which is the contract the set is keyed
		 by. */
		let subscribedCommand = message.command.lowercased()
		guard !SharedApplication.sharedPluginManager().supportedServerInputCommands
			.contains(subscribedCommand)
		else {
			return
		}
		guard shouldPrint else { return }
		if inWhoisResponse, message.params.count > 2 {
			printReply(message, in: output?.selectedChannel(on: self))
		} else {
			printReply(message)
		}
	}
}
