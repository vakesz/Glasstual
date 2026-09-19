// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

private enum OutboundTextSuppressionKey: String {
	case potentialFlood = "Input Text Possible Flood Warning"
}

/** One outbound text send, decided once.

 The three commands that carry a person's text are `PRIVMSG`, a `PRIVMSG`
 whose body is an `ACTION`, and `NOTICE`; a failed initializer is how "that is
 not a text command" is said. Everything else the send path needs — the wire
 name, the line type it prints as, and the two things the `/o…` and `/s…`
 spellings change — is read off the one remote command, so the value cannot
 disagree with itself. */
struct OutboundMessageOptions {
	let remoteCommand: RemoteCommand
	let isOperatorMessage: Bool
	let isSecretMessage: Bool

	/// How the line prints locally.
	var lineType: ChatLineKind {
		switch remoteCommand {
		case .privmsgAction: .action
		case .notice: .notice
		default: .privateMessage
		}
	}

	init?(remoteCommand: RemoteCommand, isOperatorMessage: Bool = false, isSecretMessage: Bool = false) {
		switch remoteCommand {
		case .privmsg, .privmsgAction, .notice:
			self.remoteCommand = remoteCommand
		default:
			return nil
		}

		self.isOperatorMessage = isOperatorMessage
		self.isSecretMessage = isSecretMessage
	}

	init?(command: LocalCommand?, silentlyConnecting: Bool) {
		switch command {
		case .msg, .omsg, .smsg, .umsg:
			self.init(
				remoteCommand: .privmsg,
				isOperatorMessage: command == .omsg,
				isSecretMessage: command == .smsg || silentlyConnecting
			)
		case .me, .sme, .ume:
			self.init(remoteCommand: .privmsgAction, isSecretMessage: command == .sme)
		case .notice, .onotice, .unotice:
			self.init(remoteCommand: .notice, isOperatorMessage: command == .onotice)
		default:
			return nil
		}
	}
}

extension ServerSession {
	/// An empty ACTION would be dropped by most servers, so it goes out with a
	/// single space instead.
	private static func actionBody(_ body: NSAttributedString) -> NSAttributedString {
		body.length == 0 ? NSAttributedString(string: " ") : body
	}

