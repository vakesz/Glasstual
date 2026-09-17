// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
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
		/* A DCC CHAT offer names the DCC subcommand and then the chat protocol,
		 both spelled "CHAT". The two reads look identical because the tokens
		 are. */
		let dccSubcommand = input.nextUppercaseToken()
		let chatProtocol = input.nextUppercaseToken()
		guard dccSubcommand == "CHAT", chatProtocol == "CHAT" else { return nil }
		let address = DCCWireFormat.displayAddress(input.nextToken())
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

	/** Whether the client is willing to dial the address the offer names.

	 An active offer decides which host this client connects to, exactly as a
	 DCC SEND offer does, so it goes through the same refusal: loopback, a
	 private network and the documentation ranges are not addresses a peer gets
	 to point us at. A passive offer names none — the peer connects to us — so
	 there is nothing to refuse. */
	static func isDialable(_ offer: DCCChatOffer) -> Bool {
		offer.isPassive || DCCWireFormat.isDialableAddress(offer.address)
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
extension Client {
	func directChatChannelName(forNickname nickname: String) -> String {
		DCCChatPolicy.channelName(for: nickname)
	}

	func directChatChannel(for connection: DirectChatSession) -> Channel? {
		channelList.first { $0.isDirectChat && $0.directChatConnection === connection }
	}

	func directChatChannel(forNickname nickname: String) -> Channel? {
		let channel = findChannel(directChatChannelName(forNickname: nickname))
		return channel?.isDirectChat == true ? channel : nil
	}

	func handleDCCCommand(
		_ input: CommandArguments,
		command: String,
		targetChannel: Channel?
	) {
		var input = input
		switch input.next().uppercased() {
		case "CHAT":
			guard isLoggedIn else {
				printDebugInformation(toConsole: String(localized: .IRC.failedToSendDataToServer))
				return
			}
			var nickname = input.next()
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
			let nickname = input.next()
			let path = (input.rest.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
			guard !nickname.isEmpty, stringIsNickname(nickname), !path.isEmpty else {
				printInvalidSyntaxMessage(for: command)
				return
			}
			AppServices.fileTransfers.offerSender(
				for: self, nickname: nickname, path: path, autoOpen: true
			) { [weak self] identifier in
				if identifier == nil {
					self?.printDebugInformation(String(localized: .IRC.fileAtCouldNotBeOffered(path)))
				}
			}
		default:
			printInvalidSyntaxMessage(for: command)
		}
	}

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
		} else if admitsDCCOffer(from: sender) == false {
			/* Each unsolicited offer puts a prompt in front of the user, so a
			 flood of them is dropped here, before any prompt is made. */
			return
		}

		if DCCChatPolicy.isDialable(offer) == false {
			directChatClientLogger.error("Refused a DCC CHAT offer for a non-routable address")
			printDebugInformation(
				toConsole: ConnectionSafetyStrings.DirectChat.refusedAddress(
					sender: sender, address: offer.address
				)
			)
			return
		}

		print(String(localized: .IRC.wantsToStartADirectChat(sender)), by: nil, in: nil,
		      as: .dccFileTransfer, command: LogLineFormat.defaultCommand)
		/* The address is what the user is actually being asked to approve — the
		 nickname alone says nothing about where the connection would go. */
		let body = offer.isPassive
			? PromptStrings.DirectChat.body(sender: sender)
			: ConnectionSafetyStrings.DirectChat.requestBody(sender: sender, address: offer.address)
		let request = AlertRequest(
			title: PromptStrings.DirectChat.title(sender: sender),
			body: body,
			defaultButton: PromptStrings.DirectChat.acceptButtonTitle,
			alternateButton: PromptStrings.DirectChat.declineButtonTitle
		)
		output?.presentAlertSheet(
			request,
			completion: { [weak self] outcome in
				guard let self else { return }
				guard outcome.response == .default else {
					print(String(localized: .IRC.declinedDirectChatRequest(sender)), by: nil, in: nil,
					      as: .dccFileTransfer, command: LogLineFormat.defaultCommand)
					return
				}
				guard isLoggedIn else { return }
				if offer.isPassive {
					openDirectChat(withNickname: sender, listeningWithToken: offer.token, offeredAddress: offer.address)
				} else {
					openDirectChat(withNickname: sender, address: offer.address, port: offer.port)
				}
			}
		)
	}

	func startDirectChat(withNickname nickname: String) {
		guard !nicknameIsMyself(nickname) else { return }
		openDirectChat(withNickname: nickname, listeningWithToken: nil)
	}

	func prepareDirectChatChannel(forNickname nickname: String) -> Channel? {
		guard let channel = findChannelOrCreate(
			directChatChannelName(forNickname: nickname), as: .directChat
		) else { return nil }
		channel.closeDirectChatConnection()
		if channel.isActive {
			channel.deactivate()
		}
		return channel
	}

	func openDirectChat(withNickname nickname: String, address: String, port: UInt16) {
		guard let channel = prepareDirectChatChannel(forNickname: nickname) else { return }
		let connection = DirectChatSession.connection(
			toPeer: nickname, address: address, port: port, onClient: self
		)
		channel.directChatConnection = connection
		printDebugInformation(
			String(localized: .IRC.connectingToForADirectChat(nickname, address, String(port))),
			in: channel
		)
		output?.select(channel)
		connection.open()
	}

	func openDirectChat(
		withNickname nickname: String,
		listeningWithToken token: String?,
		offeredAddress: String? = nil
	) {
		guard let channel = prepareDirectChatChannel(forNickname: nickname) else { return }
		let connection = DirectChatSession.listeningConnection(
			forPeer: nickname, token: token, offeredAddress: offeredAddress, onClient: self
		)
		channel.directChatConnection = connection
		printDebugInformation(String(localized: .IRC.offeringADirectChat(nickname)), in: channel)
		output?.select(channel)
		connection.open()
	}

	func sendDirectChatText(
		_ string: NSAttributedString,
		as command: RemoteCommand,
		to channel: Channel
	) {
		guard let connection = channel.directChatConnection, connection.isConnected else {
			printDebugInformation(String(localized: .IRC.directChatIsNotConnected), in: channel)
			return
		}
		let isAction = command == .privmsgAction
		let lineType: LogLineType = isAction ? .action : .privateMessage
		var cursor = OutboundTextCursor(string)
		enqueueOutboundText(channels: [channel]) { client in
			guard channel.directChatConnection === connection, connection.isConnected,
			      let message = cursor.next(for: channel.name, on: client, as: lineType) else { return false }
			if isAction {
				connection.sendAction(message)
			} else {
				connection.sendMessage(message)
			}
			client.print(message, by: client.userNickname, in: channel, as: lineType, command: "PRIVMSG",
			             receivedAt: Date(), isEncrypted: false)
			return true
		}
	}

	private func printInvalidDCCChatRequest(from sender: String) {
		print(String(localized: .IRC.glasstualHasReceivedADccRequest(sender)), by: nil, in: nil,
		      as: .dccFileTransfer, command: LogLineFormat.defaultCommand)
	}
}

