// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

struct DirectChatOffer: Equatable {
	let address: String
	let port: UInt16
	let token: String?

	var isPassive: Bool {
		port == 0
	}
}

enum DirectChatPolicy {
	static func parseOffer(_ source: String) -> DirectChatOffer? {
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
		return DirectChatOffer(address: address, port: UInt16(portValue), token: token)
	}

	/** Whether the session is willing to dial the address the offer names.

	 An active offer decides which host this session connects to, exactly as a
	 DCC SEND offer does, so it goes through the same refusal: loopback, a
	 private network and the documentation ranges are not addresses a peer gets
	 to point us at. A passive offer names none — the peer connects to us — so
	 there is nothing to refuse. */
	static func isDialable(_ offer: DirectChatOffer) -> Bool {
		offer.isPassive || DCCWireFormat.isDialableAddress(offer.address)
	}

	static func listeningArguments(address: String, port: UInt16, token: String?) -> String {
		let base = "chat \(address) \(port)"
		return token.map { "\(base) \($0)" } ?? base
	}

	static func conversationName(for nickname: String) -> String {
		"=\(nickname)"
	}
}

extension ServerSession {
	func directChatConversationName(forNickname nickname: String) -> String {
		DirectChatPolicy.conversationName(for: nickname)
	}

	func directChatConversation(for connection: DirectChatSession) -> Conversation? {
		conversationList.first { $0.isDirectChat && $0.directChatConnection === connection }
	}

	func directChatConversation(forNickname nickname: String) -> Conversation? {
		let conversation = findConversation(directChatConversationName(forNickname: nickname))
		return conversation?.isDirectChat == true ? conversation : nil
	}

