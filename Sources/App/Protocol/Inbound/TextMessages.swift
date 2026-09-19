// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

enum InboundTextPolicy {
	struct Classification {
		let text: String
		let lineType: ChatLineKind
	}

	static func classify(command: RemoteCommand?, payload: String) -> Classification {
		let isPrivmsg = command == .privmsg
		guard payload.hasPrefix("\u{1}") else {
			return Classification(text: payload, lineType: isPrivmsg ? .privateMessage : .notice)
		}
		var text = String(payload.dropFirst())
		if let close = text.firstIndex(of: "\u{1}") {
			text = String(text[..<close])
		}
		if isPrivmsg, hasActionPrefix(text) {
			return Classification(text: String(text.dropFirst(actionPrefix.count)), lineType: .action)
		}
		return Classification(text: text, lineType: isPrivmsg ? .ctcpQuery : .ctcpReply)
	}

	/// The CTCP verb an emote is sent as, in the casing the tag is compared in.
	private static let actionPrefix = "action "

	/** Whether `text` opens with the ACTION verb, compared as ASCII.

	 A CTCP verb is an ASCII token, so it folds as one. Folding the payload with
	 `lowercased()` folded the whole message under Unicode rules — Turkish
	 dotless I, Kelvin sign, ligatures — and could change its length, while the
	 seven characters were then dropped from the *unfolded* text; a message
	 whose fold was shorter kept part of the verb, and one whose fold was longer
	 lost the first characters of what the person actually wrote. */
	private static func hasActionPrefix(_ text: String) -> Bool {
		var index = text.utf8.startIndex

		for expected in actionPrefix.utf8 {
			guard index < text.utf8.endIndex else {
				return false
			}

			let byte = text.utf8[index]
			let folded = (byte >= 0x41 && byte <= 0x5A) ? byte + 0x20 : byte

			guard folded == expected else {
				return false
			}

			index = text.utf8.index(after: index)
		}

		return true
	}

	static func lineType(_ lineType: ChatLineKind, suppressingHighlights: Bool) -> ChatLineKind {
		guard suppressingHighlights else { return lineType }
		switch lineType {
		case .action: return .actionNoHighlight
		case .privateMessage: return .privateMessageNoHighlight
		default: return lineType
		}
	}
}

enum ServiceNoticePolicy {
	struct ChannelNotice {
		let channelName: String
		let text: String
	}

	enum NickServAction: Equatable {
		case sendIdentification(target: String, text: String)
		/// Services asked for the password, and the connection may not carry it.
		case identificationWithheld
		case identificationSucceeded
	}

	struct NickServContext {
		let isWaiting: Bool
		/// Whether SASL already authenticated the account. Services still ask
		/// a nickname that is identified to identify on some networks, and the
		/// answer would be a second copy of the password for nothing.
		let isIdentifiedWithSASL: Bool
		/// Whether the connection may carry the password; see
		/// `ServerSession.permitsCredentialsInClear`.
		let permitsCredentialsInClear: Bool
		let password: String?
		let nickname: String
		let serverAddress: String?
		let sendsAuthenticationToUserServ: Bool
		let needsIdentificationTokens: [String]
		let successfulIdentificationTokens: [String]
	}

	/** Whether a `NickServ` or `ChanServ` notice plausibly came from network services.

	 The reply to a NickServ notice carries the account password, and a ChanServ
	 notice is filed into the channel it names. Nothing stops an ordinary user
	 from holding either nickname on a network without nickname protection, so
	 the sender has to be the network's before either happens.

	 The host alone cannot say so. A reverse DNS name is whatever the owner of
	 the address publishes, so `services.attacker.example` is one record away
	 for anyone; what an ordinary user cannot have is a host inside the domain
	 of the server the session connected to. Services therefore count when they
	 are the server itself, when their host is under the network's own domain
	 (`NickServ!service@dal.net` against `irc.dal.net`), or when a `services`
	 label sits directly on that domain (`services.libera.chat` against
	 `irc.libera.chat`). The bare `services.` host some networks use is not a
	 name DNS can produce, so only the network can have given it. */
	static func noticeIsFromServices(
		senderIsServer: Bool,
		senderAddress: String?,
		serverAddress: String?
	) -> Bool {
		if senderIsServer {
			return true
		}

		guard let address = senderAddress?.lowercased(), address.isEmpty == false else {
			return false
		}

		if address == "services." {
			return true
		}

		guard let serverAddress = serverAddress?.lowercased(), serverAddress.isEmpty == false else {
			return false
		}

		var labels = address.split(separator: ".", omittingEmptySubsequences: false)

		/* `services.example.net` and `nick.services.example.net` both name the
		 domain after their `services` label; a host with no such label names
		 its own. */
		if let servicesLabel = labels.lastIndex(of: "services") {
			labels.removeSubrange(...servicesLabel)
		}

		return domain(labels.joined(separator: "."), contains: serverAddress)
	}