	@MainActor
	func dispatchMessageCommand(_ parsed: ParsedUserCommand, targetConversation: Conversation?) {
		let silentlyConnecting = isPerformingConnectCommands && config.runConnectCommandsSilently
		guard let policy = OutboundMessageOptions(
			command: parsed.localCommand,
			silentlyConnecting: silentlyConnecting
		) else { return }
		guard isLoggedIn else {
			printDebugInformation(toConsole: String(localized: .IRC.failedToSendDataToServer))
			return
		}

		var cursor = parsed.arguments
		let operatorPrefix: String?
		if policy.isOperatorMessage {
			guard let prefix = supportInfo.statusMessagePrefix(forModeSymbol: "o") else {
				printDebugInformation(String(localized: .IRC.cannotSendOperatorMessageBecause))
				return
			}
			operatorPrefix = prefix
		} else {
			operatorPrefix = nil
		}

		let targetName: String
		if policy.isSecretMessage == false, policy.lineType == .action,
		   let targetConversation
		{
			guard targetConversation.isConsole == false else {
				printDebugInformation(String(localized: .IRC.thisCommandCannotBeUsedWithin))
				return
			}
			if targetConversation.isDirectChat {
				// An empty action still has to carry a body onto the wire.
				sendDirectChatText(Self.actionBody(cursor.attributedRest), as: .privmsgAction, to: targetConversation)
				return
			}
			targetName = targetConversation.name
		} else if policy.isOperatorMessage,
		          stringIsChannelName(cursor.rest) == false,
		          targetConversation?.isChannel == true,
		          let targetConversation
		{
			targetName = targetConversation.name
		} else {
			targetName = cursor.next()
		}
		guard requireArguments(targetName, for: parsed.command) else { return }

		let body = cursor.attributedRest
		if body.length == 0, policy.lineType != .action {
			return
		}
		let arguments = Self.actionBody(body)

		var destinations = targetName.components(separatedBy: ",")
		var destinationToSelect: Conversation?
		if policy.isSecretMessage == false, silentlyConnecting == false,
		   operatorPrefix == nil,
		   supportInfo.groupsMultipleTargets(forCommand: policy.remoteCommand.wireName)
		{
			/* Channels are found under the server's casemapping, so `#Chat` and
			 `#chat` are one channel: it is grouped once, and every spelling of it
			 is taken out of the per-destination loop below. Matching the typed
			 names against the channels' own spelling left `#Chat` behind and sent
			 the message a second time. */
			var groupedChannels: [Conversation] = []
			var groupedIdentities: Set<ObjectIdentifier> = []
			for destinationName in destinations {
				guard let channel = findConversation(destinationName), channel.isChannel, channel.isActive,
				      groupedIdentities.insert(ObjectIdentifier(channel)).inserted
				else { continue }
				groupedChannels.append(channel)
			}
			if groupedChannels.count > 1 {
				sendText(arguments, as: policy.remoteCommand, toConversations: groupedChannels)
				if environment.settings.giveFocusOnMessageCommand {
					destinationToSelect = groupedChannels.first
				}
				destinations.removeAll { destinationName in
					findConversation(destinationName).map { groupedIdentities.contains(ObjectIdentifier($0)) } ?? false
				}
			}
		}

		for destination in destinations {
			let selected = sendCommandText(
				arguments,
				to: destination,
				operatorPrefix: operatorPrefix,
				policy: policy,
				localCommand: parsed.command,
				silentlyConnecting: silentlyConnecting
			)
			if destinationToSelect == nil, environment.settings.giveFocusOnMessageCommand {
				destinationToSelect = selected
			}
		}
		selectCommandDestination(destinationToSelect)
	}

	@MainActor
	func inputText(_ input: Any, destination: ChatItem) {
		inputText(input, as: .privmsg, destination: destination)
	}

	@MainActor
	func inputText(_ input: Any, as command: RemoteCommand, destination: ChatItem) {
		guard isTerminating == false, let text = attributedInput(input), text.length > 0 else { return }
		guard OutboundMessageOptions(remoteCommand: command) != nil else {
			assertionFailure("Unsupported outbound text command")
			return
		}

		let source = NSAttributedString(attributedString: text)
		let replyIdentifier = nextMessageReplyIdentifier
		nextMessageReplyIdentifier = nil
		var warningCursor = OutboundInputCursor(source)
		var lineCount = 0
		while lineCount <= 4, warningCursor.next() != nil {
			lineCount += 1
		}
		let shouldWarn = lineCount > 4 || source.length > 2040
		if shouldWarn {
			let destinationName = destination.name
			requestConfirmation(Self.potentialFloodAlert, isCurrent: { session in
				destination === session || (destination.name == destinationName &&
					session.conversationList.contains { $0 === destination })
			}, perform: { session in
				session.sendInputLines(source, as: command, destination: destination, replyIdentifier: replyIdentifier)
			})
			return
		}
		sendInputLines(source, as: command, destination: destination, replyIdentifier: replyIdentifier)
	}

