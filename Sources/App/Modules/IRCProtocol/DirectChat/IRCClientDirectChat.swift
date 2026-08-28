/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

import CocoaExtensions
import Foundation
import GlasstualPluginKit
import os

private let directChatClientLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "DCCDirectChat"
)

struct DCCChatOffer: Equatable {
	let address: String
	let port: UInt16
	let token: String?

	var isPassive: Bool {
		port == 0
	}
}

enum DCCChatPolicy {
	static func parseOffer(_ source: String) -> DCCChatOffer? {
		var input = CommandTokenizer(source)
		guard input.nextUppercaseToken() == "CHAT", input.nextUppercaseToken() == "CHAT" else { return nil }
		let address = ClientWireUtilities.displayDCCAddress(input.nextToken())
		let portText = input.nextToken()
		let rawToken = input.nextToken()
		let tokenText = rawToken.hasPrefix("T") ? String(rawToken.dropFirst()) : rawToken
		let token = tokenText.isEmpty ? nil : tokenText
		guard portText.allSatisfy(\.isNumber), let portValue = Int(portText),
		      portValue >= 0, portValue <= 65535,
		      portValue > 0 || token != nil,
		      token?.allSatisfy(\.isNumber) ?? true
		else { return nil }
		if portValue > 0, !address.isIPAddress {
			return nil
		}
		return DCCChatOffer(address: address, port: UInt16(portValue), token: token)
	}

	static func listeningArguments(address: String, port: UInt16, token: String?) -> String {
		let base = "chat \(address) \(port)"
		return token.map { "\(base) \($0)" } ?? base
	}

	static func channelName(for nickname: String) -> String {
		"=\(nickname)"
	}
}

@MainActor
public extension IRCClient {
	@objc(directChatChannelNameForNickname:)
	func directChatChannelName(forNickname nickname: String) -> String {
		DCCChatPolicy.channelName(for: nickname)
	}

	@objc(directChatChannelForConnection:)
	func directChatChannel(for connection: DirectChatConnection) -> IRCChannel? {
		channelList.first { $0.isDirectChat && $0.directChatConnection === connection }
	}

	@objc(directChatChannelForNickname:)
	func directChatChannel(forNickname nickname: String) -> IRCChannel? {
		let channel = findChannel(directChatChannelName(forNickname: nickname))
		return channel?.isDirectChat == true ? channel : nil
	}