	/// Whether `host` is `domain` or sits under it. A single label is a
	/// top-level domain, never a network's own, so it contains nothing.
	private static func domain(_ domain: String, contains host: String) -> Bool {
		let labels = domain.split(separator: ".", omittingEmptySubsequences: false)

		guard labels.count >= 2, labels.allSatisfy({ $0.isEmpty == false }) else {
			return false
		}

		return host == domain || host.hasSuffix("." + domain)
	}

	static func channelNotice(from text: String) -> ChannelNotice? {
		guard text.hasPrefix("["), let space = text.firstIndex(of: " ") else { return nil }
		let head = text[..<space]
		guard head.count >= 4, head.hasSuffix("]") else { return nil }
		return ChannelNotice(
			channelName: String(head.dropFirst().dropLast()),
			text: String(text[text.index(after: space)...])
		)
	}

	static func nickServAction(for text: String, context: NickServContext) -> NickServAction? {
		/* Whether or not this session is the one that asked: a connect command
		 may have sent the identification, and the service confirms it the
		 same way. */
		if context.successfulIdentificationTokens.contains(where: text.localizedCaseInsensitiveContains) {
			return .identificationSucceeded
		}
		if context.isWaiting || context.isIdentifiedWithSASL {
			return nil
		}

		guard let password = context.password, !password.isEmpty,
		      context.needsIdentificationTokens.contains(where: text.localizedCaseInsensitiveContains)
		else { return nil }
		guard context.permitsCredentialsInClear else {
			return .identificationWithheld
		}
		if context.serverAddress?.hasSuffix(ServerQuirks.Services.dalNetAddressSuffix) == true {
			return .sendIdentification(
				target: ServerQuirks.Services.dalNetNickServTarget,
				text: "IDENTIFY \(password)"
			)
		}
		if context.sendsAuthenticationToUserServ {
			return .sendIdentification(
				target: ServerQuirks.Services.userServTarget,
				text: "login \(context.nickname) \(password)"
			)
		}
		return .sendIdentification(target: ServerQuirks.Services.nickServ, text: "IDENTIFY \(password)")
	}
}

@MainActor
extension ServerSession {
	func receiveWallops(_ message: Message) {
		guard let payload = message.params.first else { return }
		var rewritten = message
		rewritten.rewrite(as: .notice)
		rewritten.params = [
			userNickname,
			String(format: ChatLineFormat.specialNoticeMessage, message.command, payload),
		]
		receivePrivmsgAndNotice(rewritten)
	}

	func receivePrivmsgAndNotice(_ message: Message) {
		guard message.params.count > 1 else { return }
		updateUserIdentity(fromMessageTags: message)
		let result = InboundTextPolicy.classify(command: message.remoteCommand, payload: message.params[1])
		switch result.lineType {
		case .action, .privateMessage, .notice:
			receiveText(message, lineType: result.lineType, text: result.text)
		case .ctcpQuery:
			receiveCTCPQuery(message, text: result.text)
		case .ctcpReply:
			receiveCTCPReply(message, text: result.text)
		default:
			break
		}
	}

	func receiveText(_ message: Message, lineType originalLineType: ChatLineKind, text originalText: String) {
		guard message.params.count > 1 else { return }
		var text = originalText
		if text.isEmpty {
			guard originalLineType == .action || originalLineType == .actionNoHighlight else { return }
			text = " "
		}
		var target = message.params[0]
		guard !target.isEmpty else { return }
		if supportInfo.extractStatusMessagePrefix(fromTargetNamed: target).count == 1 {
			target.removeFirst()
		}

		let ignore = message.senderHostmask.flatMap(findAddressBookEntry(forHostmask:))
		let lineType = InboundTextPolicy.lineType(
			originalLineType, suppressingHighlights: ignore?.ignorePublicMessageHighlights ?? false
		)
		if lineType == .notice, ignore?.ignoreNoticeMessages == true {
			return
		}

		if stringIsChannelName(target) {
			guard ignore?.ignorePublicMessages != true else { return }
			receivePublicText(message, lineType: lineType, target: target, text: text)
		} else if !message.senderIsServer {
			guard ignore?.ignorePrivateMessages != true else { return }
			receivePrivateText(message, lineType: lineType, target: target, text: text)
		} else {
			receiveServerText(message, lineType: lineType, target: target, text: text)
		}
	}

