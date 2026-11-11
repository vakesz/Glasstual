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
	/// Offered as `DCC SCHAT`, asking for the chat to run over TLS.
	let isSecure: Bool

	init(address: String, port: UInt16, token: String?, isSecure: Bool = false) {
		self.address = address
		self.port = port
		self.token = token
		self.isSecure = isSecure
	}

	var isPassive: Bool {
		port == 0
	}
}

enum DirectChatPolicy {
	static func parseOffer(_ source: String) -> DirectChatOffer? {
		var input = CommandTokenizer(source)
		/* A DCC CHAT offer names the DCC subcommand and then the chat protocol,
		 both spelled "CHAT". The two reads look identical because the tokens
		 are. A secure offer spells the subcommand "SCHAT" and keeps the
		 protocol "CHAT". */
		let dccSubcommand = input.nextUppercaseToken()
		let chatProtocol = input.nextUppercaseToken()
		let isSecure = dccSubcommand == DCCCommand.secureChat.rawValue
		guard dccSubcommand == DCCCommand.chat.rawValue || isSecure, chatProtocol == "CHAT" else { return nil }
		let address = DCCWireFormat.displayAddress(input.nextToken())
		let portText = input.nextToken()
		let rawToken = input.nextToken()
		let tokenText = rawToken.hasPrefix("T") ? String(rawToken.dropFirst()) : rawToken
		let token = tokenText.isEmpty ? nil : tokenText
		guard portText.allSatisfy(\.isASCIIDigit), let portValue = Int(portText),
		      portValue >= 0, portValue <= 65535,
		      portValue > 0 || token != nil,
		      token?.allSatisfy(\.isASCIIDigit) ?? true
		else { return nil }
		if portValue > 0, !address.isIPAddress {
			return nil
		}
		return DirectChatOffer(address: address, port: UInt16(portValue), token: token, isSecure: isSecure)
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

	/** Whether a passive reply answers the chat this session is listening for.

	 Only a reply of the same kind does: an `SCHAT` offer is never answered by a
	 plain `CHAT`, which would carry the conversation in plain, and a plain
	 offer is never turned secure by its reply. */
	static func reply(_ offer: DirectChatOffer, answersListeningChatThatIsSecure isSecure: Bool) -> Bool {
		offer.isSecure == isSecure
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

	func receivedDCCChatQuery(_ sender: String, text: String) {
		guard let offer = DirectChatPolicy.parseOffer(text) else {
			printInvalidDCCChatRequest(from: sender)
			return
		}
		if !offer.isPassive, offer.token != nil {
			/* A passive reply answers a chat this session offered, and only one
			 of the same kind: a secure offer is never answered in plain, and a
			 plain one never becomes secure. */
			guard let listening = directChatConversation(forNickname: sender)?.directChatConnection,
			      listening.state == .listening,
			      DirectChatPolicy.reply(offer, answersListeningChatThatIsSecure: listening.isSecure)
			else {
				DirectConnectionLog.chat.error(
					"Received a passive DCC CHAT reply from \(sender, privacy: .private(mask: .hash)) without a matching request"
				)
				return
			}
		} else if admitsDCCOffer(from: sender) == false {
			/* Each unsolicited offer puts a prompt in front of the user, so a
			 flood of them is dropped here, before any prompt is made. */
			return
		} else if offer.isSecure, environment.settings.fileTransferAcceptsSecureOffers == false {
			print(String(localized: .IRC.secureChatOfferDeclinedBySetting(sender)), by: nil, in: nil,
			      as: .dccFileTransfer, command: ChatLineFormat.defaultCommand)
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

		let announcement = offer.isSecure
			? String(localized: .IRC.wantsToStartASecureDirectChat(sender))
			: String(localized: .IRC.wantsToStartADirectChat(sender))
		print(announcement, by: nil, in: nil, as: .dccFileTransfer, command: ChatLineFormat.defaultCommand)

		/* The answer can come after the connection that carried the offer has
		 gone, and a reconnect, perhaps to another server where somebody else
		 holds the sender's nickname, must not act on it. The question records
		 that connection; answering checks it. */
		guard let id = dccDecisions.addChatOffer(
			DCCChatOfferQuestion(sender: sender, offer: offer),
			startupIdentifier: startup.identifier,
			socketIdentifier: socket?.uniqueIdentifier
		) else {
			printDebugInformation(toConsole: String(localized: .IRC.dccTooManyQuestions(sender)))
			return
		}
		print(String(localized: .IRC.dccChatOfferAnswerHint(id)), by: nil, in: nil,
		      as: .dccFileTransfer, command: ChatLineFormat.defaultCommand)
		output?.presentAlertSheet(directChatOfferRequest(offer, from: sender)) { [weak self] outcome in
			self?.answerDCCChatOffer(id, accept: outcome.response == .default)
		}
	}

	/// The alert a chat offer is put to the user with. The address is what the
	/// user is actually being asked to approve: the nickname alone says nothing
	/// about where the connection would go.
	private func directChatOfferRequest(_ offer: DirectChatOffer, from sender: String) -> AlertRequest {
		let body = switch (offer.isPassive, offer.isSecure) {
		case (true, false): PromptStrings.DirectChat.body(sender: sender)
		case (true, true): PromptStrings.DirectChat.secureBody(sender: sender)
		case (false, false): ConnectionSafetyStrings.DirectChat.requestBody(sender: sender, address: offer.address)
		case (false, true): ConnectionSafetyStrings.DirectChat.secureRequestBody(sender: sender, address: offer.address)
		}
		return AlertRequest(
			title: offer.isSecure
				? PromptStrings.DirectChat.secureTitle(sender: sender)
				: PromptStrings.DirectChat.title(sender: sender),
			body: body,
			defaultButton: PromptStrings.Action.accept,
			alternateButton: PromptStrings.Action.decline
		)
	}

	/** Answers a chat offer, from its alert or from `/dcc accept` and
	 `/dcc decline`. The first answer wins; one that arrives after the
	 connection the offer came over has gone opens nothing. */
	@discardableResult
	func answerDCCChatOffer(_ id: String, accept: Bool) -> DCCQuestionAnswerResult {
		guard let decision = dccDecisions.decision(withID: id) else { return .unknown }
		guard case let .chatOffer(question) = decision.question else { return .wrongAnswer }
		_ = dccDecisions.remove(id: id)
		let sender = question.sender
		let offer = question.offer
		guard accept else {
			print(String(localized: .IRC.declinedDirectChatRequest(sender)), by: nil, in: nil,
			      as: .dccFileTransfer, command: ChatLineFormat.defaultCommand)
			return .answered
		}
		guard isLoggedIn, !isTerminating, startup.identifier == decision.startupIdentifier,
		      socket?.uniqueIdentifier == decision.socketIdentifier
		else { return .answered }
		if offer.isPassive {
			openDirectChat(
				withNickname: sender, listeningWithToken: offer.token, offeredAddress: offer.address, secure: offer.isSecure
			)
		} else {
			openDirectChat(withNickname: sender, address: offer.address, port: offer.port, secure: offer.isSecure)
		}
		return .answered
	}

	func startDirectChat(withNickname nickname: String, secure: Bool = false) {
		guard !nicknameIsMyself(nickname) else { return }
		openDirectChat(withNickname: nickname, listeningWithToken: nil, secure: secure)
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

	func openDirectChat(withNickname nickname: String, address: String, port: UInt16, secure: Bool = false) {
		guard let conversation = prepareDirectChatConversation(forNickname: nickname) else { return }
		let connection = DirectChatSession.connection(
			toPeer: nickname, address: address, port: port, secure: secure, onSession: self
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
		offeredAddress: String? = nil,
		secure: Bool = false
	) {
		guard let conversation = prepareDirectChatConversation(forNickname: nickname) else { return }
		let connection = DirectChatSession.listeningConnection(
			forPeer: nickname, token: token, offeredAddress: offeredAddress, secure: secure, onSession: self
		)
		conversation.directChatConnection = connection
		let offering = secure
			? String(localized: .IRC.offeringASecureDirectChat(nickname))
			: String(localized: .IRC.offeringADirectChat(nickname))
		printDebugInformation(offering, in: conversation)
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
				connection.sendLine(message)
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
			let verb: DCCCommand = connection.isSecure ? .secureChat : .chat
			sendCTCPQuery(nickname, command: verb.ctcpCommand, text: arguments)
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
		printDebugInformation(directChatEstablishedNotice(for: connection), in: conversation)
	}

	private func directChatEstablishedNotice(for connection: DirectChatSession) -> String {
		let nickname = connection.peerNickname
		guard let secureSession = connection.secureSession else {
			return String(localized: .IRC.directChatWithEstablished(nickname))
		}
		return secureSession.peer == nil
			? String(localized: .IRC.secureDirectChatEstablishedUnverified(nickname, secureSession.protocolName))
			: String(localized: .IRC.secureDirectChatEstablishedVerified(nickname, secureSession.protocolName))
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
		if let error = error as? DCCTransferError,
		   let message = ConnectionSafetyStrings.SecureDCC.message(for: error, peer: connection.peerNickname)
		{
			return message
		}

		return String(localized: .IRC.directChatWithClosed(connection.peerNickname, error.localizedDescription))
	}
}