	@objc(handleDCCCommand:command:targetChannel:)
	func handleDCCCommand(
		_ input: NSMutableAttributedString,
		command: String,
		targetChannel: IRCChannel?
	) {
		switch input.nextTokenAsString().uppercased() {
		case "CHAT":
			guard isLoggedIn else {
				printDebugInformation(toConsole: IRCTransportStrings.notConnected)
				return
			}
			var nickname = input.nextTokenAsString()
			if nickname.isEmpty, let targetChannel {
				if targetChannel.isPrivateMessage {
					nickname = targetChannel.name
				} else if targetChannel.isDirectChat {
					nickname = targetChannel.directChatConnection?
						.peerNickname ?? String(targetChannel.name.dropFirst())
				}
			}
			guard !nickname.isEmpty, stringIsNickname(nickname) else {
				printInvalidSyntaxMessage(for: command)
				return
			}
			startDirectChat(withNickname: nickname)
		case "SEND":
			let nickname = input.nextTokenAsString()
			let path = (input.string.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
			guard !nickname.isEmpty, stringIsNickname(nickname), !path.isEmpty else {
				printInvalidSyntaxMessage(for: command)
				return
			}
			if SharedApplication.sharedFileTransferDialog().addSender(
				for: self, nickname: nickname, path: path, autoOpen: true
			) == nil {
				printDebugInformation(IRCDirectChatStrings.fileCouldNotBeOffered(path: path))
			}
		default:
			printInvalidSyntaxMessage(for: command)
		}
	}

	@objc(receivedDCCChatQuery:text:)
	func receivedDCCChatQuery(_ sender: String, text: String) {
		guard let offer = DCCChatPolicy.parseOffer(text) else {
			printInvalidDCCChatRequest(from: sender)
			return
		}
		if !offer.isPassive, offer.token != nil {
			guard directChatChannel(forNickname: sender)?.directChatConnection?.state == .listening else {
				directChatClientLogger.error(
					"Received a passive DCC CHAT reply from \(sender, privacy: .public) without a matching request"
				)
				return
			}
		}

		print(IRCDirectChatStrings.incomingRequest(sender: sender), by: nil, in: nil,
		      as: .dccFileTransfer, command: TVCLogLineDefaultCommandValue)
		guard let window = AppController.shared.mainWindow else { return }
		TDCAlert.alertSheet(
			with: window,
			body: PromptStrings.DirectChat.body(sender: sender),
			title: PromptStrings.DirectChat.title(sender: sender),
			defaultButton: PromptStrings.DirectChat.acceptButtonTitle,
			alternateButton: PromptStrings.DirectChat.declineButtonTitle,
			otherButton: nil,
			completionBlock: { [weak self] outcome in
				guard let self else { return }
				guard outcome.response == .default else {
					print(IRCDirectChatStrings.declined(sender: sender), by: nil, in: nil,
					      as: .dccFileTransfer, command: TVCLogLineDefaultCommandValue)
					return
				}
				guard isLoggedIn else { return }
				if offer.isPassive {
					openDirectChat(withNickname: sender, listeningWithToken: offer.token)
				} else {
					openDirectChat(withNickname: sender, address: offer.address, port: offer.port)
				}
			}
		)
	}

	@objc(startDirectChatWithNickname:)
	func startDirectChat(withNickname nickname: String) {
		guard !nicknameIsMyself(nickname) else { return }
		openDirectChat(withNickname: nickname, listeningWithToken: nil)
	}

	@objc(prepareDirectChatChannelForNickname:)
	func prepareDirectChatChannel(forNickname nickname: String) -> IRCChannel? {
		guard let channel = findChannelOrCreate(
			directChatChannelName(forNickname: nickname), as: .directChat
		) else { return nil }
		channel.closeDirectChatConnection()
		if channel.isActive {
			channel.deactivate()
		}
		return channel
	}

	@objc(openDirectChatWithNickname:address:port:)
	func openDirectChat(withNickname nickname: String, address: String, port: UInt16) {
		guard let channel = prepareDirectChatChannel(forNickname: nickname) else { return }
		let connection = DirectChatConnection.connection(
			toPeer: nickname, address: address, port: port, onClient: self, delegate: self
		)
		channel.directChatConnection = connection
		printDebugInformation(
			IRCDirectChatStrings.connecting(nickname: nickname, address: address, port: port),
			in: channel
		)
		if let treeItem = legacyDirectChatTreeItem(for: channel) {
			AppController.shared.mainWindow.select(treeItem)
		}
		connection.open()
	}

	@objc(openDirectChatWithNickname:listeningWithToken:)
	func openDirectChat(withNickname nickname: String, listeningWithToken token: String?) {
		guard let channel = prepareDirectChatChannel(forNickname: nickname) else { return }
		let connection = DirectChatConnection.listeningConnection(
			forPeer: nickname, token: token, onClient: self, delegate: self
		)
		channel.directChatConnection = connection
		printDebugInformation(IRCDirectChatStrings.offering(to: nickname), in: channel)
		if let treeItem = legacyDirectChatTreeItem(for: channel) {
			AppController.shared.mainWindow.select(treeItem)
		}
		connection.open()
	}

	@objc(sendDirectChatText:asCommand:toChannel:)
	func sendDirectChatText(
		_ string: NSAttributedString,
		as command: IRCRemoteCommand,
		to channel: IRCChannel
	) {
		guard let connection = channel.directChatConnection, connection.isConnected else {
			printDebugInformation(IRCDirectChatStrings.notConnected, in: channel)
			return
		}
		let isAction = command == .privmsgAction
		let lineType: TVCLogLineType = isAction ? .action : .privateMessage
		for line in string.splitIntoLines {
			let remainder = NSMutableAttributedString(attributedString: line)
			while remainder.length > 0 {
				let lengthBeforeFormatting = remainder.length
				let message = remainder.stringFormatted(forChannel: channel.name, on: self, with: lineType)

				// Defensive: `stringFormatted` guarantees progress, but this
				// loop must never spin if that ever stops being true.
				guard remainder.length < lengthBeforeFormatting else { break }
				if isAction {
					connection.sendAction(message)
				} else {
					connection.sendMessage(message)
				}
				print(message, by: userNickname, in: channel, as: lineType, command: "PRIVMSG",
				      receivedAt: Date(), isEncrypted: false)
			}
		}
	}

	private func printInvalidDCCChatRequest(from sender: String) {
		print(IRCDirectChatStrings.unprocessableRequest(sender: sender), by: nil, in: nil,
		      as: .dccFileTransfer, command: TVCLogLineDefaultCommandValue)
	}

	private func legacyDirectChatTreeItem(for channel: IRCChannel) -> IRCTreeItem? {
		(channel as AnyObject) as? IRCTreeItem
	}
}