	private func receivePublicText(
		_ message: Message, lineType: ChatLineKind, target: String, text: String
	) {
		guard let channel = findConversation(target) else { return }
		let sender = message.senderNickname ?? ""
		let isSelfMessage = nicknameIsMyself(sender)
		let isNotice = lineType == .notice
		// Capture the read state before asynchronous rendering.
		let alreadySeen = lineArrivedAlreadySeen(message, in: channel)
		let readGeneration = channel.readStateGeneration
		let connectionIdentifier = socket?.uniqueIdentifier
		let completion: PrintedLineCompletion = { [weak self, weak channel] context in
			guard let self, let channel, !isSelfMessage, !alreadySeen, !context.isDuplicate, !isTerminating,
			      socket?.uniqueIdentifier == connectionIdentifier, channel.associatedSession === self,
			      channel.readStateGeneration == readGeneration else { return }
			if isNotice {
				return
			}
			let highlight = context.isHighlight
			if highlight, isSafeToPostNotification(for: message, in: channel) {
				notifyEvent(.highlight, lineType: lineType, target: channel, nickname: sender, text: text)
			}
			if highlight {
				setHighlightState(for: channel)
			}
			setUnreadState(for: channel, isHighlight: highlight)
		}

		if shouldPrintReceivedText(text, message: message, destination: channel, lineType: lineType) {
			print(text, by: sender, in: channel, as: lineType, command: message.command,
			      receivedAt: message.receivedAt, isEncrypted: false, referenceMessage: message,
			      completionBlock: completion)
		}
		/* This weights the speaker. `TranscriptController` weights whoever the rendered
		 line mentioned, which is a different subject; the two do not overlap. */
		guard !isNotice, channel.memberInfo?.findMember(sender) != nil else { return }
		let localNickname = userNickname.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
		channel.recordConversation(
			with: sender,
			direction: text.localizedCaseInsensitiveContains(localNickname) ? .incoming : .mention
		)
	}

	private func receivePrivateText(
		_ message: Message, lineType: ChatLineKind, target: String, text: String
	) {
		let sender = message.senderNickname ?? ""
		let isNotice = lineType == .notice
		let isSelfMessage = nicknameIsMyself(sender)
		/* Usually the direct conversation with the sender, but a ChanServ notice
		 is filed into the channel it names and the notice setting can send any
		 notice to whatever conversation is selected. */
		var destination = findConversation(isSelfMessage ? target : sender)
		var deliveredText = text
		var newPrivateMessage = false

		if isNotice {
			if sender.caseInsensitiveCompare(ServerQuirks.Services.chanServ) == .orderedSame,
			   noticeIsFromServices(message)
			{
				(destination, deliveredText) = channelServiceNoticeDestination(current: destination, text: text)
			} else if sender.caseInsensitiveCompare(ServerQuirks.Services.nickServ) == .orderedSame {
				processNickServNotice(text, from: message)
			}
			if environment.settings.locationToSendNotices == .selectedConversation {
				destination = output?.selectedConversation(on: self)
			}
			if destination == nil, environment.settings.locationToSendNotices == .directConversation {
				destination = findConversationOrCreate(isSelfMessage ? target : sender, as: .direct)
			}
		} else if destination == nil {
			newPrivateMessage = true
			destination = findConversationOrCreate(isSelfMessage ? target : sender, as: .direct)
		}
		let textToDeliver = deliveredText
		// Capture the read state before asynchronous rendering.
		let alreadySeen = lineArrivedAlreadySeen(message, in: destination)
		let readGeneration = destination?.readStateGeneration
		let connectionIdentifier = socket?.uniqueIdentifier

		let completion: PrintedLineCompletion = { [weak self, weak destination] context in
			guard let self, let destination, !isSelfMessage, !alreadySeen, !context.isDuplicate, !isTerminating,
			      socket?.uniqueIdentifier == connectionIdentifier, destination.associatedSession === self,
			      destination.readStateGeneration == readGeneration else { return }
			let highlight = context.isHighlight
			if isSafeToPostNotification(for: message, in: destination) {
				let event: UserNotificationEvent = isNotice ? .privateNotice
					: (highlight ? .highlight : (newPrivateMessage ? .newPrivateMessage : .privateMessage))
				notifyEvent(
					event,
					lineType: lineType,
					target: destination,
					nickname: sender,
					text: textToDeliver
				)
			}
			if highlight {
				setHighlightState(for: destination)
			}
			setUnreadState(for: destination, isHighlight: highlight)
		}

		if shouldPrintReceivedText(textToDeliver, message: message, destination: destination, lineType: lineType) {
			print(textToDeliver, by: sender, in: destination, as: lineType, command: message.command,
			      receivedAt: message.receivedAt, isEncrypted: false, referenceMessage: message,
			      completionBlock: completion)
		}
		if !isNotice, let destination {
			applyPresence(true, to: destination)
		}
	}

