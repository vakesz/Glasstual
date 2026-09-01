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
extension IRCClient: IRCDirectChatConnectionDelegate {
	public func directChatConnection(_ connection: DirectChatConnection, didStartListeningOnPort port: UInt16) {
		guard let channel = directChatChannel(for: connection) else {
			connection.close()
			return
		}
		let nickname = connection.peerNickname
		let transferToken = connection.transferToken
		SharedApplication.sharedFileTransferCenter().requestIPAddress { [weak self] address in
			guard let self,
			      channel.directChatConnection === connection,
			      connection.state == .listening
			else { return }
			guard let address, let formattedAddress = DCCFormattedAddress(address), isLoggedIn else {
				printDebugInformation(IRCDirectChatStrings.addressUnavailable(nickname: nickname), in: channel)
				channel.closeDirectChatConnection()
				return
			}
			let arguments = DCCChatPolicy.listeningArguments(
				address: formattedAddress, port: port, token: transferToken
			)
			sendCTCPQuery(nickname, command: DCCCommand.chat.ctcpCommand, text: arguments)
			printDebugInformation(
				IRCDirectChatStrings.waitingForConnection(nickname: nickname, port: port),
				in: channel
			)
		}
	}

	public func directChatConnectionDidConnect(_ connection: DirectChatConnection) {
		guard let channel = directChatChannel(for: connection) else {
			connection.close()
			return
		}
		channel.activate()
		output?.reloadTreeItem(channel)
		output?.updateTitle(for: channel)
		printDebugInformation(IRCDirectChatStrings.established(nickname: connection.peerNickname), in: channel)
	}

	public func directChatConnection(
		_ connection: DirectChatConnection,
		didReceiveMessage message: String,
		isAction: Bool
	) {
		guard let channel = directChatChannel(for: connection) else { return }
		let nickname = connection.peerNickname
		let lineType: LogLineType = isAction ? .action : .privateMessage
		print(message, by: nickname, in: channel, as: lineType, command: "PRIVMSG",
		      receivedAt: Date(), isEncrypted: false)
		_ = notifyText(.privateMessage, lineType: lineType, target: channel, nickname: nickname, text: message)
	}

	public func directChatConnection(_ connection: DirectChatConnection, didCloseWithError error: Error?) {
		guard let channel = directChatChannel(for: connection) else { return }
		channel.directChatConnection = nil
		printDebugInformation(
			IRCDirectChatStrings.closed(
				nickname: connection.peerNickname,
				error: error?.localizedDescription
			),
			in: channel
		)
		if channel.isActive {
			channel.deactivate()
		}
		output?.reloadTreeItem(channel)
		output?.updateTitle(for: channel)
	}
}