	func handleDCCCommand(
		_ input: CommandArguments,
		command: String,
		targetConversation: Conversation?
	) {
		var input = input
		switch input.next().uppercased() {
		case "CHAT":
			guard isLoggedIn else {
				printDebugInformation(toConsole: String(localized: .IRC.failedToSendDataToServer))
				return
			}
			var nickname = input.next()
			if nickname.isEmpty, let targetConversation {
				if targetConversation.isDirect {
					nickname = targetConversation.name
				} else if targetConversation.isDirectChat {
					nickname = targetConversation.directChatConnection?
						.peerNickname ?? String(targetConversation.name.dropFirst())
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
			fileTransfers?.offerSender(
				for: self, nickname: nickname, path: path, autoOpen: true, accessURL: nil
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
		guard let offer = DirectChatPolicy.parseOffer(text) else {
			printInvalidDCCChatRequest(from: sender)
			return
		}
		if !offer.isPassive, offer.token != nil {
			guard directChatConversation(forNickname: sender)?.directChatConnection?.state == .listening else {
				DirectConnectionLog.chat.error(
					"Received a passive DCC CHAT reply from \(sender, privacy: .public) without a matching request"
				)
				return
			}
		} else if admitsDCCOffer(from: sender) == false {
			/* Each unsolicited offer puts a prompt in front of the user, so a
			 flood of them is dropped here, before any prompt is made. */
			return
		}

		if DirectChatPolicy.isDialable(offer) == false {
			DirectConnectionLog.chat.error("Refused a DCC CHAT offer for a non-routable address")
			printDebugInformation(
				toConsole: ConnectionSafetyStrings.DirectChat.refusedAddress(
					sender: sender, address: offer.address
				)
			)
			return
		}

		print(String(localized: .IRC.wantsToStartADirectChat(sender)), by: nil, in: nil,
		      as: .dccFileTransfer, command: ChatLineFormat.defaultCommand)
		/* The address is what the user is actually being asked to approve — the
		 nickname alone says nothing about where the connection would go. */
		let body = offer.isPassive
			? PromptStrings.DirectChat.body(sender: sender)
			: ConnectionSafetyStrings.DirectChat.requestBody(sender: sender, address: offer.address)
		let request = AlertRequest(
			title: PromptStrings.DirectChat.title(sender: sender),
			body: body,
			defaultButton: PromptStrings.Action.accept,
			alternateButton: PromptStrings.Action.decline
		)
		output?.presentAlertSheet(
			request,
			completion: { [weak self] outcome in
				guard let self else { return }
				guard outcome.response == .default else {
					print(String(localized: .IRC.declinedDirectChatRequest(sender)), by: nil, in: nil,
					      as: .dccFileTransfer, command: ChatLineFormat.defaultCommand)
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

	func prepareDirectChatConversation(forNickname nickname: String) -> Conversation? {
		guard let conversation = findConversationOrCreate(
			directChatConversationName(forNickname: nickname), as: .directChat
		) else { return nil }
		conversation.closeDirectChatConnection()
		if conversation.isActive {
			conversation.deactivate()
		}
		return conversation
	}

	func openDirectChat(withNickname nickname: String, address: String, port: UInt16) {
		guard let conversation = prepareDirectChatConversation(forNickname: nickname) else { return }
		let connection = DirectChatSession.connection(
			toPeer: nickname, address: address, port: port, onSession: self
		)
		conversation.directChatConnection = connection
		printDebugInformation(
			String(localized: .IRC.connectingToForADirectChat(nickname, address, String(port))),
			in: conversation
		)
		output?.select(conversation)
		connection.open()
	}

	func openDirectChat(
		withNickname nickname: String,
		listeningWithToken token: String?,
		offeredAddress: String? = nil
	) {
		guard let conversation = prepareDirectChatConversation(forNickname: nickname) else { return }
		let connection = DirectChatSession.listeningConnection(
			forPeer: nickname, token: token, offeredAddress: offeredAddress, onSession: self
		)
		conversation.directChatConnection = connection
		printDebugInformation(String(localized: .IRC.offeringADirectChat(nickname)), in: conversation)
		output?.select(conversation)
		connection.open()
	}

	func sendDirectChatText(
		_ string: NSAttributedString,
		as command: RemoteCommand,
		to conversation: Conversation
	) {
		guard let connection = conversation.directChatConnection, connection.isConnected else {
			printDebugInformation(String(localized: .IRC.directChatIsNotConnected), in: conversation)
			return
		}
		let isAction = command == .privmsgAction
		let lineType: ChatLineKind = isAction ? .action : .privateMessage
		var cursor = OutboundTextCursor(string)
		enqueueOutboundText(conversations: [conversation]) { session in
			guard conversation.directChatConnection === connection, connection.isConnected,
			      let message = cursor.next(for: conversation.name, on: session, as: lineType) else { return false }
			if isAction {
				connection.sendAction(message)
			} else {
				connection.sendMessage(message)
			}
			session.print(message, by: session.userNickname, in: conversation, as: lineType, command: "PRIVMSG",
			              receivedAt: Date(), isEncrypted: false)
			return true
		}
	}

	private func printInvalidDCCChatRequest(from sender: String) {
		print(String(localized: .IRC.glasstualHasReceivedADccRequest(sender)), by: nil, in: nil,
		      as: .dccFileTransfer, command: ChatLineFormat.defaultCommand)
	}
}

extension ServerSession {
	/// Offers the chat once the listener knows what to announce. `mappedAddress`
	/// is the public address the router reported for the mapping, if it made one.
	func directChatConnection(
		_ connection: DirectChatSession,
		didStartListeningOnPort port: UInt16,
		mappedAddress: String?
	) {
		guard let conversation = directChatConversation(for: connection) else {
			connection.close()
			return
		}
		let nickname = connection.peerNickname
		let transferToken = connection.transferToken
		Task { [weak self, fileTransfers] in
			let address = await fileTransfers?.lookUpIPAddress(routerAddress: mappedAddress) ?? nil

			/* The lookup can reach a public service, so the offer this answers
			 may have been closed by the time it returns. */
			guard let self,
			      conversation.directChatConnection === connection,
			      connection.state == .listening
			else { return }
			guard let address, let formattedAddress = DCCFormattedAddress(address), isLoggedIn else {
				printDebugInformation(String(localized: .IRC.couldNotDetermineAnAddress(nickname)), in: conversation)
				conversation.closeDirectChatConnection()
				return
			}
			let arguments = DirectChatPolicy.listeningArguments(
				address: formattedAddress, port: port, token: transferToken
			)
			sendCTCPQuery(nickname, command: DCCCommand.chat.ctcpCommand, text: arguments)
			printDebugInformation(
				String(localized: .IRC.waitingForToConnectOnPort(nickname, String(port))),
				in: conversation
			)
		}
	}

	func directChatConnectionDidConnect(_ connection: DirectChatSession) {
		guard let conversation = directChatConversation(for: connection) else {
			connection.close()
			return
		}
		conversation.activate()
		output?.reloadChatItem(conversation)
		output?.updateTitle(for: conversation)
		printDebugInformation(String(localized: .IRC.directChatWithEstablished(connection.peerNickname)), in: conversation)
	}

	func directChatConnection(
		_ connection: DirectChatSession,
		didReceiveMessage message: String,
		isAction: Bool
	) {
		guard let conversation = directChatConversation(for: connection) else { return }
		let nickname = connection.peerNickname
		let lineType: ChatLineKind = isAction ? .action : .privateMessage
		print(message, by: nickname, in: conversation, as: lineType, command: "PRIVMSG",
		      receivedAt: Date(), isEncrypted: false)
		notifyEvent(.privateMessage, lineType: lineType, target: conversation, nickname: nickname, text: message)
	}

	func directChatConnection(_ connection: DirectChatSession, didCloseWithError error: Error?) {
		guard let conversation = directChatConversation(for: connection) else { return }
		conversation.directChatConnection = nil
		printDebugInformation(directChatClosedNotice(for: connection, error: error), in: conversation)
		if conversation.isActive {
			conversation.deactivate()
		}
		output?.reloadChatItem(conversation)
		output?.updateTitle(for: conversation)
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