	private func sendInputLines(_ text: NSAttributedString, as command: RemoteCommand, destination: ChatItem,
	                            replyIdentifier: String?)
	{
		var remaining = OutboundInputCursor(text)
		var pendingReply = replyIdentifier
		enqueueOutboundText(conversations: (destination as? Conversation).map { [$0] } ?? []) { [weak destination] session in
			guard let destination, let originalLine = remaining.next() else { return false }
			let laterReply = session.nextMessageReplyIdentifier
			session.nextMessageReplyIdentifier = pendingReply
			defer {
				pendingReply = session.nextMessageReplyIdentifier
				session.nextMessageReplyIdentifier = laterReply
			}
			var line = originalLine
			let source = line.string
			let isPrefixed = source.hasPrefix("/")

			if destination.isSession {
				if isPrefixed {
					line = line.attributedSubstring(fromIndex: 1)
				}
				session.sendCommand(line, completeTarget: false)
				return true
			}

			guard let conversation = (destination as AnyObject) as? Conversation else {
				assertionFailure("A sidebar destination is either the session itself or a conversation")
				return false
			}

			if isPrefixed, source.hasPrefix("//") == false, line.length > 1 {
				session.sendCommand(line.attributedSubstring(fromIndex: 1), target: conversation.name)
			} else {
				if isPrefixed, line.length > 1 {
					line = line.attributedSubstring(fromIndex: 1)
				}
				session.sendText(line, as: command, to: conversation)
			}
			return true
		}
	}

	@MainActor
	func sendText(_ text: NSAttributedString, as command: RemoteCommand, to conversation: Conversation) {
		guard text.length > 0 else { return }
		guard conversation.isConsole == false else {
			printDebugInformation(String(localized: .IRC.messagesCannotBeSent), in: conversation)
			return
		}
		guard conversation.isDirectChat == false else {
			sendDirectChatText(text, as: command, to: conversation)
			return
		}
		guard let policy = OutboundMessageOptions(remoteCommand: command) else { return }

		localUserSentMessage(in: conversation)
		var replyIdentifier = nextMessageReplyIdentifier
		nextMessageReplyIdentifier = nil
		if isCapabilityEnabled(.messageTags) == false {
			replyIdentifier = nil
		}

		var cursor = OutboundTextCursor(text)
		enqueueOutboundText(conversations: [conversation]) { session in
			guard let message = cursor.next(for: conversation.name, on: session, as: policy.lineType) else {
				return false
			}
			let lineReplyIdentifier = replyIdentifier
			replyIdentifier = nil
			session.nextLineReplyToMessageIdentifier = lineReplyIdentifier

			let redactedMessage = WireRedaction.redactedServiceMessage(message, sentTo: conversation.name)
			let deliveryLabel = session.printLocallyIfNeeded(redactedMessage, in: conversation, policy: policy)
			let wireMessage = policy.lineType == .action ? CTCPPayload.action(message) : message
			session.nextLineReplyToMessageIdentifier = nil

			var tags: [String: String] = [:]
			if let deliveryLabel {
				tags["label"] = deliveryLabel
			}
			if let lineReplyIdentifier {
				tags["+draft/reply"] = lineReplyIdentifier
			}
			if tags.isEmpty {
				session.send(policy.remoteCommand, arguments: [conversation.name, wireMessage])
			} else {
				session.sendCommand(policy.remoteCommand, arguments: [conversation.name, wireMessage], tags: tags)
			}
			return true
		}
	}