	private func receiveServerText(
		_ message: Message, lineType: ChatLineKind, target _: String, text: String
	) {
		let sender = message.senderNickname ?? ""
		let directConversation = lineType == .notice
			? findConversation(sender)
			: findConversationOrCreate(sender, as: .direct)
		if shouldPrintReceivedText(text, message: message, destination: directConversation, lineType: lineType) {
			print(text, by: sender, in: directConversation, as: lineType, command: message.command,
			      receivedAt: message.receivedAt, isEncrypted: false, referenceMessage: message)
		}
		if sender.hasSuffix(ServerQuirks.Proxy.nicknameSuffix),
		   text == ServerQuirks.Proxy.connectedMessage
		{
			addDisconnectCallback { [weak self] in
				self?.printDebugInformation(toConsole: String(localized: .IRC.reconnectingToProxyToRebuildInternal))
				self?.connect(.reconnect)
			}
			disconnect()
		}
	}

	private func channelServiceNoticeDestination(
		current: Conversation?, text: String
	) -> (Conversation?, String) {
		guard let notice = ServiceNoticePolicy.channelNotice(from: text),
		      stringIsChannelName(notice.channelName),
		      let channel = findConversation(notice.channelName)
		else { return (current, text) }
		return (channel, notice.text)
	}

	private func noticeIsFromServices(_ message: Message) -> Bool {
		ServiceNoticePolicy.noticeIsFromServices(
			senderIsServer: message.senderIsServer,
			senderAddress: message.senderAddress,
			serverAddress: serverAddress
		)
	}

	private func processNickServNotice(_ text: String, from message: Message) {
		guard !message.isReplayed, message.params.first.map(nicknameIsMyself) == true else { return }
		guard noticeIsFromServices(message) else { return }

		let isIdentifiedWithSASL = isCapabilityEnabled(.isIdentifiedWithSASL)
		let action = ServiceNoticePolicy.nickServAction(
			for: (text as NSString).stripIRCEffects,
			context: .init(
				isWaiting: nickServ.isWaiting,
				isIdentifiedWithSASL: isIdentifiedWithSASL,
				permitsCredentialsInClear: permitsCredentialsInClear,
				// Read only where it could be sent: a session SASL authenticated
				// never touches the keychain for a NickServ notice.
				password: isIdentifiedWithSASL ? nil : sessionNicknamePassword,
				nickname: config.nickname,
				serverAddress: serverAddress,
				sendsAuthenticationToUserServ: config.sendAuthenticationRequestsToUserServ,
				needsIdentificationTokens: NickServTokens.needsIdentification,
				successfulIdentificationTokens: NickServTokens.identified
			)
		)
		switch action {
		case let .sendIdentification(target, text):
			send(.privmsg, arguments: [target, text])
			nickServ.isWaiting = true
			nickServ.isConfirmed = false
		case .identificationSucceeded:
			nickServ.isWaiting = false
			nickServ.isConfirmed = true
			noteAccountAuthenticated()
		case .identificationWithheld:
			reportWithheldCredentials()
		case nil:
			break
		}
	}
}

/** The NickServ phrase lists, read from the bundled property list once.

 Both lists are consulted for every notice a service sends, and the file they
 come from cannot change while the process runs, so reading them per notice
 parsed the same property list over and over. */
private nonisolated enum NickServTokens {
	static let needsIdentification = tokens(forKey: StaticStoreResource.nickServNeedsIdentificationTokensKey)
	static let identified = tokens(forKey: StaticStoreResource.nickServIdentifiedTokensKey)

	private static func tokens(forKey key: String) -> [String] {
		BundleResources.array(fromResources: StaticStoreResource.name, key: key)?
			.compactMap(\.string) ?? []
	}
}