@MainActor
extension Client {
	/// Offers the chat once the listener knows what to announce. `mappedAddress`
	/// is the public address the router reported for the mapping, if it made one.
	func directChatConnection(
		_ connection: DirectChatSession,
		didStartListeningOnPort port: UInt16,
		mappedAddress: String?
	) {
		guard let channel = directChatChannel(for: connection) else {
			connection.close()
			return
		}
		let nickname = connection.peerNickname
		let transferToken = connection.transferToken
		Task { [weak self, fileTransferCenter] in
			let address = await fileTransferCenter.lookUpIPAddress(routerAddress: mappedAddress)

			/* The lookup can reach a public service, so the offer this answers
			 may have been closed by the time it returns. */
			guard let self,
			      channel.directChatConnection === connection,
			      connection.state == .listening
			else { return }
			guard let address, let formattedAddress = DCCFormattedAddress(address), isLoggedIn else {
				printDebugInformation(String(localized: .IRC.couldNotDetermineAnAddress(nickname)), in: channel)
				channel.closeDirectChatConnection()
				return
			}
			let arguments = DCCChatPolicy.listeningArguments(
				address: formattedAddress, port: port, token: transferToken
			)
			sendCTCPQuery(nickname, command: DCCCommand.chat.ctcpCommand, text: arguments)
			printDebugInformation(
				String(localized: .IRC.waitingForToConnectOnPort(nickname, String(port))),
				in: channel
			)
		}
	}

	func directChatConnectionDidConnect(_ connection: DirectChatSession) {
		guard let channel = directChatChannel(for: connection) else {
			connection.close()
			return
		}
		channel.activate()
		output?.reloadChatItem(channel)
		output?.updateTitle(for: channel)
		printDebugInformation(String(localized: .IRC.directChatWithEstablished(connection.peerNickname)), in: channel)
	}

	func directChatConnection(
		_ connection: DirectChatSession,
		didReceiveMessage message: String,
		isAction: Bool
	) {
		guard let channel = directChatChannel(for: connection) else { return }
		let nickname = connection.peerNickname
		let lineType: LogLineType = isAction ? .action : .privateMessage
		print(message, by: nickname, in: channel, as: lineType, command: "PRIVMSG",
		      receivedAt: Date(), isEncrypted: false)
		notifyEvent(.privateMessage, lineType: lineType, target: channel, nickname: nickname, text: message)
	}

	func directChatConnection(_ connection: DirectChatSession, didCloseWithError error: Error?) {
		guard let channel = directChatChannel(for: connection) else { return }
		channel.directChatConnection = nil
		printDebugInformation(directChatClosedNotice(for: connection, error: error), in: channel)
		if channel.isActive {
			channel.deactivate()
		}
		output?.reloadChatItem(channel)
		output?.updateTitle(for: channel)
	}

	/// Why a direct chat ended. The error is only named when there was one; a
	/// chat the peer closed cleanly reads as closed, not as failed.
	private func directChatClosedNotice(for connection: DirectChatSession, error: Error?) -> String {
		guard let error else {
			return String(localized: .IRC.directChatDccChatWithClosed(connection.peerNickname))
		}

		return String(localized: .IRC.directChatWithClosed(connection.peerNickname, error.localizedDescription))
	}
}
