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
		clearTyping(for: message)
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
		/* A message to `@#channel` reached only some of its members. It is still
		 filed in the channel, and the line keeps the target it went to. */
		var statusMessageTarget: String?
		if supportInfo.extractStatusMessagePrefix(fromTargetNamed: target).count == 1 {
			statusMessageTarget = target
			target.removeFirst()
		}

		if let sender = message.senderNickname, nicknameIsMyself(sender) {
			/* The echo of a message sent without a local print stays unprinted,
			 and one of our own messages to services is shown with its
			 credentials masked, as it was when printed locally. Channel text is
			 never rewritten. */
			if consumeUnprintedEcho(message, target: target, text: text, lineType: originalLineType) {
				return
			}
			if stringIsChannelName(target) == false {
				text = WireRedaction.redactedServiceMessage(text, sentTo: target)
			}
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
			receivePublicText(
				message, lineType: lineType, target: target, text: text, statusMessageTarget: statusMessageTarget
			)
		} else if !message.sender.isServer {
			guard ignore?.ignorePrivateMessages != true else { return }
			receivePrivateText(message, lineType: lineType, target: target, text: text)
		} else {
			receiveServerText(message, lineType: lineType, target: target, text: text)
		}
	}

	private func receivePublicText(
		_ message: Message, lineType: ChatLineKind, target: String, text: String, statusMessageTarget: String?
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
			      statusMessageTarget: statusMessageTarget, completionBlock: completion)
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
			senderIsServer: message.sender.isServer,
			senderAddress: message.sender.address,
			serverAddress: serverAddress
		)
	}

	private func processNickServNotice(_ text: String, from message: Message) {
		guard !message.isReplayed, message.params.first.map(nicknameIsMyself) == true, noticeIsFromServices(message) else { return }

		let action = ServiceNoticePolicy.nickServAction(
			for: (text as NSString).stripIRCEffects,
			context: nickServContext()
		)
		switch action {
		case let .sendIdentification(target, text):
			sendUnprinted(.privmsg, to: target, text: text)
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

	private func nickServContext() -> ServiceNoticePolicy.NickServContext {
		let isIdentifiedWithSASL = isCapabilityEnabled(.isIdentifiedWithSASL)

		return .init(
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
	}

	/** Sends the identification services asked for while the connection could
	 not carry the password, once the user has allowed it. Services asked once
	 and may not ask again, so the answer cannot wait for the next notice.
	 Does nothing when the session is already identified or is waiting on an answer. */
	func identifyAfterCredentialConsent() {
		guard case let .sendIdentification(target, text) = ServiceNoticePolicy.identificationAction(for: nickServContext()) else {
			return
		}
		sendUnprinted(.privmsg, to: target, text: text)
		nickServ.isWaiting = true
		nickServ.isConfirmed = false
	}
}