	@MainActor
	func sendText(_ text: NSAttributedString, as command: RemoteCommand, toConversations conversations: [Conversation]) {
		guard text.length > 0, conversations.isEmpty == false,
		      let policy = OutboundMessageOptions(remoteCommand: command) else { return }
		/* Grouping needs the server's word for it: without an advertised limit
		 above one, every channel gets its own line. A direct conversation is
		 never grouped even where the server would take the targets, because the
		 transcript the user reads is per-conversation. */
		let groupsTargets = supportInfo.groupsMultipleTargets(forCommand: policy.remoteCommand.wireName)
		let targetLimit = supportInfo.maximumTargets(forCommand: policy.remoteCommand.wireName)
		var groupedChannels: [Conversation] = []
		for conversation in conversations {
			if groupsTargets, conversation.isChannel {
				groupedChannels.append(conversation)
			} else {
				sendText(text, as: command, to: conversation)
			}
		}
		guard groupedChannels.isEmpty == false else { return }
		let targetGroups = WireBatching.chunkTargets(groupedChannels.map(\.name), limit: targetLimit)
		var groupOffset = 0
		var groupIndex = 0
		let source = NSAttributedString(attributedString: text)
		var cursor = OutboundTextCursor(source)
		enqueueOutboundText(conversations: groupedChannels) { session in
			while groupIndex < targetGroups.count {
				let targetGroup = targetGroups[groupIndex]
				let groupChannels = Array(groupedChannels[groupOffset ..< groupOffset + targetGroup.count])
				let targetList = targetGroup.joined(separator: ",")
				if let message = cursor.next(for: targetList, on: session, as: policy.lineType) {
					/* One command carries one label, so only the first channel in
					 the group registers a delivery; the rest print untracked. The
					 label used to be discarded here, which left every grouped
					 message uncorrelated. */
					var deliveryLabel: String?
					for (index, channel) in groupChannels.enumerated() {
						let label = session.printLocallyIfNeeded(
							WireRedaction.redactedServiceMessage(message, sentTo: channel.name),
							in: channel,
							policy: policy,
							registeringDelivery: index == 0
						)

						if index == 0 {
							deliveryLabel = label
						}
					}
					let wireMessage = policy.lineType == .action
						? CTCPPayload.action(message)
						: message
					if let deliveryLabel {
						session.sendCommand(
							policy.remoteCommand,
							arguments: [targetList, wireMessage],
							tags: ["label": deliveryLabel]
						)
					} else {
						session.send(policy.remoteCommand, arguments: [targetList, wireMessage])
					}
					return true
				}
				groupIndex += 1
				groupOffset += targetGroup.count
				cursor = OutboundTextCursor(source)
			}
			return false
		}
	}

	private func attributedInput(_ input: Any) -> NSAttributedString? {
		if let text = input as? String {
			return NSAttributedString(string: text)
		}
		if let text = input as? NSAttributedString {
			return text
		}
		assertionFailure("Input must be String or NSAttributedString")
		return nil
	}

	/** The confirmation for a message large enough to flood the conversation.

	 Send/Cancel, not Yes/No: the question is whether to send, so the button
	 that does it says so -- and the one that answers Escape says that nothing
	 was sent. */
	private static var potentialFloodAlert: AlertRequest {
		AlertRequest(
			title: String(localized: .IRC.messageThatYouAreSending),
			body: String(localized: .IRC.areYouSureYouWant),
			defaultButton: PromptStrings.Action.send,
			alternateButton: PromptStrings.Action.cancel,
			suppressionKey: OutboundTextSuppressionKey.potentialFlood.rawValue,
			style: .warning
		)
	}

	private func printLocallyIfNeeded(
		_ message: String,
		in conversation: Conversation,
		policy: OutboundMessageOptions,
		localCommand: String? = nil,
		registeringDelivery: Bool = true
	) -> String? {
		/* With echo-message the server sends this message back and the inbound
		 path prints it, so printing here too would show it twice -- unless a
		 label lets the echo be matched to the line printed now. */
		if isCapabilityEnabled(.echoMessage), labeledResponseTrackingEnabled() == false {
			return nil
		}

		let label = registeringDelivery ? registerPendingDelivery(for: conversation) : nil

		if label != nil {
			nextLineDeliveryState = .pending
		}

		print(
			message,
			by: userNickname,
			in: conversation,
			as: policy.lineType,
			command: localCommand ?? policy.remoteCommand.wireName,
			receivedAt: Date(),
			isEncrypted: false,
			referenceMessage: nil
		) { [weak self] context in
			guard let label else { return }
			self?.attachLineNumber(context.lineNumber, toDeliveryWithLabel: label)
		}

		return label
	}

	@MainActor
	private func sendCommandText(
		_ text: NSAttributedString,
		to rawDestination: String,
		operatorPrefix: String?,
		policy: OutboundMessageOptions,
		localCommand: String,
		silentlyConnecting: Bool
	) -> Conversation? {
		let explicitPrefix = supportInfo.extractStatusMessagePrefix(fromTargetNamed: rawDestination)
		let prefix = explicitPrefix.isEmpty ? operatorPrefix : explicitPrefix
		let destinationName = explicitPrefix.isEmpty ? rawDestination : String(rawDestination.dropFirst())
		var conversation = findConversation(destinationName)
		if policy.isSecretMessage == false, conversation == nil, stringIsNickname(destinationName) {
			conversation = chatSession?.createDirectConversation(destinationName, on: self)
		}

		let destinationIsChannel = conversation?.isChannel == true ||
			(conversation == nil && stringIsChannelName(destinationName))
		let wireTarget = prefix.flatMap { destinationIsChannel ? "\($0)\(destinationName)" : nil }
			?? destinationName
		var cursor = LineCursor(text)
		enqueueOutboundText(conversations: conversation.map { [$0] } ?? []) { session in
			guard let message = cursor.nextLine(forTarget: wireTarget, on: session, with: policy.lineType)
			else { return false }
			let redactedMessage = WireRedaction.redactedServiceMessage(message, sentTo: wireTarget)
			let deliveryLabel: String?
			if silentlyConnecting {
				session.printDebugInformation(
					toConsole: String(localized: .IRC.connectCommandSent(wireTarget, redactedMessage))
				)
				deliveryLabel = nil
			} else if let conversation, policy.isSecretMessage == false {
				deliveryLabel = session.printLocallyIfNeeded(
					redactedMessage,
					in: conversation,
					policy: policy,
					localCommand: localCommand
				)
			} else {
				deliveryLabel = nil
			}

			let wireMessage = policy.lineType == .action
				? CTCPPayload.action(message)
				: message
			if let deliveryLabel {
				session.sendCommand(
					policy.remoteCommand,
					arguments: [wireTarget, wireMessage],
					tags: ["label": deliveryLabel]
				)
			} else {
				session.send(policy.remoteCommand, arguments: [wireTarget, wireMessage])
			}
			return true
		}
		return policy.isSecretMessage ? nil : conversation
	}

	@MainActor
	private func selectCommandDestination(_ conversation: Conversation?) {
		guard let conversation else { return }
		output?.select(conversation)
	}
}

extension ServerSession {
	@MainActor
	@discardableResult
	func sendReaction(
		_ emoji: String,
		toMessageIdentifier messageIdentifier: String,
		in conversation: Conversation
	) -> Bool {
		guard emoji.isEmpty == false, messageIdentifier.isEmpty == false, conversation.isConsole == false else {
			return false
		}

		let tags = ["+draft/react": emoji, "+draft/reply": messageIdentifier]
		guard sendTagMessage(tags, toTarget: conversation.name) else { return false }

		deliverTags(
			["draft/react": emoji, "draft/reply": messageIdentifier],
			fromSender: userNickname,
			in: conversation
		)
		return true
	}

	func sendPrivmsg(_ message: String, to conversation: Conversation) {
		sendText(NSAttributedString(string: message), as: .privmsg, to: conversation)
	}

	/// The `String` spelling is for the verb a person typed after `/ctcp`, which
	/// this session is free to know nothing about. Everything it sends on its own
	/// goes out through the ``CTCPVerb`` overload.
	func sendCTCPQuery(_ nickname: String, command: String, text: String?) {
		send(
			.privmsg,
			arguments: [nickname, CTCPPayload.framed(command: command, text: text, sanitizingLineBreaks: false)]
		)
	}

	func sendCTCPQuery(_ nickname: String, command: CTCPVerb, text: String?) {
		sendCTCPQuery(nickname, command: command.wireName, text: text)
	}

	func sendCTCPReply(_ nickname: String, command: String, text: String?) {
		send(
			.notice,
			arguments: [nickname, CTCPPayload.framed(command: command, text: text, sanitizingLineBreaks: true)]
		)
	}

	func sendCTCPPing(_ nickname: String) {
		sendCTCPQuery(nickname, command: .ping, text: String(Date().timeIntervalSince1970))
	}
}
